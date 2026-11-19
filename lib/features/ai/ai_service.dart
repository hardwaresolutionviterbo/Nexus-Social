import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException, FunctionResponse, SupabaseClient;

/// Un messaggio della chat con Piazly AI (resta solo su questo telefono).
class AiTurn {
  const AiTurn({required this.mine, required this.text, required this.at});

  final bool mine;
  final String text;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{'m': mine, 't': text, 'a': at.toUtc().toIso8601String()};

  static AiTurn? fromJson(Object? j) {
    if (j is! Map) return null;
    final DateTime? at = DateTime.tryParse('${j['a']}');
    if (j['t'] is! String || j['m'] is! bool || at == null) return null;
    return AiTurn(mine: j['m'] as bool, text: j['t'] as String, at: at.toLocal());
  }
}

class AiFailure implements Exception {
  const AiFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Il server di Piazly AI (funzione `ia` su Supabase, che usa Cloudflare Workers AI).
abstract class AiServer {
  Future<String> chat(List<AiTurn> history);

  /// Immagine JPEG generata dalla descrizione.
  Future<Uint8List> image(String prompt);
}

/// Dove si salva la cronologia di Piazly AI (nei test: in memoria).
abstract class AiStore {
  Future<List<AiTurn>> load();

  Future<void> save(List<AiTurn> turns);
}

class MemoryAiStore implements AiStore {
  List<AiTurn> turns = <AiTurn>[];

  @override
  Future<List<AiTurn>> load() async => List<AiTurn>.of(turns);

  @override
  Future<void> save(List<AiTurn> t) async => turns = List<AiTurn>.of(t);
}

class FileAiStore implements AiStore {
  FileAiStore({required this.uid});

  /// Un file per account: chi entra con un altro account non vede questa chat.
  final String Function() uid;

  Future<File> _file() async {
    final String id = uid().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return File('${(await getApplicationDocumentsDirectory()).path}/piazly_ai_$id.json');
  }

  @override
  Future<List<AiTurn>> load() async {
    try {
      final File f = await _file();
      if (!await f.exists()) return <AiTurn>[];
      final Object? j = jsonDecode(await f.readAsString());
      return <AiTurn>[for (final Object? x in (j is List ? j : const <Object?>[])) ?AiTurn.fromJson(x)];
    } catch (_) {
      return <AiTurn>[];
    }
  }

  @override
  Future<void> save(List<AiTurn> turns) async {
    final File f = await _file();
    await f.writeAsString(jsonEncode(<Object?>[for (final AiTurn t in turns) t.toJson()]), flush: true);
  }
}

/// Piazly AI: la chat fissata in cima alle chat e le «Immagini IA» della graffetta.
class AiService extends ChangeNotifier {
  AiService({required this.server, AiStore? store, DateTime Function()? clock})
    : store = store ?? MemoryAiStore(),
      _clock = clock ?? DateTime.now;

  static const int keepTurns = 200;
  static const int contextTurns = 12;
  static const int maxQuestion = 2000;

  final AiServer server;
  final AiStore store;
  final DateTime Function() _clock;

  List<AiTurn> _turns = <AiTurn>[];
  bool _loaded = false;
  bool _thinking = false;
  bool _disposed = false;

  List<AiTurn> get turns => List<AiTurn>.unmodifiable(_turns);
  bool get thinking => _thinking;
  AiTurn? get last => _turns.isEmpty ? null : _turns.last;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _turns = await store.load();
    _notify();
  }

  /// Manda una domanda e aggiunge la risposta. Lancia [AiFailure] con il motivo.
  Future<void> ask(String text) async {
    final String q = text.trim();
    if (q.isEmpty || _thinking) return;
    if (q.length > maxQuestion) throw const AiFailure('Domanda troppo lunga (massimo 2.000 caratteri).');
    await load();
    _turns = <AiTurn>[..._turns, AiTurn(mine: true, text: q, at: _clock())];
    _thinking = true;
    _notify();
    try {
      final List<AiTurn> context = _turns.length > contextTurns ? _turns.sublist(_turns.length - contextTurns) : _turns;
      final String answer = await server.chat(context);
      _turns = <AiTurn>[..._turns, AiTurn(mine: false, text: answer, at: _clock())];
    } finally {
      _thinking = false;
      if (_turns.length > keepTurns) _turns = _turns.sublist(_turns.length - keepTurns);
      unawaited(store.save(_turns).catchError((Object _) {}));
      _notify();
    }
  }

  Future<void> clear() async {
    _turns = <AiTurn>[];
    await store.save(_turns);
    _notify();
  }

  Future<Uint8List> image(String prompt) {
    final String p = prompt.trim();
    if (p.length < 3) throw const AiFailure('Descrivi l\'immagine con qualche parola in più.');
    return server.image(p.length > 400 ? p.substring(0, 400) : p);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Piazly AI dell'app (lo imposta main.dart dopo l'accesso).
abstract final class AiRegistry {
  static AiService? current;
}

class SupabaseAiServer implements AiServer {
  SupabaseAiServer(this._client);

  final SupabaseClient _client;

  Future<Map<String, Object?>> _call(Map<String, Object?> body, Duration timeout) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const AiFailure('Accesso richiesto.');
    final String token = await user.getIdToken() ?? '';
    try {
      final FunctionResponse res = await _client.functions
          .invoke('ia', headers: <String, String>{'Authorization': 'Bearer $token'}, body: body)
          .timeout(timeout);
      final Object? data = res.data;
      if (data is Map) return data.cast<String, Object?>();
      throw const AiFailure('Risposta non valida. Riprova.');
    } on FunctionException catch (e) {
      final Object? d = e.details;
      final String code = d is Map ? '${d['errore']}' : '';
      throw AiFailure(switch (e.status) {
        429 when code == 'limite' => 'Hai raggiunto il limite di oggi. Riprova domani.',
        429 => 'Piazly AI è molto richiesta in questo momento. Riprova tra poco.',
        422 => 'Questa immagine non si può creare. Prova con un\'altra descrizione.',
        503 => 'Piazly AI non è ancora attiva.',
        _ => 'Piazly AI non risponde. Riprova tra poco.',
      });
    } on TimeoutException {
      throw const AiFailure('Piazly AI ci sta mettendo troppo. Riprova.');
    } on SocketException {
      throw const AiFailure('Nessuna connessione a internet.');
    }
  }

  @override
  Future<String> chat(List<AiTurn> history) async {
    final Map<String, Object?> r = await _call(<String, Object?>{
      'azione': 'chat',
      'messaggi': <Map<String, String>>[
        for (final AiTurn t in history) <String, String>{'role': t.mine ? 'user' : 'assistant', 'content': t.text},
      ],
    }, const Duration(seconds: 45));
    final Object? text = r['risposta'];
    if (text is! String || text.trim().isEmpty) throw const AiFailure('Risposta vuota. Riprova.');
    return text.trim();
  }

  @override
  Future<Uint8List> image(String prompt) async {
    final Map<String, Object?> r = await _call(<String, Object?>{'azione': 'immagine', 'prompt': prompt},
        const Duration(seconds: 70));
    final Object? b64 = r['immagine'];
    if (b64 is! String) throw const AiFailure('Immagine non ricevuta. Riprova.');
    try {
      return base64Decode(b64);
    } catch (_) {
      throw const AiFailure('Immagine non valida. Riprova.');
    }
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chat_backup.dart';
import 'chat_models.dart' show ChatFailure;
import 'chat_service.dart';

/// Stato del backup per le schermate (Fase 4, Blocco 6).
class ChatBackup extends ChangeNotifier {
  ChatBackup({
    required this.chat,
    required this.server,
    required this.keys,
    this.kdf = const BackupKdf(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ChatService chat;
  final BackupServer server;
  final BackupKeyStore keys;
  final BackupKdf kdf;
  final DateTime Function() _now;

  /// Valore salvato al posto della chiave quando si sceglie di non ripristinare.
  static const String skipped = 'nessun-ripristino';

  BackupInfo? _info;
  bool _loaded = false;
  bool _busy = false;
  bool _enabled = false;
  bool _skipped = false;
  String? _error;

  BackupInfo? get info => _info;
  bool get loaded => _loaded;
  bool get busy => _busy;

  /// Su questo telefono c'è la chiave: i backup partono anche da soli.
  bool get enabled => _enabled;
  String? get error => _error;

  /// Telefono nuovo: c'è un backup sul server ma non la chiave qui (e non è stato rifiutato).
  bool get offersRestore => _loaded && !_enabled && !_skipped && _info != null;

  bool _disposed = false;

  void _set(VoidCallback f) {
    f();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<BackupKey?> _key() async => BackupKey.decode(await keys.read());

  /// Legge lo stato (all'avvio della chat) e rifà il backup se è passato un giorno.
  Future<void> load({bool auto = true}) async {
    try {
      final String? raw = await keys.read();
      final BackupInfo? info = await server.info();
      _set(() {
        _enabled = BackupKey.decode(raw) != null;
        _skipped = raw == skipped;
        _info = info;
        _loaded = true;
        _error = null;
      });
      if (auto && _enabled && (info == null || _now().difference(info.at) >= autoBackupEvery)) {
        await backupNow();
      }
    } catch (_) {
      _set(() => _loaded = true);
    }
  }

  Future<T> _job<T>(Future<T> Function() f) async {
    if (_busy) throw const ChatFailure('Un backup è già in corso.');
    _set(() {
      _busy = true;
      _error = null;
    });
    try {
      return await f();
    } on ChatFailure catch (e) {
      _set(() => _error = e.message);
      rethrow;
    } catch (_) {
      const ChatFailure failure = ChatFailure('Backup non riuscito. Controlla la connessione e riprova.');
      _set(() => _error = failure.message);
      throw failure;
    } finally {
      _set(() => _busy = false);
    }
  }

  /// Attiva il backup con una nuova password e lo fa subito.
  Future<void> enable(String password) async {
    final String? problem = backupPasswordProblem(password);
    if (problem != null) throw ChatFailure(problem);
    final BackupKey key = await BackupCipher.deriveKey(password, kdf: kdf);
    await keys.write(key.encode());
    _set(() => _enabled = true);
    await backupNow();
  }

  /// Fa il backup adesso con la chiave salvata su questo telefono.
  Future<void> backupNow() => _job(() async {
    final BackupKey? key = await _key();
    if (key == null) throw const ChatFailure('Prima scegli la password del backup.');
    final BackupContent content = BackupContent(made: _now(), chats: await chat.exportHistory());
    final Uint8List file = await BackupCipher.seal(key, content.encode());
    if (file.length > 20 * 1024 * 1024) throw const ChatFailure('Backup troppo grande (massimo 20 MB).');
    await server.upload(file);
    final BackupInfo? info = await server.info();
    _set(() => _info = info ?? BackupInfo(at: _now(), size: file.length));
  });

  /// Recupera le chat dal backup con la password; restituisce quanti messaggi sono tornati.
  Future<int> restore(String password) => _job(() async {
    final Uint8List file = await server.download();
    final opened = await BackupCipher.open(password, file);
    final BackupContent content = BackupContent.decode(opened.plain);
    final int added = await chat.importHistory(content.chats);
    await keys.write(opened.key.encode());
    _set(() {
      _enabled = true;
      _skipped = false;
    });
    return added;
  });

  /// «Non ora» sul telefono nuovo: non si chiede più (il ripristino resta nelle impostazioni).
  Future<void> skipRestore() async {
    await keys.write(skipped);
    _set(() => _skipped = true);
  }

  /// Spegne il backup: si cancella dal server e la chiave sparisce da questo telefono.
  Future<void> disable() => _job(() async {
    await server.remove();
    await keys.write(null);
    _set(() {
      _enabled = false;
      _info = null;
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Registro delle chiamate (come «Chiamate» di WhatsApp): solo su questo telefono, mai sul
/// server. Si tengono le ultime 200.
class CallRecord {
  const CallRecord({
    required this.id,
    required this.conversationId,
    required this.peerId,
    required this.name,
    required this.at,
    required this.outgoing,
    required this.answered,
    this.video = false,
    this.group = false,
    this.duration,
  });

  final String id;
  final String conversationId;

  /// Nelle chiamate a due: l'altra persona; nei gruppi vuoto.
  final String peerId;

  /// Nome mostrato quando la chiamata è avvenuta (persona o gruppo).
  final String name;
  final DateTime at;
  final bool outgoing;

  /// La chiamata c'è stata davvero (qualcuno ha risposto).
  final bool answered;
  final bool video;
  final bool group;
  final Duration? duration;

  /// Chiamata in arrivo a cui non ho risposto.
  bool get missed => !outgoing && !answered;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'c': conversationId,
    if (peerId.isNotEmpty) 'p': peerId,
    'n': name,
    'a': at.toUtc().toIso8601String(),
    if (outgoing) 'o': true,
    if (answered) 'r': true,
    if (video) 'v': true,
    if (group) 'g': true,
    if (duration != null) 'd': duration!.inSeconds,
  };

  static CallRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final DateTime? at = DateTime.tryParse('${j['a']}');
    if (j['id'] is! String || j['c'] is! String || at == null) return null;
    return CallRecord(
      id: j['id'] as String,
      conversationId: j['c'] as String,
      peerId: (j['p'] as String?) ?? '',
      name: (j['n'] as String?) ?? '',
      at: at.toLocal(),
      outgoing: j['o'] == true,
      answered: j['r'] == true,
      video: j['v'] == true,
      group: j['g'] == true,
      duration: j['d'] is int ? Duration(seconds: j['d'] as int) : null,
    );
  }
}

abstract class CallLogStore {
  Future<List<CallRecord>> read();

  Future<void> write(List<CallRecord> records);

  Future<DateTime?> seenAt();

  Future<void> setSeenAt(DateTime at);
}

class MemoryCallLogStore implements CallLogStore {
  List<CallRecord> records = <CallRecord>[];
  DateTime? seen;

  @override
  Future<List<CallRecord>> read() async => records;

  @override
  Future<void> write(List<CallRecord> r) async => records = r;

  @override
  Future<DateTime?> seenAt() async => seen;

  @override
  Future<void> setSeenAt(DateTime at) async => seen = at;
}

/// Nella cartella privata dell'app.
class FileCallLogStore implements CallLogStore {
  FileCallLogStore(this._dir);

  final Future<Directory> _dir;

  Future<File> get _file async => File('${(await _dir).path}/chiamate.json');

  Future<Map<String, Object?>> _all() async {
    try {
      final File f = await _file;
      if (!f.existsSync()) return <String, Object?>{};
      final Object? j = jsonDecode(await f.readAsString());
      return j is Map ? Map<String, Object?>.from(j) : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Future<void> _save(Map<String, Object?> all) async {
    final File f = await _file;
    f.parent.createSync(recursive: true);
    await f.writeAsString(jsonEncode(all), flush: true);
  }

  @override
  Future<List<CallRecord>> read() async {
    final Object? list = (await _all())['chiamate'];
    return <CallRecord>[
      if (list is List)
        for (final Object? j in list)
          if (CallRecord.fromJson(j) case final CallRecord r) r,
    ];
  }

  @override
  Future<void> write(List<CallRecord> records) async {
    final Map<String, Object?> all = await _all();
    all['chiamate'] = <Map<String, Object?>>[for (final CallRecord r in records) r.toJson()];
    await _save(all);
  }

  @override
  Future<DateTime?> seenAt() async => DateTime.tryParse('${(await _all())['visto']}')?.toLocal();

  @override
  Future<void> setSeenAt(DateTime at) async {
    final Map<String, Object?> all = await _all();
    all['visto'] = at.toUtc().toIso8601String();
    await _save(all);
  }
}

class CallLog extends ChangeNotifier {
  CallLog(this.store);

  static const int keep = 200;
  final CallLogStore store;
  List<CallRecord> _records = <CallRecord>[];
  DateTime? _seen;
  bool _loaded = false;
  bool _disposed = false;

  /// Dalla più recente.
  List<CallRecord> get records => _records;

  /// Chiamate perse dopo l'ultima volta che si è aperta la sezione «Chiamate».
  int get unseenMissed =>
      _records.where((CallRecord r) => r.missed && (_seen == null || r.at.isAfter(_seen!))).length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final List<CallRecord> all = await store.read();
      _records = all..sort((CallRecord a, CallRecord b) => b.at.compareTo(a.at));
      _seen = await store.seenAt();
    } catch (_) {
      _records = <CallRecord>[];
    }
    _notify();
  }

  Future<void> add(CallRecord r) async {
    await load();
    _records = <CallRecord>[r, ..._records.where((CallRecord x) => x.id != r.id)].take(keep).toList();
    _notify();
    try {
      await store.write(_records);
    } catch (_) {
      // Registro solo su questo telefono: se non si salva, resta fino alla chiusura.
    }
  }

  /// Aperta la sezione «Chiamate»: le perse non sono più «nuove».
  Future<void> markSeen(DateTime at) async {
    _seen = at;
    _notify();
    try {
      await store.setSeenAt(at);
    } catch (_) {
      // Non grave.
    }
  }

  Future<void> remove(String id) async {
    _records = _records.where((CallRecord r) => r.id != id).toList();
    _notify();
    await store.write(_records);
  }

  Future<void> clear() async {
    _records = <CallRecord>[];
    _notify();
    await store.write(_records);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

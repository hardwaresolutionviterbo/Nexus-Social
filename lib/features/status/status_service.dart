import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/chat_models.dart';

/// Stati (Fase 4, Blocco 13): aggiornamenti che durano 24 ore, come su WhatsApp.
///
/// Testo su sfondo colorato, foto o video breve. Chi pubblica sceglie chi li vede; le regole
/// le applica il server (migrazione 0031). Gli stati non sono cifrati end-to-end come le chat.

enum StatusKind {
  text('testo'),
  photo('foto'),
  video('video');

  const StatusKind(this.wire);

  final String wire;

  static StatusKind fromWire(String? v) =>
      StatusKind.values.firstWhere((StatusKind k) => k.wire == v, orElse: () => StatusKind.text);
}

/// Chi vede i miei stati.
enum StatusAudience {
  contacts('contatti', 'I miei contatti'),
  except('tranne', 'I miei contatti tranne…'),
  only('solo', 'Solo con…');

  const StatusAudience(this.wire, this.label);

  final String wire;
  final String label;

  static StatusAudience fromWire(String? v) => StatusAudience.values
      .firstWhere((StatusAudience a) => a.wire == v, orElse: () => StatusAudience.contacts);
}

/// Sfondi per gli stati di solo testo.
const List<int> statusColors = <int>[
  0xFF1E88E5, // blu
  0xFF8E24AA, // viola
  0xFFE53935, // rosso
  0xFFF4511E, // arancio
  0xFF43A047, // verde
  0xFF00897B, // verde acqua
  0xFF3949AB, // indaco
  0xFF5D4037, // marrone
];

class StatusItem {
  const StatusItem({
    required this.id,
    required this.userId,
    required this.username,
    required this.publicName,
    required this.kind,
    required this.createdAt,
    required this.expiresAt,
    this.avatarPath,
    this.body = '',
    this.color = 0,
    this.mediaPath,
    this.seen = false,
    this.mine = false,
    this.views = 0,
  });

  final String id;
  final String userId;
  final String username;
  final String publicName;
  final String? avatarPath;
  final StatusKind kind;
  final String body;
  final int color;
  final String? mediaPath;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool seen;
  final bool mine;
  final int views;

  StatusItem copyWith({bool? seen, int? views}) => StatusItem(
    id: id,
    userId: userId,
    username: username,
    publicName: publicName,
    avatarPath: avatarPath,
    kind: kind,
    body: body,
    color: color,
    mediaPath: mediaPath,
    createdAt: createdAt,
    expiresAt: expiresAt,
    seen: seen ?? this.seen,
    mine: mine,
    views: views ?? this.views,
  );
}

/// Gli stati di una persona, dal più vecchio.
class StatusGroup {
  const StatusGroup({required this.userId, required this.name, required this.items, this.avatarPath});

  final String userId;
  final String name;
  final String? avatarPath;
  final List<StatusItem> items;

  bool get allSeen => items.every((StatusItem s) => s.seen);

  DateTime get latest => items.last.createdAt;

  /// Da dove riprendere: il primo non ancora visto.
  int get firstUnseen {
    final int i = items.indexWhere((StatusItem s) => !s.seen);
    return i < 0 ? 0 : i;
  }
}

class StatusViewer {
  const StatusViewer({required this.userId, required this.name, required this.seenAt, this.avatarPath});

  final String userId;
  final String name;
  final String? avatarPath;
  final DateTime seenAt;
}

/// Il server degli stati. Nei test: una versione finta.
abstract class StatusServer {
  Future<List<StatusItem>> feed();

  Future<String> create({
    required StatusKind kind,
    required String body,
    required int color,
    String? mediaPath,
    required StatusAudience audience,
    required List<String> people,
  });

  Future<void> seen(String id);

  Future<List<StatusViewer>> viewers(String id);

  /// Restituisce il file da togliere, se c'era.
  Future<String?> delete(String id);

  /// Cancella i miei stati scaduti; restituisce i file da togliere.
  Future<List<String>> cleanup();

  Future<void> upload(String path, Uint8List bytes, String mime);

  Future<Uint8List> download(String path);

  Future<void> removeFiles(List<String> paths);
}

/// Scelta «chi vede i miei stati», ricordata sul telefono.
abstract class StatusPrefsStore {
  Future<(StatusAudience, List<String>)> load();

  Future<void> save(StatusAudience audience, List<String> people);
}

class MemoryStatusPrefsStore implements StatusPrefsStore {
  StatusAudience audience = StatusAudience.contacts;
  List<String> people = const <String>[];

  @override
  Future<(StatusAudience, List<String>)> load() async => (audience, people);

  @override
  Future<void> save(StatusAudience audience, List<String> people) async {
    this.audience = audience;
    this.people = people;
  }
}

class FileStatusPrefsStore implements StatusPrefsStore {
  FileStatusPrefsStore(this.folder);

  final Future<Directory> folder;

  Future<File> get _file async => File('${(await folder).path}/stati.json');

  @override
  Future<(StatusAudience, List<String>)> load() async {
    try {
      final File f = await _file;
      if (!await f.exists()) return (StatusAudience.contacts, const <String>[]);
      final Map<String, dynamic> j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (
        StatusAudience.fromWire(j['pubblico'] as String?),
        <String>[for (final Object? p in (j['persone'] as List<dynamic>? ?? const <dynamic>[])) '$p'],
      );
    } catch (_) {
      return (StatusAudience.contacts, const <String>[]);
    }
  }

  @override
  Future<void> save(StatusAudience audience, List<String> people) async {
    final File f = await _file;
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(<String, Object>{'pubblico': audience.wire, 'persone': people}));
  }
}

/// Stati dei contatti e i miei: si caricano, si pubblicano, si guardano.
class StatusService extends ChangeNotifier {
  StatusService({
    required this.server,
    required this.myId,
    StatusPrefsStore? prefs,
    this.localName,
    DateTime Function()? clock,
    Random? random,
  }) : prefs = prefs ?? MemoryStatusPrefsStore(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  /// Testo e didascalia: come sul server.
  static const int maxText = 700;

  /// Foto e video: al massimo 16 MB; video al massimo 30 secondi.
  static const int maxBytes = 16 * 1024 * 1024;
  static const Duration maxVideo = Duration(seconds: 30);

  final StatusServer server;
  final String myId;
  final StatusPrefsStore prefs;

  /// Nome come scritto nella rubrica del telefono (Blocco 11).
  final String? Function(String userId)? localName;
  final DateTime Function() _clock;
  final Random _random;

  List<StatusItem> _all = const <StatusItem>[];
  final Map<String, Uint8List> _media = <String, Uint8List>{};
  bool _loaded = false;
  bool _loading = false;
  bool _cleaned = false;
  bool _prefsLoaded = false;
  String? _error;
  StatusAudience _audience = StatusAudience.contacts;
  List<String> _people = const <String>[];

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool get loaded => _loaded;
  bool get loading => _loading;
  String? get error => _error;
  StatusAudience get audience => _audience;
  List<String> get people => _people;

  DateTime get now => _clock();

  List<StatusItem> get _live =>
      <StatusItem>[for (final StatusItem s in _all) if (s.expiresAt.isAfter(now)) s];

  /// I miei stati, dal più vecchio.
  List<StatusItem> get mine => <StatusItem>[for (final StatusItem s in _live) if (s.mine) s]
    ..sort((StatusItem a, StatusItem b) => a.createdAt.compareTo(b.createdAt));

  String nameFor(StatusItem s) {
    final String? local = localName?.call(s.userId);
    if (local != null && local.trim().isNotEmpty) return local;
    if (s.publicName.trim().isNotEmpty) return s.publicName;
    return '@${s.username}';
  }

  List<StatusGroup> _groups({required bool seen}) {
    final Map<String, List<StatusItem>> by = <String, List<StatusItem>>{};
    for (final StatusItem s in _live) {
      if (s.mine) continue;
      by.putIfAbsent(s.userId, () => <StatusItem>[]).add(s);
    }
    final List<StatusGroup> out = <StatusGroup>[
      for (final List<StatusItem> items in by.values)
        StatusGroup(
          userId: items.first.userId,
          name: nameFor(items.first),
          avatarPath: items.first.avatarPath,
          items: items..sort((StatusItem a, StatusItem b) => a.createdAt.compareTo(b.createdAt)),
        ),
    ];
    return <StatusGroup>[for (final StatusGroup g in out) if (g.allSeen == seen) g]
      ..sort((StatusGroup a, StatusGroup b) => b.latest.compareTo(a.latest));
  }

  /// Aggiornamenti non ancora visti, dal più recente.
  List<StatusGroup> get recent => _groups(seen: false);

  /// Aggiornamenti già visti.
  List<StatusGroup> get viewed => _groups(seen: true);

  /// Quante persone hanno stati nuovi (per il segno sulla sezione).
  int get unseenCount => recent.length;

  StatusGroup? get myGroup {
    final List<StatusItem> m = mine;
    if (m.isEmpty) return null;
    return StatusGroup(userId: myId, name: 'Il mio stato', avatarPath: m.first.avatarPath, items: m);
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    final (StatusAudience a, List<String> p) = await prefs.load();
    _audience = a;
    _people = p;
  }

  Future<void>? _current;
  bool _again = false;

  /// Carica gli stati. La prima volta toglie anche i miei scaduti e i loro file. Se un
  /// caricamento è già in corso, se ne fa un altro subito dopo e si aspetta quello.
  Future<void> load() async {
    if (_disposed) return;
    final Future<void>? running = _current;
    if (running != null) {
      _again = true;
      return running;
    }
    final Future<void> next = _loadLoop();
    _current = next;
    try {
      await next;
    } finally {
      _current = null;
    }
  }

  Future<void> _loadLoop() async {
    do {
      _again = false;
      await _loadOnce();
    } while (_again && !_disposed);
  }

  Future<void> _loadOnce() async {
    _loading = true;
    _notify();
    try {
      await _loadPrefs();
      if (!_cleaned) {
        _cleaned = true;
        try {
          final List<String> files = await server.cleanup();
          if (files.isNotEmpty) await server.removeFiles(files);
        } catch (_) {
          // Si riprova al prossimo avvio.
          _cleaned = false;
        }
      }
      _all = await server.feed();
      _loaded = true;
      _error = null;
    } on ChatFailure catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Connessione assente. Riprova tra poco.';
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> setAudience(StatusAudience audience, List<String> people) async {
    _audience = audience;
    _people = audience == StatusAudience.contacts ? const <String>[] : List<String>.unmodifiable(people);
    _prefsLoaded = true;
    _notify();
    await prefs.save(_audience, _people);
  }

  void _checkAudience() {
    if (_audience == StatusAudience.only && _people.isEmpty) {
      throw const ChatFailure('Scegli almeno una persona che può vedere lo stato.');
    }
  }

  Future<void> postText(String text, int color) async {
    await _loadPrefs();
    final String body = text.trim();
    if (body.isEmpty) throw const ChatFailure('Scrivi qualcosa.');
    if (body.length > maxText) throw const ChatFailure('Testo troppo lungo: al massimo 700 caratteri.');
    _checkAudience();
    await server.create(
      kind: StatusKind.text,
      body: body,
      color: color.clamp(0, statusColors.length - 1),
      audience: _audience,
      people: _people,
    );
    await load();
  }

  /// Foto (JPEG) o video (MP4) con didascalia facoltativa.
  Future<void> postMedia({required StatusKind kind, required Uint8List bytes, String caption = ''}) async {
    await _loadPrefs();
    if (kind == StatusKind.text) throw ArgumentError('usa postText');
    if (bytes.length > maxBytes) {
      throw const ChatFailure('File troppo pesante: per gli stati al massimo 16 MB.');
    }
    if (caption.trim().length > maxText) {
      throw const ChatFailure('Didascalia troppo lunga: al massimo 700 caratteri.');
    }
    _checkAudience();
    final String name = List<String>.generate(20, (_) => _random.nextInt(36).toRadixString(36)).join();
    final bool photo = kind == StatusKind.photo;
    final String path = '$myId/$name.${photo ? 'jpg' : 'mp4'}';
    await server.upload(path, bytes, photo ? 'image/jpeg' : 'video/mp4');
    try {
      await server.create(
        kind: kind,
        body: caption.trim(),
        color: 0,
        mediaPath: path,
        audience: _audience,
        people: _people,
      );
    } catch (_) {
      try {
        await server.removeFiles(<String>[path]);
      } catch (_) {}
      rethrow;
    }
    _media[path] = bytes;
    await load();
  }

  /// Guardato: lo sa solo chi l'ha pubblicato.
  Future<void> markSeen(StatusItem s) async {
    if (s.mine || s.seen) return;
    _all = <StatusItem>[for (final StatusItem x in _all) x.id == s.id ? x.copyWith(seen: true) : x];
    _notify();
    try {
      await server.seen(s.id);
    } catch (_) {
      // Non grave: si rivedrà come nuovo al prossimo caricamento.
    }
  }

  Future<List<StatusViewer>> viewers(StatusItem s) async {
    if (!s.mine) return const <StatusViewer>[];
    final List<StatusViewer> list = await server.viewers(s.id);
    return <StatusViewer>[
      for (final StatusViewer v in list)
        StatusViewer(
          userId: v.userId,
          name: (localName?.call(v.userId)?.trim().isNotEmpty ?? false) ? localName!(v.userId)! : v.name,
          avatarPath: v.avatarPath,
          seenAt: v.seenAt,
        ),
    ];
  }

  Future<void> delete(StatusItem s) async {
    if (!s.mine) return;
    final String? path = await server.delete(s.id);
    _all = <StatusItem>[for (final StatusItem x in _all) if (x.id != s.id) x];
    _notify();
    if (path != null) {
      _media.remove(path);
      try {
        await server.removeFiles(<String>[path]);
      } catch (_) {}
    }
  }

  /// Foto o video dello stato (tenuto in memoria finché l'app è aperta).
  Future<Uint8List> media(StatusItem s) async {
    final String? path = s.mediaPath;
    if (path == null) throw const ChatFailure('Questo stato non ha foto.');
    final Uint8List? cached = _media[path];
    if (cached != null) return cached;
    final Uint8List bytes = await server.download(path);
    if (_media.length > 40) _media.remove(_media.keys.first);
    return _media[path] = bytes;
  }
}

/// Stati sul server Supabase (migrazione 0031, bucket privato «stati»).
class SupabaseStatusServer implements StatusServer {
  SupabaseStatusServer(this._client);

  final SupabaseClient _client;

  Future<Object?> _rpc(String name, [Map<String, Object?>? params]) async {
    try {
      return await _client.rpc(name, params: params);
    } on PostgrestException catch (e) {
      if (e.code == '22023' || e.code == '54000') {
        throw ChatFailure(e.message.endsWith('.') ? e.message : '${e.message}.');
      }
      throw const ChatFailure('Non è stato possibile: riprova tra poco.');
    } catch (_) {
      throw const ChatFailure('Connessione assente. Riprova tra poco.');
    }
  }

  static List<Map<String, dynamic>> _rows(Object? r) =>
      <Map<String, dynamic>>[for (final Object? x in (r as List<dynamic>? ?? const <dynamic>[])) x as Map<String, dynamic>];

  static DateTime _time(Object? v) => DateTime.tryParse('$v')?.toLocal() ?? DateTime.now();

  @override
  Future<List<StatusItem>> feed() async => <StatusItem>[
    for (final Map<String, dynamic> r in _rows(await _rpc('status_feed')))
      StatusItem(
        id: '${r['id']}',
        userId: '${r['user_id']}',
        username: '${r['username'] ?? ''}',
        publicName: '${r['public_name'] ?? ''}',
        avatarPath: r['avatar_thumb_path'] as String?,
        kind: StatusKind.fromWire(r['kind'] as String?),
        body: '${r['body'] ?? ''}',
        color: (r['color'] as num?)?.toInt() ?? 0,
        mediaPath: r['media_path'] as String?,
        createdAt: _time(r['created_at']),
        expiresAt: _time(r['expires_at']),
        seen: r['seen'] == true,
        mine: r['mine'] == true,
        views: (r['views'] as num?)?.toInt() ?? 0,
      ),
  ];

  @override
  Future<String> create({
    required StatusKind kind,
    required String body,
    required int color,
    String? mediaPath,
    required StatusAudience audience,
    required List<String> people,
  }) async => '${await _rpc('status_create', <String, Object?>{
    'p_kind': kind.wire,
    'p_body': body,
    'p_color': color,
    'p_media_path': mediaPath,
    'p_audience': audience.wire,
    'p_people': people,
  })}';

  @override
  Future<void> seen(String id) async {
    await _rpc('status_seen', <String, Object?>{'p_id': id});
  }

  @override
  Future<List<StatusViewer>> viewers(String id) async => <StatusViewer>[
    for (final Map<String, dynamic> r in _rows(await _rpc('status_viewers', <String, Object?>{'p_id': id})))
      StatusViewer(
        userId: '${r['user_id']}',
        name: '${r['public_name'] ?? ''}'.trim().isNotEmpty ? '${r['public_name']}' : '@${r['username']}',
        avatarPath: r['avatar_thumb_path'] as String?,
        seenAt: _time(r['seen_at']),
      ),
  ];

  @override
  Future<String?> delete(String id) async {
    final Object? r = await _rpc('status_delete', <String, Object?>{'p_id': id});
    return r is String ? r : null;
  }

  @override
  Future<List<String>> cleanup() async => <String>[
    for (final Map<String, dynamic> r in _rows(await _rpc('status_cleanup')))
      if (r['media_path'] != null) '${r['media_path']}',
  ];

  @override
  Future<void> upload(String path, Uint8List bytes, String mime) async {
    try {
      await _client.storage.from('stati').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    } catch (_) {
      throw const ChatFailure('Caricamento non riuscito: controlla la connessione e riprova.');
    }
  }

  @override
  Future<Uint8List> download(String path) async {
    try {
      return await _client.storage.from('stati').download(path);
    } catch (_) {
      throw const ChatFailure('Questo stato non si può aprire.');
    }
  }

  @override
  Future<void> removeFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    await _client.storage.from('stati').remove(paths);
  }
}

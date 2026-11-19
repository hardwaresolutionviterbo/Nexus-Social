// Server finto degli stati (Blocco 13), con le stesse regole della migrazione 0031:
// lo stato lo vede chi l'autore ha in rubrica, non bloccato, secondo «contatti/tranne/solo».

import 'dart:typed_data';

import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/status/status_service.dart';

import 'fake_chat.dart';

class FakeStatusRow {
  FakeStatusRow({
    required this.id,
    required this.owner,
    required this.kind,
    required this.body,
    required this.color,
    required this.mediaPath,
    required this.audience,
    required this.people,
    required this.at,
  });

  final String id;
  final String owner;
  final StatusKind kind;
  final String body;
  final int color;
  final String? mediaPath;
  final StatusAudience audience;
  final Set<String> people;
  final DateTime at;
  final Map<String, DateTime> views = <String, DateTime>{};

  DateTime get expires => at.add(const Duration(hours: 24));
}

class FakeStatusHub {
  FakeStatusHub(this.chat);

  final FakeChatHub chat;
  final List<FakeStatusRow> rows = <FakeStatusRow>[];
  final Map<String, Uint8List> files = <String, Uint8List>{};
  int _seq = 0;
  bool failCreate = false;

  DateTime get now => chat.clock;

  bool visible(FakeStatusRow s, String viewer) {
    if (s.owner == viewer) return true;
    if (!s.expires.isAfter(now)) return false;
    if (!(chat.contacts[s.owner]?.contains(viewer) ?? false)) return false;
    if (chat.blocked(s.owner, viewer)) return false;
    return switch (s.audience) {
      StatusAudience.contacts => true,
      StatusAudience.except => !s.people.contains(viewer),
      StatusAudience.only => s.people.contains(viewer),
    };
  }

  FakeStatusServer serverFor(String uid) => FakeStatusServer(this, uid);

  StatusService Function(ChatService chat) serviceFor(String uid, {StatusPrefsStore? prefs}) =>
      (ChatService c) => StatusService(
        server: serverFor(uid),
        myId: uid,
        prefs: prefs,
        localName: c.localName,
        clock: () => now,
      );
}

class FakeStatusServer implements StatusServer {
  FakeStatusServer(this.hub, this.uid);

  final FakeStatusHub hub;
  final String uid;

  @override
  Future<List<StatusItem>> feed() async => <StatusItem>[
    for (final FakeStatusRow r in hub.rows)
      if (r.expires.isAfter(hub.now) && hub.visible(r, uid))
        StatusItem(
          id: r.id,
          userId: r.owner,
          username: hub.chat.people[r.owner]!.username,
          publicName: hub.chat.people[r.owner]!.name,
          kind: r.kind,
          body: r.body,
          color: r.color,
          mediaPath: r.mediaPath,
          createdAt: r.at,
          expiresAt: r.expires,
          seen: r.views.containsKey(uid),
          mine: r.owner == uid,
          views: r.owner == uid ? r.views.length : 0,
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
  }) async {
    if (hub.failCreate) throw const ChatFailure('Connessione assente. Riprova tra poco.');
    if (mediaPath != null && !mediaPath.startsWith('$uid/')) throw const ChatFailure('File non valido.');
    if (kind == StatusKind.text && body.trim().isEmpty) throw const ChatFailure('Scrivi qualcosa.');
    if (audience == StatusAudience.only && people.isEmpty) throw const ChatFailure('Scegli almeno una persona.');
    final FakeStatusRow r = FakeStatusRow(
      id: 'stato-${++hub._seq}',
      owner: uid,
      kind: kind,
      body: body,
      color: color,
      mediaPath: mediaPath,
      audience: audience,
      people: audience == StatusAudience.contacts ? <String>{} : people.toSet(),
      // Un secondo dopo l'altro, per l'ordine.
      at: hub.now.add(Duration(seconds: hub._seq)),
    );
    hub.rows.add(r);
    return r.id;
  }

  @override
  Future<void> seen(String id) async {
    final FakeStatusRow r = hub.rows.firstWhere((FakeStatusRow x) => x.id == id);
    if (!hub.visible(r, uid)) throw const ChatFailure('Stato non trovato.');
    if (r.owner != uid) r.views.putIfAbsent(uid, () => hub.now);
  }

  @override
  Future<List<StatusViewer>> viewers(String id) async {
    final FakeStatusRow r = hub.rows.firstWhere((FakeStatusRow x) => x.id == id);
    if (r.owner != uid) return const <StatusViewer>[];
    return <StatusViewer>[
      for (final MapEntry<String, DateTime> v in r.views.entries)
        StatusViewer(userId: v.key, name: hub.chat.people[v.key]!.name, seenAt: v.value),
    ];
  }

  @override
  Future<String?> delete(String id) async {
    final int i = hub.rows.indexWhere((FakeStatusRow x) => x.id == id && x.owner == uid);
    if (i < 0) return null;
    return hub.rows.removeAt(i).mediaPath;
  }

  @override
  Future<List<String>> cleanup() async {
    final List<FakeStatusRow> old = <FakeStatusRow>[
      for (final FakeStatusRow r in hub.rows)
        if (r.owner == uid && !r.expires.isAfter(hub.now)) r,
    ];
    hub.rows.removeWhere(old.contains);
    return <String>[for (final FakeStatusRow r in old) if (r.mediaPath != null) r.mediaPath!];
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String mime) async {
    if (!path.startsWith('$uid/')) throw const ChatFailure('Caricamento non riuscito.');
    hub.files[path] = bytes;
  }

  @override
  Future<Uint8List> download(String path) async {
    final FakeStatusRow? r = hub.rows.where((FakeStatusRow x) => x.mediaPath == path).firstOrNull;
    final Uint8List? f = hub.files[path];
    if (r == null || f == null || !hub.visible(r, uid)) throw const ChatFailure('Questo stato non si può aprire.');
    return f;
  }

  @override
  Future<void> removeFiles(List<String> paths) async {
    for (final String p in paths) {
      if (p.startsWith('$uid/')) hub.files.remove(p);
    }
  }
}

// Server della chat in memoria, con le stesse regole delle migrazioni 0019–0021, e una
// «cifratura» finta per i test di interfaccia (i test del motore usano MLS vero).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' show Widget;
import 'package:nexus_social/features/calls/call_service.dart';
import 'package:nexus_social/features/chat/chat_backup.dart';
import 'package:nexus_social/features/chat/chat_crypto.dart';
import 'package:nexus_social/features/chat/chat_media.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_server.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_store.dart';

class FakeConv {
  FakeConv(this.id, this.a, this.b, this.createdAt, {this.group = false, this.title = ''});
  final String id;
  final String a;
  final String b;
  final DateTime createdAt;
  final bool group;
  String title;
  String description = '';
  int photoVersion = 0;
  int generation = 0;
  String? groupId;
  int? lastId;
  DateTime? lastAt;
  final Map<String, String> status = <String, String>{};
  final Map<String, String?> joined = <String, String?>{};
  final Map<String, int> delivered = <String, int>{};
  final Map<String, int> read = <String, int>{};
  // Gruppi (migrazione 0021).
  final Map<String, String> role = <String, String>{};
  final Map<String, String> mls = <String, String>{};
  final Map<String, int> fromId = <String, int>{};
  final Map<String, String> invitedBy = <String, String>{};
  final Map<String, DateTime?> muted = <String, DateTime?>{};
  String other(String uid) => uid == a ? b : a;
  bool has(String uid) => group ? status.containsKey(uid) : (uid == a || uid == b);
  Iterable<String> inside() => status.keys.where((u) => status[u] == 'active' && mls[u] == 'in');
}

class FakeMsg {
  FakeMsg(this.id, this.conv, this.generation, this.sender, this.welcomeFor, this.payload, this.at,
      {String? kind})
    : kind = kind ?? (welcomeFor != null ? 'welcome' : 'app');
  final int id;
  final String conv;
  final int generation;
  final String sender;
  final String? welcomeFor;
  final String payload;
  final DateTime at;
  final String kind;
}

class FakePerson {
  const FakePerson(this.id, this.username, this.name);
  final String id;
  final String username;
  final String name;
}

/// Contenitore degli allegati in memoria, condiviso dai telefoni finti.
class FakeMediaServer implements ChatMediaServer {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<void> upload(String path, Uint8List bytes) async => files[path] = Uint8List.fromList(bytes);

  @override
  Future<Uint8List> download(String path) async {
    final Uint8List? f = files[path];
    if (f == null) throw const ChatFailure('Allegato non più disponibile sul server.');
    return f;
  }

  @override
  Future<void> remove(String path) async => files.remove(path);

  final Map<String, Uint8List> groupPhotos = <String, Uint8List>{};

  @override
  Future<void> uploadGroupPhoto(String conversationId, Uint8List jpeg) async =>
      groupPhotos[conversationId] = jpeg;

  @override
  Future<Uint8List?> downloadGroupPhoto(String conversationId) async => groupPhotos[conversationId];
}

/// Il «database» condiviso dai telefoni finti.
class FakeChatHub {
  final FakeMediaServer media = FakeMediaServer();

  final Map<String, FakePerson> people = <String, FakePerson>{};
  final Map<String, String> identities = <String, String>{};
  final Map<String, List<String>> packages = <String, List<String>>{};
  final List<FakeConv> convs = <FakeConv>[];
  final List<FakeMsg> messages = <FakeMsg>[];

  /// owner → persone che ha in rubrica.
  final Map<String, Set<String>> contacts = <String, Set<String>>{};
  final Set<String> blocks = <String>{};

  /// Tempo reale finto (Blocco 9): spento di base, i test lo accendono.
  bool live = false;
  final Map<String, StreamController<void>> _pokes = <String, StreamController<void>>{};

  Stream<void> pokes(String uid) => (_pokes[uid] ??= StreamController<void>.broadcast()).stream;

  /// «C'è qualcosa di nuovo» per [uid], come il database con Supabase Realtime.
  void poke(String uid) {
    if (live) _pokes[uid]?.add(null);
  }

  /// Squilli (chi chiama, chat, video): sul server vero fanno partire la notifica.
  final List<(String, String, bool)> rings = <(String, String, bool)>[];

  /// Segnalazioni ricevute (chi, chat, motivo, descrizione, messaggi scelti).
  final List<(String, String, String, String, List<Map<String, String>>)> reports =
      <(String, String, String, String, List<Map<String, String>>)>[];
  int _seq = 0;
  int _conv = 0;

  /// Codici d'invito ai gruppi → gruppo.
  final Map<String, String> invites = <String, String>{};

  String newId() => '00000000-0000-4000-8000-${(++_conv).toString().padLeft(12, '0')}';
  // Un'ora fa: «elimina per tutti» (48 ore) confronta l'ora vera con quella del server.
  DateTime clock = DateTime.now().subtract(const Duration(hours: 1));

  void addPerson(String id, String username, String name) =>
      people[id] = FakePerson(id, username, name);

  bool blocked(String x, String y) => blocks.contains('$x>$y') || blocks.contains('$y>$x');

  /// Messaggi ancora sul server (dopo la consegna spariscono).
  int get storedMessages => messages.length;

  /// Tutto ciò che il server ha visto: deve essere solo base64 illeggibile.
  Iterable<String> get payloads => messages.map((m) => m.payload);

  FakeChatServer serverFor(String uid) => FakeChatServer(this, uid);
}

class FakeChatServer implements ChatServer {
  FakeChatServer(this.hub, this.uid);

  final FakeChatHub hub;
  final String uid;

  FakeConv _member(String id) {
    final FakeConv? c = hub.convs.where((c) => c.id == id && c.has(uid)).firstOrNull;
    if (c == null) throw const ChatFailure('Questa chat non è disponibile.');
    return c;
  }

  FakeConv _group(String id, {bool admin = false}) {
    final FakeConv c = _member(id);
    if (!c.group || c.status[uid] != 'active') throw const ChatFailure('Non fai più parte di questo gruppo.');
    if (admin && c.role[uid] != 'admin') throw const ChatFailure('Solo gli amministratori del gruppo possono farlo.');
    return c;
  }

  int _push(FakeMsg Function(int id) make) {
    final FakeMsg m = make(++hub._seq);
    hub.messages.add(m);
    return m.id;
  }

  void _event(FakeConv c, Map<String, Object?> ev) => _push((int id) => FakeMsg(
    id, c.id, c.generation, uid, null, base64Encode(utf8.encode(jsonEncode(ev))), hub.clock, kind: 'event'));

  @override
  Future<String?> myIdentity() async => hub.identities[uid];

  @override
  Future<void> registerIdentity(String signatureKey, List<String> packages) async {
    if (hub.identities[uid] != signatureKey) {
      hub.identities[uid] = signatureKey;
      hub.packages[uid] = <String>[];
      for (final FakeConv c in hub.convs.where((c) => c.group && c.status[uid] == 'active')) {
        if (c.mls[uid] == 'in') c.mls[uid] = 'to_readd';
      }
    }
    await addKeyPackages(packages);
  }

  @override
  Future<int> addKeyPackages(List<String> packages) async {
    (hub.packages[uid] ??= <String>[]).addAll(packages);
    return hub.packages[uid]!.length;
  }

  @override
  Future<int> keyPackageCount() async => hub.packages[uid]?.length ?? 0;

  @override
  Future<String> openDirect(String userId) async {
    if (userId == uid || !hub.people.containsKey(userId) || hub.blocked(uid, userId)) {
      throw const ChatFailure('Persona non trovata.');
    }
    final FakeConv? found = hub.convs
        .where((c) => !c.group && ((c.a == uid && c.b == userId) || (c.a == userId && c.b == uid)))
        .firstOrNull;
    if (found != null) {
      found.status[uid] = 'active';
      return found.id;
    }
    if (!hub.identities.containsKey(userId)) {
      throw const ChatFailure('Questa persona non ha ancora attivato la chat.');
    }
    final FakeConv c = FakeConv(hub.newId(), uid, userId, hub.clock);
    c.status[uid] = 'active';
    c.status[userId] = (hub.contacts[userId] ?? const <String>{}).contains(uid) ? 'active' : 'request';
    for (final String p in <String>[uid, userId]) {
      c.delivered[p] = 0;
      c.read[p] = 0;
    }
    hub.convs.add(c);
    return c.id;
  }

  @override
  Future<ClaimedKeyPackage> claimKeyPackage(String conversationId) async {
    final FakeConv c = _member(conversationId);
    if (c.group) throw const ChatFailure('Non è una chat a due.');
    final String other = c.other(uid);
    final List<String> list = hub.packages[other] ?? <String>[];
    if (list.isEmpty) throw const ChatFailure('L\'altra persona deve aprire l\'app.');
    return ClaimedKeyPackage(list.removeAt(0), hub.identities[other]!);
  }

  @override
  Future<int> start(String conversationId, int generation, String groupId, String welcome) async {
    final FakeConv c = _member(conversationId);
    if (c.group) throw const ChatFailure('Non è una chat a due.');
    if (c.generation != generation) {
      throw const ChatFailure('La chat è appena cambiata: riprova.', conflict: true);
    }
    c.generation++;
    c.groupId = groupId;
    hub.messages.removeWhere((m) => m.conv == c.id);
    _push((int id) => FakeMsg(id, c.id, c.generation, uid, c.other(uid), welcome, hub.clock));
    for (final String p in <String>[c.a, c.b]) {
      c.joined[p] = hub.identities[p];
    }
    return c.generation;
  }

  @override
  Future<(int, DateTime)> send(String conversationId, int generation, String payload) async {
    final FakeConv c = _member(conversationId);
    if (c.group) {
      if (c.status[uid] != 'active' || c.mls[uid] != 'in') {
        throw const ChatFailure('Non fai più parte di questo gruppo.');
      }
    } else if (hub.blocked(uid, c.other(uid))) {
      throw const ChatFailure('Non puoi scrivere.');
    }
    if (c.generation == 0 || c.generation != generation) {
      throw const ChatFailure('La chat è appena cambiata: riprova.', conflict: true);
    }
    if (!c.group) c.status[uid] = 'active';
    hub.clock = hub.clock.add(const Duration(minutes: 1));
    final int id = _push((int id) => FakeMsg(id, c.id, generation, uid, null, payload, hub.clock));
    c.lastId = id;
    c.lastAt = hub.clock;
    for (final String u in c.status.keys.where((String u) => u != uid)) {
      hub.poke(u);
    }
    return (id, hub.clock);
  }

  @override
  bool get live => hub.live;

  @override
  Stream<void> wakeUps(String uid) => hub.pokes(uid);

  @override
  Future<(int, DateTime)> callSignal(String conversationId, int generation, String payload,
      {required bool ring, required bool video}) async {
    final FakeConv c = _member(conversationId);
    if (c.group || c.status[uid] != 'active' || c.status[c.other(uid)] != 'active' || hub.blocked(uid, c.other(uid))) {
      throw const ChatFailure('Chiamata non possibile in questa chat.');
    }
    if (ring) hub.rings.add((uid, conversationId, video));
    return send(conversationId, generation, payload);
  }

  bool _visible(FakeMsg m, FakeConv c) {
    if (!c.group) {
      return m.sender != uid &&
          c.status[uid] != 'declined' &&
          (m.welcomeFor == null || m.welcomeFor == uid) &&
          !hub.blocked(uid, m.sender);
    }
    if (c.status[uid] != 'active') return false;
    if (m.welcomeFor != null) return m.welcomeFor == uid;
    if (c.mls[uid] != 'in' || m.id <= (c.fromId[uid] ?? 0)) return false;
    return m.kind == 'event' || m.sender != uid;
  }

  @override
  Future<List<ChatEnvelope>> sync(int after) async => <ChatEnvelope>[
    for (final FakeMsg m in hub.messages)
      if (m.id > after)
        if (hub.convs.where((c) => c.id == m.conv && c.has(uid)).firstOrNull case final FakeConv c)
          if (_visible(m, c))
            ChatEnvelope(
              id: m.id,
              conversationId: m.conv,
              generation: m.generation,
              senderId: m.sender,
              kind: m.kind,
              payload: m.payload,
              createdAt: m.at,
            ),
  ];

  int _min(FakeConv c, Map<String, int> map) {
    final List<int> v = <int>[for (final String u in c.inside()) if (u != uid) map[u] ?? 0];
    return v.isEmpty ? 0 : v.reduce((a, b) => a < b ? a : b);
  }

  @override
  Future<List<ChatConversation>> conversations() async => <ChatConversation>[
    for (final FakeConv c in hub.convs)
      if (c.group && (c.status[uid] == 'active' || c.status[uid] == 'request'))
        ChatConversation(
          id: c.id,
          status: c.status[uid] == 'request' ? ChatStatus.request : ChatStatus.active,
          generation: c.generation,
          groupId: c.groupId,
          peerId: '',
          peerUsername: '',
          peerName: '',
          myJoinedKey: c.joined[uid],
          peerDeliveredUpto: _min(c, c.delivered),
          peerReadUpto: _min(c, c.read),
          myReadUpto: c.read[uid] ?? 0,
          lastMessageId: c.lastId,
          lastMessageAt: c.lastAt,
          createdAt: c.createdAt,
          isGroup: true,
          title: c.title,
          description: c.description,
          photoVersion: c.photoVersion,
          myRole: c.role[uid] ?? 'member',
          myMlsState: c.mls[uid] ?? 'in',
          members: c.status.values.where((s) => s == 'active').length,
          pending: c.status.keys
              .where((u) =>
                  (c.status[u] == 'active' && (c.mls[u] == 'to_add' || c.mls[u] == 'to_readd')) ||
                  c.mls[u] == 'to_remove')
              .length,
          invitedBy: c.invitedBy[uid],
          mutedUntil: c.muted[uid],
        )
      else if (!c.group && c.has(uid) && c.status[uid] != 'declined' && !hub.blocked(c.a, c.b))
        ChatConversation(
          id: c.id,
          status: c.status[uid] == 'request' ? ChatStatus.request : ChatStatus.active,
          generation: c.generation,
          groupId: c.groupId,
          peerId: c.other(uid),
          peerUsername: hub.people[c.other(uid)]!.username,
          peerName: hub.people[c.other(uid)]!.name,
          peerSignatureKey: hub.identities[c.other(uid)],
          peerJoinedKey: c.joined[c.other(uid)],
          myJoinedKey: c.joined[uid],
          peerDeliveredUpto: c.status[c.other(uid)] == 'active' ? c.delivered[c.other(uid)]! : 0,
          peerReadUpto: c.status[c.other(uid)] == 'active' ? c.read[c.other(uid)]! : 0,
          myReadUpto: c.read[uid]!,
          lastMessageId: c.lastId,
          lastMessageAt: c.lastAt,
          createdAt: c.createdAt,
          mutedUntil: c.muted[uid],
        ),
  ];

  @override
  Future<void> mark(String conversationId, {required int delivered, required int read}) async {
    final FakeConv c = _member(conversationId);
    final int last = hub.messages
        .where((m) => m.conv == c.id && (m.welcomeFor == null || m.welcomeFor == uid))
        .fold<int>(c.lastId ?? 0, (n, m) => m.id > n ? m.id : n);
    int d = delivered > last ? last : delivered;
    int r = read > last ? last : read;
    d = d > (c.delivered[uid] ?? 0) ? d : (c.delivered[uid] ?? 0);
    r = r > (c.read[uid] ?? 0) ? r : (c.read[uid] ?? 0);
    if (r > d) d = r;
    c.delivered[uid] = d;
    c.read[uid] = r;
    if (!c.group) {
      hub.messages.removeWhere((m) =>
          m.conv == c.id && m.sender != uid && m.id <= d && (m.welcomeFor == null || m.welcomeFor == uid));
      return;
    }
    hub.messages.removeWhere((m) => m.conv == c.id && m.welcomeFor == uid && m.id <= d);
    hub.messages.removeWhere((m) =>
        m.conv == c.id &&
        m.welcomeFor == null &&
        m.id <= d &&
        !c.inside().any((u) =>
            (u != m.sender || m.kind == 'event') && (c.fromId[u] ?? 0) < m.id && (c.delivered[u] ?? 0) < m.id));
  }

  @override
  Future<void> respondRequest(String conversationId, bool accept) async {
    final FakeConv c = _member(conversationId);
    if (c.status[uid] != 'request') throw const ChatFailure('Non è una richiesta in attesa.');
    if (c.group) {
      if (accept) {
        c.status[uid] = 'active';
        c.mls[uid] = 'to_add';
        _event(c, <String, Object?>{'t': 'joined', 'by': uid});
      } else {
        c.status.remove(uid);
      }
      return;
    }
    c.status[uid] = accept ? 'active' : 'declined';
    if (!accept) hub.messages.removeWhere((m) => m.conv == c.id && m.sender != uid);
  }

  // ---- gruppi

  String? _put(FakeConv c, String user) {
    if (user == uid || !hub.people.containsKey(user) || hub.blocked(uid, user)) return null;
    if (c.status[user] == 'active' || c.status[user] == 'request') return null;
    if (!hub.identities.containsKey(user)) return null;
    final String status = (hub.contacts[user] ?? const <String>{}).contains(uid) ? 'active' : 'request';
    final String? before = c.mls[user];
    c.status[user] = status;
    c.role[user] = 'member';
    c.mls[user] = before == 'to_remove' || before == 'to_readd' ? 'to_readd' : 'to_add';
    c.invitedBy[user] = uid;
    c.delivered[user] = 0;
    c.read[user] = 0;
    return status;
  }

  @override
  Future<String> createGroup(String title, List<String> members) async {
    if (title.trim().isEmpty || title.trim().length > 60) {
      throw const ChatFailure('Il nome del gruppo deve avere da 1 a 60 caratteri.');
    }
    final FakeConv c = FakeConv(hub.newId(), '', '', hub.clock, group: true, title: title.trim());
    hub.convs.add(c);
    c.status[uid] = 'active';
    c.role[uid] = 'admin';
    c.mls[uid] = 'in';
    c.delivered[uid] = 0;
    c.read[uid] = 0;
    final List<String> added = <String>[], invited = <String>[];
    for (final String u in members) {
      final String? st = _put(c, u);
      if (st == 'active') added.add(u);
      if (st == 'request') invited.add(u);
    }
    _event(c, <String, Object?>{'t': 'created', 'by': uid, 'added': added, 'invited': invited});
    return c.id;
  }

  @override
  Future<int> groupAdd(String conversationId, List<String> members) async {
    final FakeConv c = _group(conversationId, admin: true);
    final List<String> added = <String>[], invited = <String>[];
    for (final String u in members) {
      final String? st = _put(c, u);
      if (st == 'active') added.add(u);
      if (st == 'request') invited.add(u);
    }
    if (added.isNotEmpty || invited.isNotEmpty) {
      _event(c, <String, Object?>{'t': 'added', 'by': uid, 'added': added, 'invited': invited});
    }
    return added.length + invited.length;
  }

  @override
  Future<void> groupRemove(String conversationId, String userId) async {
    final bool self = userId == uid;
    final FakeConv c = _group(conversationId, admin: !self);
    final String? st = c.status[userId];
    if (st != 'active' && st != 'request') throw const ChatFailure('Non fa parte del gruppo.');
    final bool wasAdmin = c.role[userId] == 'admin';
    if (c.mls[userId] == 'to_add') {
      c.status.remove(userId);
      c.mls.remove(userId);
    } else {
      c.status[userId] = 'left';
      c.mls[userId] = 'to_remove';
    }
    c.role[userId] = 'member';
    if (wasAdmin && !c.status.keys.any((u) => c.status[u] == 'active' && c.role[u] == 'admin')) {
      final String? next = c.status.keys.where((u) => c.status[u] == 'active').firstOrNull;
      if (next != null) c.role[next] = 'admin';
    }
    if (st == 'active') _event(c, <String, Object?>{'t': self ? 'left' : 'removed', 'by': uid, 'who': userId});
  }

  @override
  Future<void> groupSetAdmin(String conversationId, String userId, bool admin) async {
    final FakeConv c = _group(conversationId, admin: true);
    if (c.status[userId] != 'active') throw const ChatFailure('Non fa parte del gruppo.');
    if (!admin && c.role[userId] == 'admin' &&
        c.status.keys.where((u) => c.status[u] == 'active' && c.role[u] == 'admin').length <= 1) {
      throw const ChatFailure('Il gruppo deve avere almeno un amministratore.');
    }
    c.role[userId] = admin ? 'admin' : 'member';
    _event(c, <String, Object?>{'t': admin ? 'admin' : 'not_admin', 'by': uid, 'who': userId});
  }

  @override
  Future<void> groupUpdate(String conversationId, String title, String description,
      {bool photoChanged = false}) async {
    final FakeConv c = _group(conversationId, admin: true);
    final bool renamed = c.title != title;
    c.title = title;
    c.description = description;
    if (photoChanged) c.photoVersion++;
    if (renamed) _event(c, <String, Object?>{'t': 'title', 'by': uid, 'title': title});
    if (photoChanged) _event(c, <String, Object?>{'t': 'photo', 'by': uid});
  }

  @override
  Future<String> groupInviteCode(String conversationId, {bool renew = false}) async {
    final FakeConv c = _group(conversationId, admin: true);
    if (renew) hub.invites.removeWhere((_, v) => v == c.id);
    final String? code = hub.invites.entries.where((e) => e.value == c.id).firstOrNull?.key;
    if (code != null) return code;
    final String fresh = 'CODICE${(hub.invites.length + 1000).toString().padLeft(4, '0')}';
    hub.invites[fresh] = c.id;
    return fresh;
  }

  @override
  Future<void> groupInviteRevoke(String conversationId) async {
    final FakeConv c = _group(conversationId, admin: true);
    hub.invites.removeWhere((_, v) => v == c.id);
  }

  @override
  Future<GroupInviteInfo> groupInviteInfo(String code) async {
    final String? id = hub.invites[code];
    final FakeConv? c = hub.convs.where((c) => c.id == id).firstOrNull;
    if (c == null) throw const ChatFailure('Codice non valido o scaduto.');
    return GroupInviteInfo(
      conversationId: c.id,
      title: c.title,
      members: c.status.values.where((s) => s == 'active' || s == 'request').length,
      alreadyMember: c.status[uid] == 'active',
    );
  }

  @override
  Future<String> groupJoin(String code) async {
    final String? id = hub.invites[code];
    final FakeConv? c = hub.convs.where((c) => c.id == id).firstOrNull;
    if (c == null) throw const ChatFailure('Codice non valido o scaduto.');
    if (c.status[uid] == 'active') return c.id;
    final String? before = c.mls[uid];
    c.status[uid] = 'active';
    c.role[uid] = 'member';
    c.mls[uid] = before == 'to_remove' || before == 'to_readd' ? 'to_readd' : 'to_add';
    c.delivered[uid] = 0;
    c.read[uid] = 0;
    _event(c, <String, Object?>{'t': 'joined', 'by': uid});
    return c.id;
  }

  @override
  Future<List<GroupMember>> groupMembers(String conversationId) async {
    final FakeConv c = _member(conversationId);
    if (!c.group || (c.status[uid] != 'active' && c.status[uid] != 'request')) {
      throw const ChatFailure('Gruppo non trovato.');
    }
    return <GroupMember>[
      for (final String u in c.status.keys)
        if (c.status[u] == 'active' || c.status[u] == 'request' || c.mls[u] == 'to_remove')
          GroupMember(
            userId: u,
            username: hub.people[u]!.username,
            name: hub.people[u]!.name,
            role: c.role[u] ?? 'member',
            status: c.status[u]!,
            mlsState: c.mls[u] ?? 'in',
            signatureKey: hub.identities[u],
            joinedKey: c.joined[u],
          ),
    ];
  }

  @override
  Future<ClaimedKeyPackage> groupClaimKeyPackage(String conversationId, String userId) async {
    final FakeConv c = _group(conversationId, admin: true);
    if (c.status[userId] != 'active' || (c.mls[userId] != 'to_add' && c.mls[userId] != 'to_readd')) {
      throw const ChatFailure('Questa persona non va aggiunta.');
    }
    final List<String> list = hub.packages[userId] ?? <String>[];
    if (list.isEmpty) throw const ChatFailure('Un membro deve aprire l\'app.');
    return ClaimedKeyPackage(list.removeAt(0), hub.identities[userId]!);
  }

  @override
  Future<int> groupCommit(
    String conversationId,
    int generation, {
    required String groupId,
    String? commit,
    String? welcome,
    List<String> added = const <String>[],
    List<String> removed = const <String>[],
  }) async {
    final FakeConv c = _group(conversationId, admin: true);
    if (c.generation != generation) {
      throw const ChatFailure('Il gruppo è appena cambiato: riprova.', conflict: true);
    }
    if ((generation == 0) != (commit == null)) throw const ChatFailure('Modifica non valida.');
    if (added.isNotEmpty != (welcome != null)) throw const ChatFailure('Invito mancante.');
    for (final String u in added) {
      if (c.status[u] != 'active' || (c.mls[u] != 'to_add' && c.mls[u] != 'to_readd')) {
        throw const ChatFailure('Persona da aggiungere non valida.');
      }
    }
    for (final String u in removed) {
      if (c.mls[u] != 'to_remove' && c.mls[u] != 'to_readd') {
        throw const ChatFailure('Persona da togliere non valida.');
      }
    }
    final int next = generation + 1;
    int commitId = 0;
    if (commit != null) {
      commitId = _push((int id) => FakeMsg(id, c.id, generation, uid, null, commit, hub.clock, kind: 'commit'));
    }
    if (welcome != null) {
      for (final String u in added) {
        _push((int id) => FakeMsg(id, c.id, next, uid, u, welcome, hub.clock));
      }
    }
    c.generation = next;
    c.groupId = groupId;
    for (final String u in added) {
      c.mls[u] = 'in';
      c.fromId[u] = commitId;
      c.delivered[u] = commitId;
      c.read[u] = commitId;
      c.joined[u] = hub.identities[u];
    }
    for (final String u in removed) {
      if (c.mls[u] == 'to_remove') {
        c.status.remove(u);
        c.mls.remove(u);
      } else if (c.mls[u] == 'to_readd' && !added.contains(u)) {
        c.mls[u] = 'to_add';
      }
    }
    if (generation == 0) c.joined[uid] = hub.identities[uid];
    return next;
  }

  @override
  Future<void> report(String conversationId, String reason, String details, List<Map<String, String>> messages) async {
    _member(conversationId);
    if (messages.length > 50) throw const ChatFailure('Al massimo 50 messaggi.');
    hub.reports.add((uid, conversationId, reason, details, messages));
  }

  @override
  Future<void> blockUser(String userId) async => hub.blocks.add('$uid>$userId');

  @override
  Future<void> setMute(String conversationId, String? until) async {
    final FakeConv c = _member(conversationId);
    c.muted[uid] = until == null ? null : (until == 'infinity' ? DateTime(9999) : DateTime.parse(until).toLocal());
  }

  @override
  Future<void> groupRejoin(String conversationId) async {
    final FakeConv c = _group(conversationId);
    if (c.mls[uid] == 'in') c.mls[uid] = 'to_readd';
  }
}

/// «Cifratura» finta per i test di interfaccia: base64 con un prefisso, nessun MLS.
class FakeChatCrypto implements ChatCrypto {
  FakeChatCrypto(this.uid, {this.key = 'chiave'});

  final String uid;
  final String key;
  int _groups = 0;

  @override
  Future<ChatIdentity> ensureIdentity() async =>
      ChatIdentity(base64Encode(utf8.encode('$uid:$key')), isNew: false);

  @override
  Future<List<String>> newKeyPackages(int count) async =>
      <String>[for (int i = 0; i < count; i++) base64Encode(utf8.encode('kp:$uid:$i'))];

  @override
  Future<StartedGroup> startGroup({
    required String peerId,
    required String peerPackage,
    required String peerSignatureKey,
  }) async {
    final String g = base64Encode(utf8.encode('g:$uid:${++_groups}'));
    return StartedGroup(g, base64Encode(utf8.encode('w:$g')));
  }

  @override
  Future<String> joinGroup(String welcome, {required String peerId}) async =>
      utf8.decode(base64Decode(welcome)).substring(2);

  @override
  Future<String> encrypt(String groupId, List<int> plain) async => base64Encode(plain);

  @override
  Future<List<int>?> decrypt(String groupId, String payload) async => base64Decode(payload);

  @override
  Future<void> dropGroup(String groupId) async {}

  final Map<String, Map<String, Set<String>>> _roster = <String, Map<String, Set<String>>>{};

  @override
  Future<String> createGroupAlone() async {
    final String g = base64Encode(utf8.encode('g:$uid:${++_groups}'));
    _roster[g] = <String, Set<String>>{uid: <String>{base64Encode(utf8.encode('$uid:$key'))}};
    return g;
  }

  @override
  Future<(String, String)> addToGroup(String groupId, List<GroupJoiner> joiners) async {
    for (final GroupJoiner j in joiners) {
      ((_roster[groupId] ??= <String, Set<String>>{})[j.userId] ??= <String>{}).add(j.signatureKey);
    }
    return (base64Encode(utf8.encode('c:$groupId')), base64Encode(utf8.encode('w:$groupId')));
  }

  @override
  Future<String?> removeFromGroup(String groupId, List<GroupLeaver> leavers) async =>
      leavers.isEmpty ? null : base64Encode(utf8.encode('r:$groupId'));

  @override
  Future<void> confirmCommit(String groupId) async {}

  @override
  Future<void> discardCommit(String groupId) async {}

  @override
  Future<bool> applyCommit(String groupId, String payload) async => true;

  @override
  Future<Map<String, Set<String>>> roster(String groupId) async =>
      _roster[groupId] ?? <String, Set<String>>{};
}

/// Telefono finto pronto all'uso (cifratura finta, messaggi in memoria, nessun timer utile).
Future<ChatService> fakePhone(
  FakeChatHub hub,
  String uid, {
  String key = 'chiave',
  Directory? files,
  BackupServer? backup,
  BackupKeyStore? backupKeys,
  CallService Function(ChatService chat)? calls,
}) async {
  final ChatService s = ChatService(
    calls: calls,
    clock: () => hub.clock,
    backupServer: backup,
    backupKeys: backup == null ? null : (backupKeys ?? MemoryBackupKeyStore()),
    backupKdf: fastKdfForTests(),
    media: hub.media,
    files: files == null ? null : ChatMediaFiles(Future<Directory>.value(files)),
    server: hub.serverFor(uid),
    crypto: () async => FakeChatCrypto(uid, key: key),
    store: MemoryChatStore(),
    myId: uid,
    contactsLoader: () async => <ChatContact>[
      for (final String id in hub.contacts[uid] ?? const <String>{})
        ChatContact(id: id, name: hub.people[id]!.name, username: hub.people[id]!.username),
    ],
    fastPoll: const Duration(days: 1),
    slowPoll: const Duration(days: 1),
  );
  await s.start();
  return s;
}

/// Server finto del backup (Blocco 6): un file per account, come il bucket `chat-backups`.
class FakeBackupServer implements BackupServer {
  FakeBackupServer({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;
  Uint8List? file;
  DateTime? at;
  int uploads = 0;
  bool offline = false;

  @override
  Future<BackupInfo?> info() async {
    if (offline) throw Exception('rete');
    final Uint8List? f = file;
    return f == null ? null : BackupInfo(at: at!, size: f.length);
  }

  @override
  Future<void> upload(Uint8List bytes) async {
    if (offline) throw const ChatFailure('Backup non caricato. Riprova.');
    file = Uint8List.fromList(bytes);
    at = now();
    uploads++;
  }

  @override
  Future<Uint8List> download() async {
    final Uint8List? f = file;
    if (f == null || offline) throw const ChatFailure('Backup non scaricato. Controlla la connessione.');
    return f;
  }

  @override
  Future<void> remove() async {
    file = null;
    at = null;
  }
}


/// Audio e video finti (Blocco 8): si «collega» quando arriva la risposta.
class FakeCallMedia implements CallMedia {
  static int opened = 0;
  final StreamController<bool> _up = StreamController<bool>.broadcast();
  bool video = false;
  bool mic = true;
  bool camera = true;
  bool speaker = false;
  bool closed = false;

  @override
  Stream<bool> get connected => _up.stream;

  @override
  Future<void> open({required List<IceServer> ice, required bool video}) async {
    opened++;
    this.video = video;
  }

  @override
  Future<String> createOffer() async => 'v=0 offerta';

  @override
  Future<String> answer(String offer) async {
    scheduleMicrotask(() => _up.isClosed ? null : _up.add(true));
    return 'v=0 risposta a ($offer)';
  }

  @override
  Future<void> acceptAnswer(String answer) async => scheduleMicrotask(() => _up.isClosed ? null : _up.add(true));

  void drop() => _up.add(false);

  @override
  Future<void> setMicrophone(bool on) async => mic = on;

  @override
  Future<void> setCamera(bool on) async => camera = on;

  @override
  Future<void> setSpeaker(bool on) async => speaker = on;

  @override
  Future<void> switchCamera() async {}

  @override
  Widget? remoteView() => null;

  @override
  Widget? localView() => null;

  @override
  Future<void> close() async {
    closed = true;
    await _up.close();
  }
}

class FakeIce implements IceProvider {
  @override
  Future<List<IceServer>> servers() async => const <IceServer>[IceServer(urls: <String>['stun:stun.example.org'])];
}

/// Telefono finto con le chiamate.
CallService Function(ChatService) fakeCalls({Duration ring = const Duration(seconds: 45)}) =>
    (ChatService chat) => CallService(chat: chat, ice: FakeIce(), media: FakeCallMedia.new, ringTimeout: ring);

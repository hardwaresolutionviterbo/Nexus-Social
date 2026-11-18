// Server della chat in memoria, con le stesse regole della migrazione 0019, e una
// «cifratura» finta per i test di interfaccia (i test del motore usano MLS vero).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nexus_social/features/chat/chat_crypto.dart';
import 'package:nexus_social/features/chat/chat_media.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_server.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_store.dart';

class FakeConv {
  FakeConv(this.id, this.a, this.b, this.createdAt);
  final String id;
  final String a;
  final String b;
  final DateTime createdAt;
  int generation = 0;
  String? groupId;
  int? lastId;
  DateTime? lastAt;
  final Map<String, String> status = <String, String>{};
  final Map<String, String?> joined = <String, String?>{};
  final Map<String, int> delivered = <String, int>{};
  final Map<String, int> read = <String, int>{};
  String other(String uid) => uid == a ? b : a;
}

class FakeMsg {
  FakeMsg(this.id, this.conv, this.generation, this.sender, this.welcomeFor, this.payload, this.at);
  final int id;
  final String conv;
  final int generation;
  final String sender;
  final String? welcomeFor;
  final String payload;
  final DateTime at;
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
  int _seq = 0;
  int _conv = 0;
  DateTime clock = DateTime(2026, 11, 16, 18, 30);

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
    final FakeConv? c = hub.convs.where((c) => c.id == id && (c.a == uid || c.b == uid)).firstOrNull;
    if (c == null) throw const ChatFailure('Questa chat non è disponibile.');
    return c;
  }

  @override
  Future<String?> myIdentity() async => hub.identities[uid];

  @override
  Future<void> registerIdentity(String signatureKey, List<String> packages) async {
    if (hub.identities[uid] != signatureKey) {
      hub.identities[uid] = signatureKey;
      hub.packages[uid] = <String>[];
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
        .where((c) => (c.a == uid && c.b == userId) || (c.a == userId && c.b == uid))
        .firstOrNull;
    if (found != null) {
      found.status[uid] = 'active';
      return found.id;
    }
    if (!hub.identities.containsKey(userId)) {
      throw const ChatFailure('Questa persona non ha ancora attivato la chat.');
    }
    final FakeConv c = FakeConv('conv-${++hub._conv}', uid, userId, hub.clock);
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
    final String other = c.other(uid);
    final List<String> list = hub.packages[other] ?? <String>[];
    if (list.isEmpty) throw const ChatFailure('L\'altra persona deve aprire l\'app.');
    return ClaimedKeyPackage(list.removeAt(0), hub.identities[other]!);
  }

  @override
  Future<int> start(String conversationId, int generation, String groupId, String welcome) async {
    final FakeConv c = _member(conversationId);
    if (c.generation != generation) {
      throw const ChatFailure('La chat è appena cambiata: riprova.', conflict: true);
    }
    c.generation++;
    c.groupId = groupId;
    hub.messages.removeWhere((m) => m.conv == c.id);
    hub.messages.add(FakeMsg(++hub._seq, c.id, c.generation, uid, c.other(uid), welcome, hub.clock));
    for (final String p in <String>[c.a, c.b]) {
      c.joined[p] = hub.identities[p];
    }
    return c.generation;
  }

  @override
  Future<(int, DateTime)> send(String conversationId, int generation, String payload) async {
    final FakeConv c = _member(conversationId);
    if (hub.blocked(uid, c.other(uid))) throw const ChatFailure('Non puoi scrivere.');
    if (c.generation == 0 || c.generation != generation) {
      throw const ChatFailure('La chat è appena cambiata: riprova.', conflict: true);
    }
    c.status[uid] = 'active';
    hub.clock = hub.clock.add(const Duration(minutes: 1));
    final FakeMsg m = FakeMsg(++hub._seq, c.id, generation, uid, null, payload, hub.clock);
    hub.messages.add(m);
    c.lastId = m.id;
    c.lastAt = m.at;
    return (m.id, m.at);
  }

  @override
  Future<List<ChatEnvelope>> sync(int after) async => <ChatEnvelope>[
    for (final FakeMsg m in hub.messages)
      if (m.id > after && m.sender != uid)
        if (hub.convs.any((c) => c.id == m.conv && (c.a == uid || c.b == uid) && c.status[uid] != 'declined'))
          if (m.welcomeFor == null || m.welcomeFor == uid)
            if (!hub.blocked(uid, m.sender))
              ChatEnvelope(
                id: m.id,
                conversationId: m.conv,
                generation: m.generation,
                senderId: m.sender,
                isWelcome: m.welcomeFor != null,
                payload: m.payload,
                createdAt: m.at,
              ),
  ];

  @override
  Future<List<ChatConversation>> conversations() async => <ChatConversation>[
    for (final FakeConv c in hub.convs)
      if ((c.a == uid || c.b == uid) && c.status[uid] != 'declined' && !hub.blocked(c.a, c.b))
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
    d = d > c.delivered[uid]! ? d : c.delivered[uid]!;
    r = r > c.read[uid]! ? r : c.read[uid]!;
    if (r > d) d = r;
    c.delivered[uid] = d;
    c.read[uid] = r;
    hub.messages.removeWhere((m) =>
        m.conv == c.id && m.sender != uid && m.id <= d && (m.welcomeFor == null || m.welcomeFor == uid));
  }

  @override
  Future<void> respondRequest(String conversationId, bool accept) async {
    final FakeConv c = _member(conversationId);
    if (c.status[uid] != 'request') throw const ChatFailure('Non è una richiesta in attesa.');
    c.status[uid] = accept ? 'active' : 'declined';
    if (!accept) hub.messages.removeWhere((m) => m.conv == c.id && m.sender != uid);
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
}

/// Telefono finto pronto all'uso (cifratura finta, messaggi in memoria, nessun timer utile).
Future<ChatService> fakePhone(FakeChatHub hub, String uid, {String key = 'chiave', Directory? files}) async {
  final ChatService s = ChatService(
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

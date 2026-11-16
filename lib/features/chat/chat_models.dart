import 'dart:convert';

/// Errore da mostrare all'utente (testo già in italiano).
class ChatFailure implements Exception {
  const ChatFailure(this.message, {this.conflict = false});

  final String message;

  /// La chat è cambiata nel frattempo (generazione diversa): si ricarica e si riprova.
  final bool conflict;

  @override
  String toString() => message;
}

/// Stato della chat per chi la guarda.
enum ChatStatus { active, request }

/// Una chat come la restituisce il server (`chat_conversations`). Mai il numero di telefono.
class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.status,
    required this.generation,
    required this.groupId,
    required this.peerId,
    required this.peerUsername,
    required this.peerName,
    this.peerAvatarPath,
    this.peerSignatureKey,
    this.peerJoinedKey,
    this.myJoinedKey,
    this.peerDeliveredUpto = 0,
    this.peerReadUpto = 0,
    this.myReadUpto = 0,
    this.lastMessageId,
    this.lastMessageAt,
    required this.createdAt,
  });

  final String id;
  final ChatStatus status;
  final int generation;
  final String? groupId;
  final String peerId;
  final String peerUsername;
  final String peerName;
  final String? peerAvatarPath;
  final String? peerSignatureKey;
  final String? peerJoinedKey;
  final String? myJoinedKey;
  final int peerDeliveredUpto;
  final int peerReadUpto;
  final int myReadUpto;
  final int? lastMessageId;
  final DateTime? lastMessageAt;
  final DateTime createdAt;

  bool get isRequest => status == ChatStatus.request;

  /// L'altra persona ha cambiato telefono dopo l'ultima apertura cifrata.
  bool get peerChangedPhone =>
      generation > 0 && peerSignatureKey != null && peerJoinedKey != peerSignatureKey;

  factory ChatConversation.fromRow(Map<String, dynamic> r) {
    int asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    return ChatConversation(
      id: r['id'] as String,
      status: r['status'] == 'request' ? ChatStatus.request : ChatStatus.active,
      generation: asInt(r['generation']),
      groupId: r['mls_group_id'] as String?,
      peerId: r['peer_id'] as String,
      peerUsername: (r['peer_username'] as String?) ?? '',
      peerName: (r['peer_public_name'] as String?) ?? '',
      peerAvatarPath: r['peer_avatar_thumb_path'] as String?,
      peerSignatureKey: r['peer_signature_key'] as String?,
      peerJoinedKey: r['peer_joined_key'] as String?,
      myJoinedKey: r['my_joined_key'] as String?,
      peerDeliveredUpto: asInt(r['peer_delivered_upto']),
      peerReadUpto: asInt(r['peer_read_upto']),
      myReadUpto: asInt(r['my_read_upto']),
      lastMessageId: r['last_message_id'] == null ? null : asInt(r['last_message_id']),
      lastMessageAt: DateTime.tryParse('${r['last_message_at']}')?.toLocal(),
      createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
    );
  }
}

/// Messaggio cifrato in arrivo (`chat_sync`).
class ChatEnvelope {
  const ChatEnvelope({
    required this.id,
    required this.conversationId,
    required this.generation,
    required this.senderId,
    required this.isWelcome,
    required this.payload,
    required this.createdAt,
  });

  final int id;
  final String conversationId;
  final int generation;
  final String senderId;
  final bool isWelcome;
  final String payload;
  final DateTime createdAt;

  factory ChatEnvelope.fromRow(Map<String, dynamic> r) => ChatEnvelope(
    id: (r['id'] as num).toInt(),
    conversationId: r['conversation_id'] as String,
    generation: (r['generation'] as num).toInt(),
    senderId: r['sender_id'] as String,
    isWelcome: r['kind'] == 'welcome',
    payload: r['payload'] as String,
    createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
  );
}

/// Pacchetto chiave dell'altra persona, con la sua chiave di firma registrata.
class ClaimedKeyPackage {
  const ClaimedKeyPackage(this.package, this.signatureKey);

  final String package;
  final String signatureKey;
}

/// Contenuto in chiaro, cifrato prima di partire. Versione 1: solo testo.
class ChatContent {
  const ChatContent.text(this.body, {required this.localId}) : type = 'text';

  const ChatContent._(this.type, this.body, this.localId);

  final String type;
  final String body;
  final String localId;

  static const int maxTextLength = 4000;

  List<int> encode() => utf8.encode(jsonEncode(<String, Object>{
    'v': 1,
    't': type,
    'id': localId,
    'b': body,
  }));

  /// null se il contenuto non è riconosciuto (versioni future: «aggiorna l'app»).
  static ChatContent? decode(List<int> bytes) {
    try {
      final Object? json = jsonDecode(utf8.decode(bytes));
      if (json is! Map || json['v'] != 1) return null;
      final Object? type = json['t'];
      final Object? body = json['b'];
      final Object? id = json['id'];
      if (type is! String || body is! String || id is! String) return null;
      return ChatContent._(type, body, id);
    } catch (_) {
      return null;
    }
  }
}

/// Spunte di un messaggio inviato.
enum MessageTicks { sending, failed, sent, delivered, read }

/// Tipo di riga nella conversazione.
enum MessageKind {
  text,

  /// Il messaggio è arrivato ma non si può leggere (telefono cambiato, versione nuova...).
  unreadable,

  /// Avviso di sistema: «X ha cambiato telefono».
  notice,
}

/// Messaggio salvato sul telefono (in chiaro, solo qui).
class ChatMessage {
  const ChatMessage({
    required this.localId,
    required this.conversationId,
    required this.mine,
    required this.kind,
    required this.body,
    required this.at,
    this.serverId,
    this.ticks = MessageTicks.sent,
  });

  final String localId;
  final String conversationId;
  final int? serverId;
  final bool mine;
  final MessageKind kind;
  final String body;
  final DateTime at;

  /// Solo per i messaggi in uscita non ancora sul server (in memoria).
  final MessageTicks ticks;

  ChatMessage copyWith({int? serverId, MessageTicks? ticks}) => ChatMessage(
    localId: localId,
    conversationId: conversationId,
    serverId: serverId ?? this.serverId,
    mine: mine,
    kind: kind,
    body: body,
    at: at,
    ticks: ticks ?? this.ticks,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'l': localId,
    's': serverId,
    'm': mine,
    'k': kind.name,
    'b': body,
    'a': at.toUtc().toIso8601String(),
  };

  static ChatMessage? fromJson(String conversationId, Map<String, dynamic> j) {
    final MessageKind? kind = MessageKind.values.where((k) => k.name == j['k']).firstOrNull;
    final DateTime? at = DateTime.tryParse('${j['a']}');
    if (kind == null || at == null || j['l'] is! String || j['b'] is! String) return null;
    return ChatMessage(
      localId: j['l'] as String,
      conversationId: conversationId,
      serverId: (j['s'] as num?)?.toInt(),
      mine: j['m'] == true,
      kind: kind,
      body: j['b'] as String,
      at: at.toLocal(),
    );
  }

  /// Spunte calcolate dai puntatori dell'altra persona.
  MessageTicks ticksFor(ChatConversation? c) {
    if (!mine || kind != MessageKind.text) return ticks;
    final int? id = serverId;
    if (id == null) return ticks;
    if (c == null) return MessageTicks.sent;
    if (c.peerReadUpto >= id) return MessageTicks.read;
    if (c.peerDeliveredUpto >= id) return MessageTicks.delivered;
    return MessageTicks.sent;
  }
}

/// Riga della lista delle chat.
class ChatThread {
  const ChatThread({required this.conversation, this.last, this.unread = 0});

  final ChatConversation conversation;
  final ChatMessage? last;
  final int unread;

  DateTime get sortAt => last?.at ?? conversation.lastMessageAt ?? conversation.createdAt;
}

/// Contatto della rubrica a cui scrivere (mai il numero).
class ChatContact {
  const ChatContact({required this.id, required this.name, required this.username, this.avatarPath});

  final String id;
  final String name;
  final String username;
  final String? avatarPath;
}

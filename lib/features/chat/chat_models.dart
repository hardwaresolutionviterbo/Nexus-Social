import 'dart:convert';

import 'chat_media.dart';

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
    this.isGroup = false,
    this.title = '',
    this.description = '',
    this.photoVersion = 0,
    this.myRole = 'member',
    this.myMlsState = 'in',
    this.members = 2,
    this.pending = 0,
    this.invitedBy,
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

  /// Gruppo (Blocco 4): niente «altra persona», ma titolo, membri e ruoli.
  final bool isGroup;
  final String title;
  final String description;
  final int photoVersion;
  final String myRole;

  /// Stato nel gruppo cifrato: in, to_add, to_remove, to_readd.
  final String myMlsState;
  final int members;

  /// Modifiche al gruppo cifrato in attesa (persone da aggiungere o togliere).
  final int pending;
  final String? invitedBy;

  bool get isRequest => status == ChatStatus.request;

  bool get isAdmin => myRole == 'admin';

  /// Nome da mostrare: titolo del gruppo o nome dell'altra persona.
  String get displayName => isGroup ? title : (peerName.isEmpty ? '@$peerUsername' : peerName);

  /// L'altra persona ha cambiato telefono dopo l'ultima apertura cifrata.
  bool get peerChangedPhone =>
      !isGroup && generation > 0 && peerSignatureKey != null && peerJoinedKey != peerSignatureKey;

  ChatConversation copyWith({
    int? generation,
    String? groupId,
    String? peerSignatureKey,
    String? peerJoinedKey,
    String? myJoinedKey,
    String? myMlsState,
    int? pending,
  }) => ChatConversation(
    id: id,
    status: status,
    generation: generation ?? this.generation,
    groupId: groupId ?? this.groupId,
    peerId: peerId,
    peerUsername: peerUsername,
    peerName: peerName,
    peerAvatarPath: peerAvatarPath,
    peerSignatureKey: peerSignatureKey ?? this.peerSignatureKey,
    peerJoinedKey: peerJoinedKey ?? this.peerJoinedKey,
    myJoinedKey: myJoinedKey ?? this.myJoinedKey,
    peerDeliveredUpto: peerDeliveredUpto,
    peerReadUpto: peerReadUpto,
    myReadUpto: myReadUpto,
    lastMessageId: lastMessageId,
    lastMessageAt: lastMessageAt,
    createdAt: createdAt,
    isGroup: isGroup,
    title: title,
    description: description,
    photoVersion: photoVersion,
    myRole: myRole,
    myMlsState: myMlsState ?? this.myMlsState,
    members: members,
    pending: pending ?? this.pending,
    invitedBy: invitedBy,
  );

  factory ChatConversation.fromRow(Map<String, dynamic> r) {
    int asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    return ChatConversation(
      id: r['id'] as String,
      status: r['status'] == 'request' ? ChatStatus.request : ChatStatus.active,
      generation: asInt(r['generation']),
      groupId: r['mls_group_id'] as String?,
      peerId: (r['peer_id'] as String?) ?? '',
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
      isGroup: r['kind'] == 'group',
      title: (r['title'] as String?) ?? '',
      description: (r['description'] as String?) ?? '',
      photoVersion: asInt(r['photo_version']),
      myRole: (r['my_role'] as String?) ?? 'member',
      myMlsState: (r['my_mls_state'] as String?) ?? 'in',
      members: r['members'] == null ? 2 : asInt(r['members']),
      pending: asInt(r['pending']),
      invitedBy: r['invited_by'] as String?,
    );
  }
}

/// Membro di un gruppo (`chat_group_members`). Mai il numero di telefono.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.username,
    required this.name,
    this.avatarPath,
    required this.role,
    required this.status,
    required this.mlsState,
    this.signatureKey,
    this.joinedKey,
  });

  final String userId;
  final String username;
  final String name;
  final String? avatarPath;
  final String role;
  final String status;
  final String mlsState;
  final String? signatureKey;
  final String? joinedKey;

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';
  bool get isInvited => status == 'request';
  String get displayName => name.isEmpty ? '@$username' : name;

  factory GroupMember.fromRow(Map<String, dynamic> r) => GroupMember(
    userId: r['user_id'] as String,
    username: (r['username'] as String?) ?? '',
    name: (r['public_name'] as String?) ?? '',
    avatarPath: r['avatar_thumb_path'] as String?,
    role: (r['role'] as String?) ?? 'member',
    status: (r['status'] as String?) ?? 'active',
    mlsState: (r['mls_state'] as String?) ?? 'in',
    signatureKey: r['signature_key'] as String?,
    joinedKey: r['joined_key'] as String?,
  );
}

/// Anteprima di un gruppo dal codice d'invito.
class GroupInviteInfo {
  const GroupInviteInfo({
    required this.conversationId,
    required this.title,
    required this.members,
    required this.alreadyMember,
  });

  final String conversationId;
  final String title;
  final int members;
  final bool alreadyMember;
}

/// Messaggio cifrato in arrivo (`chat_sync`).
class ChatEnvelope {
  const ChatEnvelope({
    required this.id,
    required this.conversationId,
    required this.generation,
    required this.senderId,
    required this.kind,
    required this.payload,
    required this.createdAt,
  });

  final int id;
  final String conversationId;
  final int generation;
  final String senderId;

  /// welcome (invito cifrato), app (messaggio), commit (modifica del gruppo cifrato),
  /// event (avviso del gruppo generato dal server).
  final String kind;
  final String payload;

  bool get isWelcome => kind == 'welcome';
  final DateTime createdAt;

  factory ChatEnvelope.fromRow(Map<String, dynamic> r) => ChatEnvelope(
    id: (r['id'] as num).toInt(),
    conversationId: r['conversation_id'] as String,
    generation: (r['generation'] as num).toInt(),
    senderId: r['sender_id'] as String,
    kind: (r['kind'] as String?) ?? 'app',
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

/// Reazioni rapide (Fase 4, Blocco 2).
const List<String> chatReactions = <String>['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// «Elimina per tutti» possibile fino a 48 ore dopo l'invio.
const Duration deleteForEveryoneWindow = Duration(hours: 48);

/// Citazione di un messaggio nella risposta.
class ChatQuote {
  const ChatQuote({required this.localId, required this.authorId, required this.text});

  final String localId;
  final String authorId;

  /// Inizio del testo citato (al massimo 200 caratteri).
  final String text;

  static const int maxText = 200;
}

/// Contenuto in chiaro, cifrato prima di partire.
///
/// Tipi: `text` (con citazione e «inoltrato» facoltativi), `del` (elimina per tutti il
/// messaggio [target]), `react` (reazione [emoji] al messaggio [target]; vuota = tolta).
class ChatContent {
  const ChatContent.text(this.body, {required this.localId, this.quote, this.forwarded = false})
    : type = 'text',
      target = null,
      emoji = null,
      media = null;

  /// Allegato cifrato con didascalia facoltativa in [body].
  const ChatContent.media(
    this.body, {
    required this.localId,
    required ChatMedia this.media,
    this.quote,
    this.forwarded = false,
  }) : type = 'media',
       target = null,
       emoji = null;

  const ChatContent.delete({required this.localId, required String this.target})
    : type = 'del',
      body = '',
      quote = null,
      forwarded = false,
      emoji = null,
      media = null;

  const ChatContent.react({required this.localId, required String this.target, required String this.emoji})
    : type = 'react',
      body = '',
      quote = null,
      forwarded = false,
      media = null;

  const ChatContent._(
    this.type,
    this.body,
    this.localId, {
    this.quote,
    this.forwarded = false,
    this.target,
    this.emoji,
    this.media,
  });

  final String type;
  final String body;
  final String localId;
  final ChatQuote? quote;
  final bool forwarded;
  final String? target;
  final String? emoji;
  final ChatMedia? media;

  static const int maxTextLength = 4000;

  bool get isText => type == 'text';

  /// Testo o allegato: diventa un fumetto nella conversazione.
  bool get isMessage => type == 'text' || (type == 'media' && media != null);

  List<int> encode() => utf8.encode(jsonEncode(<String, Object>{
    'v': 1,
    't': type,
    'id': localId,
    'b': body,
    if (quote != null) 'q': <String, String>{'id': quote!.localId, 'a': quote!.authorId, 'x': quote!.text},
    if (forwarded) 'f': true,
    'tg': ?target,
    'e': ?emoji,
    if (media != null) 'md': media!.toJson(),
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
      ChatQuote? quote;
      final Object? q = json['q'];
      if (q is Map && q['id'] is String && q['a'] is String && q['x'] is String) {
        final String text = q['x'] as String;
        quote = ChatQuote(
          localId: q['id'] as String,
          authorId: q['a'] as String,
          text: text.length > ChatQuote.maxText ? text.substring(0, ChatQuote.maxText) : text,
        );
      }
      final Object? target = json['tg'];
      final Object? emoji = json['e'];
      switch (type) {
        case 'text':
          return ChatContent._(type, body, id, quote: quote, forwarded: json['f'] == true);
        case 'media':
          final ChatMedia? media = ChatMedia.fromJson(json['md']);
          if (media == null) return null;
          return ChatContent._(
            type,
            body.length > MediaLimits.maxCaption ? body.substring(0, MediaLimits.maxCaption) : body,
            id,
            quote: quote,
            forwarded: json['f'] == true,
            media: media,
          );
        case 'del':
          return target is String ? ChatContent._(type, '', id, target: target) : null;
        case 'react':
          if (target is! String || emoji is! String) return null;
          if (emoji.isNotEmpty && !chatReactions.contains(emoji)) return null;
          return ChatContent._(type, '', id, target: target, emoji: emoji);
        default:
          return ChatContent._(type, body, id);
      }
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

/// Evento su un messaggio già salvato: elimina per tutti, reazione, elimina per me,
/// allegato salvato sul telefono ([ChatEvent.value] = nome del file).
enum ChatEventKind { delete, react, hide, saved }

class ChatEvent {
  const ChatEvent({
    required this.conversationId,
    required this.kind,
    required this.target,
    required this.byMe,
    required this.at,
    this.emoji = '',
    this.serverId,
    this.value = '',
    this.by = '',
  });

  final String conversationId;
  final ChatEventKind kind;

  /// localId del messaggio interessato.
  final String target;
  final bool byMe;
  final DateTime at;
  final String emoji;
  final int? serverId;
  final String value;

  /// Chi l'ha fatto (per gli eventi altrui; nei gruppi distingue i membri).
  final String by;

  Map<String, Object?> toJson() => <String, Object?>{
    'ev': kind.name,
    if (by.isNotEmpty) 'u': by,
    if (value.isNotEmpty) 'v': value,
    't': target,
    'm': byMe,
    'a': at.toUtc().toIso8601String(),
    if (emoji.isNotEmpty) 'x': emoji,
    's': serverId,
  };

  static ChatEvent? fromJson(String conversationId, Map<String, dynamic> j) {
    final ChatEventKind? kind = ChatEventKind.values.where((k) => k.name == j['ev']).firstOrNull;
    final DateTime? at = DateTime.tryParse('${j['a']}');
    if (kind == null || at == null || j['t'] is! String) return null;
    return ChatEvent(
      conversationId: conversationId,
      kind: kind,
      target: j['t'] as String,
      byMe: j['m'] == true,
      at: at.toLocal(),
      emoji: (j['x'] as String?) ?? '',
      serverId: (j['s'] as num?)?.toInt(),
      value: (j['v'] as String?) ?? '',
      by: (j['u'] as String?) ?? '',
    );
  }
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
    this.quote,
    this.forwarded = false,
    this.deleted = false,
    this.myReaction = '',
    this.peerReaction = '',
    this.media,
    this.localFile = '',
    this.senderId = '',
    this.reactions = const <String, String>{},
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

  final ChatQuote? quote;
  final bool forwarded;

  /// Eliminato per tutti da chi l'aveva scritto: il testo non c'è più.
  final bool deleted;
  final String myReaction;
  final String peerReaction;

  /// Allegato (null per i messaggi di solo testo).
  final ChatMedia? media;

  /// Nome del file in chiaro sul telefono, se già scaricato (o inviato da qui).
  final String localFile;

  /// Chi l'ha scritto (vuoto per i miei; nei gruppi serve per il nome nel fumetto).
  final String senderId;

  /// Reazioni degli altri membri del gruppo (chi → emoji). Nelle chat a due c'è solo
  /// [peerReaction].
  final Map<String, String> reactions;

  /// Tutte le reazioni da mostrare: le mie e quelle degli altri.
  List<String> get allReactions => <String>[
    if (myReaction.isNotEmpty) myReaction,
    if (reactions.isEmpty && peerReaction.isNotEmpty) peerReaction,
    ...reactions.values.where((e) => e.isNotEmpty),
  ];

  /// Messaggio normale non eliminato (testo o allegato).
  bool get isText => kind == MessageKind.text && !deleted;

  bool get hasMedia => media != null && !deleted;

  /// Si può eliminare per tutti: mio, già inviato, entro 48 ore.
  bool canDeleteForEveryone(DateTime now) =>
      mine && isText && serverId != null && now.difference(at) < deleteForEveryoneWindow;

  ChatMessage copyWith({
    int? serverId,
    MessageTicks? ticks,
    bool? deleted,
    String? myReaction,
    String? peerReaction,
    String? localFile,
    Map<String, String>? reactions,
  }) => ChatMessage(
    localId: localId,
    conversationId: conversationId,
    serverId: serverId ?? this.serverId,
    mine: mine,
    kind: kind,
    body: (deleted ?? this.deleted) ? '' : body,
    at: at,
    ticks: ticks ?? this.ticks,
    quote: (deleted ?? this.deleted) ? null : quote,
    forwarded: forwarded,
    deleted: deleted ?? this.deleted,
    myReaction: myReaction ?? this.myReaction,
    peerReaction: peerReaction ?? this.peerReaction,
    media: (deleted ?? this.deleted) ? null : media,
    localFile: (deleted ?? this.deleted) ? '' : (localFile ?? this.localFile),
    senderId: senderId,
    reactions: reactions ?? this.reactions,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'l': localId,
    if (media != null) 'md': media!.toJson(),
    if (localFile.isNotEmpty) 'lf': localFile,
    if (senderId.isNotEmpty) 'sd': senderId,
    's': serverId,
    'm': mine,
    'k': kind.name,
    'b': body,
    'a': at.toUtc().toIso8601String(),
    if (quote != null) 'q': <String, String>{'id': quote!.localId, 'a': quote!.authorId, 'x': quote!.text},
    if (forwarded) 'f': true,
  };

  static ChatMessage? fromJson(String conversationId, Map<String, dynamic> j) {
    final MessageKind? kind = MessageKind.values.where((k) => k.name == j['k']).firstOrNull;
    final DateTime? at = DateTime.tryParse('${j['a']}');
    if (kind == null || at == null || j['l'] is! String || j['b'] is! String) return null;
    final Object? q = j['q'];
    return ChatMessage(
      localId: j['l'] as String,
      conversationId: conversationId,
      serverId: (j['s'] as num?)?.toInt(),
      mine: j['m'] == true,
      kind: kind,
      body: j['b'] as String,
      at: at.toLocal(),
      quote: q is Map && q['id'] is String && q['a'] is String && q['x'] is String
          ? ChatQuote(localId: q['id'] as String, authorId: q['a'] as String, text: q['x'] as String)
          : null,
      forwarded: j['f'] == true,
      media: ChatMedia.fromJson(j['md']),
      localFile: (j['lf'] as String?) ?? '',
      senderId: (j['sd'] as String?) ?? '',
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

/// Applica gli eventi ai messaggi: eliminazioni, reazioni, «elimina per me».
List<ChatMessage> foldChatEvents(List<ChatMessage> messages, List<ChatEvent> events) {
  if (events.isEmpty) return messages;
  final Map<String, int> index = <String, int>{
    for (int i = 0; i < messages.length; i++) messages[i].localId: i,
  };
  final List<ChatMessage?> out = List<ChatMessage?>.of(messages);
  for (final ChatEvent e in events) {
    final int? i = index[e.target];
    if (i == null) continue;
    final ChatMessage? m = out[i];
    if (m == null) continue;
    switch (e.kind) {
      case ChatEventKind.hide:
        out[i] = null;
      case ChatEventKind.delete:
        // Solo chi l'ha scritto può eliminarlo per tutti (nei gruppi: lo stesso membro).
        final bool author = e.byMe ? m.mine : (!m.mine && (m.senderId.isEmpty || e.by.isEmpty || e.by == m.senderId));
        if (author && m.kind == MessageKind.text) out[i] = m.copyWith(deleted: true);
      case ChatEventKind.react:
        if (m.deleted || m.kind != MessageKind.text) continue;
        if (e.byMe) {
          out[i] = m.copyWith(myReaction: e.emoji);
        } else if (e.by.isEmpty) {
          out[i] = m.copyWith(peerReaction: e.emoji);
        } else {
          out[i] = m.copyWith(
            peerReaction: e.emoji,
            reactions: <String, String>{...m.reactions, e.by: e.emoji}..removeWhere((_, v) => v.isEmpty),
          );
        }
      case ChatEventKind.saved:
        if (m.media != null && !m.deleted) out[i] = m.copyWith(localFile: e.value);
    }
  }
  return out.whereType<ChatMessage>().toList();
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

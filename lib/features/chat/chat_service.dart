import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'chat_crypto.dart';
import 'chat_media.dart';
import 'chat_models.dart';
import 'chat_server.dart';
import 'chat_store.dart';

/// Motore della chat: tiene insieme server, cifratura e messaggi sul telefono.
///
/// Tutte le operazioni che toccano chiavi o messaggi passano in fila una alla volta
/// ([_run]): un messaggio MLS si decifra una sola volta e mai in parallelo.
class ChatService extends ChangeNotifier {
  ChatService({
    required this.server,
    required Future<ChatCrypto> Function() crypto,
    required this.store,
    required this.myId,
    this.contactsLoader,
    this.media,
    this.files,
    this.fastPoll = const Duration(seconds: 3),
    this.slowPoll = const Duration(seconds: 10),
  }) : _openCrypto = crypto;

  final ChatServer server;
  final ChatStore store;
  final String myId;
  final Future<List<ChatContact>> Function()? contactsLoader;

  /// Allegati cifrati sul server e in chiaro sul telefono (Blocco 3).
  final ChatMediaServer? media;
  final ChatMediaFiles? files;
  final Duration fastPoll;
  final Duration slowPoll;

  final Future<ChatCrypto> Function() _openCrypto;
  ChatCrypto? _crypto;
  String? _myKey;

  /// Pacchetti chiave da tenere pronti sul server.
  static const int keyPackageTarget = 30;
  static const int keyPackageLow = 15;

  bool _ready = false;
  bool _starting = false;
  String? _startError;
  bool _disposed = false;
  Timer? _timer;
  bool _foreground = true;
  bool _polling = false;

  final Map<String, ChatConversation> _conversations = <String, ChatConversation>{};
  final Map<String, List<ChatMessage>> _messages = <String, List<ChatMessage>>{};
  final Map<String, List<ChatMessage>> _pending = <String, List<ChatMessage>>{};
  String? _open;
  DateTime _conversationsAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _queue = Future<void>.value();

  bool get ready => _ready;

  /// Errore all'avvio (per esempio senza connessione): la schermata offre «Riprova».
  String? get startError => _startError;

  // ---------------------------------------------------------------- fila

  Future<T> _run<T>(Future<T> Function() job) {
    final Completer<T> done = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await job());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------- avvio

  Future<void> start() async {
    if (_ready || _starting) return;
    _starting = true;
    _startError = null;
    _changed();
    try {
      await _run(_init);
      _ready = true;
      await refresh();
      _schedule();
    } on ChatFailure catch (f) {
      _startError = f.message;
    } catch (_) {
      _startError = 'La chat non si è avviata. Controlla la connessione e riprova.';
    } finally {
      _starting = false;
      _changed();
    }
  }

  Future<void> _init() async {
    final ChatCrypto crypto = _crypto ??= await _openCrypto();
    final ChatIdentity identity = await crypto.ensureIdentity();
    _myKey = identity.signatureKey;
    final String? onServer = await server.myIdentity();
    if (onServer != identity.signatureKey) {
      // Primo avvio della chat o telefono nuovo: questo telefono diventa quello della chat.
      await server.registerIdentity(
        identity.signatureKey,
        await crypto.newKeyPackages(keyPackageTarget),
      );
    } else if (await server.keyPackageCount() < keyPackageLow) {
      await server.addKeyPackages(await crypto.newKeyPackages(keyPackageTarget));
    }
  }

  /// App in primo piano o in background: in background niente controlli.
  void setForeground(bool value) {
    _foreground = value;
    _schedule();
    if (value) unawaited(refresh());
  }

  /// Chat aperta sullo schermo: controlli più frequenti e messaggi segnati come letti.
  void setOpenConversation(String? id) {
    _open = id;
    _schedule();
    if (id != null) unawaited(markRead(id));
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_ready || !_foreground || _disposed) return;
    _timer = Timer.periodic(_open == null ? slowPoll : fastPoll, (_) => unawaited(refresh()));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- lettura

  List<ChatThread> _threads(bool requests) {
    final List<ChatThread> list = <ChatThread>[
      for (final ChatConversation c in _conversations.values)
        // Come WhatsApp: una chat a due compare dal primo messaggio, un gruppo subito.
        if (c.isRequest == requests && (c.isGroup || _visible(c.id).isNotEmpty))
            ChatThread(
              conversation: c,
              last: _visible(c.id).lastOrNull,
              unread: _unread(c),
            ),
    ];
    list.sort((a, b) => b.sortAt.compareTo(a.sortAt));
    return list;
  }

  /// Chat attive, dalla più recente.
  List<ChatThread> get threads => _threads(false);

  /// Richieste di messaggio: chi ti scrive senza essere nella tua rubrica.
  List<ChatThread> get requests => _threads(true);

  int get unreadTotal =>
      threads.fold<int>(0, (n, t) => n + t.unread) + requests.length;

  ChatConversation? conversation(String id) => _conversations[id];

  List<ChatMessage> _messagesOf(String id) => _messages[id] ?? const <ChatMessage>[];

  /// In ordine di tempo (gli avvisi del gruppo possono arrivare dopo i messaggi).
  List<ChatMessage> _visible(String id) {
    final List<ChatMessage> saved = List<ChatMessage>.of(_messagesOf(id));
    final List<int> order = List<int>.generate(saved.length, (int i) => i);
    order.sort((int x, int y) {
      final int byTime = saved[x].at.compareTo(saved[y].at);
      return byTime != 0 ? byTime : x.compareTo(y);
    });
    return <ChatMessage>[for (final int i in order) saved[i], ...?_pending[id]];
  }

  /// Messaggi della chat, dal più vecchio.
  List<ChatMessage> messages(String id) => _visible(id);

  int _unread(ChatConversation c) => _messagesOf(c.id)
      .where((m) => !m.mine && m.kind != MessageKind.notice && (m.serverId ?? 0) > c.myReadUpto)
      .length;

  Future<List<ChatContact>> contacts() async =>
      contactsLoader == null ? const <ChatContact>[] : await contactsLoader!();

  // ---------------------------------------------------------------- aggiornamento

  /// Nuovi messaggi e stato delle chat. Silenzioso: gli errori di rete si riprovano dopo.
  Future<void> refresh() async {
    if (!_ready || _polling) return;
    _polling = true;
    try {
      await _run(() async {
        await _syncInbox();
        await _loadConversations();
        await _maintainGroups();
      });
    } catch (_) {
      // Rete assente: si riprova al prossimo giro.
    } finally {
      _polling = false;
      _changed();
    }
    unawaited(_runAutoDownloads());
  }

  Future<void> _loadConversations() async {
    final List<ChatConversation> list = await server.conversations();
    _conversations
      ..clear()
      ..addEntries(list.map((c) => MapEntry<String, ChatConversation>(c.id, c)));
    _conversationsAt = DateTime.now();
    for (final ChatConversation c in list) {
      if (!_messages.containsKey(c.id)) _messages[c.id] = await store.messages(c.id);
    }
  }

  Future<void> _append(ChatMessage m) async {
    await store.append(m);
    (_messages[m.conversationId] ??= <ChatMessage>[]).add(m);
  }

  Future<void> _appendEvent(ChatEvent e) async {
    await store.appendEvent(e);
    _messages[e.conversationId] = await store.messages(e.conversationId);
  }

  Future<List<ChatMessage>> _stored(String conversationId) async =>
      _messages[conversationId] ??= await store.messages(conversationId);

  Future<void> _syncInbox() async {
    final ChatCrypto crypto = _crypto!;
    int cursor = await store.cursor();
    final Map<String, int> touched = <String, int>{};
    while (true) {
      final List<ChatEnvelope> batch = await server.sync(cursor);
      if (batch.isEmpty) break;
      for (final ChatEnvelope e in batch) {
        await _stored(e.conversationId);
        if (!await store.hasServerId(e.conversationId, e.id)) {
          if (!_conversations.containsKey(e.conversationId)) await _loadConversations();
          switch (e.kind) {
            case 'welcome':
              await _accept(crypto, e);
            case 'commit':
              await _applyCommit(crypto, e);
            case 'event':
              await _groupEvent(e);
            default:
              await _receive(crypto, e);
          }
        }
        cursor = e.id;
        await store.setCursor(cursor);
        touched[e.conversationId] = max(touched[e.conversationId] ?? 0, e.id);
      }
      if (batch.length < 200) break;
    }
    for (final MapEntry<String, int> t in touched.entries) {
      try {
        await server.mark(t.key, delivered: t.value, read: _open == t.key ? t.value : 0);
      } catch (_) {
        // Si riprova al prossimo messaggio.
      }
    }
    // Gruppi rimasti indietro (telefono spento troppo a lungo, commit perso): un
    // amministratore ci riaggiunge.
    for (final String id in _lost.toList()) {
      try {
        await server.groupRejoin(id);
        _lost.remove(id);
      } catch (_) {
        // Si riprova.
      }
    }
  }

  /// Gruppi in cui questo telefono ha perso il filo del gruppo cifrato.
  final Set<String> _lost = <String>{};

  Future<void> _applyCommit(ChatCrypto crypto, ChatEnvelope e) async {
    final LocalSession? s = await store.session(e.conversationId);
    if (s != null && s.generation > e.generation) return; // già applicato
    if (s == null || s.generation < e.generation || !await crypto.applyCommit(s.groupId, e.payload)) {
      _lost.add(e.conversationId);
      return;
    }
    await store.setSession(e.conversationId, LocalSession(e.generation + 1, s.groupId));
  }

  // ---------------------------------------------------------------- avvisi del gruppo

  final Map<String, Map<String, String>> _names = <String, Map<String, String>>{};

  /// Nome di un membro del gruppo («Tu» per sé stessi).
  String memberName(String conversationId, String userId) {
    if (userId == myId) return 'Tu';
    return _names[conversationId]?[userId] ?? 'Un membro';
  }

  Future<void> _loadNames(String conversationId) async {
    try {
      final List<GroupMember> list = await server.groupMembers(conversationId);
      _names[conversationId] = <String, String>{
        ...?_names[conversationId],
        for (final GroupMember m in list) m.userId: m.displayName,
      };
    } catch (_) {
      // Nomi non disponibili: si mostra «Un membro».
    }
  }

  Future<void> _groupEvent(ChatEnvelope e) async {
    Map<String, dynamic> ev;
    try {
      ev = Map<String, dynamic>.from(jsonDecode(utf8.decode(base64Decode(e.payload))) as Map);
    } catch (_) {
      return;
    }
    final List<String> ids = <String>[
      if (ev['by'] is String) ev['by'] as String,
      if (ev['who'] is String) ev['who'] as String,
      ...((ev['added'] as List?) ?? const <Object>[]).whereType<String>(),
      ...((ev['invited'] as List?) ?? const <Object>[]).whereType<String>(),
    ];
    final Map<String, String> known = _names[e.conversationId] ?? const <String, String>{};
    if (ids.any((id) => id != myId && !known.containsKey(id))) await _loadNames(e.conversationId);
    final String text = groupEventText(ev, (String id) => memberName(e.conversationId, id));
    if (text.isEmpty) return;
    await _append(ChatMessage(
      localId: 'ev-${e.id}',
      conversationId: e.conversationId,
      serverId: e.id,
      mine: false,
      kind: MessageKind.notice,
      body: text,
      at: e.createdAt,
      senderId: e.senderId,
    ));
  }

  Future<void> _accept(ChatCrypto crypto, ChatEnvelope e) async {
    final bool group = _conversations[e.conversationId]?.isGroup ?? false;
    final LocalSession? old = await store.session(e.conversationId);
    // Nel gruppo il vecchio stato cifrato (stesso identificativo) va tolto prima.
    if (group && old != null) await crypto.dropGroup(old.groupId);
    final String groupId;
    try {
      groupId = await crypto.joinGroup(e.payload, peerId: group ? '' : e.senderId);
    } catch (_) {
      // Invito per un telefono precedente: chi scrive per primo riaprirà la chat.
      if (group) _lost.add(e.conversationId);
      return;
    }
    if (!group && old != null && old.groupId != groupId) await crypto.dropGroup(old.groupId);
    await store.setSession(e.conversationId, LocalSession(e.generation, groupId));
    _lost.remove(e.conversationId);
    if (old != null && !group) await _notice(e.conversationId, e.createdAt, renewed: true);
  }

  Future<void> _receive(ChatCrypto crypto, ChatEnvelope e) async {
    final LocalSession? s = await store.session(e.conversationId);
    ChatContent? content;
    if (s != null && s.generation == e.generation) {
      final List<int>? plain = await crypto.decrypt(s.groupId, e.payload);
      if (plain != null) content = ChatContent.decode(plain);
    }
    if (content != null && (content.type == 'del' || content.type == 'react')) {
      await _appendEvent(ChatEvent(
        conversationId: e.conversationId,
        kind: content.type == 'del' ? ChatEventKind.delete : ChatEventKind.react,
        target: content.target!,
        byMe: false,
        at: e.createdAt,
        emoji: content.emoji ?? '',
        serverId: e.id,
        by: e.senderId,
      ));
      return;
    }
    final bool ok = content != null && content.isMessage;
    final ChatMessage m = ChatMessage(
      localId: content?.localId ?? 'srv-${e.id}',
      conversationId: e.conversationId,
      serverId: e.id,
      mine: false,
      kind: ok ? MessageKind.text : MessageKind.unreadable,
      body: ok ? content.body : '',
      at: e.createdAt,
      quote: ok ? content.quote : null,
      forwarded: ok && content.forwarded,
      media: ok ? content.media : null,
      senderId: e.senderId,
    );
    await _append(m);
    final ChatMedia? md = m.media;
    if (md != null &&
        (md.kind == MediaKind.image || md.kind == MediaKind.audio) &&
        md.size <= MediaLimits.autoDownloadBytes) {
      _autoDownload.add(m);
    }
  }

  /// Foto e vocali piccoli da scaricare da soli dopo la sincronizzazione.
  final List<ChatMessage> _autoDownload = <ChatMessage>[];
  bool _autoRunning = false;

  Future<void> _runAutoDownloads() async {
    if (_autoRunning || media == null || files == null) return;
    _autoRunning = true;
    try {
      while (_autoDownload.isNotEmpty && !_disposed) {
        final ChatMessage m = _autoDownload.removeAt(0);
        try {
          await download(m);
        } catch (_) {
          // Si potrà scaricare toccandolo.
        }
      }
    } finally {
      _autoRunning = false;
    }
  }

  /// Orario di un avviso locale: subito dopo l'ultimo messaggio della chat.
  DateTime _noticeTime(String conversationId) {
    final List<ChatMessage> list = _messagesOf(conversationId);
    if (list.isEmpty) return DateTime.now();
    return list.map((m) => m.at).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  Future<void> _notice(String conversationId, DateTime at, {required bool renewed, String text = ''}) =>
      _append(
        ChatMessage(
          localId: 'avviso-${at.microsecondsSinceEpoch}',
          conversationId: conversationId,
          mine: false,
          kind: MessageKind.notice,
          body: renewed ? 'Chat cifrata rinnovata: uno dei due ha cambiato telefono.' : text,
          at: at,
        ),
      );

  // ---------------------------------------------------------------- azioni

  /// Apre (o ritrova) la chat con [userId]; restituisce il suo identificativo.
  Future<String> openDirect(String userId) async {
    if (!_ready) await start();
    if (!_ready) throw ChatFailure(_startError ?? 'La chat non è pronta.');
    final String id = await server.openDirect(userId);
    await _run(_loadConversations);
    _changed();
    return id;
  }

  Future<void> respondRequest(String conversationId, bool accept) async {
    await server.respondRequest(conversationId, accept);
    if (!accept) {
      await _run(() async {
        final LocalSession? s = await store.session(conversationId);
        if (s != null) await _crypto?.dropGroup(s.groupId);
        await store.deleteConversation(conversationId);
        _messages.remove(conversationId);
      });
    }
    await _run(_loadConversations);
    _changed();
  }

  Future<void> markRead(String conversationId) async {
    final ChatConversation? c = _conversations[conversationId];
    if (c == null) return;
    final int last = _messagesOf(conversationId)
        .where((m) => !m.mine && m.serverId != null)
        .fold<int>(0, (n, m) => max(n, m.serverId!));
    if (last <= c.myReadUpto) return;
    try {
      await server.mark(conversationId, delivered: last, read: last);
      await _run(_loadConversations);
      _changed();
    } catch (_) {
      // Si riprova alla prossima apertura.
    }
  }

  static final Random _rng = Random.secure();

  static String _localId() =>
      List<String>.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  /// Invia un testo, eventualmente in risposta a [replyTo] o inoltrato. Compare subito con
  /// l'orologio; se non parte resta in rosso con «Riprova».
  Future<void> send(
    String conversationId,
    String text, {
    ChatMessage? replyTo,
    bool forwarded = false,
  }) async {
    final String body = text.trim();
    if (body.isEmpty) return;
    if (body.length > ChatContent.maxTextLength) {
      throw const ChatFailure('Messaggio troppo lungo (massimo 4.000 caratteri).');
    }
    final ChatQuote? quote = _quoteOf(replyTo, _conversations[conversationId]);
    final ChatMessage local = ChatMessage(
      localId: _localId(),
      conversationId: conversationId,
      mine: true,
      kind: MessageKind.text,
      body: body,
      at: DateTime.now(),
      ticks: MessageTicks.sending,
      quote: quote,
      forwarded: forwarded,
    );
    (_pending[conversationId] ??= <ChatMessage>[]).add(local);
    _changed();
    await _deliver(local);
  }

  /// Nuovo tentativo per un messaggio rimasto in rosso.
  Future<void> retry(ChatMessage message) async {
    final List<ChatMessage>? list = _pending[message.conversationId];
    final int i = list?.indexWhere((m) => m.localId == message.localId) ?? -1;
    if (i < 0) return;
    list![i] = message.copyWith(ticks: MessageTicks.sending);
    _changed();
    await _deliver(list[i]);
  }

  /// Inoltra un testo in una o più chat (al massimo 5 alla volta, come WhatsApp).
  Future<void> forward(ChatMessage message, List<String> conversationIds) async {
    if (!message.isText) return;
    if (conversationIds.length > 5) {
      throw const ChatFailure('Puoi inoltrare a 5 chat per volta.');
    }
    final ChatMedia? md = message.media;
    if (md != null) {
      // L'allegato si cifra di nuovo, con una chiave nuova, per ogni chat.
      final File? file = message.localFile.isEmpty ? null : await files?.existing(message.localFile);
      if (file == null) throw const ChatFailure('Scarica prima l\'allegato, poi inoltralo.');
      for (final String id in conversationIds) {
        await sendMedia(
          id,
          kind: md.kind,
          bytes: await file.readAsBytes(),
          mime: md.mime,
          name: md.name,
          width: md.width,
          height: md.height,
          durationMs: md.durationMs,
          thumb: md.thumb,
          caption: message.body,
          forwarded: true,
        );
      }
      return;
    }
    for (final String id in conversationIds) {
      await send(id, message.body, forwarded: true);
    }
  }

  final Map<String, Future<File>> _downloading = <String, Future<File>>{};

  /// L'allegato del messaggio [localId] si sta scaricando.
  bool isDownloading(String localId) => _downloading.containsKey(localId);

  /// File in chiaro dell'allegato sul telefono, se c'è.
  Future<File?> localFileOf(ChatMessage m) async =>
      m.localFile.isEmpty ? null : await files?.existing(m.localFile);

  /// Invia un allegato già preparato (foto ridotta, vocale, video, documento).
  Future<void> sendMedia(
    String conversationId, {
    required MediaKind kind,
    required Uint8List bytes,
    required String mime,
    String name = '',
    int width = 0,
    int height = 0,
    int durationMs = 0,
    String thumb = '',
    String caption = '',
    ChatMessage? replyTo,
    bool forwarded = false,
  }) async {
    final ChatMediaFiles? store = files;
    if (media == null || store == null) throw const ChatFailure('Allegati non disponibili.');
    if (bytes.isEmpty) throw const ChatFailure('File vuoto.');
    if (bytes.length > MediaLimits.maxBytes) {
      throw const ChatFailure('File troppo pesante: massimo 50 MB.');
    }
    final String text = caption.trim();
    if (text.length > MediaLimits.maxCaption) {
      throw const ChatFailure('Didascalia troppo lunga (massimo 1.000 caratteri).');
    }
    final String localId = _localId();
    final ChatMedia draft = ChatMedia(
      kind: kind,
      path: '',
      key: '',
      size: bytes.length,
      mime: mime,
      name: name,
      width: width,
      height: height,
      durationMs: durationMs,
      thumb: thumb,
    );
    // Copia in chiaro sul telefono: il fumetto si vede subito.
    final String fileName = '$localId.${draft.extension}';
    await (await store.fileFor(fileName)).writeAsBytes(bytes, flush: true);
    final ChatConversation? c = _conversations[conversationId];
    final ChatMessage local = ChatMessage(
      localId: localId,
      conversationId: conversationId,
      mine: true,
      kind: MessageKind.text,
      body: text,
      at: DateTime.now(),
      ticks: MessageTicks.sending,
      quote: _quoteOf(replyTo, c),
      forwarded: forwarded,
      media: draft,
      localFile: fileName,
    );
    (_pending[conversationId] ??= <ChatMessage>[]).add(local);
    _changed();
    await _deliver(local);
  }

  ChatQuote? _quoteOf(ChatMessage? replyTo, ChatConversation? c) => replyTo == null || !replyTo.isText
      ? null
      : ChatQuote(
          localId: replyTo.localId,
          authorId: replyTo.mine ? myId : (replyTo.senderId.isNotEmpty ? replyTo.senderId : (c?.peerId ?? '')),
          text: _quoteText(replyTo),
        );

  static String _quoteText(ChatMessage m) {
    final String base = m.body.isNotEmpty
        ? m.body
        : switch (m.media?.kind) {
            MediaKind.image => '📷 Foto',
            MediaKind.video => '🎬 Video',
            MediaKind.audio => '🎤 Messaggio vocale',
            MediaKind.file => '📄 ${m.media!.name}',
            null => '',
          };
    return base.length > ChatQuote.maxText ? base.substring(0, ChatQuote.maxText) : base;
  }

  /// Scarica e decifra l'allegato; chi riceve poi lo cancella dal server.
  Future<File> download(ChatMessage m) async {
    final ChatMedia? md = m.media;
    final ChatMediaFiles? store = files;
    final ChatMediaServer? server = media;
    if (md == null || store == null || server == null || md.path.isEmpty) {
      throw const ChatFailure('Allegato non disponibile.');
    }
    final File? have = await localFileOf(m);
    if (have != null) return have;
    final Future<File>? running = _downloading[m.localId];
    if (running != null) return running;
    final Future<File> job = _fetch(m, md, store, server);
    _downloading[m.localId] = job;
    _changed();
    try {
      return await job;
    } finally {
      _downloading.remove(m.localId);
      _changed();
    }
  }

  Future<File> _fetch(ChatMessage m, ChatMedia md, ChatMediaFiles store, ChatMediaServer server) async {
    final Uint8List blob = await server.download(md.path);
    final Uint8List plain = await MediaCipher.decrypt(blob, md.key);
    final String fileName = '${m.localId}.${md.extension}';
    final File file = await store.fileFor(fileName);
    await file.writeAsBytes(plain, flush: true);
    await _run(() => _appendEvent(ChatEvent(
      conversationId: m.conversationId,
      kind: ChatEventKind.saved,
      target: m.localId,
      byMe: true,
      at: DateTime.now(),
      value: fileName,
    )));
    if (!m.mine) await server.remove(md.path);
    return file;
  }

  /// Reazione al messaggio; la stessa reazione toccata di nuovo si toglie.
  Future<void> react(ChatMessage message, String emoji) async {
    if (!message.isText || message.serverId == null || !chatReactions.contains(emoji)) return;
    final String value = message.myReaction == emoji ? '' : emoji;
    await _event(
      message,
      ChatContent.react(localId: _localId(), target: message.localId, emoji: value),
      ChatEventKind.react,
      emoji: value,
    );
  }

  /// «Elimina per tutti»: solo i propri messaggi, entro 48 ore.
  Future<void> deleteForEveryone(ChatMessage message) async {
    if (!message.canDeleteForEveryone(DateTime.now())) {
      throw const ChatFailure('Questo messaggio non si può più eliminare per tutti.');
    }
    await _event(
      message,
      ChatContent.delete(localId: _localId(), target: message.localId),
      ChatEventKind.delete,
    );
    // L'allegato non serve più a nessuno: via anche dal server.
    final String? path = message.media?.path;
    if (path != null && path.isNotEmpty) await media?.remove(path);
  }

  /// «Elimina per me»: sparisce solo da questo telefono.
  Future<void> deleteForMe(ChatMessage message) async {
    final List<ChatMessage>? pending = _pending[message.conversationId];
    if (pending != null && pending.any((m) => m.localId == message.localId)) {
      pending.removeWhere((m) => m.localId == message.localId);
      _changed();
      return;
    }
    if (message.localFile.isNotEmpty) await files?.deleteAll(<String>[message.localFile]);
    await _run(() => _appendEvent(ChatEvent(
      conversationId: message.conversationId,
      kind: ChatEventKind.hide,
      target: message.localId,
      byMe: true,
      at: DateTime.now(),
    )));
    _changed();
  }

  Future<void> _event(ChatMessage message, ChatContent content, ChatEventKind kind, {String emoji = ''}) async {
    try {
      await _run(() async {
        final (int, DateTime) sent = await _transmit(message.conversationId, content);
        await _appendEvent(ChatEvent(
          conversationId: message.conversationId,
          kind: kind,
          target: message.localId,
          byMe: true,
          at: sent.$2,
          emoji: emoji,
          serverId: sent.$1,
        ));
      });
    } on ChatFailure {
      rethrow;
    } catch (_) {
      throw const ChatFailure('Non riuscito. Riprova.');
    } finally {
      _changed();
    }
  }

  /// Cifra e invia [content]; se la chat è cambiata nel frattempo si ricarica e si riprova.
  /// Da chiamare dentro [_run].
  Future<(int, DateTime)> _transmit(String conversationId, ChatContent content) async {
    Future<(int, DateTime)> attempt() async {
      final ChatConversation c = await _fresh(conversationId);
      final LocalSession s = await _ensureSession(c);
      final String payload = await _crypto!.encrypt(s.groupId, content.encode());
      return server.send(c.id, s.generation, payload);
    }

    try {
      return await attempt();
    } on ChatFailure catch (f) {
      if (!f.conflict) rethrow;
      // La chat è cambiata (l'altra persona l'ha riaperta): si ricarica e si riprova.
      await _syncInbox();
      await _loadConversations();
      return attempt();
    }
  }

  /// Cifra e carica l'allegato (fuori dalla fila: può richiedere tempo).
  Future<ChatMessage> _uploaded(ChatMessage local) async {
    final ChatMedia? draft = local.media;
    if (draft == null || draft.path.isNotEmpty) return local;
    final File? file = await localFileOf(local);
    if (file == null) throw const ChatFailure('File non più disponibile sul telefono.');
    final (Uint8List blob, String key) = await MediaCipher.encrypt(await file.readAsBytes());
    final String path = '${local.conversationId}/$myId/${MediaCipher.randomName()}.bin';
    await media!.upload(path, blob);
    final ChatMessage ready = ChatMessage(
      localId: local.localId,
      conversationId: local.conversationId,
      mine: true,
      kind: local.kind,
      body: local.body,
      at: local.at,
      ticks: local.ticks,
      quote: local.quote,
      forwarded: local.forwarded,
      media: ChatMedia(
        kind: draft.kind,
        path: path,
        key: key,
        size: draft.size,
        mime: draft.mime,
        name: draft.name,
        width: draft.width,
        height: draft.height,
        durationMs: draft.durationMs,
        thumb: draft.thumb,
      ),
      localFile: local.localFile,
    );
    final List<ChatMessage>? list = _pending[local.conversationId];
    final int i = list?.indexWhere((m) => m.localId == local.localId) ?? -1;
    if (i >= 0) list![i] = ready;
    return ready;
  }

  Future<void> _deliver(ChatMessage pending) async {
    ChatMessage local = pending;
    try {
      local = await _uploaded(pending);
      final ChatMessage ready = local;
      await _run(() async {
        final ChatMedia? md = ready.media;
        final (int, DateTime) sent = await _transmit(
          ready.conversationId,
          md == null
              ? ChatContent.text(
                  ready.body,
                  localId: ready.localId,
                  quote: ready.quote,
                  forwarded: ready.forwarded,
                )
              : ChatContent.media(
                  ready.body,
                  localId: ready.localId,
                  media: md,
                  quote: ready.quote,
                  forwarded: ready.forwarded,
                ),
        );
        final ChatMessage local = ready;
        _pending[local.conversationId]?.removeWhere((m) => m.localId == local.localId);
        await _append(ChatMessage(
          localId: local.localId,
          conversationId: local.conversationId,
          serverId: sent.$1,
          mine: true,
          kind: MessageKind.text,
          body: local.body,
          at: sent.$2,
          quote: local.quote,
          forwarded: local.forwarded,
          media: local.media,
          localFile: local.localFile,
        ));
        await _loadConversations();
      });
    } on ChatFailure {
      _markFailed(local);
      rethrow;
    } catch (_) {
      _markFailed(local);
      throw const ChatFailure('Messaggio non inviato. Riprova.');
    } finally {
      _changed();
    }
  }

  void _markFailed(ChatMessage local) {
    final List<ChatMessage>? list = _pending[local.conversationId];
    final int i = list?.indexWhere((m) => m.localId == local.localId) ?? -1;
    if (i >= 0) list![i] = local.copyWith(ticks: MessageTicks.failed);
  }

  /// Stato della chat aggiornato da pochi secondi (serve prima di scrivere).
  Future<ChatConversation> _fresh(String id) async {
    if (DateTime.now().difference(_conversationsAt) > const Duration(seconds: 5) ||
        !_conversations.containsKey(id)) {
      await _loadConversations();
    }
    final ChatConversation? c = _conversations[id];
    if (c == null) throw const ChatFailure('Questa chat non è disponibile.');
    return c;
  }

  bool _valid(ChatConversation c, LocalSession? s) =>
      s != null &&
      c.generation > 0 &&
      s.generation == c.generation &&
      s.groupId == c.groupId &&
      !c.peerChangedPhone &&
      c.myJoinedKey == _myKey;

  /// La chat cifrata pronta per scrivere: se manca o è vecchia (telefono cambiato da una
  /// delle due parti) si riapre con un nuovo pacchetto chiave dell'altra persona.
  Future<LocalSession> _ensureSession(ChatConversation c) async {
    if (c.isGroup) return _ensureGroupSession(c);
    LocalSession? s = await store.session(c.id);
    if (_valid(c, s)) return s!;
    // Forse è appena arrivato l'invito della generazione attuale.
    await _syncInbox();
    s = await store.session(c.id);
    if (_valid(c, s)) return s!;

    final ChatCrypto crypto = _crypto!;
    final ClaimedKeyPackage kp = await server.claimKeyPackage(c.id);
    final StartedGroup started = await crypto.startGroup(
      peerId: c.peerId,
      peerPackage: kp.package,
      peerSignatureKey: kp.signatureKey,
    );
    final int generation;
    try {
      generation = await server.start(c.id, c.generation, started.groupId, started.welcome);
    } catch (_) {
      await crypto.dropGroup(started.groupId);
      rethrow;
    }
    if (s != null && s.groupId != started.groupId) await crypto.dropGroup(s.groupId);
    final LocalSession fresh = LocalSession(generation, started.groupId);
    await store.setSession(c.id, fresh);
    if (c.generation > 0) await _notice(c.id, _noticeTime(c.id), renewed: true);
    _conversations[c.id] = c.copyWith(
      generation: generation,
      groupId: started.groupId,
      peerSignatureKey: kp.signatureKey,
      peerJoinedKey: kp.signatureKey,
      myJoinedKey: _myKey,
    );
    return fresh;
  }

  // ---------------------------------------------------------------- gruppi (Blocco 4)

  Future<LocalSession> _ensureGroupSession(ChatConversation c) async {
    LocalSession? s = await store.session(c.id);
    bool ok(ChatConversation c, LocalSession? s) =>
        s != null && c.myMlsState == 'in' && c.generation > 0 && s.generation == c.generation;
    if (ok(c, s)) return s!;
    await _syncInbox();
    await _loadConversations();
    final ChatConversation now = _conversations[c.id] ?? c;
    s = await store.session(c.id);
    if (ok(now, s)) return s!;
    // Il creatore può far nascere il gruppo cifrato da sé.
    if (now.isAdmin && now.generation == 0) {
      await _maintainGroup(now);
      s = await store.session(c.id);
      final ChatConversation after = _conversations[c.id] ?? now;
      if (ok(after, s)) return s!;
    }
    if (now.myMlsState == 'in' && (s == null || s.generation < now.generation)) {
      _lost.add(c.id);
      try {
        await server.groupRejoin(c.id);
        _lost.remove(c.id);
      } catch (_) {
        // Si riprova al prossimo giro.
      }
    }
    throw const ChatFailure(
      'Un amministratore deve ancora aggiungerti al gruppo cifrato: succede da solo appena '
      'apre l\'app. Riprova tra poco.',
    );
  }

  /// Gli amministratori tengono allineato il gruppo cifrato: aggiungono chi è entrato,
  /// tolgono chi è uscito, riaggiungono chi ha cambiato telefono.
  Future<void> _maintainGroups() async {
    for (final ChatConversation c in _conversations.values.toList()) {
      if (!c.isGroup || !c.isAdmin || c.myMlsState != 'in' || c.isRequest) continue;
      if (c.generation > 0 && c.pending == 0) continue;
      try {
        await _maintainGroup(c);
      } catch (_) {
        // Un altro amministratore è stato più veloce, o manca un pacchetto: al prossimo giro.
      }
    }
  }

  Future<void> _maintainGroup(ChatConversation c) async {
    final ChatCrypto crypto = _crypto!;
    final List<GroupMember> members = await server.groupMembers(c.id);
    _names[c.id] = <String, String>{
      ...?_names[c.id],
      for (final GroupMember m in members) m.userId: m.displayName,
    };
    LocalSession? s = await store.session(c.id);
    int generation = c.generation;
    String groupId;
    if (generation == 0) {
      if (s != null) await crypto.dropGroup(s.groupId);
      groupId = await crypto.createGroupAlone();
    } else {
      if (s == null || s.generation != generation) return;
      groupId = s.groupId;
      // 1) Togliere chi è uscito e i telefoni vecchi.
      final List<GroupMember> leaving = <GroupMember>[
        for (final GroupMember m in members)
          if (m.mlsState == 'to_remove' || m.mlsState == 'to_readd') m,
      ];
      if (leaving.isNotEmpty) {
        final String? commit = await crypto.removeFromGroup(groupId, <GroupLeaver>[
          for (final GroupMember m in leaving)
            GroupLeaver(m.userId, keepKey: m.mlsState == 'to_readd' ? m.signatureKey : null),
        ]);
        if (commit != null) {
          generation = await _commit(c, generation, groupId, commit: commit,
              removed: <String>[for (final GroupMember m in leaving) m.userId]);
        }
      }
    }
    // 2) Aggiungere chi è entrato (e chi ha un telefono nuovo).
    final List<GroupJoiner> joiners = <GroupJoiner>[];
    for (final GroupMember m in members) {
      if (!m.isActive || (m.mlsState != 'to_add' && m.mlsState != 'to_readd')) continue;
      try {
        final ClaimedKeyPackage kp = await server.groupClaimKeyPackage(c.id, m.userId);
        joiners.add(GroupJoiner(m.userId, kp.package, kp.signatureKey));
      } catch (_) {
        // Non ha ancora attivato la chat su questo telefono: al prossimo giro.
      }
    }
    if (generation == 0) {
      String? welcome;
      if (joiners.isNotEmpty) {
        final (_, String w) = await crypto.addToGroup(groupId, joiners);
        await crypto.confirmCommit(groupId);
        welcome = w;
      }
      try {
        generation = await server.groupCommit(c.id, 0, groupId: groupId, welcome: welcome,
            added: <String>[for (final GroupJoiner j in joiners) j.userId]);
      } catch (_) {
        await crypto.dropGroup(groupId);
        rethrow;
      }
      await store.setSession(c.id, LocalSession(generation, groupId));
    } else if (joiners.isNotEmpty) {
      final (String commit, String welcome) = await crypto.addToGroup(groupId, joiners);
      generation = await _commit(c, generation, groupId, commit: commit, welcome: welcome,
          added: <String>[for (final GroupJoiner j in joiners) j.userId]);
    }
    await _verifyRoster(c.id, groupId, members, joiners);
    _conversations[c.id] = c.copyWith(generation: generation, groupId: groupId, pending: 0);
  }

  /// Invia il commit; se il server lo accetta diventa effettivo, altrimenti si annulla.
  Future<int> _commit(
    ChatConversation c,
    int generation,
    String groupId, {
    required String commit,
    String? welcome,
    List<String> added = const <String>[],
    List<String> removed = const <String>[],
  }) async {
    final ChatCrypto crypto = _crypto!;
    final int next;
    try {
      next = await server.groupCommit(c.id, generation, groupId: groupId, commit: commit,
          welcome: welcome, added: added, removed: removed);
    } catch (_) {
      await crypto.discardCommit(groupId);
      rethrow;
    }
    await crypto.confirmCommit(groupId);
    await store.setSession(c.id, LocalSession(next, groupId));
    return next;
  }

  /// Dopo un'aggiunta: dentro il gruppo cifrato ci sono solo membri con la chiave giusta.
  Future<void> _verifyRoster(
    String conversationId,
    String groupId,
    List<GroupMember> members,
    List<GroupJoiner> joiners,
  ) async {
    if (joiners.isEmpty) return;
    final Map<String, Set<String>> roster = await _crypto!.roster(groupId);
    final bool fine = joiners.every((j) => roster[j.userId]?.contains(j.signatureKey) ?? false);
    if (!fine) {
      await _notice(conversationId, _noticeTime(conversationId), renewed: false,
          text: 'Attenzione: la chiave di un membro non corrisponde. Verifica con lui di persona.');
    }
  }

  /// Nuovo gruppo con i contatti scelti (chi non ti ha in rubrica riceve un invito).
  Future<String> createGroup(String title, List<String> members) async {
    if (!_ready) await start();
    final String id = await server.createGroup(title.trim(), members);
    await _run(() async {
      await _loadConversations();
      final ChatConversation? c = _conversations[id];
      if (c != null) {
        try {
          await _maintainGroup(c);
        } catch (_) {
          // Ci si riprova al prossimo aggiornamento.
        }
        await _loadConversations();
      }
    });
    _changed();
    return id;
  }

  Future<List<GroupMember>> groupMembers(String conversationId) async {
    final List<GroupMember> list = await server.groupMembers(conversationId);
    _names[conversationId] = <String, String>{
      ...?_names[conversationId],
      for (final GroupMember m in list) m.userId: m.displayName,
    };
    return list;
  }

  Future<void> _afterGroupChange() async {
    await _run(() async {
      await _loadConversations();
      await _maintainGroups();
    });
    _changed();
    unawaited(refresh());
  }

  Future<int> addToGroup(String conversationId, List<String> members) async {
    final int n = await server.groupAdd(conversationId, members);
    await _afterGroupChange();
    return n;
  }

  Future<void> removeFromGroup(String conversationId, String userId) async {
    await server.groupRemove(conversationId, userId);
    await _afterGroupChange();
  }

  /// Esce dal gruppo: sparisce dalla lista e dal telefono.
  Future<void> leaveGroup(String conversationId) async {
    await server.groupRemove(conversationId, myId);
    await _run(() async {
      final LocalSession? s = await store.session(conversationId);
      if (s != null) await _crypto?.dropGroup(s.groupId);
      await store.deleteConversation(conversationId);
      _messages.remove(conversationId);
      await _loadConversations();
    });
    _changed();
  }

  Future<void> setGroupAdmin(String conversationId, String userId, bool admin) async {
    await server.groupSetAdmin(conversationId, userId, admin);
    await _afterGroupChange();
  }

  Future<void> updateGroup(String conversationId, {required String title, required String description}) async {
    await server.groupUpdate(conversationId, title.trim(), description.trim());
    await _afterGroupChange();
  }

  final Map<String, Uint8List?> _photos = <String, Uint8List?>{};

  /// Foto del gruppo (null se non c'è). Tenuta in memoria per versione.
  Future<Uint8List?> groupPhoto(ChatConversation c) async {
    if (!c.isGroup || c.photoVersion == 0 || media == null) return null;
    final String key = '${c.id}:${c.photoVersion}';
    if (_photos.containsKey(key)) return _photos[key];
    try {
      return _photos[key] = await media!.downloadGroupPhoto(c.id);
    } catch (_) {
      return null;
    }
  }

  Future<void> setGroupPhoto(String conversationId, Uint8List jpeg) async {
    final ChatConversation? c = _conversations[conversationId];
    if (c == null || media == null) throw const ChatFailure('Foto non disponibile.');
    await media!.uploadGroupPhoto(conversationId, jpeg);
    await server.groupUpdate(conversationId, c.title, c.description, photoChanged: true);
    await _afterGroupChange();
  }

  /// Silenzia le notifiche di una chat per [duration] (null = sempre) o le riattiva.
  Future<void> setMute(String conversationId, {Duration? duration, bool unmute = false}) async {
    final String? until = unmute
        ? null
        : (duration == null ? 'infinity' : DateTime.now().add(duration).toUtc().toIso8601String());
    await server.setMute(conversationId, until);
    await _run(_loadConversations);
    _changed();
  }

  /// Un messaggio è appena arrivato con l'app aperta (notifica): si controlla subito.
  void ping() => unawaited(refresh());

  Future<String> inviteCode(String conversationId, {bool renew = false}) =>
      server.groupInviteCode(conversationId, renew: renew);

  Future<void> revokeInvite(String conversationId) => server.groupInviteRevoke(conversationId);

  Future<GroupInviteInfo> inviteInfo(String code) => server.groupInviteInfo(code.trim().toUpperCase());

  /// Entra con un codice: un amministratore ti aggiunge al gruppo cifrato appena apre l'app.
  Future<String> joinWithCode(String code) async {
    if (!_ready) await start();
    final String id = await server.groupJoin(code.trim().toUpperCase());
    await _run(_loadConversations);
    _changed();
    return id;
  }
}

/// Testo dell'avviso di gruppo («Anna ha aggiunto Bruno»). [name] dà «Tu» per sé stessi.
String groupEventText(Map<String, dynamic> ev, String Function(String id) name) {
  final String by = ev['by'] is String ? ev['by'] as String : '';
  final String who = ev['who'] is String ? ev['who'] as String : '';
  final bool me = name(by) == 'Tu';
  String list(Object? ids) {
    final List<String> names = <String>[
      for (final Object? id in (ids as List?) ?? const <Object>[])
        if (id is String) name(id) == 'Tu' ? 'te' : name(id),
    ];
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';
  }

  final String added = list(ev['added']);
  final String invited = list(ev['invited']);
  String withInvites(String base) {
    if (invited.isEmpty) return base;
    final String inv = me ? 'Hai invitato $invited' : '${name(by)} ha invitato $invited';
    return base.isEmpty ? inv : '$base · $inv';
  }

  switch (ev['t']) {
    case 'created':
      final String base = me ? 'Hai creato il gruppo' : '${name(by)} ha creato il gruppo';
      return withInvites(added.isEmpty ? base : '$base con $added');
    case 'added':
      final String base = added.isEmpty ? '' : (me ? 'Hai aggiunto $added' : '${name(by)} ha aggiunto $added');
      return withInvites(base);
    case 'removed':
      final String target = name(who) == 'Tu' ? 'te' : name(who);
      return me ? 'Hai rimosso $target' : '${name(by)} ha rimosso $target';
    case 'left':
      return name(who) == 'Tu' ? 'Sei uscito dal gruppo' : '${name(who)} è uscito dal gruppo';
    case 'joined':
      return me ? 'Sei entrato nel gruppo' : '${name(by)} è entrato nel gruppo';
    case 'admin':
      return name(who) == 'Tu' ? 'Ora sei amministratore' : '${name(who)} ora è amministratore';
    case 'not_admin':
      return name(who) == 'Tu' ? 'Non sei più amministratore' : '${name(who)} non è più amministratore';
    case 'title':
      final String title = ev['title'] is String ? ev['title'] as String : '';
      return me ? 'Hai cambiato il nome in «$title»' : '${name(by)} ha cambiato il nome in «$title»';
    case 'photo':
      return me ? 'Hai cambiato la foto del gruppo' : '${name(by)} ha cambiato la foto del gruppo';
    default:
      return '';
  }
}

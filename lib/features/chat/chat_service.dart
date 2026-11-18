import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
        // Come WhatsApp: una chat compare nella lista dal primo messaggio.
        if (c.isRequest == requests && _visible(c.id).isNotEmpty)
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

  List<ChatMessage> _visible(String id) =>
      <ChatMessage>[..._messagesOf(id), ...?_pending[id]];

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
          if (e.isWelcome) {
            await _accept(crypto, e);
          } else {
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
  }

  Future<void> _accept(ChatCrypto crypto, ChatEnvelope e) async {
    final String groupId;
    try {
      groupId = await crypto.joinGroup(e.payload, peerId: e.senderId);
    } catch (_) {
      // Invito per un telefono precedente: chi scrive per primo riaprirà la chat.
      return;
    }
    final LocalSession? old = await store.session(e.conversationId);
    if (old != null && old.groupId != groupId) await crypto.dropGroup(old.groupId);
    await store.setSession(e.conversationId, LocalSession(e.generation, groupId));
    if (old != null) await _notice(e.conversationId, e.createdAt, renewed: true);
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

  Future<void> _notice(String conversationId, DateTime at, {required bool renewed}) => _append(
    ChatMessage(
      localId: 'avviso-${at.microsecondsSinceEpoch}',
      conversationId: conversationId,
      mine: false,
      kind: MessageKind.notice,
      body: renewed ? 'Chat cifrata rinnovata: uno dei due ha cambiato telefono.' : '',
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
          authorId: replyTo.mine ? myId : (c?.peerId ?? ''),
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
    if (c.generation > 0) await _notice(c.id, DateTime.now(), renewed: true);
    _conversations[c.id] = ChatConversation(
      id: c.id,
      status: c.status,
      generation: generation,
      groupId: started.groupId,
      peerId: c.peerId,
      peerUsername: c.peerUsername,
      peerName: c.peerName,
      peerAvatarPath: c.peerAvatarPath,
      peerSignatureKey: kp.signatureKey,
      peerJoinedKey: kp.signatureKey,
      myJoinedKey: _myKey,
      peerDeliveredUpto: c.peerDeliveredUpto,
      peerReadUpto: c.peerReadUpto,
      myReadUpto: c.myReadUpto,
      lastMessageId: c.lastMessageId,
      lastMessageAt: c.lastMessageAt,
      createdAt: c.createdAt,
    );
    return fresh;
  }
}

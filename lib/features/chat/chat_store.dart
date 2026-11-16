import 'dart:convert';
import 'dart:io';

import 'chat_models.dart';

/// Stato di una chat sul telefono: con quale generazione e gruppo cifrato è aperta.
class LocalSession {
  const LocalSession(this.generation, this.groupId);

  final int generation;
  final String groupId;

  Map<String, Object> toJson() => <String, Object>{'g': generation, 'id': groupId};
}

/// Messaggi in chiaro e stato delle chat: restano solo su questo telefono.
abstract class ChatStore {
  Future<int> cursor();

  Future<void> setCursor(int value);

  Future<LocalSession?> session(String conversationId);

  Future<void> setSession(String conversationId, LocalSession? session);

  /// Messaggi con eliminazioni e reazioni già applicate.
  Future<List<ChatMessage>> messages(String conversationId);

  Future<void> append(ChatMessage message);

  /// Eventi (elimina per tutti, reazioni, elimina per me) su messaggi già salvati.
  Future<void> appendEvent(ChatEvent event);

  /// Il messaggio del server [serverId] è già stato elaborato (messaggio o evento).
  Future<bool> hasServerId(String conversationId, int serverId);

  Future<void> deleteConversation(String conversationId);
}

/// Versione in memoria (test e anteprime).
class MemoryChatStore implements ChatStore {
  int _cursor = 0;
  final Map<String, LocalSession> _sessions = <String, LocalSession>{};
  final Map<String, List<ChatMessage>> _messages = <String, List<ChatMessage>>{};
  final Map<String, List<ChatEvent>> _events = <String, List<ChatEvent>>{};

  @override
  Future<int> cursor() async => _cursor;

  @override
  Future<void> setCursor(int value) async => _cursor = value;

  @override
  Future<LocalSession?> session(String conversationId) async => _sessions[conversationId];

  @override
  Future<void> setSession(String conversationId, LocalSession? session) async {
    if (session == null) {
      _sessions.remove(conversationId);
    } else {
      _sessions[conversationId] = session;
    }
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => foldChatEvents(
    List<ChatMessage>.of(_messages[conversationId] ?? const <ChatMessage>[]),
    _events[conversationId] ?? const <ChatEvent>[],
  );

  @override
  Future<void> append(ChatMessage message) async =>
      (_messages[message.conversationId] ??= <ChatMessage>[]).add(message);

  @override
  Future<void> appendEvent(ChatEvent event) async =>
      (_events[event.conversationId] ??= <ChatEvent>[]).add(event);

  @override
  Future<bool> hasServerId(String conversationId, int serverId) async =>
      (_messages[conversationId] ?? const <ChatMessage>[]).any((m) => m.serverId == serverId) ||
      (_events[conversationId] ?? const <ChatEvent>[]).any((e) => e.serverId == serverId);

  @override
  Future<void> deleteConversation(String conversationId) async {
    _messages.remove(conversationId);
    _events.remove(conversationId);
    _sessions.remove(conversationId);
  }
}

/// Versione su file nella cartella privata dell'app: una riga JSON per messaggio (si
/// aggiunge in fondo, non si riscrive), più un piccolo file di stato.
class FileChatStore implements ChatStore {
  /// [directory] può arrivare più tardi (la cartella dell'app si chiede al sistema).
  FileChatStore(this._directory);

  final Future<Directory> _directory;
  Directory? _dir;
  Map<String, Object?>? _state;
  final Map<String, List<ChatMessage>> _cache = <String, List<ChatMessage>>{};
  final Map<String, List<ChatEvent>> _eventCache = <String, List<ChatEvent>>{};

  Future<Directory> get _d async => _dir ??= await _directory;

  Future<File> get _stateFile async => File('${(await _d).path}/stato.json');

  Future<File> _thread(String conversationId) async => File(
    '${(await _d).path}/chat_${conversationId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}.jsonl',
  );

  Future<Map<String, Object?>> _load() async {
    final Map<String, Object?>? cached = _state;
    if (cached != null) return cached;
    Map<String, Object?> state = <String, Object?>{};
    try {
      final File file = await _stateFile;
      if (file.existsSync()) {
        final Object? json = jsonDecode(await file.readAsString());
        if (json is Map) state = Map<String, Object?>.from(json);
      }
    } catch (_) {
      state = <String, Object?>{};
    }
    return _state = state;
  }

  Future<void> _save() async {
    (await _d).createSync(recursive: true);
    final File file = await _stateFile;
    final File tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_state), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<int> cursor() async => ((await _load())['cursor'] as num?)?.toInt() ?? 0;

  @override
  Future<void> setCursor(int value) async {
    (await _load())['cursor'] = value;
    await _save();
  }

  @override
  Future<LocalSession?> session(String conversationId) async {
    final Object? sessions = (await _load())['sessions'];
    if (sessions is! Map) return null;
    final Object? s = sessions[conversationId];
    if (s is! Map || s['g'] is! num || s['id'] is! String) return null;
    return LocalSession((s['g'] as num).toInt(), s['id'] as String);
  }

  @override
  Future<void> setSession(String conversationId, LocalSession? session) async {
    final Map<String, Object?> state = await _load();
    final Map<String, Object?> sessions = state['sessions'] is Map
        ? Map<String, Object?>.from(state['sessions'] as Map)
        : <String, Object?>{};
    if (session == null) {
      sessions.remove(conversationId);
    } else {
      sessions[conversationId] = session.toJson();
    }
    state['sessions'] = sessions;
    await _save();
  }

  /// Legge il file della chat una volta: messaggi ed eventi.
  Future<void> _read(String conversationId) async {
    if (_cache.containsKey(conversationId)) return;
    final List<ChatMessage> list = <ChatMessage>[];
    final List<ChatEvent> events = <ChatEvent>[];
    final File f = await _thread(conversationId);
    if (f.existsSync()) {
      for (final String line in await f.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final Map<String, dynamic> j = Map<String, dynamic>.from(jsonDecode(line) as Map);
          if (j.containsKey('ev')) {
            final ChatEvent? e = ChatEvent.fromJson(conversationId, j);
            if (e != null) events.add(e);
          } else {
            final ChatMessage? m = ChatMessage.fromJson(conversationId, j);
            if (m != null) list.add(m);
          }
        } catch (_) {
          // Riga rovinata (spegnimento a metà scrittura): si salta.
        }
      }
    }
    _cache[conversationId] = list;
    _eventCache[conversationId] = events;
  }

  Future<void> _write(String conversationId, Map<String, Object?> json) async {
    (await _d).createSync(recursive: true);
    await (await _thread(conversationId))
        .writeAsString('${jsonEncode(json)}\n', mode: FileMode.append, flush: true);
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId) async {
    await _read(conversationId);
    return foldChatEvents(List<ChatMessage>.of(_cache[conversationId]!), _eventCache[conversationId]!);
  }

  @override
  Future<void> append(ChatMessage message) async {
    await _read(message.conversationId);
    await _write(message.conversationId, message.toJson());
    _cache[message.conversationId]!.add(message);
  }

  @override
  Future<void> appendEvent(ChatEvent event) async {
    await _read(event.conversationId);
    await _write(event.conversationId, event.toJson());
    _eventCache[event.conversationId]!.add(event);
  }

  @override
  Future<bool> hasServerId(String conversationId, int serverId) async {
    await _read(conversationId);
    return _cache[conversationId]!.any((m) => m.serverId == serverId) ||
        _eventCache[conversationId]!.any((e) => e.serverId == serverId);
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    _cache.remove(conversationId);
    _eventCache.remove(conversationId);
    final File f = await _thread(conversationId);
    if (f.existsSync()) f.deleteSync();
    await setSession(conversationId, null);
  }
}

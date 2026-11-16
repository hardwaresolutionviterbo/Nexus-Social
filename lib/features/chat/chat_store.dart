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

  Future<List<ChatMessage>> messages(String conversationId);

  Future<void> append(ChatMessage message);

  Future<void> deleteConversation(String conversationId);
}

/// Versione in memoria (test e anteprime).
class MemoryChatStore implements ChatStore {
  int _cursor = 0;
  final Map<String, LocalSession> _sessions = <String, LocalSession>{};
  final Map<String, List<ChatMessage>> _messages = <String, List<ChatMessage>>{};

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
  Future<List<ChatMessage>> messages(String conversationId) async =>
      List<ChatMessage>.of(_messages[conversationId] ?? const <ChatMessage>[]);

  @override
  Future<void> append(ChatMessage message) async =>
      (_messages[message.conversationId] ??= <ChatMessage>[]).add(message);

  @override
  Future<void> deleteConversation(String conversationId) async {
    _messages.remove(conversationId);
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

  @override
  Future<List<ChatMessage>> messages(String conversationId) async {
    final List<ChatMessage>? cached = _cache[conversationId];
    if (cached != null) return List<ChatMessage>.of(cached);
    final List<ChatMessage> list = <ChatMessage>[];
    final File f = await _thread(conversationId);
    if (f.existsSync()) {
      for (final String line in await f.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final ChatMessage? m = ChatMessage.fromJson(
            conversationId,
            Map<String, dynamic>.from(jsonDecode(line) as Map),
          );
          if (m != null) list.add(m);
        } catch (_) {
          // Riga rovinata (spegnimento a metà scrittura): si salta.
        }
      }
    }
    _cache[conversationId] = list;
    return List<ChatMessage>.of(list);
  }

  @override
  Future<void> append(ChatMessage message) async {
    await messages(message.conversationId);
    (await _d).createSync(recursive: true);
    await (await _thread(message.conversationId))
        .writeAsString('${jsonEncode(message.toJson())}\n', mode: FileMode.append, flush: true);
    _cache[message.conversationId]!.add(message);
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    _cache.remove(conversationId);
    final File f = await _thread(conversationId);
    if (f.existsSync()) f.deleteSync();
    await setSession(conversationId, null);
  }
}

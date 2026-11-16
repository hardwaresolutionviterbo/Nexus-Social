import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, SupabaseClient;

import 'chat_models.dart';

/// Funzioni della chat sul server (migrazione 0019). Il server riceve solo testo cifrato.
/// Nei test: una versione in memoria con le stesse regole.
abstract class ChatServer {
  /// Chiave registrata per la chat di questo account (null se mai attivata).
  Future<String?> myIdentity();

  Future<void> registerIdentity(String signatureKey, List<String> packages);

  Future<int> addKeyPackages(List<String> packages);

  Future<int> keyPackageCount();

  Future<String> openDirect(String userId);

  Future<ClaimedKeyPackage> claimKeyPackage(String conversationId);

  /// Nuova generazione della chat cifrata. [ChatFailure.conflict] se è già cambiata.
  Future<int> start(String conversationId, int generation, String groupId, String welcome);

  Future<(int, DateTime)> send(String conversationId, int generation, String payload);

  Future<List<ChatEnvelope>> sync(int after);

  Future<List<ChatConversation>> conversations();

  Future<void> mark(String conversationId, {required int delivered, required int read});

  Future<void> respondRequest(String conversationId, bool accept);
}

class SupabaseChatServer implements ChatServer {
  SupabaseChatServer(this._client);

  final SupabaseClient _client;

  Future<Object?> _rpc(String name, [Map<String, Object?>? params]) async {
    try {
      return await _client.rpc(name, params: params);
    } on PostgrestException catch (e) {
      throw failureFor(e.code, e.message);
    } catch (_) {
      throw const ChatFailure('Connessione assente. Riprova tra poco.');
    }
  }

  /// Messaggio per un errore del server, senza dati tecnici.
  static ChatFailure failureFor(String? code, String message) {
    switch (code) {
      case '40001':
        return const ChatFailure('La chat è appena cambiata: riprova.', conflict: true);
      case '22023':
        // Messaggi scritti dal server per l'utente (migrazione 0019).
        return ChatFailure(message.endsWith('.') ? message : '$message.');
      case '42501':
        if (message.contains('sospeso')) {
          return const ChatFailure('Il tuo account è sospeso: non puoi scrivere.');
        }
        if (message.contains('profilo')) return const ChatFailure('Completa prima il profilo.');
        return const ChatFailure('Questa chat non è disponibile.');
      default:
        return const ChatFailure('Qualcosa non ha funzionato. Riprova.');
    }
  }

  List<Map<String, dynamic>> _rows(Object? r) =>
      r is List ? r.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];

  @override
  Future<String?> myIdentity() async => await _rpc('chat_my_identity') as String?;

  @override
  Future<void> registerIdentity(String signatureKey, List<String> packages) async {
    await _rpc('chat_register_identity', {'p_signature_key': signatureKey, 'p_packages': packages});
  }

  @override
  Future<int> addKeyPackages(List<String> packages) async =>
      ((await _rpc('chat_add_key_packages', {'p_packages': packages})) as num?)?.toInt() ?? 0;

  @override
  Future<int> keyPackageCount() async =>
      ((await _rpc('chat_key_package_count')) as num?)?.toInt() ?? 0;

  @override
  Future<String> openDirect(String userId) async =>
      (await _rpc('chat_open_direct', {'p_user': userId})) as String;

  @override
  Future<ClaimedKeyPackage> claimKeyPackage(String conversationId) async {
    final rows = _rows(await _rpc('chat_claim_key_package', {'p_conversation': conversationId}));
    if (rows.isEmpty) {
      throw const ChatFailure('L\'altra persona deve aprire l\'app per attivare la chat.');
    }
    return ClaimedKeyPackage(rows.first['package'] as String, rows.first['signature_key'] as String);
  }

  @override
  Future<int> start(String conversationId, int generation, String groupId, String welcome) async =>
      ((await _rpc('chat_start', {
        'p_conversation': conversationId,
        'p_generation': generation,
        'p_group_id': groupId,
        'p_welcome': welcome,
      })) as num).toInt();

  @override
  Future<(int, DateTime)> send(String conversationId, int generation, String payload) async {
    final rows = _rows(await _rpc('chat_send', {
      'p_conversation': conversationId,
      'p_generation': generation,
      'p_payload': payload,
    }));
    if (rows.isEmpty) throw const ChatFailure('Messaggio non inviato. Riprova.');
    return (
      (rows.first['id'] as num).toInt(),
      DateTime.tryParse('${rows.first['created_at']}')?.toLocal() ?? DateTime.now(),
    );
  }

  @override
  Future<List<ChatEnvelope>> sync(int after) async =>
      _rows(await _rpc('chat_sync', {'p_after': after, 'p_limit': 200}))
          .map(ChatEnvelope.fromRow)
          .toList();

  @override
  Future<List<ChatConversation>> conversations() async =>
      _rows(await _rpc('chat_conversations')).map(ChatConversation.fromRow).toList();

  @override
  Future<void> mark(String conversationId, {required int delivered, required int read}) async {
    await _rpc('chat_mark', {
      'p_conversation': conversationId,
      'p_delivered': delivered,
      'p_read': read,
    });
  }

  @override
  Future<void> respondRequest(String conversationId, bool accept) async {
    await _rpc('chat_respond_request', {'p_conversation': conversationId, 'p_accept': accept});
  }
}

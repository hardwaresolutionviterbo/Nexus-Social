import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, RealtimeChannel, RealtimeChannelConfig, RealtimeSubscribeStatus, SupabaseClient;

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

  /// Tocchi in tempo reale sul canale privato (Blocco 9): «c'è qualcosa di nuovo».
  Stream<void> wakeUps(String uid);

  /// Il canale in tempo reale è collegato.
  bool get live;

  /// Messaggio di una chiamata (Blocco 8): come [send], ma [ring] fa squillare il telefono
  /// dell'altra persona e gli altri passaggi non mandano notifiche.
  Future<(int, DateTime)> callSignal(String conversationId, int generation, String payload,
      {required bool ring, required bool video});

  Future<List<ChatEnvelope>> sync(int after);

  Future<List<ChatConversation>> conversations();

  Future<void> mark(String conversationId, {required int delivered, required int read});

  Future<void> respondRequest(String conversationId, bool accept);

  // ---- Gruppi (Blocco 4)

  Future<String> createGroup(String title, List<String> members);

  Future<int> groupAdd(String conversationId, List<String> members);

  /// Toglie [userId] (amministratori) o esce dal gruppo (se è chi chiama).
  Future<void> groupRemove(String conversationId, String userId);

  Future<void> groupSetAdmin(String conversationId, String userId, bool admin);

  Future<void> groupUpdate(String conversationId, String title, String description, {bool photoChanged = false});

  Future<String> groupInviteCode(String conversationId, {bool renew = false});

  Future<void> groupInviteRevoke(String conversationId);

  Future<GroupInviteInfo> groupInviteInfo(String code);

  Future<String> groupJoin(String code);

  Future<List<GroupMember>> groupMembers(String conversationId);

  Future<ClaimedKeyPackage> groupClaimKeyPackage(String conversationId, String userId);

  /// Modifica del gruppo cifrato. [ChatFailure.conflict] se la generazione è cambiata.
  Future<int> groupCommit(
    String conversationId,
    int generation, {
    required String groupId,
    String? commit,
    String? welcome,
    List<String> added = const <String>[],
    List<String> removed = const <String>[],
  });

  Future<void> groupRejoin(String conversationId);

  /// «Silenzia» (Blocco 5): [until] ISO 8601, 'infinity' per sempre, null per riattivare.
  Future<void> setMute(String conversationId, String? until);

  /// Segnalazione (Blocco 7): solo i messaggi scelti da chi segnala, in chiaro.
  Future<void> report(String conversationId, String reason, String details, List<Map<String, String>> messages);

  /// Blocca una persona (stessa funzione della Privacy, Fase 2).
  Future<void> blockUser(String userId);
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
        if (message.contains('amministratori')) {
          return const ChatFailure('Solo gli amministratori del gruppo possono farlo.');
        }
        if (message.toLowerCase().contains('gruppo')) {
          return const ChatFailure('Non fai più parte di questo gruppo.');
        }
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

  bool _live = false;

  @override
  bool get live => _live;

  @override
  Stream<void> wakeUps(String uid) {
    RealtimeChannel? channel;
    late final StreamController<void> out;
    out = StreamController<void>.broadcast(
      onListen: () {
        channel = _client.channel('u:$uid', opts: const RealtimeChannelConfig(private: true))
          ..onBroadcast(event: 'nuovo', callback: (_) {
            if (!out.isClosed) out.add(null);
          })
          ..subscribe((RealtimeSubscribeStatus status, [Object? error]) {
            _live = status == RealtimeSubscribeStatus.subscribed;
            // Appena collegato si controlla subito: qualcosa può essere arrivato nel frattempo.
            if (_live && !out.isClosed) out.add(null);
          });
      },
      onCancel: () async {
        final RealtimeChannel? c = channel;
        channel = null;
        _live = false;
        if (c != null) await _client.removeChannel(c);
      },
    );
    return out.stream;
  }

  @override
  Future<(int, DateTime)> callSignal(String conversationId, int generation, String payload,
      {required bool ring, required bool video}) async {
    final rows = _rows(await _rpc('call_signal', {
      'p_conversation': conversationId,
      'p_generation': generation,
      'p_payload': payload,
      'p_ring': ring,
      'p_video': video,
    }));
    if (rows.isEmpty) throw const ChatFailure('Chiamata non riuscita. Riprova.');
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

  @override
  Future<String> createGroup(String title, List<String> members) async =>
      (await _rpc('chat_create_group', {'p_title': title, 'p_members': members})) as String;

  @override
  Future<int> groupAdd(String conversationId, List<String> members) async =>
      ((await _rpc('chat_group_add', {'p_conversation': conversationId, 'p_members': members})) as num?)
          ?.toInt() ??
      0;

  @override
  Future<void> groupRemove(String conversationId, String userId) async {
    await _rpc('chat_group_remove', {'p_conversation': conversationId, 'p_user': userId});
  }

  @override
  Future<void> groupSetAdmin(String conversationId, String userId, bool admin) async {
    await _rpc('chat_group_set_admin', {'p_conversation': conversationId, 'p_user': userId, 'p_admin': admin});
  }

  @override
  Future<void> groupUpdate(String conversationId, String title, String description,
      {bool photoChanged = false}) async {
    await _rpc('chat_group_update', {
      'p_conversation': conversationId,
      'p_title': title,
      'p_description': description,
      'p_photo_changed': photoChanged,
    });
  }

  @override
  Future<String> groupInviteCode(String conversationId, {bool renew = false}) async =>
      (await _rpc('chat_group_invite_code', {'p_conversation': conversationId, 'p_renew': renew})) as String;

  @override
  Future<void> groupInviteRevoke(String conversationId) async {
    await _rpc('chat_group_invite_revoke', {'p_conversation': conversationId});
  }

  @override
  Future<GroupInviteInfo> groupInviteInfo(String code) async {
    final rows = _rows(await _rpc('chat_group_invite_info', {'p_code': code}));
    if (rows.isEmpty) throw const ChatFailure('Codice non valido o scaduto.');
    final r = rows.first;
    return GroupInviteInfo(
      conversationId: r['conversation_id'] as String,
      title: (r['title'] as String?) ?? '',
      members: (r['members'] as num?)?.toInt() ?? 0,
      alreadyMember: r['already_member'] == true,
    );
  }

  @override
  Future<String> groupJoin(String code) async =>
      (await _rpc('chat_group_join', {'p_code': code})) as String;

  @override
  Future<List<GroupMember>> groupMembers(String conversationId) async =>
      _rows(await _rpc('chat_group_members', {'p_conversation': conversationId}))
          .map(GroupMember.fromRow)
          .toList();

  @override
  Future<ClaimedKeyPackage> groupClaimKeyPackage(String conversationId, String userId) async {
    final rows = _rows(await _rpc('chat_group_claim_key_package', {
      'p_conversation': conversationId,
      'p_user': userId,
    }));
    if (rows.isEmpty) throw const ChatFailure('Un membro deve aprire l\'app per attivare la chat.');
    return ClaimedKeyPackage(rows.first['package'] as String, rows.first['signature_key'] as String);
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
  }) async => ((await _rpc('chat_group_commit', {
    'p_conversation': conversationId,
    'p_generation': generation,
    'p_group_id': groupId,
    'p_commit': commit,
    'p_welcome': welcome,
    'p_added': added,
    'p_removed': removed,
  })) as num).toInt();

  @override
  Future<void> groupRejoin(String conversationId) async {
    await _rpc('chat_group_rejoin', {'p_conversation': conversationId});
  }

  @override
  Future<void> setMute(String conversationId, String? until) async {
    await _rpc('chat_set_mute', {'p_conversation': conversationId, 'p_until': until});
  }

  @override
  Future<void> report(String conversationId, String reason, String details, List<Map<String, String>> messages) async {
    await _rpc('chat_report', {
      'p_conversation': conversationId,
      'p_reason': reason,
      'p_details': details.trim().isEmpty ? null : details.trim(),
      'p_messages': messages,
    });
  }

  @override
  Future<void> blockUser(String userId) async {
    await _rpc('block_user', {'p_user_id': userId});
  }
}

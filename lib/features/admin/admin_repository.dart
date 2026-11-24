import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, SupabaseClient;

import '../security/app_lock.dart';
import 'admin_models.dart';

/// Gestionale (Fase 7): ogni funzione richiede un amministratore con il PIN attivo (migrazione 0038).
abstract class AdminRepository {
  Future<AdminAccess> access();

  /// [closed] false: da gestire; true: gestite negli ultimi 30 giorni.
  Future<List<AdminReport>> reports({bool closed = false});

  Future<void> resolve(
    AdminReport report,
    ReportAction action, {
    String? message,
    BanLength? ban,
    bool removeContent = false,
  });

  Future<List<AdminPerson>> searchUsers(String query);

  Future<AdminUserDetail?> user(String id);

  Future<DateTime?> ban(String id, BanLength length, String reason);

  Future<void> unban(String id, {String? reason});

  Future<void> warn(String id, String message);
}

/// Per la persona: ban in corso e avvisi del Team Piazly.
abstract class ModerationRepository {
  Future<ModerationState?> mine();

  Future<void> markRead();
}

/// Collegamenti creati all'avvio, solo con il server attivo.
abstract final class AdminRegistry {
  static AdminRepository? current;

  /// Impronta o volto all'ingresso del gestionale (se il telefono la ha).
  static BiometricLock? biometric;
}

abstract final class ModerationRegistry {
  static ModerationRepository? current;
}

Future<Object?> _call(SupabaseClient client, String name, [Map<String, Object?>? params]) async {
  try {
    return await client.rpc(name, params: params);
  } on PostgrestException catch (e) {
    if (e.code == '22023') throw AdminFailure(e.message.endsWith('.') ? e.message : '${e.message}.');
    if (e.code == '42501') {
      throw AdminFailure(
        e.message.contains('PIN')
            ? 'Per il gestionale serve la verifica in due passaggi (PIN).'
            : 'Operazione permessa solo agli amministratori.',
      );
    }
    throw const AdminFailure('Non è stato possibile: riprova tra poco.');
  } catch (_) {
    throw const AdminFailure('Connessione assente. Riprova tra poco.');
  }
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AdminAccess> access() async {
    final Object? r = await _call(_client, 'admin_access');
    return r is Map<String, dynamic> ? AdminAccess.fromJson(r) : const AdminAccess();
  }

  @override
  Future<List<AdminReport>> reports({bool closed = false}) async {
    final Object? r = await _call(_client, 'admin_reports', <String, Object?>{'p_closed': closed});
    return <AdminReport>[
      for (final Object? it in (r is List<dynamic> ? r : const <dynamic>[]))
        if (it is Map<String, dynamic>) AdminReport.fromJson(it),
    ];
  }

  @override
  Future<void> resolve(
    AdminReport report,
    ReportAction action, {
    String? message,
    BanLength? ban,
    bool removeContent = false,
  }) async {
    await _call(_client, 'admin_report_resolve', <String, Object?>{
      'p_kind': report.kind.key,
      'p_id': report.id,
      'p_action': action.key,
      'p_message': message?.trim(),
      'p_ban_days': ban?.days,
      'p_remove': removeContent,
    });
  }

  @override
  Future<List<AdminPerson>> searchUsers(String query) async {
    final Object? r = await _call(_client, 'admin_users_search', <String, Object?>{'p_query': query.trim()});
    return <AdminPerson>[
      for (final Object? it in (r is List<dynamic> ? r : const <dynamic>[]))
        if (it is Map<String, dynamic>) AdminPerson.fromJson(it),
    ];
  }

  @override
  Future<AdminUserDetail?> user(String id) async {
    final Object? r = await _call(_client, 'admin_user_detail', <String, Object?>{'p_user': id});
    return r is Map<String, dynamic> ? AdminUserDetail.fromJson(r) : null;
  }

  @override
  Future<DateTime?> ban(String id, BanLength length, String reason) async {
    final Object? r = await _call(_client, 'admin_ban_user', <String, Object?>{
      'p_user': id,
      'p_days': length.days,
      'p_reason': reason.trim(),
    });
    if (r == 'infinity') return DateTime(9999);
    return r is String ? DateTime.tryParse(r)?.toLocal() : null;
  }

  @override
  Future<void> unban(String id, {String? reason}) async {
    await _call(_client, 'admin_unban_user', <String, Object?>{'p_user': id, 'p_reason': reason?.trim()});
  }

  @override
  Future<void> warn(String id, String message) async {
    await _call(_client, 'admin_warn_user', <String, Object?>{'p_user': id, 'p_message': message.trim()});
  }
}

class SupabaseModerationRepository implements ModerationRepository {
  SupabaseModerationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ModerationState?> mine() async {
    final Object? r = await _call(_client, 'my_moderation');
    return r is Map<String, dynamic> ? ModerationState.fromJson(r) : null;
  }

  @override
  Future<void> markRead() async {
    await _call(_client, 'moderation_notices_read');
  }
}

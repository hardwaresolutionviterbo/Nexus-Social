import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, SupabaseClient;

import '../profile/profile_repository.dart' show ProfileFailure, SupabaseProfileRepository;

/// Chi può vedere il numero (P5, P6). Agli sconosciuti mai, in nessuna opzione.
enum PhoneVisibility {
  contacts('contacts', 'Contatti riconosciuti dalla rubrica'),
  nobody('nobody', 'Nessuno');

  const PhoneVisibility(this.key, this.label);

  final String key;
  final String label;

  static PhoneVisibility fromKey(Object? key) =>
      key == 'nobody' ? PhoneVisibility.nobody : PhoneVisibility.contacts;
}

/// Scelte attuali della pagina Privacy (lette dal server, che le applica: P2).
class PrivacySettings {
  const PrivacySettings({
    this.phoneVisibility = PhoneVisibility.contacts,
    this.discoverable = false,
    this.showBio = true,
    this.showSocial = true,
    this.blockedCount = 0,
  });

  factory PrivacySettings.fromJson(Map<String, dynamic> json) => PrivacySettings(
    phoneVisibility: PhoneVisibility.fromKey(json['phone_visibility']),
    discoverable: json['discoverable'] as bool? ?? false,
    showBio: json['show_bio'] as bool? ?? true,
    showSocial: json['show_social'] as bool? ?? true,
    blockedCount: (json['blocked_count'] as num?)?.toInt() ?? 0,
  );

  final PhoneVisibility phoneVisibility;

  /// «Permetti a chi ha il mio numero di trovarmi» (P8): si accende con la rubrica (Blocco 5).
  final bool discoverable;
  final bool showBio;
  final bool showSocial;
  final int blockedCount;

  PrivacySettings copyWith({
    PhoneVisibility? phoneVisibility,
    bool? showBio,
    bool? showSocial,
    int? blockedCount,
  }) => PrivacySettings(
    phoneVisibility: phoneVisibility ?? this.phoneVisibility,
    discoverable: discoverable,
    showBio: showBio ?? this.showBio,
    showSocial: showSocial ?? this.showSocial,
    blockedCount: blockedCount ?? this.blockedCount,
  );
}

/// Utente bloccato, con i soli dati pubblici.
class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.username,
    required this.publicName,
    this.avatarThumbPath,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
    id: json['id'] as String,
    username: json['username'] as String,
    publicName: (json['public_name'] as String?) ?? '',
    avatarThumbPath: json['avatar_thumb_path'] as String?,
  );

  final String id;
  final String username;
  final String publicName;
  final String? avatarThumbPath;
}

abstract class PrivacyRepository {
  Future<PrivacySettings> fetch();

  Future<void> setPhoneVisibility(PhoneVisibility value);

  Future<void> setProfileVisibility({required bool showBio, required bool showSocial});

  Future<List<BlockedUser>> blockedUsers();

  Future<void> block(String userId);

  Future<void> unblock(String userId);
}

class SupabasePrivacyRepository implements PrivacyRepository {
  SupabasePrivacyRepository(this._client);

  final SupabaseClient _client;

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      throw SupabaseProfileRepository.failureFor(e.code, e.message);
    } on ProfileFailure {
      rethrow;
    } catch (_) {
      throw const ProfileFailure(
        'Non è stato possibile salvare. Controlla la connessione e riprova.',
      );
    }
  }

  @override
  Future<PrivacySettings> fetch() => _guard(() async {
    final Object? data = await _client.rpc('get_my_privacy');
    return data is Map<String, dynamic>
        ? PrivacySettings.fromJson(data)
        : const PrivacySettings();
  });

  @override
  Future<void> setPhoneVisibility(PhoneVisibility value) => _guard(() async {
    await _client.rpc('set_phone_visibility', params: <String, Object?>{'p_value': value.key});
  });

  @override
  Future<void> setProfileVisibility({required bool showBio, required bool showSocial}) =>
      _guard(() async {
        await _client.rpc(
          'set_profile_visibility',
          params: <String, Object?>{'p_show_bio': showBio, 'p_show_social': showSocial},
        );
      });

  @override
  Future<List<BlockedUser>> blockedUsers() => _guard(() async {
    final Object? data = await _client.rpc('my_blocked_users');
    if (data is! List) return const <BlockedUser>[];
    return <BlockedUser>[
      for (final Object? row in data)
        if (row is Map<String, dynamic>) BlockedUser.fromJson(row),
    ];
  });

  @override
  Future<void> block(String userId) => _guard(() async {
    await _client.rpc('block_user', params: <String, Object?>{'p_user_id': userId});
  });

  @override
  Future<void> unblock(String userId) => _guard(() async {
    await _client.rpc('unblock_user', params: <String, Object?>{'p_user_id': userId});
  });
}

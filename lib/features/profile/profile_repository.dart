import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException, StorageException, SupabaseClient;

import 'avatar_images.dart';
import 'profile_models.dart';

/// Errore del profilo con un messaggio già pronto per l'utente.
class ProfileFailure implements Exception {
  const ProfileFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Accesso ai dati del profilo (migrazione 0003). Nei test si usa una versione simulata.
abstract class ProfileRepository {
  /// Il proprio profilo, oppure null se non è ancora stato creato.
  Future<MyProfile?> fetchMine();

  Future<bool> isUsernameAvailable(String username);

  Future<void> create(NewProfile profile);

  Future<void> update(ProfileUpdate update);

  /// Prepara foto e miniatura dall'immagine scelta, le carica e le collega al profilo.
  Future<void> setAvatar(Uint8List imageBytes);

  Future<void> removeAvatar();

  Future<PublicProfile?> fetchPublic(String id);

  /// Scarica una foto profilo (bucket privato: solo utenti autenticati).
  Future<Uint8List?> downloadAvatar(String path);
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client, {required this.uid});

  final SupabaseClient _client;
  final String Function() uid;

  static const String bucket = 'avatars';
  static const ProfileFailure _generic = ProfileFailure(
    'Non è stato possibile salvare. Controlla la connessione e riprova.',
  );

  @override
  Future<MyProfile?> fetchMine() => _guard(() async {
    final Object? data = await _client.rpc('get_my_profile');
    if (data is Map<String, dynamic>) return MyProfile.fromJson(data);
    return null;
  });

  @override
  Future<bool> isUsernameAvailable(String username) => _guard(() async {
    final Object? data = await _client.rpc(
      'username_available',
      params: <String, Object?>{'p_username': username},
    );
    return data == true;
  });

  @override
  Future<void> create(NewProfile p) => _guard(() async {
    await _client.rpc(
      'create_my_profile',
      params: <String, Object?>{
        'p_username': p.username,
        'p_full_name': p.fullName,
        'p_birth_date': _date(p.birthDate),
        'p_account_type': p.isBusiness ? 'business' : 'private',
        'p_business_name': p.isBusiness ? p.businessName : null,
        'p_vat_number': p.isBusiness ? p.vatNumber : null,
      },
    );
  });

  @override
  Future<void> update(ProfileUpdate u) => _guard(() async {
    await _client.rpc(
      'update_my_profile',
      params: <String, Object?>{
        'p_username': u.username,
        'p_full_name': u.fullName,
        'p_bio': u.bio,
        'p_social_links': socialToJson(u.social),
        'p_show_bio': u.showBio,
        'p_show_social': u.showSocial,
        'p_business_name': u.businessName,
      },
    );
  });

  @override
  Future<void> setAvatar(Uint8List imageBytes) => _guard(() async {
    final AvatarImages images = await AvatarImages.prepareInBackground(imageBytes);
    final String id = uid();
    final String token = _randomToken();
    final String avatarPath = '$id/avatar-$token.jpg';
    final String thumbPath = '$id/thumb-$token.jpg';
    const FileOptions options = FileOptions(contentType: 'image/jpeg', upsert: false);
    final MyProfile? before = await fetchMine();
    await _client.storage.from(bucket).uploadBinary(avatarPath, images.avatar, fileOptions: options);
    await _client.storage.from(bucket).uploadBinary(thumbPath, images.thumbnail, fileOptions: options);
    await _client.rpc(
      'set_my_avatar',
      params: <String, Object?>{'p_avatar_path': avatarPath, 'p_thumb_path': thumbPath},
    );
    await _removeFiles(before);
  });

  @override
  Future<void> removeAvatar() => _guard(() async {
    final MyProfile? before = await fetchMine();
    await _client.rpc(
      'set_my_avatar',
      params: <String, Object?>{'p_avatar_path': null, 'p_thumb_path': null},
    );
    await _removeFiles(before);
  });

  @override
  Future<PublicProfile?> fetchPublic(String id) => _guard(() async {
    final Object? data = await _client.rpc(
      'get_public_profile',
      params: <String, Object?>{'p_id': id},
    );
    if (data is List && data.isNotEmpty && data.first is Map<String, dynamic>) {
      return PublicProfile.fromJson(data.first as Map<String, dynamic>);
    }
    return null;
  });

  @override
  Future<Uint8List?> downloadAvatar(String path) async {
    try {
      return await _client.storage.from(bucket).download(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeFiles(MyProfile? before) async {
    final List<String> old = <String>[
      if (before?.avatarPath != null) before!.avatarPath!,
      if (before?.avatarThumbPath != null) before!.avatarThumbPath!,
    ];
    if (old.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove(old);
    } catch (_) {
      // Una foto vecchia rimasta non è un errore per l'utente.
    }
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _randomToken() {
    const String chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final Random r = Random.secure();
    return List<String>.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Traduce gli errori del server in messaggi per l'utente, senza dati tecnici.
  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ProfileFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw failureFor(e.code, e.message);
    } on StorageException {
      throw const ProfileFailure('La foto non è stata caricata. Riprova.');
    } on AvatarImageException catch (e) {
      throw ProfileFailure(e.message);
    } catch (_) {
      throw _generic;
    }
  }

  /// Messaggio per un errore del database (codice SQLSTATE e testo del server).
  static ProfileFailure failureFor(String? code, String message) {
    switch (code) {
      case '23505':
        if (message.contains('già creato')) {
          return const ProfileFailure('Il profilo esiste già.');
        }
        return const ProfileFailure('Questo nome utente è già preso: scegline un altro.');
      case '22023':
        // Messaggi scritti dal server per l'utente (migrazione 0003).
        return ProfileFailure('$message.');
      case '42501':
        return const ProfileFailure('Accesso non valido: esci e rientra.');
      default:
        return _generic;
    }
  }
}

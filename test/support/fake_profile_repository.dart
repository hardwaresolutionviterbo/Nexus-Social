import 'dart:typed_data';

import 'package:nexus_social/features/profile/profile_models.dart';
import 'package:nexus_social/features/profile/profile_repository.dart';

/// Profilo simulato in memoria: nessun Supabase reale (regola F8).
/// Ripete i controlli principali del server per verificare che l'app li gestisca.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.mine});

  MyProfile? mine;
  final List<String> calls = <String>[];
  final Set<String> takenUsernames = <String>{'gia_preso'};
  NewProfile? created;
  ProfileUpdate? updated;
  Uint8List? avatarBytes;
  ProfileFailure? failNext;
  final Map<String, PublicProfile> others = <String, PublicProfile>{};

  void _maybeFail() {
    final ProfileFailure? f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Future<MyProfile?> fetchMine() async {
    calls.add('fetchMine');
    _maybeFail();
    return mine;
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    calls.add('isUsernameAvailable:$username');
    return !takenUsernames.contains(username);
  }

  @override
  Future<void> create(NewProfile profile) async {
    calls.add('create');
    _maybeFail();
    created = profile;
    mine = MyProfile(
      id: 'utenteProva',
      isBusiness: profile.isBusiness,
      username: profile.username,
      publicName: ProfileRules.shortPublicName(profile.fullName),
      fullName: profile.fullName,
      birthDate: profile.birthDate,
      businessName: profile.businessName,
      vatNumber: profile.vatNumber,
      businessStatus: profile.isBusiness ? BusinessStatus.pending : null,
    );
  }

  @override
  Future<void> update(ProfileUpdate update) async {
    calls.add('update');
    _maybeFail();
    updated = update;
    final MyProfile old = mine!;
    mine = MyProfile(
      id: old.id,
      isBusiness: old.isBusiness,
      username: update.username,
      publicName: ProfileRules.shortPublicName(update.fullName),
      fullName: update.fullName,
      birthDate: old.birthDate,
      businessName: update.businessName,
      vatNumber: old.vatNumber,
      businessStatus: old.businessStatus,
      avatarPath: old.avatarPath,
      avatarThumbPath: old.avatarThumbPath,
      bio: update.bio,
      social: update.social,
      showBio: update.showBio,
      showSocial: update.showSocial,
    );
  }

  @override
  Future<void> setAvatar(Uint8List imageBytes) async {
    calls.add('setAvatar');
    avatarBytes = imageBytes;
  }

  @override
  Future<void> removeAvatar() async {
    calls.add('removeAvatar');
    avatarBytes = null;
  }

  @override
  Future<PublicProfile?> fetchPublic(String id) async => others[id];

  @override
  Future<Uint8List?> downloadAvatar(String path) async => null;
}

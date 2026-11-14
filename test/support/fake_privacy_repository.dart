import 'package:nexus_social/features/privacy/privacy_repository.dart';
import 'package:nexus_social/features/profile/profile_repository.dart';

/// Impostazioni privacy simulate in memoria: nessun Supabase reale (regola F8).
class FakePrivacyRepository implements PrivacyRepository {
  PrivacySettings settings = const PrivacySettings();
  List<BlockedUser> blocked = <BlockedUser>[];
  final List<String> calls = <String>[];
  ProfileFailure? failNextSave;

  void _maybeFail() {
    final ProfileFailure? f = failNextSave;
    if (f != null) {
      failNextSave = null;
      throw f;
    }
  }

  @override
  Future<PrivacySettings> fetch() async {
    calls.add('fetch');
    return settings.copyWith(blockedCount: blocked.length);
  }

  @override
  Future<void> setPhoneVisibility(PhoneVisibility value) async {
    calls.add('setPhoneVisibility:${value.key}');
    _maybeFail();
    settings = settings.copyWith(phoneVisibility: value);
  }

  @override
  Future<void> setProfileVisibility({required bool showBio, required bool showSocial}) async {
    calls.add('setProfileVisibility:$showBio,$showSocial');
    _maybeFail();
    settings = settings.copyWith(showBio: showBio, showSocial: showSocial);
  }

  @override
  Future<List<BlockedUser>> blockedUsers() async => List<BlockedUser>.of(blocked);

  @override
  Future<void> block(String userId) async {
    calls.add('block:$userId');
    _maybeFail();
  }

  @override
  Future<void> unblock(String userId) async {
    calls.add('unblock:$userId');
    _maybeFail();
    blocked.removeWhere((BlockedUser b) => b.id == userId);
  }
}

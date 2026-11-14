import 'package:nexus_social/features/profile/profile_repository.dart';
import 'package:nexus_social/features/security/app_lock.dart';
import 'package:nexus_social/features/security/security_repository.dart';

/// Verifica in due passaggi simulata in memoria (regola F8), con le stesse regole del server.
class FakeSecurityRepository implements SecurityRepository {
  String? pin;
  bool trusted = true;
  DateTime? lockedUntil;
  DateTime? resetAvailableAt;
  int failures = 0;
  final List<String> calls = <String>[];

  @override
  Future<SecurityStatus> status() async => SecurityStatus(
    pinEnabled: pin != null,
    deviceTrusted: pin == null || trusted,
    lockedUntil: lockedUntil,
    resetAvailableAt: resetAvailableAt,
  );

  @override
  Future<void> setPin(String newPin, {String? currentPin}) async {
    calls.add('setPin');
    if (!PinRules.isValid(newPin)) throw const ProfileFailure('Il PIN deve avere 6 cifre.');
    if (pin != null && currentPin != pin) throw const ProfileFailure('PIN attuale errato.');
    pin = newPin;
    trusted = true;
  }

  @override
  Future<void> disablePin(String p) async {
    calls.add('disablePin');
    if (p != pin) throw const ProfileFailure('PIN errato.');
    pin = null;
  }

  @override
  Future<bool> verifyPin(String p) async {
    calls.add('verifyPin');
    if (p == pin) {
      trusted = true;
      return true;
    }
    if (++failures >= 5) lockedUntil = DateTime.now().add(const Duration(hours: 1));
    return false;
  }

  @override
  Future<DateTime?> requestReset() async {
    calls.add('requestReset');
    return resetAvailableAt ??= DateTime.now().add(const Duration(days: 7));
  }

  @override
  Future<void> completeReset() async {
    calls.add('completeReset');
    pin = null;
    trusted = true;
  }

  @override
  Future<void> forgetThisDevice() async {
    calls.add('forgetThisDevice');
    trusted = false;
  }
}

class FakeBiometricLock implements BiometricLock {
  bool available = true;
  bool enabled = false;
  bool succeed = true;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeed;
  }
}

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, SupabaseClient;

import '../profile/profile_repository.dart' show ProfileFailure, SupabaseProfileRepository;

/// Stato della verifica in due passaggi per questo telefono.
class SecurityStatus {
  const SecurityStatus({
    this.pinEnabled = false,
    this.deviceTrusted = true,
    this.lockedUntil,
    this.resetAvailableAt,
  });

  factory SecurityStatus.fromJson(Map<String, dynamic> json) => SecurityStatus(
    pinEnabled: json['pin_enabled'] as bool? ?? false,
    deviceTrusted: json['device_trusted'] as bool? ?? true,
    lockedUntil: _date(json['locked_until']),
    resetAvailableAt: _date(json['reset_available_at']),
  );

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  final bool pinEnabled;
  final bool deviceTrusted;
  final DateTime? lockedUntil;
  final DateTime? resetAvailableAt;

  /// Serve il PIN prima di usare l'app (telefono nuovo).
  bool get needsPin => pinEnabled && !deviceTrusted;
}

/// Verifica in due passaggi con PIN di 6 cifre (S2), controllata dal server (migrazione 0005).
abstract class SecurityRepository {
  Future<SecurityStatus> status();

  Future<void> setPin(String newPin, {String? currentPin});

  Future<void> disablePin(String pin);

  /// true se il PIN è giusto: da quel momento il telefono è attendibile.
  Future<bool> verifyPin(String pin);

  /// Chiede il ripristino del PIN dimenticato; restituisce quando sarà possibile.
  Future<DateTime?> requestReset();

  Future<void> completeReset();

  /// Uscita sicura: il telefono non è più attendibile.
  Future<void> forgetThisDevice();
}

abstract final class PinRules {
  static bool isValid(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);
}

class SupabaseSecurityRepository implements SecurityRepository {
  SupabaseSecurityRepository(this._client);

  final SupabaseClient _client;

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      throw SupabaseProfileRepository.failureFor(e.code, e.message);
    } on ProfileFailure {
      rethrow;
    } catch (_) {
      throw const ProfileFailure('Connessione assente. Riprova.');
    }
  }

  @override
  Future<SecurityStatus> status() => _guard(() async {
    final Object? data = await _client.rpc('security_status');
    return data is Map<String, dynamic> ? SecurityStatus.fromJson(data) : const SecurityStatus();
  });

  @override
  Future<void> setPin(String newPin, {String? currentPin}) => _guard(() async {
    await _client.rpc(
      'set_pin',
      params: <String, Object?>{'p_new_pin': newPin, 'p_current_pin': currentPin},
    );
  });

  @override
  Future<void> disablePin(String pin) => _guard(() async {
    await _client.rpc('disable_pin', params: <String, Object?>{'p_pin': pin});
  });

  @override
  Future<bool> verifyPin(String pin) => _guard(() async {
    final Object? data = await _client.rpc('verify_pin', params: <String, Object?>{'p_pin': pin});
    return data == true;
  });

  @override
  Future<DateTime?> requestReset() => _guard(() async {
    final Object? data = await _client.rpc('request_pin_reset');
    return data is String ? DateTime.tryParse(data)?.toLocal() : null;
  });

  @override
  Future<void> completeReset() => _guard(() async {
    await _client.rpc('complete_pin_reset');
  });

  @override
  Future<void> forgetThisDevice() async {
    try {
      await _client.rpc('forget_this_device');
    } catch (_) {
      // L'uscita deve riuscire anche senza rete.
    }
  }
}

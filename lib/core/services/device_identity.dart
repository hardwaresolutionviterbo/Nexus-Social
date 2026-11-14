import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Codice casuale di questo telefono (Fase 2, Blocco 4).
///
/// Serve alla verifica in due passaggi: dopo il PIN il server considera «attendibile» il
/// telefono che invia questo codice (intestazione `x-device-id`) e ne conserva solo l'hash.
/// Resta nella memoria protetta del telefono (Keystore / Keychain) e non è un dato personale.
abstract final class DeviceIdentity {
  static const String _key = 'piazly_device_id';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String? _cached;

  /// Codice di questo telefono; lo crea al primo avvio.
  static Future<String> load() async {
    final String? cached = _cached;
    if (cached != null) return cached;
    String? value;
    try {
      value = await _storage.read(key: _key);
      if (value == null || !isValid(value)) {
        value = generate();
        await _storage.write(key: _key, value: value);
      }
    } catch (_) {
      // Memoria protetta non disponibile: codice valido solo per questa sessione. Con il PIN
      // attivo il server chiederà di nuovo il PIN al prossimo avvio, che è il comportamento
      // più prudente.
      value ??= generate();
    }
    return _cached = value;
  }

  static bool isValid(String value) => RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(value);

  static String generate() {
    const String chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
    final Random r = Random.secure();
    return List<String>.generate(48, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

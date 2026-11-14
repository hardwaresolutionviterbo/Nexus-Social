import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, SupabaseClient;

import '../../core/crypto/p256_oprf.dart';
import '../onboarding/registration_rules.dart';
import '../profile/profile_repository.dart' show ProfileFailure, SupabaseProfileRepository;

/// Limiti della decisione S6.
abstract final class ContactsLimits {
  static const int maxNumbers = 2000;
  static const int syncsPerDay = 3;
  static const Duration expiry = Duration(days: 30);
}

/// Numeri della rubrica in formato internazionale, senza doppioni (solo cellulari italiani, L3).
List<String> normalizeContactNumbers(Iterable<String> raw) {
  final Set<String> out = <String>{};
  for (final String n in raw) {
    final String? e164 = RegistrationRules.italianMobile(n);
    if (e164 != null) out.add(e164);
    if (out.length >= ContactsLimits.maxNumbers) break;
  }
  return out.toList()..sort();
}

/// Rubrica del telefono, letta solo con il permesso del sistema.
abstract class ContactsReader {
  Future<bool> requestPermission();

  Future<List<String>> phoneNumbers();
}

class DeviceContactsReader implements ContactsReader {
  @override
  Future<bool> requestPermission() => FlutterContacts.requestPermission(readonly: true);

  @override
  Future<List<String>> phoneNumbers() async {
    final List<Contact> contacts = await FlutterContacts.getContacts(withProperties: true);
    return <String>[
      for (final Contact c in contacts)
        for (final Phone p in c.phones) p.normalizedNumber.isNotEmpty ? p.normalizedNumber : p.number,
    ];
  }
}

/// Contatto riconosciuto, con i soli dati pubblici e il numero solo se consentito.
class RecognizedContact {
  const RecognizedContact({
    required this.id,
    required this.username,
    required this.publicName,
    this.avatarThumbPath,
    this.phone,
  });

  factory RecognizedContact.fromJson(Map<String, dynamic> json) => RecognizedContact(
    id: json['id'] as String,
    username: json['username'] as String,
    publicName: (json['public_name'] as String?) ?? '',
    avatarThumbPath: json['avatar_thumb_path'] as String?,
    phone: json['phone'] as String?,
  );

  final String id;
  final String username;
  final String publicName;
  final String? avatarThumbPath;
  final String? phone;
}

/// Rubrica (Fase 2, Blocco 5): consenso, sincronizzazione protetta, contatti, revoca.
abstract class ContactsRepository {
  /// Registra il consenso (con la data) e accende «Permetti di trovarmi» (P8).
  Future<void> enable();

  /// Legge la rubrica, la protegge con OPRF e cerca i contatti iscritti.
  /// [onProgress] riceve valori da 0 a 1.
  Future<List<RecognizedContact>> sync({void Function(double)? onProgress});

  Future<List<RecognizedContact>> contacts();

  Future<void> setDiscoverable(bool value);

  /// «Revoca e cancella»: stop e cancellazione dei dati derivati.
  Future<void> revoke();
}

/// Lavoro pesante (curve ellittiche) fuori dal thread dell'interfaccia.
List<BlindedInput> _blindAll(List<String> numbers) => <BlindedInput>[
  for (final String n in numbers) P256Oprf.blind(utf8.encode(n)),
];

List<String> _finalizeAll((List<BlindedInput>, List<String>) args) => <String>[
  for (int i = 0; i < args.$1.length; i++)
    toHex(P256Oprf.finalize(args.$1[i], fromHex(args.$2[i]))),
];

class SupabaseContactsRepository implements ContactsRepository {
  SupabaseContactsRepository(this._client, {ContactsReader? reader, FirebaseAuth? auth})
    : _reader = reader ?? DeviceContactsReader(),
      _auth = auth ?? FirebaseAuth.instance;

  final SupabaseClient _client;
  final ContactsReader _reader;
  final FirebaseAuth _auth;

  static const String region = 'europe-west1';

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      throw SupabaseProfileRepository.failureFor(e.code, e.message);
    } on ProfileFailure {
      rethrow;
    } catch (_) {
      throw const ProfileFailure('Sincronizzazione non riuscita. Riprova più tardi.');
    }
  }

  /// Chiama una Cloud Function «callable» con il token dell'utente.
  Future<Map<String, dynamic>> _callable(String name, Map<String, Object?> data) async {
    final User? user = _auth.currentUser;
    if (user == null) throw const ProfileFailure('Accesso richiesto.');
    final String token = await user.getIdToken() ?? '';
    final String project = Firebase.app().options.projectId;
    final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest request = await client.postUrl(
        Uri.https('$region-$project.cloudfunctions.net', '/$name'),
      );
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode(<String, Object?>{'data': data}));
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final Object? body = jsonDecode(await response.transform(utf8.decoder).join());
      if (body is Map<String, dynamic> && body['result'] is Map<String, dynamic>) {
        return body['result'] as Map<String, dynamic>;
      }
      final Object? status = body is Map<String, dynamic> ? (body['error'] as Map?)?['status'] : null;
      throw ProfileFailure(switch (status) {
        'RESOURCE_EXHAUSTED' => 'Hai già sincronizzato 3 volte oggi. Riprova domani.',
        'FAILED_PRECONDITION' => 'La rubrica non è ancora disponibile.',
        _ => 'Sincronizzazione non riuscita. Riprova più tardi.',
      });
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> enable() => _guard(() async {
    await _client.rpc('enable_contacts');
    // Il proprio numero entra nell'indice di chi vuole farsi trovare (P8).
    final Map<String, dynamic> mine = await _callable('rubricaMioNumero', <String, Object?>{});
    await _client.rpc(
      'register_my_phone',
      params: <String, Object?>{
        'p_phone': mine['telefono'],
        'p_tag': mine['codice'],
        'p_ts': mine['istante'],
        'p_sig': mine['firma'],
      },
    );
  });

  @override
  Future<List<RecognizedContact>> sync({void Function(double)? onProgress}) => _guard(() async {
    if (!await _reader.requestPermission()) {
      throw const ProfileFailure('Permesso ai contatti non concesso.');
    }
    onProgress?.call(0.05);
    final List<String> numbers = normalizeContactNumbers(await _reader.phoneNumbers());
    if (numbers.isEmpty) {
      await _client.rpc('match_contacts', params: <String, Object?>{'p_tags': <String>[]});
      onProgress?.call(1);
      return const <RecognizedContact>[];
    }
    final List<BlindedInput> blinded = await compute(_blindAll, numbers);
    onProgress?.call(0.45);
    final Map<String, dynamic> evaluated = await _callable('rubricaValuta', <String, Object?>{
      'elementi': <String>[for (final BlindedInput b in blinded) toHex(b.blinded)],
    });
    final List<String> values = (evaluated['valutati'] as List<dynamic>).cast<String>();
    if (values.length != blinded.length) throw const ProfileFailure('Risposta non valida.');
    onProgress?.call(0.6);
    final List<String> tags = await compute(_finalizeAll, (blinded, values));
    onProgress?.call(0.9);
    await _client.rpc('match_contacts', params: <String, Object?>{'p_tags': tags});
    onProgress?.call(1);
    return contacts();
  });

  @override
  Future<List<RecognizedContact>> contacts() => _guard(() async {
    final Object? data = await _client.rpc('my_contacts');
    if (data is! List) return const <RecognizedContact>[];
    return <RecognizedContact>[
      for (final Object? row in data)
        if (row is Map<String, dynamic>) RecognizedContact.fromJson(row),
    ];
  });

  @override
  Future<void> setDiscoverable(bool value) => _guard(() async {
    await _client.rpc('set_discoverable', params: <String, Object?>{'p_value': value});
  });

  @override
  Future<void> revoke() => _guard(() async {
    await _client.rpc('revoke_contacts');
  });
}

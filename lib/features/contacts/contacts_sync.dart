import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show ValueNotifier, compute;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, FunctionResponse, PostgrestException, SupabaseClient;

import '../../core/crypto/p256_oprf.dart';
import '../onboarding/registration_rules.dart';
import '../profile/profile_repository.dart' show ProfileFailure, SupabaseProfileRepository;

/// Limiti della decisione S6.
abstract final class ContactsLimits {
  static const int maxNumbers = 2000;
  static const int syncsPerDay = 3;
  static const Duration expiry = Duration(days: 30);

  /// Aggiornamento automatico: subito se la rubrica è cambiata, altrimenti una volta al giorno.
  static const Duration autoInterval = Duration(hours: 24);
}

/// Decide se aggiornare la rubrica da sola, come WhatsApp (solo con il consenso attivo).
bool shouldAutoSync({
  required bool enabled,
  required bool contactsChanged,
  required DateTime? lastSync,
  required DateTime now,
}) {
  if (!enabled) return false;
  if (contactsChanged || lastSync == null) return true;
  return now.difference(lastSync) >= ContactsLimits.autoInterval;
}

/// Impronta dei numeri in rubrica: serve solo a capire se la rubrica è cambiata.
/// Resta sul telefono, nella memoria protetta; dall'impronta non si risale ai numeri.
String contactsFingerprint(List<String> normalized) =>
    sha256.convert(utf8.encode(normalized.join(','))).toString();

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

/// Messaggio per gli errori della funzione `rubrica` (codice HTTP).
String rubricaErrorMessage(int status) => switch (status) {
  429 => 'Hai già sincronizzato 3 volte oggi. Riprova domani.',
  503 => 'La rubrica non è ancora disponibile.',
  401 => 'Accesso scaduto: riapri l\'app e riprova.',
  _ => 'Sincronizzazione non riuscita. Riprova più tardi.',
};

/// Avvisi per chi mostra i nomi della rubrica (la chat): sono cambiati, rileggili.
abstract final class ContactsEvents {
  static final ValueNotifier<int> namesChanged = ValueNotifier<int>(0);
}

/// Rubrica del telefono, letta solo con il permesso del sistema.
abstract class ContactsReader {
  Future<bool> requestPermission();

  Future<List<String>> phoneNumbers();

  /// Nome scritto in rubrica e numeri di ogni contatto (restano sul telefono).
  Future<List<(String, List<String>)>> entries();

  /// Avvisa quando la rubrica del telefono cambia (contatto aggiunto o modificato).
  void addListener(void Function() listener);

  void removeListener(void Function() listener);
}

class DeviceContactsReader implements ContactsReader {
  @override
  Future<bool> requestPermission() => FlutterContacts.requestPermission(readonly: true);

  @override
  void addListener(void Function() listener) => FlutterContacts.addListener(listener);

  @override
  void removeListener(void Function() listener) => FlutterContacts.removeListener(listener);

  @override
  Future<List<(String, List<String>)>> entries() async {
    final List<Contact> contacts = await FlutterContacts.getContacts(withProperties: true);
    return <(String, List<String>)>[
      for (final Contact c in contacts)
        if (c.displayName.trim().isNotEmpty)
          (
            c.displayName.trim(),
            <String>[for (final Phone p in c.phones) p.normalizedNumber.isNotEmpty ? p.normalizedNumber : p.number],
          ),
    ];
  }

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

  /// Nomi come scritti nella rubrica del telefono, per persona di Piazly (Fase 4, Blocco 11).
  /// Restano sul telefono.
  Future<Map<String, String>> localNames();

  Future<void> setDiscoverable(bool value);

  /// «Revoca e cancella»: stop e cancellazione dei dati derivati.
  Future<void> revoke();

  /// Aggiornamento automatico all'apertura e quando la rubrica cambia: solo con il consenso
  /// attivo, subito se la rubrica è cambiata, altrimenti al massimo una volta al giorno.
  /// Restituisce true se ha sincronizzato. Gli errori non disturbano l'utente.
  Future<bool> autoSyncIfNeeded();

  void watchContacts(void Function() onChange);

  void unwatchContacts(void Function() onChange);
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

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _fingerprintKey = 'piazly_contacts_fingerprint';

  /// Persona di Piazly → numeri della rubrica che le corrispondono (solo sul telefono).
  static const String _numbersKey = 'piazly_contacts_numbers';
  bool _autoRunning = false;

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

  /// Chiama la funzione `rubrica` di Supabase (al posto delle Cloud Functions, niente piano
  /// Blaze) con il token Firebase dell'utente; vedi supabase/functions/rubrica.
  Future<Map<String, dynamic>> _rubrica(Map<String, Object?> body) async {
    final User? user = _auth.currentUser;
    if (user == null) throw const ProfileFailure('Accesso richiesto.');
    final String token = await user.getIdToken() ?? '';
    try {
      final FunctionResponse res = await _client.functions
          .invoke(
            'rubrica',
            headers: <String, String>{'Authorization': 'Bearer $token'},
            body: body,
          )
          .timeout(const Duration(seconds: 60));
      final Object? data = res.data;
      if (data is Map<String, dynamic>) return data;
      throw const ProfileFailure('Risposta non valida.');
    } on FunctionException catch (e) {
      throw ProfileFailure(rubricaErrorMessage(e.status));
    }
  }

  @override
  Future<void> enable() => _guard(() async {
    await _client.rpc('enable_contacts');
    // Il proprio numero entra nell'indice di chi vuole farsi trovare (P8).
    final Map<String, dynamic> mine = await _rubrica(<String, Object?>{'azione': 'mio_numero'});
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
      await _saveFingerprint(numbers);
      onProgress?.call(1);
      return const <RecognizedContact>[];
    }
    final List<BlindedInput> blinded = await compute(_blindAll, numbers);
    onProgress?.call(0.45);
    final Map<String, dynamic> evaluated = await _rubrica(<String, Object?>{
      'azione': 'valuta',
      'elementi': <String>[for (final BlindedInput b in blinded) toHex(b.blinded)],
    });
    final List<String> values = (evaluated['valutati'] as List<dynamic>).cast<String>();
    if (values.length != blinded.length) throw const ProfileFailure('Risposta non valida.');
    onProgress?.call(0.6);
    final List<String> tags = await compute(_finalizeAll, (blinded, values));
    onProgress?.call(0.85);
    // Prima i nomi della rubrica (senza limiti): così compaiono anche se poi il limite
    // giornaliero ferma l'aggiornamento dei collegamenti.
    await _saveNumbers(numbers, tags);
    onProgress?.call(0.9);
    try {
      await _client.rpc('match_contacts', params: <String, Object?>{'p_tags': tags});
    } on PostgrestException catch (e) {
      if (e.message.contains('Limite')) {
        await _markLimited();
        ContactsEvents.namesChanged.value++;
        throw ProfileFailure(rubricaErrorMessage(429));
      }
      rethrow;
    }
    await _saveFingerprint(numbers);
    ContactsEvents.namesChanged.value++;
    onProgress?.call(1);
    return contacts();
  });

  /// Quale numero della rubrica corrisponde a quale persona: serve per mostrare i nomi della
  /// rubrica nelle chat. Il nome non lascia mai il telefono.
  Future<void> _saveNumbers(List<String> numbers, List<String> tags) async {
    // Le coppie numero → codice restano nell'archivio sicuro del telefono: così i nomi della
    // rubrica si possono ricalcolare senza consumare gli aggiornamenti del giorno.
    try {
      await _storage.write(
        key: _tagsKey,
        value: jsonEncode(<String, String>{
          for (int i = 0; i < tags.length && i < numbers.length; i++) numbers[i]: tags[i],
        }),
      );
    } catch (_) {}
    try {
      final Object? rows = await _client.rpc('match_contact_tags', params: <String, Object?>{'p_tags': tags});
      final Map<String, String> byTag = <String, String>{
        for (int i = 0; i < tags.length && i < numbers.length; i++) tags[i]: numbers[i],
      };
      final Map<String, List<String>> byUser = <String, List<String>>{};
      if (rows is List) {
        for (final Object? r in rows) {
          if (r is! Map) continue;
          final String? number = byTag['${r['tag']}'];
          if (number != null) (byUser['${r['id']}'] ??= <String>[]).add(number);
        }
      }
      await _storage.write(key: _numbersKey, value: jsonEncode(byUser));
    } catch (_) {
      // Senza questa informazione le chat mostrano il nome scelto dalla persona su Piazly.
    }
  }

  @override
  Future<Map<String, String>> localNames() async {
    try {
      final String? raw = await _storage.read(key: _numbersKey);
      if (raw == null) return const <String, String>{};
      final Object? j = jsonDecode(raw);
      if (j is! Map || j.isEmpty) return const <String, String>{};
      if (!await _reader.requestPermission()) return const <String, String>{};
      final Map<String, String> nameOf = <String, String>{};
      for (final (String name, List<String> phones) in await _reader.entries()) {
        for (final String n in normalizeContactNumbers(phones)) {
          nameOf.putIfAbsent(n, () => name);
        }
      }
      return <String, String>{
        for (final MapEntry<dynamic, dynamic> e in j.entries)
          if (e.value is List)
            if ((e.value as List).map((Object? n) => nameOf['$n']).whereType<String>().firstOrNull
                case final String name)
              '${e.key}': name,
      };
    } catch (_) {
      return const <String, String>{};
    }
  }

  static const String _limitedKey = 'piazly_contacts_limit_day';
  static const String _tagsKey = 'piazly_contacts_tags';

  /// Ricalcola «persona → numeri» con i codici già salvati (nessun limite giornaliero).
  Future<bool> _remapFromSavedTags() async {
    try {
      final String? raw = await _storage.read(key: _tagsKey);
      if (raw == null) return false;
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      if (j.isEmpty) return false;
      await _saveNumbers(<String>[...j.keys], <String>[for (final Object? t in j.values) '$t']);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _today() {
    final DateTime n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// Limite di oggi raggiunto: niente altri tentativi automatici fino a domani (ognuno
  /// consumerebbe uno dei 3 aggiornamenti al giorno).
  Future<void> _markLimited() async {
    try {
      await _storage.write(key: _limitedKey, value: _today());
    } catch (_) {}
  }

  Future<bool> _limitedToday() async {
    try {
      return await _storage.read(key: _limitedKey) == _today();
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveFingerprint(List<String> numbers) async {
    try {
      await _storage.write(key: _fingerprintKey, value: contactsFingerprint(numbers));
    } catch (_) {
      // Senza impronta si aggiorna comunque una volta al giorno.
    }
  }

  @override
  Future<bool> autoSyncIfNeeded() async {
    if (_autoRunning) return false;
    _autoRunning = true;
    try {
      final Object? status = await _client.rpc('get_my_privacy');
      if (status is! Map<String, dynamic> || status['contacts_enabled'] != true) return false;
      final Object? synced = status['contacts_synced_at'];
      final DateTime? lastSync = synced is String ? DateTime.tryParse(synced) : null;
      if (!await _reader.requestPermission()) return false;
      final List<String> numbers = normalizeContactNumbers(await _reader.phoneNumbers());
      String? stored;
      try {
        stored = await _storage.read(key: _fingerprintKey);
      } catch (_) {
        stored = null;
      }
      bool hasNumbers = false;
      try {
        hasNumbers = await _storage.read(key: _numbersKey) != null;
      } catch (_) {
        hasNumbers = false;
      }
      // Prima volta dopo l'aggiornamento: serve una sincronizzazione per i nomi della rubrica.
      final bool changed = (stored != null && stored != contactsFingerprint(numbers)) || !hasNumbers;
      if (!shouldAutoSync(
        enabled: true,
        contactsChanged: changed,
        lastSync: lastSync,
        now: DateTime.now(),
      )) {
        return false;
      }
      if (await _limitedToday()) {
        if (await _remapFromSavedTags()) ContactsEvents.namesChanged.value++;
        return false;
      }
      try {
        await sync();
      } on ProfileFailure catch (f) {
        if (f.message == rubricaErrorMessage(429)) await _markLimited();
        rethrow;
      }
      return true;
    } catch (_) {
      // Limite giornaliero, rete assente…: si riprova alla prossima apertura.
      return false;
    } finally {
      _autoRunning = false;
    }
  }

  @override
  void watchContacts(void Function() onChange) => _reader.addListener(onChange);

  @override
  void unwatchContacts(void Function() onChange) => _reader.removeListener(onChange);

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
    try {
      await _storage.delete(key: _fingerprintKey);
      await _storage.delete(key: _numbersKey);
    } catch (_) {
      // L'impronta locale è facoltativa.
    }
  });
}

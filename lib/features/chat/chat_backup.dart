import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient, FileOptions, StorageException;

import 'chat_models.dart' show ChatFailure;

/// Backup della chat cifrato con una password (Fase 4, Blocco 6).
///
/// La cronologia viene compressa e cifrata sul telefono con AES-256-GCM. La chiave si ricava
/// dalla password con Argon2id. Sul server c'è un solo file per account, illeggibile senza la
/// password, che il server non conosce. Gli allegati non sono nel backup.

/// Costo di Argon2id: memoria in KiB, passaggi, parallelismo.
class BackupKdf {
  const BackupKdf({this.memory = 19456, this.iterations = 2, this.parallelism = 1});

  final int memory;
  final int iterations;
  final int parallelism;

  /// Valori minimi accettati da un file (contro file manomessi che rendono la chiave debole).
  bool get acceptable => memory >= 1024 && memory <= 262144 && iterations >= 1 && iterations <= 10 &&
      parallelism >= 1 && parallelism <= 4;

  Map<String, int> toJson() => <String, int>{'m': memory, 't': iterations, 'p': parallelism};

  static BackupKdf? fromJson(Object? j) {
    if (j is! Map || j['m'] is! int || j['t'] is! int || j['p'] is! int) return null;
    return BackupKdf(memory: j['m'] as int, iterations: j['t'] as int, parallelism: j['p'] as int);
  }
}

/// Chiave del backup: resta sul telefono (archivio sicuro), mai la password.
class BackupKey {
  const BackupKey({required this.key, required this.salt, required this.kdf});

  final Uint8List key;
  final Uint8List salt;
  final BackupKdf kdf;

  String encode() => jsonEncode(<String, Object>{
    'k': base64Encode(key),
    's': base64Encode(salt),
    'kdf': kdf.toJson(),
  });

  static BackupKey? decode(String? raw) {
    if (raw == null) return null;
    try {
      final Map<String, dynamic> j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final BackupKdf? kdf = BackupKdf.fromJson(j['kdf']);
      if (kdf == null) return null;
      return BackupKey(key: base64Decode(j['k'] as String), salt: base64Decode(j['s'] as String), kdf: kdf);
    } catch (_) {
      return null;
    }
  }
}

/// Password troppo debole: il messaggio spiega perché.
String? backupPasswordProblem(String password) {
  if (password.length < 8) return 'Usa almeno 8 caratteri.';
  if (!password.contains(RegExp(r'[A-Za-zÀ-ÿ]'))) return 'Metti almeno una lettera.';
  if (!password.contains(RegExp(r'[0-9]')) && !password.contains(RegExp(r'[^A-Za-zÀ-ÿ0-9]'))) {
    return 'Aggiungi almeno un numero o un simbolo.';
  }
  return null;
}

Future<Uint8List> _argon2(List<Object> args) async {
  final String password = args[0] as String;
  final Uint8List salt = args[1] as Uint8List;
  final BackupKdf kdf = BackupKdf.fromJson(args[2])!;
  final Argon2id algorithm = Argon2id(
    memory: kdf.memory,
    iterations: kdf.iterations,
    parallelism: kdf.parallelism,
    hashLength: 32,
  );
  final SecretKey k = await algorithm.deriveKeyFromPassword(password: password, nonce: salt);
  return Uint8List.fromList(await k.extractBytes());
}

abstract final class BackupCipher {
  static const List<int> magic = <int>[0x50, 0x5A, 0x42, 0x4B, 0x01]; // «PZBK» versione 1
  static final AesGcm _aes = AesGcm.with256bits();

  static Uint8List _random(int n) {
    final Random r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  /// Ricava la chiave dalla password (in un altro isolate: Argon2id è lento apposta).
  static Future<BackupKey> deriveKey(String password, {Uint8List? salt, BackupKdf kdf = const BackupKdf()}) async {
    final Uint8List s = salt ?? _random(16);
    final Uint8List key = await Isolate.run(() => _argon2(<Object>[password, s, kdf.toJson()]));
    return BackupKey(key: key, salt: s, kdf: kdf);
  }

  /// File del backup: intestazione in chiaro (sale, costi, nonce) + cronologia cifrata.
  static Future<Uint8List> seal(BackupKey key, Uint8List plain) async {
    final Uint8List nonce = _random(12);
    final Uint8List header = utf8.encode(jsonEncode(<String, Object>{
      's': base64Encode(key.salt),
      'kdf': key.kdf.toJson(),
      'n': base64Encode(nonce),
    }));
    final SecretBox box = await _aes.encrypt(
      gzip.encode(plain),
      secretKey: SecretKey(key.key),
      nonce: nonce,
      aad: header,
    );
    final BytesBuilder out = BytesBuilder(copy: false)
      ..add(magic)
      ..add(<int>[header.length >> 8, header.length & 0xff])
      ..add(header)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  /// Intestazione del file: serve il sale per ricavare la chiave dalla password.
  static ({Uint8List salt, BackupKdf kdf, Uint8List nonce, Uint8List header, Uint8List body})? _parse(Uint8List file) {
    if (file.length < magic.length + 2 + 16) return null;
    for (int i = 0; i < magic.length; i++) {
      if (file[i] != magic[i]) return null;
    }
    final int len = (file[magic.length] << 8) | file[magic.length + 1];
    final int start = magic.length + 2;
    if (start + len + 16 > file.length) return null;
    final Uint8List header = Uint8List.sublistView(file, start, start + len);
    try {
      final Map<String, dynamic> j = Map<String, dynamic>.from(jsonDecode(utf8.decode(header)) as Map);
      final BackupKdf? kdf = BackupKdf.fromJson(j['kdf']);
      if (kdf == null || !kdf.acceptable) return null;
      return (
        salt: base64Decode(j['s'] as String),
        kdf: kdf,
        nonce: base64Decode(j['n'] as String),
        header: header,
        body: Uint8List.sublistView(file, start + len),
      );
    } catch (_) {
      return null;
    }
  }

  /// Apre il file con la password. Restituisce la chiave (per i backup successivi) e la cronologia.
  static Future<({BackupKey key, Uint8List plain})> open(String password, Uint8List file) async {
    final parsed = _parse(file);
    if (parsed == null) throw const ChatFailure('Il backup è rovinato o di un formato sconosciuto.');
    final BackupKey key = await deriveKey(password, salt: parsed.salt, kdf: parsed.kdf);
    return (key: key, plain: await openWithKey(key, file));
  }

  /// Apre il file con una chiave già ricavata.
  static Future<Uint8List> openWithKey(BackupKey key, Uint8List file) async {
    final parsed = _parse(file);
    if (parsed == null) throw const ChatFailure('Il backup è rovinato o di un formato sconosciuto.');
    final Uint8List body = parsed.body;
    try {
      final List<int> clear = await _aes.decrypt(
        SecretBox(
          Uint8List.sublistView(body, 0, body.length - 16),
          nonce: parsed.nonce,
          mac: Mac(Uint8List.sublistView(body, body.length - 16)),
        ),
        secretKey: SecretKey(key.key),
        aad: parsed.header,
      );
      return Uint8List.fromList(gzip.decode(clear));
    } on SecretBoxAuthenticationError {
      throw const ChatFailure('Password sbagliata.');
    }
  }
}

/// Contenuto del backup: le righe di ogni chat, come le salva il telefono.
class BackupContent {
  const BackupContent({required this.made, required this.chats});

  final DateTime made;
  final Map<String, List<Map<String, Object?>>> chats;

  int get messageCount => chats.values.fold(0, (int n, List<Map<String, Object?>> l) =>
      n + l.where((Map<String, Object?> r) => !r.containsKey('ev')).length);

  Uint8List encode() => utf8.encode(jsonEncode(<String, Object>{
    'v': 1,
    'made': made.toUtc().toIso8601String(),
    'chats': chats,
  }));

  static BackupContent decode(Uint8List bytes) {
    try {
      final Map<String, dynamic> j = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
      if (j['v'] != 1 || j['chats'] is! Map) throw const FormatException();
      return BackupContent(
        made: DateTime.tryParse('${j['made']}')?.toLocal() ?? DateTime.now(),
        chats: <String, List<Map<String, Object?>>>{
          for (final MapEntry<dynamic, dynamic> e in (j['chats'] as Map).entries)
            if (e.key is String && e.value is List)
              e.key as String: <Map<String, Object?>>[
                for (final Object? r in e.value as List)
                  if (r is Map) Map<String, Object?>.from(r),
              ],
        },
      );
    } catch (_) {
      throw const ChatFailure('Il backup è rovinato o di un formato sconosciuto.');
    }
  }
}

/// Dov'è il backup sul server.
class BackupInfo {
  const BackupInfo({required this.at, required this.size});

  final DateTime at;
  final int size;
}

abstract class BackupServer {
  Future<BackupInfo?> info();

  Future<void> upload(Uint8List bytes);

  Future<Uint8List> download();

  Future<void> remove();
}

class SupabaseBackupServer implements BackupServer {
  SupabaseBackupServer(this._client, {required this.uid});

  static const String bucket = 'chat-backups';
  final SupabaseClient _client;
  final String Function() uid;

  String get _path => '${uid()}/backup.bin';

  @override
  Future<BackupInfo?> info() async {
    final Object? r = await _client.rpc('chat_backup_info');
    final Object? row = r is List && r.isNotEmpty ? r.first : (r is Map ? r : null);
    if (row is! Map) return null;
    final DateTime? at = DateTime.tryParse('${row['updated_at']}');
    if (at == null) return null;
    return BackupInfo(at: at.toLocal(), size: (row['size'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<void> upload(Uint8List bytes) async {
    try {
      await _client.storage.from(bucket).uploadBinary(
        _path,
        bytes,
        fileOptions: const FileOptions(contentType: 'application/octet-stream', upsert: true),
      );
    } on StorageException catch (e) {
      throw ChatFailure(e.statusCode == '413' ? 'Backup troppo grande (massimo 20 MB).' : 'Backup non caricato. Riprova.');
    }
  }

  @override
  Future<Uint8List> download() async {
    try {
      return await _client.storage.from(bucket).download(_path);
    } on StorageException {
      throw const ChatFailure('Backup non scaricato. Controlla la connessione.');
    }
  }

  @override
  Future<void> remove() async {
    await _client.storage.from(bucket).remove(<String>[_path]);
  }
}

/// Dove resta la chiave del backup sul telefono.
abstract class BackupKeyStore {
  Future<String?> read();

  Future<void> write(String? value);
}

class SecureBackupKeyStore implements BackupKeyStore {
  SecureBackupKeyStore(this._secrets, {required this.uid});

  final FlutterSecureStorage _secrets;
  final String uid;

  String get _name => 'chat_backup_key_$uid';

  @override
  Future<String?> read() => _secrets.read(key: _name);

  @override
  Future<void> write(String? value) =>
      value == null ? _secrets.delete(key: _name) : _secrets.write(key: _name, value: value);
}

class MemoryBackupKeyStore implements BackupKeyStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? v) async => value = v;
}

/// Ogni quanto si rifà il backup da solo (all'apertura dell'app).
const Duration autoBackupEvery = Duration(hours: 24);

@visibleForTesting
BackupKdf fastKdfForTests() => const BackupKdf(memory: 1024, iterations: 1);

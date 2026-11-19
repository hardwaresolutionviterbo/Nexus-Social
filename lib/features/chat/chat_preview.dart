import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'chat_media.dart';

/// Testo del messaggio nella notifica (Fase 4, Blocco 10).
///
/// Ogni telefono ha una chiave sua per ogni chat e la manda agli altri membri dentro la chat
/// cifrata (MLS). Con quella cifra una breve anteprima che il server passa alla notifica senza
/// poterla leggere; il telefono di chi riceve la decifra anche con l'app chiusa.

/// Lunghezza massima dell'anteprima.
const int previewMaxChars = 100;

/// Testo da mettere nell'anteprima.
String previewOf({required String body, MediaKind? media}) {
  final String caption = body.trim();
  final String kind = switch (media) {
    MediaKind.image => '📷 Foto',
    MediaKind.video => '🎥 Video',
    MediaKind.audio => '🎤 Messaggio vocale',
    MediaKind.file => '📄 Documento',
    null => '',
  };
  final String text = media == null ? caption : (caption.isEmpty ? kind : '$kind · $caption');
  final String flat = text.replaceAll(RegExp(r'\s+'), ' ');
  return flat.length <= previewMaxChars ? flat : '${flat.substring(0, previewMaxChars - 1)}…';
}

abstract final class PreviewCipher {
  static final AesGcm _aes = AesGcm.with256bits();

  static Uint8List newKey() {
    final Random r = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  /// nonce (12) + testo cifrato + mac (16), in base64.
  static Future<String> seal(List<int> key, String text) async {
    final SecretBox box = await _aes.encrypt(utf8.encode(text), secretKey: SecretKey(key));
    return base64Encode(<int>[...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<String?> open(List<int> key, String sealed) async {
    try {
      final Uint8List all = base64Decode(sealed);
      if (all.length < 12 + 16) return null;
      final List<int> clear = await _aes.decrypt(
        SecretBox(
          all.sublist(12, all.length - 16),
          nonce: all.sublist(0, 12),
          mac: Mac(all.sublist(all.length - 16)),
        ),
        secretKey: SecretKey(key),
      );
      final String text = utf8.decode(clear);
      return text.length > previewMaxChars ? text.substring(0, previewMaxChars) : text;
    } catch (_) {
      return null;
    }
  }
}

/// Chiavi delle anteprime: la mia per ogni chat e quelle degli altri membri.
abstract class PreviewKeyStore {
  Future<Map<String, Object?>> read();

  Future<void> write(Map<String, Object?> value);
}

class MemoryPreviewKeyStore implements PreviewKeyStore {
  Map<String, Object?> value = <String, Object?>{};

  @override
  Future<Map<String, Object?>> read() async => value;

  @override
  Future<void> write(Map<String, Object?> v) async => value = v;
}

/// Nell'archivio sicuro del telefono: lo legge anche la notifica con l'app chiusa.
class SecurePreviewKeyStore implements PreviewKeyStore {
  const SecurePreviewKeyStore([this._secrets = const FlutterSecureStorage()]);

  static const String name = 'piazly_chiavi_anteprime';
  final FlutterSecureStorage _secrets;

  @override
  Future<Map<String, Object?>> read() async {
    try {
      final String? raw = await _secrets.read(key: name);
      final Object? j = raw == null ? null : jsonDecode(raw);
      return j is Map ? Map<String, Object?>.from(j) : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  @override
  Future<void> write(Map<String, Object?> value) => _secrets.write(key: name, value: jsonEncode(value));
}

/// Operazioni sulle chiavi. Struttura: {"mie": {chat: chiave}, "altri": {chat: {autore: chiave}},
/// "mandate": {chat: generazione}}.
class PreviewKeys {
  PreviewKeys(this.store);

  final PreviewKeyStore store;

  static Map<String, Object?> _section(Map<String, Object?> all, String name) =>
      all[name] is Map ? Map<String, Object?>.from(all[name] as Map) : <String, Object?>{};

  /// La mia chiave per la chat (creata la prima volta).
  Future<Uint8List> mine(String conversationId) async {
    final Map<String, Object?> all = await store.read();
    final Map<String, Object?> mie = _section(all, 'mie');
    final Object? have = mie[conversationId];
    if (have is String) return base64Decode(have);
    final Uint8List key = PreviewCipher.newKey();
    mie[conversationId] = base64Encode(key);
    all['mie'] = mie;
    await store.write(all);
    return key;
  }

  /// La mia chiave è già stata mandata a questa generazione della chat.
  Future<bool> sent(String conversationId, int generation) async =>
      _section(await store.read(), 'mandate')[conversationId] == generation;

  Future<void> markSent(String conversationId, int generation) async {
    final Map<String, Object?> all = await store.read();
    final Map<String, Object?> sent = _section(all, 'mandate')..[conversationId] = generation;
    all['mandate'] = sent;
    await store.write(all);
  }

  Future<void> savePeer(String conversationId, String senderId, List<int> key) async {
    if (key.length != 32) return;
    final Map<String, Object?> all = await store.read();
    final Map<String, Object?> altri = _section(all, 'altri');
    final Map<String, Object?> chat = altri[conversationId] is Map
        ? Map<String, Object?>.from(altri[conversationId] as Map)
        : <String, Object?>{};
    chat[senderId] = base64Encode(key);
    altri[conversationId] = chat;
    all['altri'] = altri;
    await store.write(all);
  }

  Future<Uint8List?> peer(String conversationId, String senderId) async {
    final Object? chat = _section(await store.read(), 'altri')[conversationId];
    final Object? k = chat is Map ? chat[senderId] : null;
    return k is String ? base64Decode(k) : null;
  }

  /// Anteprima arrivata con la notifica: il testo, oppure null se non si può leggere.
  Future<String?> open(String conversationId, String senderId, String sealed) async {
    final Uint8List? key = await peer(conversationId, senderId);
    return key == null ? null : PreviewCipher.open(key, sealed);
  }
}

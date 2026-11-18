import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, SupabaseClient;

import 'chat_models.dart';

/// Tipo di allegato (Fase 4, Blocco 3).
enum MediaKind { image, video, audio, file }

/// Limiti degli allegati.
abstract final class MediaLimits {
  /// Il contenitore accetta 50 MB per file; la cifratura aggiunge 28 byte.
  static const int maxBytes = 50 * 1024 * 1024 - 1024;

  /// Scaricati da soli all'arrivo (foto e vocali fino a 15 MB).
  static const int autoDownloadBytes = 15 * 1024 * 1024;

  static const Duration maxVoice = Duration(minutes: 5);
  static const Duration maxVideo = Duration(minutes: 3);
  static const int maxCaption = 1000;
}

/// Descrizione di un allegato dentro il messaggio cifrato: dove sta sul server (solo byte
/// cifrati), la chiave per aprirlo e i dati per mostrarlo prima di scaricarlo.
class ChatMedia {
  const ChatMedia({
    required this.kind,
    required this.path,
    required this.key,
    required this.size,
    required this.mime,
    this.name = '',
    this.width = 0,
    this.height = 0,
    this.durationMs = 0,
    this.thumb = '',
  });

  final MediaKind kind;

  /// Percorso nel contenitore «chat-media».
  final String path;

  /// Chiave AES-256 (base64): esiste solo dentro il messaggio cifrato.
  final String key;
  final int size;
  final String mime;

  /// Nome del documento (solo per i file).
  final String name;
  final int width;
  final int height;
  final int durationMs;

  /// Anteprima minuscola (JPEG base64, pochi KB) per le foto.
  final String thumb;

  Map<String, Object> toJson() => <String, Object>{
    'k': kind.name,
    'p': path,
    'key': key,
    's': size,
    'm': mime,
    if (name.isNotEmpty) 'n': name,
    if (width > 0) 'w': width,
    if (height > 0) 'h': height,
    if (durationMs > 0) 'd': durationMs,
    if (thumb.isNotEmpty) 'th': thumb,
  };

  static final RegExp _pathRule = RegExp(r'^[0-9a-f-]{36}/[^/]{1,64}/[A-Za-z0-9_-]{16,64}\.bin$');

  /// null se i dati non sono validi (un allegato mal formato non si mostra).
  static ChatMedia? fromJson(Object? j) {
    if (j is! Map) return null;
    final MediaKind? kind = MediaKind.values.where((k) => k.name == j['k']).firstOrNull;
    final Object? path = j['p'];
    final Object? key = j['key'];
    final Object? size = j['s'];
    final Object? mime = j['m'];
    if (kind == null || path is! String || key is! String || size is! num || mime is! String) {
      return null;
    }
    if (!_pathRule.hasMatch(path) || size < 0 || size > MediaLimits.maxBytes) return null;
    try {
      if (base64Decode(key).length != 32) return null;
    } catch (_) {
      return null;
    }
    String text(Object? v, int max) {
      final String s = v is String ? v : '';
      return s.length > max ? s.substring(0, max) : s;
    }

    int number(Object? v) => v is num && v > 0 && v < 1 << 31 ? v.toInt() : 0;
    return ChatMedia(
      kind: kind,
      path: path,
      key: key,
      size: size.toInt(),
      mime: text(mime, 100),
      name: text(j['n'], 200).replaceAll(RegExp(r'[/\\]'), '_'),
      width: number(j['w']),
      height: number(j['h']),
      durationMs: number(j['d']),
      thumb: text(j['th'], 20000),
    );
  }

  /// Estensione per il file salvato sul telefono.
  String get extension {
    switch (kind) {
      case MediaKind.image:
        return 'jpg';
      case MediaKind.video:
        return mime.contains('quicktime') ? 'mov' : 'mp4';
      case MediaKind.audio:
        return 'm4a';
      case MediaKind.file:
        final int dot = name.lastIndexOf('.');
        final String ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
        return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext) ? ext : 'bin';
    }
  }
}

/// Cifratura degli allegati: AES-256-GCM con una chiave casuale per ogni file.
/// Formato sul server: nonce (12 byte) · testo cifrato · etichetta (16 byte).
abstract final class MediaCipher {
  static final AesGcm _aes = AesGcm.with256bits();

  static Future<(Uint8List, String)> encrypt(List<int> plain) async {
    final SecretKey key = await _aes.newSecretKey();
    final SecretBox box = await _aes.encrypt(plain, secretKey: key);
    final List<int> raw = await key.extractBytes();
    return (Uint8List.fromList(box.concatenation()), base64Encode(raw));
  }

  /// Lancia [ChatFailure] se il file è stato alterato o la chiave è sbagliata.
  static Future<Uint8List> decrypt(List<int> blob, String key) async {
    try {
      final SecretBox box = SecretBox.fromConcatenation(
        blob,
        nonceLength: 12,
        macLength: 16,
        copy: false,
      );
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(base64Decode(key))));
    } catch (_) {
      throw const ChatFailure('Allegato rovinato o non valido.');
    }
  }

  static final Random _rng = Random.secure();

  /// Nome casuale del file sul server.
  static String randomName() {
    const String abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(24, (_) => abc[_rng.nextInt(abc.length)]).join();
  }
}

/// Contenitore degli allegati cifrati sul server.
abstract class ChatMediaServer {
  Future<void> upload(String path, Uint8List bytes);

  Future<Uint8List> download(String path);

  /// Cancella il file dal server (chi riceve, dopo averlo scaricato).
  Future<void> remove(String path);
}

class SupabaseChatMediaServer implements ChatMediaServer {
  SupabaseChatMediaServer(this._client);

  final SupabaseClient _client;

  static const String bucket = 'chat-media';

  @override
  Future<void> upload(String path, Uint8List bytes) async {
    try {
      await _client.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'application/octet-stream'),
      );
    } catch (_) {
      throw const ChatFailure('Allegato non caricato. Controlla la connessione e riprova.');
    }
  }

  @override
  Future<Uint8List> download(String path) async {
    try {
      return await _client.storage.from(bucket).download(path);
    } catch (_) {
      throw const ChatFailure('Allegato non più disponibile sul server.');
    }
  }

  @override
  Future<void> remove(String path) async {
    try {
      await _client.storage.from(bucket).remove(<String>[path]);
    } catch (_) {
      // Resta sul server: si riprova alla prossima apertura.
    }
  }
}

/// Cartella sul telefono con gli allegati in chiaro (solo dentro l'app).
class ChatMediaFiles {
  ChatMediaFiles(this._directory);

  final Future<Directory> _directory;

  Future<File> fileFor(String name) async {
    final Directory d = await _directory;
    d.createSync(recursive: true);
    return File('${d.path}/${name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}');
  }

  Future<File?> existing(String name) async {
    final File f = await fileFor(name);
    return f.existsSync() ? f : null;
  }

  Future<void> deleteAll(Iterable<String> names) async {
    for (final String n in names) {
      final File f = await fileFor(n);
      if (f.existsSync()) f.deleteSync();
    }
  }
}

/// «1,2 MB», «340 KB».
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// «0:42», «3:05».
String formatDuration(int ms) {
  final int s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

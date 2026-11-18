import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'chat_media.dart';
import 'chat_models.dart';

/// Allegato scelto sul telefono, pronto per [ChatService.sendMedia].
class PickedMedia {
  const PickedMedia({
    required this.kind,
    required this.bytes,
    required this.mime,
    this.name = '',
    this.width = 0,
    this.height = 0,
    this.durationMs = 0,
    this.thumb = '',
  });

  final MediaKind kind;
  final Uint8List bytes;
  final String mime;
  final String name;
  final int width;
  final int height;
  final int durationMs;
  final String thumb;
}

/// Fotocamera, galleria, documenti e microfono. Nei test: una versione finta.
abstract class ChatDevice {
  Future<PickedMedia?> pickImage({required bool camera});

  Future<PickedMedia?> pickVideo();

  Future<PickedMedia?> pickFile();

  /// false se il permesso del microfono è negato.
  Future<bool> startVoice();

  /// Termina la registrazione e restituisce il vocale (null se troppo corto).
  Future<PickedMedia?> stopVoice();

  Future<void> cancelVoice();
}

/// Foto ridotta (lato massimo 1600 px) e anteprima minuscola, fuori dal thread principale.
Future<PickedMedia?> prepareImage(Uint8List original) => compute(_prepareImage, original);

PickedMedia? _prepareImage(Uint8List original) {
  final img.Image? decoded = img.decodeImage(original);
  if (decoded == null) return null;
  final img.Image upright = img.bakeOrientation(decoded);
  final img.Image big = upright.width > 1600 || upright.height > 1600
      ? img.copyResize(upright,
          width: upright.width >= upright.height ? 1600 : null,
          height: upright.height > upright.width ? 1600 : null)
      : upright;
  final Uint8List jpeg = img.encodeJpg(big, quality: 80);
  final img.Image small = img.copyResize(big, width: big.width >= big.height ? 40 : null,
      height: big.height > big.width ? 40 : null);
  return PickedMedia(
    kind: MediaKind.image,
    bytes: jpeg,
    mime: 'image/jpeg',
    width: big.width,
    height: big.height,
    thumb: base64Encode(img.encodeJpg(small, quality: 50)),
  );
}

String _mimeFor(String name) {
  final String ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return const <String, String>{
        'pdf': 'application/pdf',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'txt': 'text/plain',
        'zip': 'application/zip',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'mp3': 'audio/mpeg',
        'mp4': 'video/mp4',
      }[ext] ??
      'application/octet-stream';
}

class RealChatDevice implements ChatDevice {
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _voiceStart;
  String? _voicePath;

  @override
  Future<PickedMedia?> pickImage({required bool camera}) async {
    final XFile? x = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 90,
    );
    if (x == null) return null;
    final PickedMedia? ready = await prepareImage(await x.readAsBytes());
    if (ready == null) throw const ChatFailure('Questa immagine non si può aprire.');
    return ready;
  }

  @override
  Future<PickedMedia?> pickVideo() async {
    final XFile? x = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: MediaLimits.maxVideo,
    );
    if (x == null) return null;
    final int size = await x.length();
    if (size > MediaLimits.maxBytes) {
      throw ChatFailure('Video troppo pesante (${formatBytes(size)}): massimo 50 MB, '
          'circa 1–2 minuti. Taglialo e riprova.');
    }
    return PickedMedia(
      kind: MediaKind.video,
      bytes: await x.readAsBytes(),
      mime: x.name.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4',
      name: x.name,
    );
  }

  @override
  Future<PickedMedia?> pickFile() async {
    final List<PlatformFile> picked = await FilePicker.pickFiles();
    final PlatformFile? f = picked.firstOrNull;
    if (f == null) return null;
    final int size = await f.xFile.length();
    if (size > MediaLimits.maxBytes) {
      throw ChatFailure('Documento troppo pesante (${formatBytes(size)}): massimo 50 MB.');
    }
    return PickedMedia(
      kind: MediaKind.file,
      bytes: await f.xFile.readAsBytes(),
      mime: _mimeFor(f.name),
      name: f.name,
    );
  }

  @override
  Future<bool> startVoice() async {
    if (!await _recorder.hasPermission()) return false;
    final Directory tmp = await getTemporaryDirectory();
    _voicePath = '${tmp.path}/vocale_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 48000, sampleRate: 44100, numChannels: 1),
      path: _voicePath!,
    );
    _voiceStart = DateTime.now();
    return true;
  }

  @override
  Future<PickedMedia?> stopVoice() async {
    final String? path = await _recorder.stop();
    final DateTime? start = _voiceStart;
    _voiceStart = null;
    if (path == null || start == null) return null;
    final File f = File(path);
    final int ms = DateTime.now().difference(start).inMilliseconds;
    try {
      if (ms < 800 || !f.existsSync()) return null;
      return PickedMedia(
        kind: MediaKind.audio,
        bytes: await f.readAsBytes(),
        mime: 'audio/mp4',
        durationMs: ms,
      );
    } finally {
      if (f.existsSync()) f.deleteSync();
    }
  }

  @override
  Future<void> cancelVoice() async {
    await _recorder.cancel();
    _voiceStart = null;
    final String? p = _voicePath;
    if (p != null && File(p).existsSync()) File(p).deleteSync();
  }
}

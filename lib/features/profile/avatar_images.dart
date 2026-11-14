import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

class AvatarImageException implements Exception {
  const AvatarImageException(this.message);

  final String message;
}

/// Foto profilo e miniatura compresse al caricamento (S5, A5).
///
/// - Foto: quadrata 512×512, JPEG. Miniatura: 128×128, JPEG (servirà anche come marker
///   sulla mappa in Fase 3).
/// - La ricodifica elimina i metadati dell'immagine originale (EXIF, posizione GPS).
class AvatarImages {
  const AvatarImages({required this.avatar, required this.thumbnail});

  static const int avatarSize = 512;
  static const int thumbnailSize = 128;

  /// Limite del server (bucket `avatars`).
  static const int maxBytes = 1024 * 1024;

  final Uint8List avatar;
  final Uint8List thumbnail;

  static Future<AvatarImages> prepareInBackground(Uint8List original) =>
      compute(prepare, original);

  static AvatarImages prepare(Uint8List original) {
    final img.Image? decoded = img.decodeImage(original);
    if (decoded == null) {
      throw const AvatarImageException('Formato dell\'immagine non supportato.');
    }
    final img.Image oriented = img.bakeOrientation(decoded);
    final int side = oriented.width < oriented.height ? oriented.width : oriented.height;
    final img.Image square = img.copyCrop(
      oriented,
      x: (oriented.width - side) ~/ 2,
      y: (oriented.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final img.Image big = img.copyResize(
      square,
      width: avatarSize,
      height: avatarSize,
      interpolation: img.Interpolation.average,
    );
    final img.Image small = img.copyResize(
      square,
      width: thumbnailSize,
      height: thumbnailSize,
      interpolation: img.Interpolation.average,
    );
    // Niente metadati nel file finale (posizione GPS, modello del telefono…).
    big.exif = img.ExifData();
    small.exif = img.ExifData();
    final Uint8List avatar = img.encodeJpg(big, quality: 82);
    final Uint8List thumbnail = img.encodeJpg(small, quality: 78);
    if (avatar.length > maxBytes) {
      throw const AvatarImageException('Immagine troppo pesante: scegline un\'altra.');
    }
    return AvatarImages(avatar: avatar, thumbnail: thumbnail);
  }
}

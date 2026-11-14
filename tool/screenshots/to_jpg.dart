// Converte le anteprime PNG in JPEG leggeri (720 px di larghezza) per il log.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final Directory out = Directory('tool/screenshots/jpg')..createSync(recursive: true);
  final List<File> pngs = Directory('tool/screenshots/out')
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.png'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  for (final File f in pngs) {
    final img.Image source = img.decodePng(f.readAsBytesSync())!;
    final img.Image small = img.copyResize(source, width: 720, interpolation: img.Interpolation.average);
    final String name = f.uri.pathSegments.last.replaceAll('.png', '.jpg');
    File('${out.path}/$name').writeAsBytesSync(img.encodeJpg(small, quality: 85));
    stdout.writeln('Convertita: $name');
  }
}

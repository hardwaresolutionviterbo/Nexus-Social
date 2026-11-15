// Anteprime per il titolare (Fase 3, Blocco 1): schermate della Mappa con una mappa
// disegnata a mano (non reale) e una posizione inventata. Nessun servizio reale.
//
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/shell/app_shell.dart';

import '../../test/support/fake_map.dart';

Future<void> _loadFonts() async {
  final String root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final Directory dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final FontLoader roboto = FontLoader('Roboto');
  final FontLoader fallback = FontLoader('FlutterTest');
  final FontLoader ahem = FontLoader('Ahem');
  final FontLoader icons = FontLoader('MaterialIcons');
  for (final FileSystemEntity f in dir.listSync()) {
    final String name = f.uri.pathSegments.last;
    final Future<ByteData> data =
        File(f.path).readAsBytes().then((Uint8List b) => ByteData.view(b.buffer));
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) {
      roboto.addFont(data);
      fallback.addFont(data);
      ahem.addFont(data);
    }
    if (name.startsWith('MaterialIcons-Regular')) icons.addFont(data);
  }
  await roboto.load();
  await fallback.load();
  await ahem.load();
  await icons.load();
}

ThemeData _withRoboto(ThemeData t) => t.copyWith(
  filledButtonTheme: FilledButtonThemeData(
    style: t.filledButtonTheme.style?.copyWith(
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w800),
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      textStyle: const TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700),
    ),
  ),
  chipTheme: t.chipTheme.copyWith(
    labelStyle: (t.chipTheme.labelStyle ?? const TextStyle()).copyWith(fontFamily: 'Roboto'),
  ),
);

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester tester, String name, FakeMap map,
      {Future<void> Function()? before}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _withRoboto(AppTheme.light),
      home: AppShell(map: map.services),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Mappa')));
    await tester.pumpAndSettle();
    if (before != null) await before();
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
  }

  testWidgets('mappa 1 · avviso di sicurezza al primo accesso', (tester) async {
    await shoot(tester, 'mappa_1_avviso_sicurezza', FakeMap());
  });

  testWidgets('mappa 2 · spiegazione prima del permesso di posizione', (tester) async {
    await shoot(tester, 'mappa_2_permesso_posizione', FakeMap(noticeSeen: true));
  });

  testWidgets('mappa 3 · mappa con il segnaposto rotondo', (tester) async {
    final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
    await shoot(
      tester,
      'mappa_3_mappa',
      map,
      before: () async => map.location.emit(fixAt(42.42, 12.10)),
    );
  });
}

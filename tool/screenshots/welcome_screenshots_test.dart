// Anteprima per il titolare: schermata iniziale di registrazione (grafica del 24/11/2026).
//
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/onboarding/onboarding_flow.dart';

import '../../test/support/fake_auth_gateway.dart';

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
  // Emoji a colori (installate dal workflow delle anteprime, se disponibili).
  final File emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emoji.existsSync()) {
    final FontLoader e = FontLoader('NotoColorEmoji')
      ..addFont(emoji.readAsBytes().then((Uint8List b) => ByteData.view(b.buffer)));
    await e.load();
  }
  await roboto.load();
  await fallback.load();
  await ahem.load();
  await icons.load();
}

ThemeData _withRoboto(ThemeData base) => _withRobotoOnly(
  base.copyWith(textTheme: base.textTheme.apply(fontFamilyFallback: const <String>['NotoColorEmoji'])),
);

ThemeData _withRobotoOnly(ThemeData t) => t.copyWith(
  filledButtonTheme: FilledButtonThemeData(
    style: t.filledButtonTheme.style?.copyWith(
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w800),
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: (t.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700),
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
  listTileTheme: t.listTileTheme.copyWith(
    titleTextStyle: (t.listTileTheme.titleTextStyle ?? t.textTheme.bodyLarge)
        ?.copyWith(fontFamily: 'Roboto'),
    subtitleTextStyle: (t.listTileTheme.subtitleTextStyle ?? t.textTheme.bodyMedium)
        ?.copyWith(fontFamily: 'Roboto'),
  ),
);

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester tester, String name, Widget home,
      {Future<void> Function()? before}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // Nei test le ombre diventano bordi neri: qui si disegnano come sul telefono.
    debugDisableShadows = false;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _withRoboto(AppTheme.light),
      home: home,
    ));
    await tester.pumpAndSettle();
    if (before != null) await before();
    await tester.pumpAndSettle();
    // Le foto si decodificano solo fuori dal tempo finto dei test.
    await tester.runAsync(() async {
      for (final Element e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();
    try {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('benvenuto · schermata iniziale di registrazione', (tester) async {
    final FakeAuthGateway gateway = FakeAuthGateway();
    addTearDown(gateway.close);
    await shoot(tester, 'benvenuto_1', OnboardingFlow(gateway: gateway, today: () => DateTime(2026, 11, 24)));
  });
}

// Anteprime per il titolare (Fase 6, Blocco 1): Aziende con dati inventati, nessun servizio reale.
//
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/business/business_models.dart';
import 'package:nexus_social/features/business/business_screens.dart';
import 'package:nexus_social/features/market/comuni_italia.dart';

import '../../test/support/fake_business.dart';
import '../../test/support/fake_comuni.dart';

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

const String io = 'utenteAnna000000000000000001';
const BusinessAddress sede =
    BusinessAddress(street: 'Piazza del Popolo', civic: '7', city: 'Porano', cap: '05010', province: 'TR');
final DateTime now = DateTime(2026, 11, 17, 10, 30);

const BusinessHours orari = BusinessHours(<int, List<HourSlot>>{
  1: <HourSlot>[HourSlot(420, 780), HourSlot(960, 1200)],
  2: <HourSlot>[HourSlot(420, 780), HourSlot(960, 1200)],
  3: <HourSlot>[HourSlot(420, 780), HourSlot(960, 1200)],
  4: <HourSlot>[HourSlot(420, 780), HourSlot(960, 1200)],
  5: <HourSlot>[HourSlot(420, 780), HourSlot(1080, 1560)],
  6: <HourSlot>[HourSlot(480, 1560)],
});

FakeBusinessRepository seeded({VerificationStatus status = VerificationStatus.verified}) => FakeBusinessRepository(me: io)
  ..seed(
    id: io,
    username: 'barcentrale',
    name: 'Bar Centrale',
    category: BusinessCategory.bar,
    address: sede,
    lat: 42.6851,
    lng: 12.1029,
    status: status,
    hours: orari,
    phone: '0763 000000',
    bookingUrl: 'https://esempio.it/prenota',
    description: 'Colazioni, pranzi veloci e aperitivi in piazza. Dehors riscaldato d\'inverno.',
  );

void main() {
  setUpAll(() async {
    await _loadFonts();
    ComuniItalia.testData = fakeComuni();
  });

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

  testWidgets('aziende 1 · invito a registrare l\'attività', (tester) async {
    await shoot(tester, 'aziende_1_invito', MyBusinessScreen(repository: FakeBusinessRepository(me: io), now: () => now));
  });

  testWidgets('aziende 2 · la mia attività in verifica', (tester) async {
    await shoot(tester, 'aziende_2_mia_attivita',
        MyBusinessScreen(repository: seeded(status: VerificationStatus.pending), now: () => now));
  });

  testWidgets('aziende 3 · modifica del profilo attività', (tester) async {
    final FakeBusinessRepository repo = seeded();
    await shoot(tester, 'aziende_3_modifica', BusinessPageEditScreen(repository: repo, initial: repo.pages[io]));
  });

  testWidgets('aziende 4 · scheda pubblica verificata', (tester) async {
    await shoot(tester, 'aziende_4_scheda',
        BusinessProfileScreen(repository: seeded(), id: io, now: () => now));
  });

  testWidgets('aziende 5 · verifica degli amministratori', (tester) async {
    await shoot(tester, 'aziende_5_verifica', BusinessReviewScreen(repository: seeded(status: VerificationStatus.pending)));
  });
}

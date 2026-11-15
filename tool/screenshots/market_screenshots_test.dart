// Anteprime per il titolare (Fase 5, Blocco 1): Scambia & Vendi con dati finti.
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/market/market_catalog_data.dart';
import 'package:nexus_social/features/market/market_models.dart';
import 'package:nexus_social/features/market/market_section_screen.dart';
import 'package:nexus_social/features/market/my_market_screen.dart';

import '../../test/support/fake_map.dart';
import '../../test/support/fake_market.dart';

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
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _withRoboto(AppTheme.light),
      home: home,
    ));
    await tester.pumpAndSettle();
    if (before != null) await before();
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
  }

  Widget section(MarketSection s, FakeMarketRepository repo, FakeMap map) => Scaffold(
    body: SafeArea(
      child: MarketSectionScreen(
        section: s,
        repository: repo,
        services: map.services,
        pickImage: () async => img.encodePng(img.Image(width: 64, height: 64)),
      ),
    ),
  );

  testWidgets('mercato 1 · sezione Vendita', (tester) async {
    await shoot(tester, 'mercato_1_vendita',
        section(MarketSection.sale, FakeMarketRepository(), FakeMap()));
  });

  testWidgets('mercato 2 · categorie principali', (tester) async {
    await shoot(tester, 'mercato_2_categorie',
        section(MarketSection.sale, FakeMarketRepository(), FakeMap()), before: () async {
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_sale')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('scegli_categoria')));
    });
  });

  testWidgets('mercato 3 · sottocategorie di Elettronica', (tester) async {
    await shoot(tester, 'mercato_3_sottocategorie',
        section(MarketSection.sale, FakeMarketRepository(), FakeMap()), before: () async {
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_sale')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('scegli_categoria')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elettronica'));
    });
  });

  testWidgets('mercato 4 · modulo di vendita compilato', (tester) async {
    final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
    await shoot(tester, 'mercato_4_modulo',
        section(MarketSection.sale, FakeMarketRepository(), map), before: () async {
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_sale')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('scegli_categoria')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elettronica'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smartphone'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_titolo')), 'iPhone 13 128 GB');
      await tester.enterText(
          find.byKey(const ValueKey<String>('mercato_descrizione')), 'Perfetto, con scatola e cover');
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_prezzo')), '350');
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_campo_memoria')), '128 GB');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Ottimo stato'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ottimo stato'));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('mercato 5 · consegna, posizione e divieti', (tester) async {
    final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
    await shoot(tester, 'mercato_5_conferma',
        section(MarketSection.swap, FakeMarketRepository(), map), before: () async {
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_swap')));
      await tester.pumpAndSettle();
      final Finder pos = find.byKey(const ValueKey<String>('mercato_mia_posizione'));
      await tester.ensureVisible(pos);
      await tester.pumpAndSettle();
      await tester.tap(pos);
      await tester.pump();
      map.location.emit(fixAt(41.9028, 12.4964));
      await tester.pumpAndSettle();
      final Finder ok = find.byKey(const ValueKey<String>('mercato_conferma_divieti'));
      await tester.tap(ok);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey<String>('mercato_pubblica')));
    });
  });

  testWidgets('mercato 6 · i miei annunci', (tester) async {
    await shoot(
      tester,
      'mercato_6_miei_annunci',
      MyMarketScreen(
        repository: FakeMarketRepository(items: <MyMarketListing>[
          sampleMarket(expiresAt: DateTime.now().add(const Duration(days: 25))),
          sampleMarket(id: 'm2', title: 'Divano tre posti', slug: 'casa-arredamento-divani-poltrone',
              priceCents: 15000, expiresAt: DateTime.now().add(const Duration(days: 3))),
          sampleMarket(id: 'm3', title: 'Fiat Panda 2015', slug: 'motori-auto', priceCents: 450000,
              review: ReviewStatus.pendingReview,
              expiresAt: DateTime.now().add(const Duration(days: 29))),
        ]),
        catalog: MarketCatalog(builtInMarketCatalog),
        section: MarketSection.sale,
      ),
    );
  });
}

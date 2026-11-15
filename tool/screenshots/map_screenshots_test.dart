// Anteprime per il titolare (Fase 3, Blocco 1): schermate della Mappa con una mappa
// disegnata a mano (non reale) e una posizione inventata. Nessun servizio reale.
//
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/latest_listings_screen.dart';
import 'package:nexus_social/features/map/listing_form_screen.dart';
import 'package:nexus_social/features/map/listing_sheets.dart';
import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/map/my_listings_screen.dart';
import 'package:nexus_social/features/shell/app_shell.dart';

import '../../test/support/fake_listings.dart';
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
      {Future<void> Function()? before, FakeListingRepository? listings}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _withRoboto(AppTheme.light),
      home: AppShell(map: map.services, listings: listings),
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

  Future<void> shootScreen(WidgetTester tester, String name, Widget screen,
      {Future<void> Function()? before}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _withRoboto(AppTheme.light),
      home: screen,
    ));
    await tester.pumpAndSettle();
    if (before != null) await before();
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
  }

  final DateTime now = DateTime(2026, 11, 15, 10, 30);

  testWidgets('annuncio 1 · nuovo annuncio, zona approssimata', (tester) async {
    await shootScreen(
      tester,
      'annuncio_1_nuovo',
      ListingFormScreen(
        repository: FakeListingRepository(),
        surface: FakeMap().services.surface,
        currentPosition: const GeoPoint(43.7696, 11.2558),
        now: () => now,
      ),
      before: () async {
        await tester.enterText(
            find.byKey(const ValueKey<String>('annuncio_testo')), 'Chi viene a prendere un caffè?');
        await tester.enterText(
            find.byKey(const ValueKey<String>('annuncio_dettagli')), 'Verso le 17, centro storico');
        FocusManager.instance.primaryFocus?.unfocus();
      },
    );
  });

  testWidgets('annuncio 2 · scelta del punto sulla mappa', (tester) async {
    final FakeMap map = FakeMap();
    await shootScreen(
      tester,
      'annuncio_2_scegli_punto',
      ListingFormScreen(
        repository: FakeListingRepository(),
        surface: map.services.surface,
        currentPosition: const GeoPoint(43.7696, 11.2558),
        now: () => now,
      ),
      before: () async {
        await tester.ensureVisible(find.text('Scegli il punto'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Scegli il punto'));
      },
    );
  });

  testWidgets('annuncio 3 · punto scelto, modalità mostrata', (tester) async {
    await shootScreen(
      tester,
      'annuncio_3_punto_scelto',
      ListingFormScreen(
        repository: FakeListingRepository(),
        surface: FakeMap().services.surface,
        currentPosition: const GeoPoint(43.7696, 11.2558),
        now: () => now,
      ),
      before: () async {
        await tester.enterText(find.byKey(const ValueKey<String>('annuncio_testo')),
            'Ci manca uno per il calcetto, chi viene?');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.ensureVisible(find.text('Scegli il punto'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Scegli il punto'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Usa questo punto'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey<String>('annuncio_pubblica')));
      },
    );
  });

  testWidgets('annuncio 4 · i miei annunci', (tester) async {
    await shootScreen(
      tester,
      'annuncio_4_miei_annunci',
      MyListingsScreen(
        repository: FakeListingRepository(items: <MyListing>[
          sampleListing(),
          sampleListing(id: 'a2', title: 'Ci manca uno per il calcetto, chi viene?',
              place: ListingPlace.chosenPoint, expiresAt: DateTime(2026, 11, 18, 10, 30)),
          sampleListing(id: 'a3', title: 'Partita a carte al circolo',
              state: ListingState.expired),
          sampleListing(id: 'a4', title: 'Regalo libri di scuola', state: ListingState.completed),
        ]),
        surface: FakeMap().services.surface,
        now: () => now,
      ),
    );
  });

  List<NearbyListing> vicini() => <NearbyListing>[
    sampleNearby(),
    sampleNearby(id: 'n2', title: 'Chi viene a prendere un caffè in centro?', availableNow: true,
        distance: 250),
    sampleNearby(id: 'n3', title: 'Cerco compagni per una partita a padel', distance: 3500),
  ];

  testWidgets('vicini 1 · scheda di un annuncio', (tester) async {
    final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
    final FakeListingRepository repo = FakeListingRepository()..nearbyItems = vicini();
    await shoot(tester, 'vicini_1_scheda', map, listings: repo, before: () async {
      map.location.emit(fixAt(43.7696, 11.2558));
      await tester.pumpAndSettle();
      map.handle.tapMarker('n1');
    });
  });

  testWidgets('vicini 2 · ultimi annunci', (tester) async {
    await shootScreen(
      tester,
      'vicini_2_ultimi_annunci',
      LatestListingsScreen(
        services: ListingSheetServices(
          listings: FakeListingRepository()..nearbyItems = vicini(),
        ),
        origin: const GeoPoint(43.7696, 11.2558),
        filters: const MapFilters(),
        now: () => now,
      ),
    );
  });

  testWidgets('vicini 3 · filtri', (tester) async {
    final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
    final FakeListingRepository repo = FakeListingRepository()..nearbyItems = vicini();
    await shoot(tester, 'vicini_3_filtri', map, listings: repo, before: () async {
      map.location.emit(fixAt(43.7696, 11.2558));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filtri'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ultime 24 ore'));
    });
  });
}

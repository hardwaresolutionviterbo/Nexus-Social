import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/listing_form_screen.dart';
import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/listing_repository.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/map/map_screen.dart';
import 'package:nexus_social/features/map/my_listings_screen.dart';
import 'package:nexus_social/features/profile/profile_models.dart';
import 'package:nexus_social/features/shell/app_shell.dart';

import '../support/app_helpers.dart';
import '../support/fake_listings.dart';
import '../support/fake_map.dart';

/// Fase 3, Blocco 2 · Pubblicare un annuncio sulla Mappa (categoria Libera, foto, scadenza,
/// zona approssimata o punto scelto a mano, modifica e chiusura).
void main() {
  final DateTime now = DateTime(2026, 11, 15, 10, 30);
  const GeoPoint here = GeoPoint(43.7696, 11.2558);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Apre [screen] sopra una pagina di partenza, così la chiusura con un risultato funziona.
  Future<List<Object?>> open(WidgetTester tester, Widget screen) async {
    phone(tester);
    final List<Object?> results = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => Center(
              child: TextButton(
                onPressed: () async =>
                    results.add(await Navigator.of(ctx).push<Object?>(
                      MaterialPageRoute<Object?>(builder: (_) => screen),
                    )),
                child: const Text('apri'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder publishButton() => find.byKey(const ValueKey<String>('annuncio_pubblica'));

  ListingFormScreen form(
    FakeListingRepository repo, {
    GeoPoint? position = here,
    bool isMinor = false,
    MyListing? existing,
    FakeMap? map,
    List<Uint8List>? gallery,
  }) => ListingFormScreen(
    repository: repo,
    surface: (map ?? FakeMap()).services.surface,
    currentPosition: position,
    isMinor: isMinor,
    existing: existing,
    now: () => now,
    pickImage: () async => gallery == null || gallery.isEmpty ? null : gallery.removeAt(0),
  );

  group('Regole', () {
    test('T5 · scadenze da 1 ora a 7 giorni; «Oggi» fino a mezzanotte, almeno un\'ora', () {
      expect(ListingExpiry.values.map((ListingExpiry e) => e.label),
          <String>['1 ora', '3 ore', 'Oggi', '3 giorni', '7 giorni']);
      expect(ListingExpiry.oneHour.resolve(now), now.add(const Duration(hours: 1)));
      expect(ListingExpiry.today.resolve(now), DateTime(2026, 11, 15, 23, 59));
      final DateTime late = DateTime(2026, 11, 15, 23, 30);
      expect(ListingExpiry.today.resolve(late), late.add(const Duration(hours: 1)));
      expect(ListingExpiry.sevenDays.resolve(now), now.add(const Duration(days: 7)));
    });

    test('testo da 3 a 120 caratteri, dettagli al massimo 2000', () {
      expect(ListingRules.titleError('ok'), isNotNull);
      expect(ListingRules.titleError('  ab  '), isNotNull);
      expect(ListingRules.titleError('Caffè?'), isNull);
      expect(ListingRules.titleError('x' * 121), isNotNull);
      expect(ListingRules.detailsError('x' * 2001), isNotNull);
      expect(ListingRules.freeCategory, 'libera');
    });

    test('scadenza leggibile nell\'elenco', () {
      expect(expiryLabel(now.add(const Duration(minutes: 20)), now), 'scade tra 20 min');
      expect(expiryLabel(now.add(const Duration(hours: 1)), now), 'scade tra 1 ora');
      expect(expiryLabel(now.add(const Duration(hours: 5)), now), 'scade tra 5 ore');
      expect(expiryLabel(now.add(const Duration(days: 3)), now), 'scade tra 3 giorni');
      expect(expiryLabel(now.subtract(const Duration(minutes: 1)), now), 'scaduto');
    });

    test('annuncio dal server: modalità, punto pubblico e punto salvato, stato', () {
      final MyListing l = MyListing.fromJson(<String, dynamic>{
        'id': 'x1',
        'title': 'Calcetto stasera',
        'details': '',
        'photos': <String>['u/f.jpg'],
        'location_mode': 'precise',
        'public_lat': 43.7731,
        'public_lon': 11.256,
        'exact_lat': 43.7731,
        'exact_lon': 11.256,
        'status': 'expired',
        'expires_at': '2026-11-15T10:00:00Z',
        'created_at': '2026-11-15T09:00:00Z',
      });
      expect(l.place, ListingPlace.chosenPoint);
      expect(l.state, ListingState.expired);
      expect(l.editable, isFalse);
      expect(l.photos, <String>['u/f.jpg']);
      expect(ListingPlace.approximateZone.serverValue, 'approximate');
      expect(ListingPlace.chosenPoint.serverValue, 'precise');
    });

    test('foto: lato lungo ridotto a 1600 px e ricodificata in JPEG', () {
      final Uint8List big = img.encodePng(img.Image(width: 3000, height: 2000));
      final img.Image out = img.decodeJpg(ListingPhotos.prepare(big))!;
      expect(out.width, 1600);
      expect(out.height, closeTo(1067, 1));
      expect(
        () => ListingPhotos.prepare(Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(isA<ListingFailure>()),
      );
    });
  });

  group('Nuovo annuncio', () {
    testWidgets('categoria Libera, zona approssimata preselezionata e modalità sempre scritta', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository();
      final List<Object?> results = await open(tester, form(repo));

      expect(find.text('Libera · gratuito'), findsOneWidget);
      expect(find.text('Modalità di posizione: Zona approssimata'), findsOneWidget);
      expect(find.textContaining('mai dove ti trovi esattamente'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('annuncio_testo')),
        'Chi viene a prendere un caffè?',
      );
      await tapVisible(tester, publishButton());

      expect(repo.published, hasLength(1));
      final ListingDraft d = repo.published.single;
      expect(d.title, 'Chi viene a prendere un caffè?');
      expect(d.place, ListingPlace.approximateZone);
      expect(d.point, here);
      expect(d.expiresAt, now.add(const Duration(hours: 3)));
      expect(results, <Object?>[true]);
    });

    testWidgets('testo troppo corto: nessuna pubblicazione', (WidgetTester tester) async {
      final FakeListingRepository repo = FakeListingRepository();
      await open(tester, form(repo));
      await tester.enterText(find.byKey(const ValueKey<String>('annuncio_testo')), 'ok');
      await tapVisible(tester, publishButton());
      expect(find.text('Scrivi almeno 3 caratteri.'), findsOneWidget);
      expect(repo.published, isEmpty);
    });

    testWidgets('scadenza scelta tra le cinque proposte', (WidgetTester tester) async {
      final FakeListingRepository repo = FakeListingRepository();
      await open(tester, form(repo));
      await tester.enterText(find.byKey(const ValueKey<String>('annuncio_testo')), 'Partita a carte');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, '7 giorni'));
      await tapVisible(tester, publishButton());
      expect(repo.published.single.expiresAt, now.add(const Duration(days: 7)));
    });

    testWidgets('senza posizione: si chiede di consentirla o di scegliere un punto', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository();
      await open(tester, form(repo, position: null));
      expect(find.text('Serve la posizione: consentila dalla Mappa.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('annuncio_testo')), 'Calcetto stasera');
      await tapVisible(tester, publishButton());
      expect(find.byKey(const ValueKey<String>('annuncio_errore')), findsOneWidget);
      expect(repo.published, isEmpty);
    });

    testWidgets('punto scelto a mano: dalla mappa, solo per questo annuncio', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository();
      final FakeMap map = FakeMap();
      map.handle.centerPoint = const GeoPoint(43.7731, 11.256);
      await open(tester, form(repo, map: map));
      await tester.enterText(
        find.byKey(const ValueKey<String>('annuncio_testo')),
        'Ci manca uno per il calcetto, chi viene?',
      );
      await tapVisible(tester, find.text('Scegli il punto'));
      expect(find.text('Usa questo punto'), findsOneWidget);
      expect(find.textContaining('non scegliere casa tua'), findsOneWidget);
      await tester.tap(find.text('Usa questo punto'));
      await tester.pumpAndSettle();

      expect(find.text('Modalità di posizione: Punto scelto sulla mappa'), findsOneWidget);
      expect(find.text('Cambia punto'), findsOneWidget);
      await tapVisible(tester, publishButton());

      final ListingDraft d = repo.published.single;
      expect(d.place, ListingPlace.chosenPoint);
      expect(d.point, const GeoPoint(43.7731, 11.256));
    });

    testWidgets('M3 · minorenne e punto preciso: prima l\'avviso di sicurezza', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository();
      await open(tester, form(repo, isMinor: true));
      await tester.enterText(find.byKey(const ValueKey<String>('annuncio_testo')), 'Giro in bici');
      await tapVisible(tester, find.text('Scegli il punto'));
      await tester.tap(find.text('Usa questo punto'));
      await tester.pumpAndSettle();
      await tapVisible(tester, publishButton());

      expect(find.text('Sicurezza sulla mappa'), findsOneWidget);
      expect(repo.published, isEmpty);
      await tester.tap(find.text('Ho capito'));
      await tester.pumpAndSettle();
      expect(repo.published, hasLength(1));
    });

    testWidgets('M3 · minorenne con zona approssimata: nessun avviso in più', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository();
      await open(tester, form(repo, isMinor: true));
      await tester.enterText(find.byKey(const ValueKey<String>('annuncio_testo')), 'Giro in bici');
      await tapVisible(tester, publishButton());
      expect(find.text('Sicurezza sulla mappa'), findsNothing);
      expect(repo.published, hasLength(1));
    });

    testWidgets('foto dalla galleria, al massimo 4, si possono togliere', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository();
      final List<Uint8List> gallery = <Uint8List>[
        for (int i = 0; i < 5; i++) img.encodePng(img.Image(width: 8, height: 8)),
      ];
      await open(tester, form(repo, gallery: gallery));
      final Finder add = find.byKey(const ValueKey<String>('aggiungi_foto'));
      for (int i = 0; i < 4; i++) {
        await tapVisible(tester, add);
      }
      expect(add, findsNothing);
      await tester.tap(find.byTooltip('Togli la foto').first);
      await tester.pumpAndSettle();
      expect(add, findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey<String>('annuncio_testo')), 'Regalo libri');
      await tapVisible(tester, publishButton());
      expect(repo.published.single.newPhotos, hasLength(3));
    });

    testWidgets('errore del server: messaggio chiaro, si resta nel modulo', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository()
        ..failWith = 'Scadenza non valida (da 1 ora a 7 giorni).';
      await open(tester, form(repo));
      await tester.enterText(find.byKey(const ValueKey<String>('annuncio_testo')), 'Partita a carte');
      await tapVisible(tester, publishButton());
      expect(find.text('Scadenza non valida (da 1 ora a 7 giorni).'), findsOneWidget);
      expect(find.text('Nuovo annuncio'), findsOneWidget);
    });
  });

  group('I miei annunci', () {
    testWidgets('stato, modalità e scadenza; azioni solo sugli annunci attivi', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository(items: <MyListing>[
        sampleListing(),
        sampleListing(id: 'a2', title: 'Calcetto ieri', state: ListingState.expired,
            place: ListingPlace.chosenPoint),
      ]);
      await open(tester, MyListingsScreen(
        repository: repo, surface: FakeMap().services.surface, now: () => now));

      expect(find.text('Chi viene a prendere un caffè?'), findsOneWidget);
      expect(find.text('Attivo'), findsOneWidget);
      expect(find.text('Scaduto'), findsOneWidget);
      expect(find.text('Zona approssimata'), findsOneWidget);
      expect(find.text('Punto scelto sulla mappa'), findsOneWidget);
      expect(find.text('scade tra 3 ore'), findsOneWidget);
      expect(find.text('Modifica'), findsOneWidget);
      expect(find.text('Chiudi'), findsOneWidget);
    });

    testWidgets('Modifica: testo e scadenza; il luogo si sposta solo se cambia', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository(items: <MyListing>[sampleListing()]);
      await open(tester, MyListingsScreen(
        repository: repo, surface: FakeMap().services.surface, currentPosition: here,
        now: () => now));
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();

      expect(find.text('Modifica annuncio'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Lascia com\'è'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('annuncio_testo')), 'Caffè al bar della piazza?');
      await tapVisible(tester, publishButton());

      expect(repo.updates.single.$1, 'a1');
      expect(repo.updates.single.$2.title, 'Caffè al bar della piazza?');
      expect(repo.updates.single.$2.expiresAt, DateTime(2026, 11, 15, 14));
      expect(repo.moves, isEmpty);
    });

    testWidgets('Modifica: nuovo punto scelto sulla mappa → l\'annuncio si sposta', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository(items: <MyListing>[sampleListing()]);
      final FakeMap map = FakeMap();
      map.handle.centerPoint = const GeoPoint(43.78, 11.24);
      await open(tester, MyListingsScreen(
        repository: repo, surface: map.services.surface, currentPosition: here, now: () => now));
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Scegli il punto'));
      await tester.tap(find.text('Usa questo punto'));
      await tester.pumpAndSettle();
      await tapVisible(tester, publishButton());

      expect(repo.moves.single.$2, const GeoPoint(43.78, 11.24));
      expect(repo.moves.single.$3, ListingPlace.chosenPoint);
    });

    testWidgets('Chiudi: con conferma, poi l\'annuncio risulta chiuso', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository(items: <MyListing>[sampleListing()]);
      await open(tester, MyListingsScreen(
        repository: repo, surface: FakeMap().services.surface, now: () => now));
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      expect(find.text('Chiudere l\'annuncio?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Chiudi'));
      await tester.pumpAndSettle();
      expect(repo.closed, <String>['a1']);
      expect(find.text('Chiuso'), findsOneWidget);
      expect(find.text('Modifica'), findsNothing);
    });
  });

  group('Dalla Mappa', () {
    Future<void> pumpMap(WidgetTester tester, {FakeListingRepository? repo}) async {
      phone(tester);
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: MapScreen(services: map.services, listings: repo)),
      ));
      await tester.pumpAndSettle();
      map.location.emit(fixAt(here.latitude, here.longitude));
      await tester.pumpAndSettle();
    }

    testWidgets('server spento: «Pubblica» spiega che serve il collegamento', (
      WidgetTester tester,
    ) async {
      await pumpMap(tester);
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_annuncio')));
      await tester.pump();
      expect(find.textContaining('serve il collegamento al server'), findsOneWidget);
      expect(find.text('Nuovo annuncio'), findsNothing);
    });

    testWidgets('«Pubblica» apre il modulo con la posizione attuale; poi conferma', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = FakeListingRepository();
      await pumpMap(tester, repo: repo);
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_annuncio')));
      await tester.pumpAndSettle();
      expect(find.text('Nuovo annuncio'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('annuncio_testo')), 'Caffè?');
      await tapVisible(tester, publishButton());
      expect(repo.published.single.point, here);
      expect(find.text('Annuncio pubblicato.'), findsOneWidget);
    });

    testWidgets('«I miei annunci» dalla Mappa', (WidgetTester tester) async {
      final FakeListingRepository repo = FakeListingRepository(items: <MyListing>[sampleListing()]);
      await pumpMap(tester, repo: repo);
      await tester.tap(find.byTooltip('I miei annunci'));
      await tester.pumpAndSettle();
      expect(find.text('I miei annunci'), findsWidgets);
      expect(find.text('Chi viene a prendere un caffè?'), findsOneWidget);
    });

    testWidgets('M3 · la barra calcola se il profilo è di un minorenne', (
      WidgetTester tester,
    ) async {
      MyProfile profile(DateTime birth) => MyProfile(
        id: 'u', isBusiness: false, username: 'prova', publicName: 'Prova P.',
        fullName: 'Prova Prova', birthDate: birth);
      for (final (DateTime birth, bool minor) in <(DateTime, bool)>[
        (DateTime(2010, 3, 1), true),
        (DateTime(2008, 11, 16), true),
        (DateTime(2008, 11, 15), false),
      ]) {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: AppShell(profile: profile(birth), today: () => now),
        ));
        await tester.pumpAndSettle();
        await openSection(tester, 'Mappa');
        expect(tester.widget<MapScreen>(find.byType(MapScreen)).isMinor, minor, reason: '$birth');
      }
    });
  });
}

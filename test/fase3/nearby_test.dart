import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/latest_listings_screen.dart';
import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/listing_sheets.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/map/map_screen.dart';
import 'package:nexus_social/features/map/my_listings_screen.dart';
import 'package:nexus_social/features/profile/profile_models.dart';

import '../support/fake_listings.dart';
import '../support/fake_map.dart';
import '../support/fake_privacy_repository.dart';
import '../support/fake_profile_repository.dart';

/// Fase 3, Blocco 3 · Annunci vicino a te: segnaposti, scheda dell'annuncio con «Contatta»
/// e «Segnala», raggio e filtri, «Ultimi annunci» con Annunci e Promozioni, «Disponibile ora».
void main() {
  final DateTime now = DateTime(2026, 11, 15, 10, 30);
  const GeoPoint here = GeoPoint(43.7696, 11.2558);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('Regole', () {
    test('distanza sempre arrotondata e scritta in modo approssimato', () {
      expect(distanceLabel(0), 'a meno di 250 m');
      expect(distanceLabel(750), 'a circa 750 m');
      expect(distanceLabel(1000), 'a circa 1 km');
      expect(distanceLabel(1250), 'a circa 1,3 km');
      expect(distanceLabel(12000), 'a circa 12 km');
    });

    test('raggio 1-30 km con 10 di partenza; filtri orario e «Disponibile ora»', () {
      expect(MapFilters.radiusOptions, <int>[1, 5, 10, 30]);
      expect(const MapFilters().radiusKm, 10);
      expect(const MapFilters().narrowed, isFalse);
      expect(const MapFilters(availableNowOnly: true).narrowed, isTrue);
      expect(PublishedWithin.values.map((PublishedWithin p) => p.hours), <int?>[null, 1, 24, 168]);
      expect(ListingTab.values.map((ListingTab t) => t.category), <String>['libera', 'promozione']);
    });

    test('motivi di segnalazione uguali a quelli del server', () {
      expect(
        ReportReason.values.map((ReportReason r) => r.serverValue),
        <String>['spam', 'truffa', 'contenuto_inappropriato', 'pericolo', 'falso', 'altro'],
      );
    });

    test('annuncio vicino dal server: solo punto pubblico, iniziale per il segnaposto', () {
      final NearbyListing l = NearbyListing.fromJson(<String, dynamic>{
        'id': 'x',
        'title': 'Caffè?',
        'details': '',
        'category': 'libera',
        'photos': <String>[],
        'location_mode': 'approximate',
        'lat': 43.77,
        'lon': 11.255,
        'distance_band_m': 500,
        'available_now': true,
        'expires_at': '2026-11-15T13:00:00Z',
        'created_at': '2026-11-15T09:00:00Z',
        'is_mine': false,
        'owner_id': 'u2',
        'owner_username': 'giulia',
        'owner_public_name': 'giulia B.',
        'owner_avatar_thumb_path': null,
        'owner_is_business': false,
      });
      expect(l.point, const GeoPoint(43.77, 11.255));
      expect(l.place, ListingPlace.approximateZone);
      expect(l.initial, 'G');
      expect(l.availableNow, isTrue);
      expect(publishedLabel(DateTime(2026, 11, 15, 10), DateTime(2026, 11, 15, 10, 25)),
          'pubblicato 25 min fa');
    });
  });

  group('Sulla Mappa', () {
    Future<(FakeMap, FakeListingRepository)> pumpMap(
      WidgetTester tester, {
      List<NearbyListing>? items,
      FakeProfileRepository? profiles,
      FakePrivacyRepository? privacy,
    }) async {
      phone(tester);
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      final FakeListingRepository repo = FakeListingRepository()
        ..nearbyItems = items ?? <NearbyListing>[sampleNearby()];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MapScreen(
            services: map.services,
            listings: repo,
            profiles: profiles,
            privacy: privacy,
            now: () => now,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      map.location.emit(fixAt(here.latitude, here.longitude));
      await tester.pumpAndSettle();
      return (map, repo);
    }

    testWidgets('la posizione porta gli annunci vicini: segnaposti e conteggio', (
      WidgetTester tester,
    ) async {
      final (FakeMap map, FakeListingRepository repo) = await pumpMap(tester, items: <NearbyListing>[
        sampleNearby(),
        sampleNearby(id: 'n2', title: 'Caffè in centro?', availableNow: true),
      ]);
      expect(repo.nearbyCalls, isNotEmpty);
      expect(repo.nearbyCalls.last.$1, here);
      expect(repo.nearbyCalls.last.$2.radiusKm, 10);
      expect(map.handle.markers.map((NearbyListing l) => l.id), <String>['n1', 'n2']);
      expect(find.text('2 annunci entro 10 km'), findsOneWidget);
    });

    testWidgets('ogni ~300 m (nuova posizione) gli annunci si aggiornano', (
      WidgetTester tester,
    ) async {
      final (FakeMap map, FakeListingRepository repo) = await pumpMap(tester);
      final int before = repo.nearbyCalls.length;
      map.location.emit(fixAt(43.7723, 11.2558));
      await tester.pumpAndSettle();
      expect(repo.nearbyCalls.length, before + 1);
      expect(repo.nearbyCalls.last.$1, const GeoPoint(43.7723, 11.2558));
    });

    testWidgets('cambiare il raggio rifà la ricerca con quel raggio', (WidgetTester tester) async {
      final (_, FakeListingRepository repo) = await pumpMap(tester);
      // Il carattere dei test è più largo di quello vero: si scorre la fila dei raggi.
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '30 km'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '30 km'));
      await tester.pumpAndSettle();
      expect(repo.nearbyCalls.last.$2.radiusKm, 30);
      expect(find.text('1 annuncio entro 30 km'), findsOneWidget);
    });

    testWidgets('filtri: orario e «Disponibile ora», con il segno sul pulsante', (
      WidgetTester tester,
    ) async {
      final (FakeMap map, FakeListingRepository repo) = await pumpMap(tester, items: <NearbyListing>[
        sampleNearby(),
        sampleNearby(id: 'n2', availableNow: true),
      ]);
      await tester.tap(find.byTooltip('Filtri'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ultima ora'));
      await tester.tap(find.byKey(const ValueKey<String>('filtro_disponibile_ora')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('applica_filtri')));
      await tester.pumpAndSettle();

      final MapFilters f = repo.nearbyCalls.last.$2;
      expect(f.published, PublishedWithin.lastHour);
      expect(f.availableNowOnly, isTrue);
      expect(map.handle.markers.map((NearbyListing l) => l.id), <String>['n2']);
      final Badge badge = tester.widget<Badge>(
        find.descendant(of: find.byTooltip('Filtri'), matching: find.byType(Badge)),
      );
      expect(badge.isLabelVisible, isTrue);
    });

    testWidgets('toccando un segnaposto: scheda con autore, distanza approssimata, Contatta', (
      WidgetTester tester,
    ) async {
      final (FakeMap map, _) = await pumpMap(tester);
      map.handle.tapMarker('n1');
      await tester.pumpAndSettle();

      expect(find.text('Ci manca uno per il calcetto, chi viene?'), findsOneWidget);
      expect(find.text('Marco R.'), findsOneWidget);
      expect(find.text('@marco_r'), findsOneWidget);
      expect(find.text('a circa 1,3 km'), findsOneWidget);
      expect(find.text('Punto d\'incontro'), findsOneWidget);

      // T7: «Contatta» c'è, la chat arriva con la Fase 4.
      await tester.tap(find.text('Contatta'));
      await tester.pumpAndSettle();
      expect(find.text('Chat in arrivo'), findsOneWidget);
    });

    testWidgets('scheda: il profilo dell\'autore con i social, e da lì «Blocca»', (
      WidgetTester tester,
    ) async {
      final FakeProfileRepository profiles = FakeProfileRepository()
        ..others['utente-b'] = const PublicProfile(
          id: 'utente-b',
          isBusiness: false,
          username: 'marco_r',
          publicName: 'Marco R.',
          social: <SocialNetwork, String>{SocialNetwork.instagram: 'marco.calcetto'},
        );
      final FakePrivacyRepository privacy = FakePrivacyRepository();
      final (FakeMap map, FakeListingRepository repo) =
          await pumpMap(tester, profiles: profiles, privacy: privacy);
      map.handle.tapMarker('n1');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('autore_annuncio')));
      await tester.pumpAndSettle();
      expect(find.text('Profilo'), findsWidgets);
      expect(find.textContaining('marco.calcetto'), findsOneWidget);

      final int calls = repo.nearbyCalls.length;
      await tester.tap(find.byKey(const ValueKey<String>('menu_profilo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('blocca_utente')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('conferma_blocco')));
      await tester.pumpAndSettle();

      expect(privacy.calls, contains('block:utente-b'));
      // Scheda chiusa e annunci ricaricati: quelli della persona bloccata spariscono.
      expect(find.text('Contatta'), findsNothing);
      expect(repo.nearbyCalls.length, greaterThan(calls));
    });

    testWidgets('«Segnala annuncio»: motivo obbligatorio, poi inviato', (
      WidgetTester tester,
    ) async {
      final (FakeMap map, FakeListingRepository repo) = await pumpMap(tester);
      map.handle.tapMarker('n1');
      await tester.pumpAndSettle();
      // Il foglio si allarga trascinandolo, come farebbe la persona.
      await tester.drag(find.text('Marco R.'), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Segnala annuncio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Segnala annuncio'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('invia_segnalazione')));
      await tester.pumpAndSettle();
      expect(find.text('Scegli un motivo.'), findsOneWidget);
      expect(repo.reports, isEmpty);

      await tester.tap(find.text(ReportReason.scam.label));
      await tester.enterText(
        find.byKey(const ValueKey<String>('segnalazione_dettagli')), 'Chiede soldi in anticipo');
      await tester.tap(find.byKey(const ValueKey<String>('invia_segnalazione')));
      await tester.pumpAndSettle();

      expect(repo.reports.single.$1, 'n1');
      expect(repo.reports.single.$2, ReportReason.scam);
      expect(repo.reports.single.$3, 'Chiede soldi in anticipo');
      expect(find.textContaining('segnalazione è stata inviata'), findsOneWidget);
    });

    testWidgets('il proprio annuncio: niente «Contatta» né «Segnala»', (
      WidgetTester tester,
    ) async {
      final (FakeMap map, _) = await pumpMap(tester, items: <NearbyListing>[
        sampleNearby(id: 'm1', isMine: true),
      ]);
      map.handle.tapMarker('m1');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('annuncio_mio')), findsOneWidget);
      expect(find.text('Contatta'), findsNothing);
      expect(find.text('Segnala annuncio'), findsNothing);
    });

    testWidgets('server spento: nessuna ricerca, «Ultimi annunci» spiega perché', (
      WidgetTester tester,
    ) async {
      phone(tester);
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: MapScreen(services: map.services)),
      ));
      await tester.pumpAndSettle();
      map.location.emit(fixAt(here.latitude, here.longitude));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('conteggio_annunci')), findsNothing);
      expect(map.handle.markerUpdates, 0);
      await tester.tap(find.byTooltip('Ultimi annunci'));
      await tester.pump();
      expect(find.textContaining('serve il collegamento al server'), findsOneWidget);
    });
  });

  group('Ultimi annunci', () {
    Future<FakeListingRepository> pumpLatest(
      WidgetTester tester, {
      GeoPoint? origin = here,
      List<NearbyListing>? items,
    }) async {
      phone(tester);
      final FakeListingRepository repo = FakeListingRepository()
        ..nearbyItems = items ?? <NearbyListing>[
          sampleNearby(),
          sampleNearby(id: 'n2', title: 'Caffè in centro?', availableNow: true, distance: 250),
        ];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: LatestListingsScreen(
          services: ListingSheetServices(listings: repo),
          origin: origin,
          filters: const MapFilters(),
          now: () => now,
        ),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('due schede: Annunci delle persone e Promozioni (vuota per ora)', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = await pumpLatest(tester);
      expect(find.text('Annunci'), findsOneWidget);
      expect(find.text('Promozioni'), findsOneWidget);
      expect(find.text('Caffè in centro?'), findsOneWidget);
      expect(find.text('Marco R. · a circa 250 m'), findsOneWidget);
      expect(find.text('Disponibile ora'), findsOneWidget);
      expect(find.text('Entro 10 km'), findsOneWidget);
      expect(
        repo.nearbyCalls.map((c) => c.$3).toSet(),
        <ListingTab>{ListingTab.free, ListingTab.promotions},
      );

      await tester.tap(find.text('Promozioni'));
      await tester.pumpAndSettle();
      expect(find.text('Qui compariranno le promozioni delle attività della zona.'), findsOneWidget);
    });

    testWidgets('filtri dall\'elenco: riepilogo aggiornato e nuova ricerca', (
      WidgetTester tester,
    ) async {
      final FakeListingRepository repo = await pumpLatest(tester);
      await tester.tap(find.byTooltip('Filtri'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Entro 30 km'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ultime 24 ore'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('applica_filtri')));
      await tester.pumpAndSettle();
      expect(find.text('Entro 30 km · Ultime 24 ore'), findsOneWidget);
      expect(repo.nearbyCalls.last.$2.radiusKm, 30);
      expect(repo.nearbyCalls.last.$2.published, PublishedWithin.today);
    });

    testWidgets('toccando un annuncio si apre la sua scheda', (WidgetTester tester) async {
      await pumpLatest(tester);
      await tester.tap(find.text('Caffè in centro?'));
      await tester.pumpAndSettle();
      expect(find.text('Contatta'), findsOneWidget);
      expect(find.text('Segnala annuncio'), findsOneWidget);
    });

    testWidgets('senza posizione: invito a consentirla', (WidgetTester tester) async {
      final FakeListingRepository repo = await pumpLatest(tester, origin: null);
      expect(find.textContaining('Consenti la posizione dalla Mappa'), findsOneWidget);
      expect(repo.nearbyCalls, isEmpty);
    });
  });

  group('I miei annunci', () {
    testWidgets('«Disponibile ora» si accende e si spegne dall\'elenco', (
      WidgetTester tester,
    ) async {
      phone(tester);
      final FakeListingRepository repo = FakeListingRepository(items: <MyListing>[sampleListing()]);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MyListingsScreen(
          repository: repo,
          surface: FakeMap().services.surface,
          now: () => now,
        ),
      ));
      await tester.pumpAndSettle();
      final Finder sw = find.byKey(const ValueKey<String>('disponibile_a1'));
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(repo.availability, <(String, bool)>[('a1', true)]);
      expect(tester.widget<SwitchListTile>(sw).value, isTrue);
    });
  });
}

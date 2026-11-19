import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/market/market_listing_screen.dart';
import 'package:nexus_social/features/market/market_models.dart';
import 'package:nexus_social/features/market/market_section_screen.dart';

import '../support/fake_map.dart';
import '../support/fake_market.dart';

/// Fase 5, Blocco 2 · Scambia & Vendi: ricerca per parola, 13 filtri, 5 ordinamenti,
/// pagine da 20, scheda con avviso antitruffa, Contatta, Segnala, Condividi.
void main() {
  group('Regole della ricerca', () {
    test('parametri per il server: sezione, filtri, ordinamento senza punto o parola', () {
      final MarketQuery q = MarketQuery(
        text: '  iphone ',
        categoryId: categoryBySlug('elettronica').id,
        types: const <MarketType>{MarketType.sell, MarketType.swap},
        priceMinCents: 1000,
        conditions: const <ItemCondition>{ItemCondition.good},
        seller: SellerKind.business,
        ships: true,
        openToSwap: true,
        cashAdjustment: true,
        published: MarketPublished.week,
        sort: MarketSort.nearest,
      );
      final Map<String, Object?> sale = q.toParams(MarketSection.sale, offset: 20);
      expect(sale['p_section'], 'sale');
      expect(sale['p_query'], 'iphone');
      expect(sale['p_types'], <String>['sell']); // lo Scambio non è della Vendita
      expect(sale['p_conditions'], <String>['good']);
      expect(sale['p_seller'], 'business');
      expect(sale['p_open_to_swap'], isTrue);
      expect(sale['p_published_within_days'], 7);
      expect(sale['p_lat'], isNull); // nessun punto: niente posizione inviata
      expect(sale['p_radius_km'], isNull);
      expect(sale['p_sort'], 'recent'); // «Più vicini» senza punto non si può
      expect(sale['p_offset'], 20);
      final Map<String, Object?> swap = q.toParams(MarketSection.swap);
      expect(swap['p_section'], 'swap');
      expect(swap['p_types'], <String>['swap']);
      expect(swap['p_open_to_swap'], isFalse); // nello Scambia vale già la tipologia
      expect(q.activeFilters, 9);

      final MarketQuery near = const MarketQuery(sort: MarketSort.nearest).copyWith(
        origin: SearchOrigin.myPosition,
        point: () => const GeoPoint(41.9, 12.5),
        radiusKm: 500,
      );
      final Map<String, Object?> p = near.toParams(MarketSection.sale);
      expect(p['p_sort'], 'nearest');
      expect(p['p_radius_km'], MarketQuery.maxRadiusKm);
      expect(const MarketQuery(sort: MarketSort.relevant).toParams(MarketSection.sale)['p_sort'], 'recent');
      expect(near.cleared().activeFilters, 0);
    });

    test('prezzo e distanza come li vede chi cerca', () {
      expect(sampleListing().priceLabel, '350 €');
      expect(sampleListing(type: MarketType.free, priceCents: null).priceLabel, 'Gratis');
      expect(sampleListing(type: MarketType.swap, priceCents: null).priceLabel, 'Scambio');
      expect(sampleListing(type: MarketType.wanted, priceCents: 5000).priceLabel, 'Cerco · fino a 50 €');
      expect(marketDistanceLabel(750), 'a meno di 1 km');
      expect(marketDistanceLabel(12250), 'a 12 km');
      final String share = marketShareText(sampleListing());
      expect(share, contains('iPhone 13'));
      expect(share, isNot(contains('41.9')));
      expect(share, isNot(contains('km')));
    });
  });

  group('Sezione con ricerca', () {
    late FakeMarketRepository repo;
    late FakeMap map;

    Future<void> openSection(
      WidgetTester tester,
      MarketSection section,
      List<MarketListing> listings,
    ) async {
      // Schermo alto: l'elenco costruisce solo le schede visibili.
      tester.view.physicalSize = const Size(1170, 9000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      repo = FakeMarketRepository(listings: listings);
      map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MarketSectionScreen(
            section: section,
            repository: repo,
            services: map.services,
            pickImage: () async => img.encodePng(img.Image(width: 8, height: 8)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// Posizione nell'ordine di lettura delle schede (riga, poi colonna).
    double readingOrder(WidgetTester tester, String id) {
      final Offset o = tester.getTopLeft(find.byKey(ValueKey<String>('risultato_$id')));
      return o.dy.roundToDouble() * 10000 + o.dx;
    }

    Future<void> tapVisible(WidgetTester tester, Finder f) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    final List<MarketListing> three = <MarketListing>[
      sampleListing(id: 'a', title: 'iPhone 13 128 GB', priceCents: 35000),
      sampleListing(
        id: 'b',
        title: 'Chitarra acustica',
        slug: 'musica-strumenti-chitarre',
        priceCents: 12000,
        condition: ItemCondition.good,
        ships: false,
        business: true,
        createdAt: DateTime(2026, 11, 14),
      ),
      sampleListing(
        id: 'c',
        title: 'Divano tre posti',
        slug: 'casa-arredamento-divani-poltrone',
        priceCents: 20000,
        condition: ItemCondition.fair,
        openToSwap: true,
        createdAt: DateTime(2026, 11, 13),
      ),
    ];

    testWidgets('all\'apertura cerca le vendite più recenti e le mostra', (WidgetTester tester) async {
      await openSection(tester, MarketSection.sale, three);
      expect(repo.searches.single.$1, MarketSection.sale);
      expect(repo.searches.single.$2.sort, MarketSort.recent);
      for (final String id in <String>['a', 'b', 'c']) {
        expect(find.byKey(ValueKey<String>('risultato_$id')), findsOneWidget);
      }
      expect(find.text('350 €'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('avviso_antitruffa')), findsOneWidget);
      // Il più recente per primo (a schede su due colonne: si legge riga per riga).
      expect(readingOrder(tester, 'b'), lessThan(readingOrder(tester, 'c')));
    });

    testWidgets('barra di ricerca: parola, poi «Più pertinenti» (D4); nessun risultato', (
      WidgetTester tester,
    ) async {
      await openSection(tester, MarketSection.sale, three);
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_cerca')), 'chitarra');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(repo.searches.last.$2.text, 'chitarra');
      expect(repo.searches.last.$2.sort, MarketSort.relevant);
      expect(find.byKey(const ValueKey<String>('risultato_b')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('risultato_a')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey<String>('mercato_cerca')), 'pianoforte');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('mercato_nessun_risultato')), findsOneWidget);
    });

    testWidgets('categoria dalla fila in alto', (WidgetTester tester) async {
      await openSection(tester, MarketSection.sale, three);
      // Nuova grafica: quattro categorie in vista, le altre in «Altre».
      await tester.ensureVisible(find.byKey(const ValueKey<String>('categoria_altre')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('categoria_altre')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('categoria_musica-strumenti')));
      await tester.pumpAndSettle();
      expect(repo.searches.last.$2.categoryId, categoryBySlug('musica-strumenti').id);
      expect(find.byKey(const ValueKey<String>('risultato_b')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('risultato_a')), findsNothing);
    });

    testWidgets('filtri: prezzo, condizioni, aziende, spedizione, scambio, data; il pulsante li conta', (
      WidgetTester tester,
    ) async {
      await openSection(tester, MarketSection.sale, three);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_filtri')));
      expect(find.text('Filtri'), findsOneWidget);
      // Nella Vendita la tipologia non si sceglie: c'è solo «Vendo».
      expect(find.byKey(const ValueKey<String>('filtro_tipo_sell')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey<String>('filtro_prezzo_min')), '100');
      await tester.enterText(find.byKey(const ValueKey<String>('filtro_prezzo_max')), '250');
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtro_condizione_fair')));
      await tapVisible(tester, find.text('Privati'));
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtro_scambio')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtro_data_week')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtri_mostra')));

      final MarketQuery q = repo.searches.last.$2;
      expect(q.priceMinCents, 10000);
      expect(q.priceMaxCents, 25000);
      expect(q.conditions, <ItemCondition>{ItemCondition.fair});
      expect(q.seller, SellerKind.private);
      expect(q.openToSwap, isTrue);
      expect(q.published, MarketPublished.week);
      expect(find.byTooltip('Filtri (5)'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('risultato_c')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('risultato_a')), findsNothing);

      // Prezzo minimo sopra il massimo: si dice subito.
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_filtri')));
      await tester.enterText(find.byKey(const ValueKey<String>('filtro_prezzo_min')), '500');
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtri_mostra')));
      expect(find.text('Il prezzo minimo supera il massimo.'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtri_azzera')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtri_mostra')));
      expect(repo.searches.last.$2.activeFilters, 0);
      expect(find.byTooltip('Filtri'), findsOneWidget);
    });

    testWidgets('Scambia: tipologie Scambio, Regalo e Cerco; conguaglio', (WidgetTester tester) async {
      await openSection(tester, MarketSection.swap, <MarketListing>[
        sampleListing(id: 's', type: MarketType.swap, priceCents: null, cashAdjustment: true,
            wantedInExchange: 'una bici'),
        sampleListing(id: 'r', type: MarketType.free, priceCents: null, title: 'Libri per bambini',
            slug: 'libri-cultura-libri-bambini'),
      ]);
      expect(find.text('Gratis'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_filtri')));
      expect(find.byKey(const ValueKey<String>('filtro_tipo_sell')), findsNothing);
      expect(find.byKey(const ValueKey<String>('filtro_scambio')), findsNothing);
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtro_tipo_free')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtri_mostra')));
      expect(repo.searches.last.$2.types, <MarketType>{MarketType.free});
      expect(find.byKey(const ValueKey<String>('risultato_r')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('risultato_s')), findsNothing);

      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_filtri')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtro_tipo_free')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtro_conguaglio')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtri_mostra')));
      expect(find.byKey(const ValueKey<String>('risultato_s')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('risultato_r')), findsNothing);
    });

    testWidgets('località: «Vicino a me» una volta sola, raggio, poi «Più vicini»', (
      WidgetTester tester,
    ) async {
      await openSection(tester, MarketSection.sale, three);
      // Senza punto di ricerca «Più vicini» non si può scegliere.
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_ordina')));
      final PopupMenuItem<MarketSort> nearest = tester.widget<PopupMenuItem<MarketSort>>(
        find.byKey(const ValueKey<String>('ordina_nearest')),
      );
      expect(nearest.enabled, isFalse);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_filtri')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtro_mia_posizione')));
      map.location.emit(fixAt(41.9028, 12.4964));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('filtro_raggio')), findsOneWidget);
      expect(find.text('Raggio: 30 km'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('filtri_mostra')));
      final MarketQuery q = repo.searches.last.$2;
      expect(q.point, const GeoPoint(41.9028, 12.4964));
      expect(q.toParams(MarketSection.sale)['p_radius_km'], 30);

      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_ordina')));
      await tester.tap(find.byKey(const ValueKey<String>('ordina_nearest')));
      await tester.pumpAndSettle();
      expect(repo.searches.last.$2.sort, MarketSort.nearest);
      expect(find.text('Più vicini'), findsOneWidget);
    });

    testWidgets('ordinamento per prezzo', (WidgetTester tester) async {
      await openSection(tester, MarketSection.sale, three);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_ordina')));
      await tester.tap(find.byKey(const ValueKey<String>('ordina_price_asc')));
      await tester.pumpAndSettle();
      expect(readingOrder(tester, 'b') < readingOrder(tester, 'c') && readingOrder(tester, 'c') < readingOrder(tester, 'a'),
          isTrue);
    });

    testWidgets('pagine da 20 (D9): «Mostra altri» carica il resto', (WidgetTester tester) async {
      await openSection(tester, MarketSection.sale, <MarketListing>[
        for (int i = 0; i < 25; i++)
          sampleListing(id: 'p$i', title: 'Oggetto $i',
              createdAt: DateTime(2026, 11, 14).subtract(Duration(minutes: i))),
      ]);
      expect(repo.searches.single.$3, 0);
      expect(find.byKey(const ValueKey<String>('risultato_p20')), findsNothing);
      // Arrivando in fondo si carica la pagina successiva (o con «Mostra altri annunci»).
      await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('risultato_p24')), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(repo.searches.map(((MarketSection, MarketQuery, int) s) => s.$3), <int>[0, 20]);
      expect(find.byKey(const ValueKey<String>('risultato_p24')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('mercato_altri')), findsNothing);
    });

    testWidgets('scheda: prezzo, condizioni, consegna, antitruffa, Contatta e Segnala', (
      WidgetTester tester,
    ) async {
      await openSection(tester, MarketSection.sale, <MarketListing>[
        sampleListing(id: 'a', openToSwap: true, cashAdjustment: true),
      ]);
      await tapVisible(tester, find.byKey(const ValueKey<String>('risultato_a')));
      expect(find.byType(MarketListingScreen), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('scheda_prezzo')), findsOneWidget);
      expect(find.text('Ottimo stato'), findsOneWidget);
      expect(find.text('Ritiro a mano'), findsOneWidget);
      expect(find.text('Spedizione'), findsOneWidget);
      expect(find.text('Valuta anche scambi'), findsOneWidget);
      expect(find.text('Accetta conguaglio'), findsOneWidget);
      expect(find.text('Elettronica › Smartphone'), findsOneWidget);
      expect(find.text('Memoria: 128 GB'), findsOneWidget);
      expect(find.textContaining('a 1 km'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('avviso_antitruffa')), findsOneWidget);
      // Senza il server delle interazioni resta «Condividi».
      expect(find.byKey(const ValueKey<String>('condividi')), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey<String>('scheda_contatta')));
      expect(find.text('Chat in arrivo'), findsOneWidget);
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.byKey(const ValueKey<String>('scheda_segnala')));
      await tester.tap(find.text(ReportReason.scam.label));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey<String>('invia_segnalazione')));
      expect(repo.reports.single, ('a', ReportReason.scam));
      expect(find.textContaining('segnalazione è stata inviata'), findsOneWidget);
    });

    testWidgets('scheda: il proprio annuncio in revisione; un annuncio sparito', (WidgetTester tester) async {
      await openSection(tester, MarketSection.sale, <MarketListing>[
        sampleListing(id: 'm', mine: true, review: ReviewStatus.pendingReview),
        sampleListing(id: 'g', title: 'Già venduto', createdAt: DateTime(2026, 11, 1)),
      ]);
      await tapVisible(tester, find.byKey(const ValueKey<String>('risultato_m')));
      expect(find.byKey(const ValueKey<String>('annuncio_mio')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('scheda_in_revisione')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('scheda_contatta')), findsNothing);
      expect(find.byKey(const ValueKey<String>('condividi')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      repo.gone.add('g');
      await tapVisible(tester, find.byKey(const ValueKey<String>('risultato_g')));
      expect(find.byKey(const ValueKey<String>('annuncio_non_disponibile')), findsOneWidget);
    });

    testWidgets('pubblicare una vendita che valuta scambi, con conguaglio', (WidgetTester tester) async {
      await openSection(tester, MarketSection.sale, const <MarketListing>[]);
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_sale')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey<String>('scegli_categoria')));
      await tester.tap(find.text('Libri e cultura'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Gialli e thriller'), 200,
          scrollable: find.descendant(of: find.byKey(const ValueKey<String>('sottocategorie')),
              matching: find.byType(Scrollable)));
      await tester.tap(find.text('Gialli e thriller'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('mercato_conguaglio')), findsNothing);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_valuto_scambi')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_conguaglio')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_aggiungi_foto')));
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_titolo')), 'Tre gialli');
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_prezzo')), '12');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Buono stato'));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_mia_posizione')));
      map.location.emit(fixAt(41.9028, 12.4964));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_conferma_divieti')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_pubblica')));
      final MarketDraft d = repo.published.single;
      expect(d.openToSwap, isTrue);
      expect(d.cashAdjustment, isTrue);
      expect(d.newPhotos.single, isA<Uint8List>());
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/market/market_catalog_data.dart';
import 'package:nexus_social/features/market/market_models.dart';
import 'package:nexus_social/features/market/market_section_screen.dart';
import 'package:nexus_social/features/market/my_market_screen.dart';

import '../support/fake_map.dart';
import '../support/fake_market.dart';

/// Fase 5, Blocco 1 · Scambia & Vendi: catalogo della specifica del titolare, 4 tipologie,
/// pubblicazione con foto obbligatorie, campi specifici, divieti, i miei annunci.
void main() {
  final DateTime now = DateTime(2026, 11, 15, 10, 30);

  group('Catalogo (specifica del titolare, test di accettazione)', () {
    final MarketCatalog catalog = MarketCatalog(builtInMarketCatalog);

    test('19 categorie e 271 sottocategorie, ID e slug univoci, sottocategorie collegate', () {
      expect(catalog.mains, hasLength(19));
      final Iterable<MarketCategory> subs = builtInMarketCatalog.where((MarketCategory c) => !c.isMain);
      expect(subs, hasLength(271));
      expect(builtInMarketCatalog.map((MarketCategory c) => c.id).toSet(), hasLength(290));
      expect(builtInMarketCatalog.map((MarketCategory c) => c.slug).toSet(), hasLength(290));
      for (final MarketCategory s in subs) {
        expect(catalog.byId(s.parentId!)?.isMain, isTrue, reason: s.slug);
        expect(s.slug, startsWith('${catalog.byId(s.parentId!)!.slug}-'));
      }
      for (final MarketCategory c in builtInMarketCatalog) {
        expect(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(c.slug), isTrue, reason: c.slug);
      }
      for (final String slug in <String>[
        'motori', 'immobili', 'elettronica', 'casa-arredamento', 'motori-auto',
        'motori-moto-scooter', 'elettronica-smartphone',
      ]) {
        expect(builtInMarketCatalog.any((MarketCategory c) => c.slug == slug), isTrue, reason: slug);
      }
    });

    test('nomi e ordine identici al documento della specifica', () {
      final List<String> doc = File('docs/fase5/CATALOGO_TITOLARE.md').readAsLinesSync();
      final int start = doc.indexWhere((String l) => l.startsWith('## 2.'));
      final int end = doc.indexWhere((String l) => l.startsWith('## 3.'));
      final List<String> expected = <String>[];
      for (final String l in doc.sublist(start, end)) {
        final RegExpMatch? m = RegExp(r'^### \d+ – (.+) \(`').firstMatch(l);
        if (m != null) expected.add('#${m.group(1)!.toLowerCase()}');
        if (l.startsWith('- ')) expected.add(l.substring(2).trim());
      }
      final List<String> actual = <String>[
        for (final MarketCategory m in catalog.mains) ...<String>[
          '#${m.name.toLowerCase()}',
          for (final MarketCategory s in catalog.subsOf(m.id)) s.name,
        ],
      ];
      expect(actual, expected);
    });

    test('animali: solo accessori e attrezzature, nessuna compravendita di animali', () {
      final MarketCategory animals = catalog.mains.firstWhere((MarketCategory c) => c.slug == 'animali-accessori');
      for (final MarketCategory s in catalog.subsOf(animals.id)) {
        expect(
          RegExp('accessori|cucce|giochi|attrezzature|toelettatura', caseSensitive: false).hasMatch(s.name),
          isTrue,
          reason: s.name,
        );
      }
    });
  });

  group('Regole', () {
    test('prezzo e foto secondo la tipologia', () {
      expect(MarketType.sell.priceRequired, isTrue);
      expect(MarketType.swap.priceRequired, isFalse);
      expect(MarketType.free.priceAllowed, isFalse);
      expect(MarketType.wanted.priceAllowed, isTrue);
      expect(MarketType.values.where((MarketType t) => t.photosRequired),
          <MarketType>[MarketType.sell, MarketType.swap, MarketType.free]);
      expect(MarketSection.swap.types, <MarketType>[MarketType.swap, MarketType.free, MarketType.wanted]);
      expect(MarketSection.sale.types, <MarketType>[MarketType.sell]);
    });

    test('campi specifici e obbligatori (D3)', () {
      expect(MarketRules.attributesFor('motori').map((MarketAttribute a) => a.key), <String>['anno', 'km']);
      expect(MarketRules.attributesFor('immobili').map((MarketAttribute a) => a.key), <String>['mq', 'locali']);
      expect(MarketRules.attributesFor('libri-cultura'), isEmpty);
      expect(MarketRules.requiredAttributes(categoryBySlug('motori-auto'), 'motori', MarketType.sell),
          <String>{'anno'});
      expect(MarketRules.requiredAttributes(categoryBySlug('motori-moto-scooter'), 'motori', MarketType.sell),
          isEmpty);
      expect(MarketRules.requiredAttributes(categoryBySlug('motori-auto'), 'motori', MarketType.wanted),
          isEmpty);
      expect(MarketRules.noObjectFields('servizi'), isTrue);
      expect(MarketRules.noObjectFields('elettronica'), isFalse);
    });

    test('prezzo in euro: lettura e scrittura', () {
      expect(MarketRules.parsePriceCents('350'), 35000);
      expect(MarketRules.parsePriceCents('1.250,50'), 125050);
      expect(MarketRules.parsePriceCents(' '), isNull);
      expect(() => MarketRules.parsePriceCents('abc'), throwsFormatException);
      expect(() => MarketRules.parsePriceCents('1000000000'), throwsFormatException);
      expect(MarketRules.parsePriceCents('999.999.999'), MarketRules.maxPriceCents);
      expect(MarketRules.formatPrice(35000), '350 €');
      expect(MarketRules.formatPrice(125050), '1.250,50 €');
      expect(MarketRules.formatPrice(25000000000), '250.000.000 €');
    });

    test('annuncio dal server e rinnovo negli ultimi 7 giorni', () {
      final MyMarketListing l = MyMarketListing.fromJson(<String, dynamic>{
        'id': 'x',
        'market_type': 'swap',
        'category_id': categoryBySlug('sport-outdoor-biciclette').id,
        'title': 'Bici da corsa',
        'description': '',
        'price_cents': null,
        'item_condition': 'good',
        'ships': false,
        'pickup': true,
        'attributes': <String, dynamic>{},
        'photos': <String>['u/a.jpg'],
        'wanted_in_exchange': 'una e-bike',
        'location_mode': 'approximate',
        'exact_lat': 41.9,
        'exact_lon': 12.5,
        'status': 'active',
        'review_status': 'pending_review',
        'expires_at': '2026-11-20T10:00:00Z',
        'created_at': '2026-10-21T10:00:00Z',
      });
      expect(l.type, MarketType.swap);
      expect(l.condition, ItemCondition.good);
      expect(l.review, ReviewStatus.pendingReview);
      expect(l.wantedInExchange, 'una e-bike');
      expect(l.canRenew(now), isTrue);
      expect(sampleMarket(expiresAt: DateTime(2026, 12, 10)).canRenew(now), isFalse);
    });
  });

  group('Pubblicare', () {
    late FakeMarketRepository repo;
    late FakeMap map;
    late List<Uint8List> gallery;

    Future<void> openSection(WidgetTester tester, MarketSection section, {bool server = true}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      repo = FakeMarketRepository();
      map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      gallery = <Uint8List>[for (int i = 0; i < 3; i++) img.encodePng(img.Image(width: 8, height: 8))];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MarketSectionScreen(
            section: section,
            repository: server ? repo : null,
            services: map.services,
            pickImage: () async => gallery.isEmpty ? null : gallery.removeAt(0),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tapVisible(WidgetTester tester, Finder f) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> chooseCategory(WidgetTester tester, String main, String sub) async {
      await tapVisible(tester, find.byKey(const ValueKey<String>('scegli_categoria')));
      await tester.tap(find.text(main));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(sub), 200,
          scrollable: find.descendant(of: find.byKey(const ValueKey<String>('sottocategorie')),
              matching: find.byType(Scrollable)));
      await tester.tap(find.text(sub));
      await tester.pumpAndSettle();
    }

    Future<void> useMyPosition(WidgetTester tester) async {
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_mia_posizione')));
      map.location.emit(fixAt(41.9028, 12.4964));
      await tester.pumpAndSettle();
    }

    testWidgets('sezioni: titolo, avviso antitruffa, 19 categorie; senza server lo dice', (
      WidgetTester tester,
    ) async {
      await openSection(tester, MarketSection.sale, server: false);
      expect(find.text('Vendita tra privati'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('avviso_antitruffa')), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(20)); // «Tutte» e le 19 categorie
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_sale')));
      await tester.pump();
      expect(find.textContaining('serve il collegamento al server'), findsOneWidget);
    });

    testWidgets('Vendita completa: categoria a due passi, foto, prezzo, condizioni, posizione', (
      WidgetTester tester,
    ) async {
      await openSection(tester, MarketSection.sale);
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_sale')));
      await tester.pumpAndSettle();
      expect(find.text('Nuovo annuncio'), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey<String>('scegli_categoria')));
      expect(find.text('Elettronica'), findsOneWidget);
      await tester.tap(find.text('Elettronica'));
      await tester.pumpAndSettle();
      // Solo le sottocategorie dell'Elettronica.
      expect(find.text('Smartphone'), findsOneWidget);
      expect(find.text('Auto'), findsNothing);
      await tester.tap(find.text('Smartphone'));
      await tester.pumpAndSettle();
      expect(find.text('Memoria (facoltativo)'), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_aggiungi_foto')));
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_titolo')), 'iPhone 13 128 GB');
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_prezzo')), '350');
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_campo_memoria')), '128 GB');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Ottimo stato'));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_spedizione')));
      await useMyPosition(tester);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_conferma_divieti')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_pubblica')));

      final MarketDraft d = repo.published.single;
      expect(d.type, MarketType.sell);
      expect(d.categoryId, categoryBySlug('elettronica-smartphone').id);
      expect(d.priceCents, 35000);
      expect(d.condition, ItemCondition.excellent);
      expect(d.pickup && d.ships, isTrue);
      expect(d.attributes, <String, Object>{'memoria': '128 GB'});
      expect(d.newPhotos, hasLength(1));
      expect(d.point, const GeoPoint(41.9028, 12.4964));
      expect(d.place, ListingPlace.approximateZone);
      expect(d.noProhibitedItems, isTrue);
      expect(find.text('Annuncio pubblicato.'), findsOneWidget);
    });

    testWidgets('foto obbligatorie, prezzo e conferma dei divieti: si dice cosa manca', (
      WidgetTester tester,
    ) async {
      await openSection(tester, MarketSection.sale);
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_sale')));
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Libri e cultura', 'Gialli e thriller');
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_titolo')), 'Tre gialli');
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_pubblica')));
      expect(find.text('Per la vendita il prezzo è obbligatorio.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey<String>('mercato_prezzo')), '10');
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_pubblica')));
      expect(find.text('Aggiungi almeno una foto.'), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_aggiungi_foto')));
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Buono stato'));
      await useMyPosition(tester);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_pubblica')));
      expect(find.text('Conferma che non pubblichi prodotti vietati.'), findsOneWidget);
      expect(repo.published, isEmpty);

      // L'elenco dei divieti si apre dal modulo.
      await tapVisible(tester, find.text('Vedi l\'elenco dei divieti'));
      expect(find.text('• Droghe e sostanze illegali'), findsOneWidget);
      expect(find.text('• Animali vivi (solo accessori e attrezzature)'), findsOneWidget);
    });

    testWidgets('Auto: l\'anno è obbligatorio, i km facoltativi', (WidgetTester tester) async {
      await openSection(tester, MarketSection.sale);
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_sale')));
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Motori', 'Auto');
      expect(find.text('Anno'), findsOneWidget);
      expect(find.text('Chilometri (facoltativo)'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_aggiungi_foto')));
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_titolo')), 'Fiat Panda');
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_prezzo')), '4.500');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Buono stato'));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_pubblica')));
      expect(find.text('Indica il campo «Anno».'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey<String>('mercato_campo_anno')), '2015');
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_campo_km')), '90.000');
      await useMyPosition(tester);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_conferma_divieti')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_pubblica')));
      expect(repo.published.single.attributes, <String, Object>{'anno': 2015, 'km': 90000});
      expect(repo.published.single.priceCents, 450000);
    });

    testWidgets('Immobili e servizi: niente condizioni né consegna', (WidgetTester tester) async {
      await openSection(tester, MarketSection.sale);
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_sale')));
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Immobili', 'Appartamenti in vendita');
      expect(find.text('Condizioni'), findsNothing);
      expect(find.text('Consegna'), findsNothing);
      expect(find.text('Metri quadri'), findsOneWidget);
    });

    testWidgets('Scambia: Scambio con «cosa cerchi», Regalo senza prezzo, Cerco con foto facoltative', (
      WidgetTester tester,
    ) async {
      await openSection(tester, MarketSection.swap);
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_swap')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Scambio'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Vendo'), findsNothing);
      expect(find.byKey(const ValueKey<String>('mercato_in_cambio')), findsOneWidget);
      expect(find.text('Valore indicativo (€, facoltativo)'), findsOneWidget);

      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Regalo'));
      expect(find.byKey(const ValueKey<String>('mercato_prezzo')), findsNothing);
      expect(find.byKey(const ValueKey<String>('mercato_in_cambio')), findsNothing);

      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Cerco'));
      expect(find.text('Foto (facoltative, fino a 10)'), findsOneWidget);
      expect(find.text('Prezzo massimo (€, facoltativo)'), findsOneWidget);
      expect(find.text('Condizioni'), findsNothing);

      await chooseCategory(tester, 'Bambini e neonati', 'Passeggini');
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_titolo')), 'Cerco passeggino gemellare');
      await useMyPosition(tester);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_conferma_divieti')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_pubblica')));
      expect(repo.published.single.type, MarketType.wanted);
      expect(repo.published.single.newPhotos, isEmpty);
    });

    testWidgets('parole a rischio: l\'annuncio va in revisione e lo si dice', (WidgetTester tester) async {
      await openSection(tester, MarketSection.swap);
      repo.flagNext = true;
      await tester.tap(find.byKey(const ValueKey<String>('pubblica_swap')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Regalo'));
      await chooseCategory(tester, 'Libri e cultura', 'Riviste');
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_aggiungi_foto')));
      await tester.enterText(find.byKey(const ValueKey<String>('mercato_titolo')), 'Riviste di caccia');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Discreto'));
      await useMyPosition(tester);
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_conferma_divieti')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('mercato_pubblica')));
      expect(find.textContaining('dopo il controllo della moderazione'), findsOneWidget);
    });
  });

  group('I miei annunci', () {
    Future<FakeMarketRepository> openMine(WidgetTester tester, List<MyMarketListing> items) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final FakeMarketRepository repo = FakeMarketRepository(items: items);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MyMarketScreen(
          repository: repo,
          catalog: MarketCatalog(builtInMarketCatalog),
          section: MarketSection.sale,
          services: FakeMap().services,
          now: () => now,
        ),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('prezzo, tipologia, stato, revisione; Rinnova solo vicino alla scadenza', (
      WidgetTester tester,
    ) async {
      final FakeMarketRepository repo = await openMine(tester, <MyMarketListing>[
        sampleMarket(),
        sampleMarket(id: 'm2', title: 'Divano tre posti', slug: 'casa-arredamento-divani-poltrone',
            priceCents: 15000, expiresAt: DateTime(2026, 11, 18), review: ReviewStatus.pendingReview),
        sampleMarket(id: 'm3', type: MarketType.swap, title: 'Non in questa sezione'),
      ]);
      expect(find.text('iPhone 13 128 GB'), findsOneWidget);
      expect(find.text('350 €'), findsOneWidget);
      expect(find.text('In revisione'), findsOneWidget);
      expect(find.text('Non in questa sezione'), findsNothing);
      expect(find.byKey(const ValueKey<String>('rinnova_m1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('rinnova_m2')));
      await tester.pumpAndSettle();
      expect(repo.renewed, <String>['m2']);
      expect(find.text('Rinnovato per altri 30 giorni.'), findsOneWidget);
    });

    testWidgets('Chiudi con conferma; Modifica apre il modulo con i dati', (WidgetTester tester) async {
      final FakeMarketRepository repo = await openMine(tester, <MyMarketListing>[sampleMarket()]);
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();
      expect(find.text('Modifica annuncio'), findsOneWidget);
      expect(find.text('Smartphone'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'iPhone 13 128 GB'), findsOneWidget);
      final Finder save = find.byKey(const ValueKey<String>('mercato_pubblica'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.updates.single.$1, 'm1');
      expect(repo.updates.single.$2.priceCents, 35000);
      expect(repo.updates.single.$2.keptPhotos, <String>['u/f.jpg']);

      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Chiudi'));
      await tester.pumpAndSettle();
      expect(repo.closed, <String>['m1']);
      expect(find.text('Concluso'), findsOneWidget);
    });
  });
}

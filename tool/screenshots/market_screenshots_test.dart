// Anteprime per il titolare (Fase 5, Blocchi 1-5): Scambia & Vendi con dati finti.
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/comments_screen.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/map/social_models.dart';
import 'package:nexus_social/features/market/market_catalog_data.dart';
import 'package:nexus_social/features/market/market_listing_screen.dart';
import 'package:nexus_social/features/market/market_models.dart';
import 'package:nexus_social/features/market/market_section_screen.dart';
import 'package:nexus_social/features/market/market_deals_screen.dart';
import 'package:nexus_social/features/market/market_feedback.dart';
import 'package:nexus_social/features/market/my_market_screen.dart';
import 'package:nexus_social/features/market/swap_offer_screen.dart';
import 'package:nexus_social/features/market/swap_proposals_screen.dart';

import '../../test/support/fake_map.dart';
import '../../test/support/fake_market.dart';
import '../../test/support/fake_social.dart';

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

  // ---------------------------------------------------------------- Blocco 2
  Uint8List photo(int r, int g, int b) {
    final img.Image im = img.Image(width: 240, height: 240);
    for (int y = 0; y < 240; y++) {
      for (int x = 0; x < 240; x++) {
        final double t = (x + y) / 480;
        im.setPixelRgb(x, y, (r * (1 - t) + 255 * t * 0.4).round(), (g * (1 - t * 0.5)).round(),
            (b * (0.6 + t * 0.4)).round());
      }
    }
    return img.encodePng(im);
  }

  FakeMarketRepository shop() {
    final List<MarketListing> l = <MarketListing>[
      sampleListing(id: 'a', title: 'iPhone 13 128 GB', photos: const <String>['f/a1.jpg', 'f/a2.jpg', 'f/a3.jpg'],
          openToSwap: true, cashAdjustment: true, distance: 1250,
          description: 'Perfetto, sempre con cover e vetro. Batteria all\'89%, con scatola e cavo.',
          createdAt: DateTime.now().subtract(const Duration(hours: 2))),
      sampleListing(id: 'b', title: 'Chitarra acustica Yamaha F310', slug: 'musica-strumenti-chitarre',
          priceCents: 12000, condition: ItemCondition.good, ships: false, distance: 3500,
          photos: const <String>['f/b1.jpg'], createdAt: DateTime.now().subtract(const Duration(hours: 5))),
      sampleListing(id: 'c', title: 'Divano tre posti in tessuto', slug: 'casa-arredamento-divani-poltrone',
          priceCents: 18000, condition: ItemCondition.fair, ships: false, distance: 6250,
          photos: const <String>['f/c1.jpg'], createdAt: DateTime.now().subtract(const Duration(days: 1))),
      sampleListing(id: 'd', title: 'Trapano avvitatore 18V', slug: 'giardino-fai-da-te-utensili-elettrici',
          priceCents: 6500, condition: ItemCondition.likeNew, business: true, distance: 9000,
          photos: const <String>['f/d1.jpg'], createdAt: DateTime.now().subtract(const Duration(days: 2))),
      sampleListing(id: 'e', title: 'Bici da corsa in alluminio', slug: 'sport-outdoor-ciclismo',
          priceCents: 32000, condition: ItemCondition.good, distance: 12250,
          photos: const <String>['f/e1.jpg'], createdAt: DateTime.now().subtract(const Duration(days: 3))),
    ];
    return FakeMarketRepository(listings: l, photoBytes: <String, Uint8List>{
      'f/a1.jpg': photo(40, 60, 90),
      'f/a2.jpg': photo(90, 40, 60),
      'f/a3.jpg': photo(60, 90, 40),
      'f/b1.jpg': photo(200, 140, 60),
      'f/c1.jpg': photo(120, 120, 160),
      'f/d1.jpg': photo(220, 90, 40),
      'f/e1.jpg': photo(40, 160, 140),
    });
  }

  testWidgets('mercato 7 · risultati della ricerca', (tester) async {
    await shoot(tester, 'mercato_7_risultati', section(MarketSection.sale, shop(), FakeMap()),
        before: () async {
      await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    });
  });

  testWidgets('mercato 8 · filtri', (tester) async {
    final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
    await shoot(tester, 'mercato_8_filtri', section(MarketSection.sale, shop(), map),
        before: () async {
      await tester.tap(find.byKey(const ValueKey<String>('mercato_filtri')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey<String>('filtro_prezzo_min')), '50');
      await tester.enterText(find.byKey(const ValueKey<String>('filtro_prezzo_max')), '400');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      for (final String k in <String>['filtro_condizione_like_new', 'filtro_condizione_excellent']) {
        await tester.ensureVisible(find.byKey(ValueKey<String>(k)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey<String>(k)));
        await tester.pumpAndSettle();
      }
      final Finder me = find.byKey(const ValueKey<String>('filtro_mia_posizione'));
      await tester.ensureVisible(me);
      await tester.pumpAndSettle();
      await tester.tap(me);
      await tester.pump();
      map.location.emit(fixAt(41.9028, 12.4964));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey<String>('filtro_raggio')));
    });
  });

  testWidgets('mercato 9 · scheda dell\'annuncio', (tester) async {
    final FakeMarketRepository repo = shop();
    await shoot(
      tester,
      'mercato_9_scheda',
      MarketListingScreen(
        listing: repo.listings.first,
        repository: repo,
        catalog: MarketCatalog(builtInMarketCatalog),
      ),
    );
  });

  // ---------------------------------------------------------------- Blocco 3
  testWidgets('mercato 10 · proposta di scambio', (tester) async {
    final FakeMarketRepository repo = shop();
    repo.candidates = const <SwapItem>[
      SwapItem(id: 'b1', title: 'Bici da città', priceCents: 9000, photo: 'f/e1.jpg'),
      SwapItem(id: 'b2', title: 'Monopattino elettrico', priceCents: 15000, photo: 'f/d1.jpg'),
      SwapItem(id: 'b3', title: 'Chitarra classica', priceCents: 6000, photo: 'f/b1.jpg'),
    ];
    await shoot(
      tester,
      'mercato_10_proposta',
      SwapOfferScreen(repository: repo, targetTitle: 'Console PS4 con giochi', cashAllowed: true,
          targetListingId: 'x'),
      before: () async {
        await tester.tap(find.byKey(const ValueKey<String>('offerta_b1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('offerta_conguaglio')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey<String>('offerta_importo')), '20');
        await tester.enterText(find.byKey(const ValueKey<String>('offerta_messaggio')),
            'Ciao! Ti propongo la bici più 20 €, è quasi nuova.');
        FocusManager.instance.primaryFocus?.unfocus();
      },
    );
  });

  testWidgets('mercato 11 · proposte ricevute', (tester) async {
    final FakeMarketRepository repo = shop();
    repo.swaps.addAll(<SwapProposal>[
      sampleSwap(),
      sampleSwap(id: 'p2', cashCents: null, message: 'Scambieresti con il monopattino?',
          targetTitle: 'Tenda da campeggio 4 posti'),
    ]);
    await shoot(tester, 'mercato_11_proposte', SwapProposalsScreen(repository: repo));
  });

  // ---------------------------------------------------------------- Blocco 4
  testWidgets('mercato 12 · conclusioni e feedback', (tester) async {
    final FakeMarketRepository repo = shop();
    repo.deals.addAll(<MarketDeal>[
      sampleDeal(),
      sampleDeal(id: 'd2', iAmOwner: true, iConfirmed: true, otherConfirmed: false, title: 'Tenda da campeggio'),
      sampleDeal(id: 'd3', proposalId: 'p1', completed: true, title: 'Console PS4 con giochi', theirStars: 5),
      sampleDeal(id: 'd4', completed: true, myStars: 5, theirStars: 4, title: 'Chitarra acustica'),
    ]);
    await shoot(tester, 'mercato_12_conclusioni', MarketDealsScreen(repository: repo));
  });

  testWidgets('mercato 13 · lascia un feedback', (tester) async {
    await shoot(
      tester,
      'mercato_13_feedback',
      LeaveFeedbackScreen(repository: shop(), deal: sampleDeal(completed: true, title: 'Console PS4 con giochi')),
      before: () async {
        await tester.tap(find.byKey(const ValueKey<String>('stella_5')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey<String>('feedback_commento')),
            'Puntuale, gentile e tutto come descritto. Consigliato!');
        FocusManager.instance.primaryFocus?.unfocus();
      },
    );
  });

  testWidgets('mercato 14 · feedback ricevuti', (tester) async {
    final FakeMarketRepository repo = shop();
    repo.feedbackEntries = <FeedbackEntry>[
      sampleFeedback(),
      sampleFeedback(id: 'f2', stars: 4, comment: 'Oggetto come in foto, un po\' di ritardo.'),
      sampleFeedback(id: 'f3', stars: 5, comment: ''),
    ];
    await shoot(
      tester,
      'mercato_14_feedback_ricevuti',
      FeedbackListScreen(
        repository: repo,
        userId: 'utente1',
        name: 'Luca R.',
        summary: const FeedbackSummary(average: 4.7, count: 3, completedDeals: 4),
      ),
    );
  });

  // ---------------------------------------------------------------- Blocco 5
  testWidgets('mercato 15 · commenti: modificato, nascosto, menu', (tester) async {
    final FakeSocialRepository social = FakeSocialRepository()
      ..items.addAll(<ListingComment>[
        commentBy('a', 'Giulia B.', 'È ancora disponibile? Potrei passare sabato.', likes: 2, canHide: true,
            canDelete: true),
        commentBy('b', 'Io P.', 'Sì, sabato mattina va benissimo!', parentId: 'a', minute: 4, isMine: true,
            canDelete: true, edited: true, canHide: true),
        commentBy('c', 'Marco T.', 'Pagami fuori dall\'app con una ricarica', minute: 8, hidden: true,
            canHide: true, canDelete: true),
        commentBy('d', 'Sara L.', 'Ci sono anche i giochi originali?', minute: 12, canHide: true, canDelete: true),
      ]);
    await shoot(
      tester,
      'mercato_15_commenti',
      CommentsScreen(
        listingId: 'x',
        listingTitle: 'Console PS4 con giochi',
        repository: social,
        now: () => DateTime(2026, 11, 15, 10, 30),
      ),
      before: () async {
        await tester.tap(find.byKey(const ValueKey<String>('menu_commento_d')));
        await tester.pumpAndSettle();
      },
    );
  });
}

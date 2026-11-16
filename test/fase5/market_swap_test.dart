import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/social_models.dart';
import 'package:nexus_social/features/market/market_listing_screen.dart';
import 'package:nexus_social/features/market/market_models.dart';
import 'package:nexus_social/features/market/swap_offer_screen.dart';
import 'package:nexus_social/features/market/swap_proposals_screen.dart';
import 'package:nexus_social/features/market/market_catalog_data.dart';

import '../support/fake_market.dart';

/// Fase 5, Blocco 3 · Proposte di scambio: annunci offerti, conguaglio, controproposta,
/// accetta, rifiuta, annulla, stati e notifiche.
void main() {
  group('Regole', () {
    test('stati della specifica e conguaglio visto da ciascuna parte', () {
      expect(SwapStatus.values.map((SwapStatus s) => s.label), <String>[
        'In attesa', 'Accettata', 'Rifiutata', 'Controproposta', 'Annullata', 'Completata',
      ]);
      // Chi ha pubblicato l'annuncio riceve 20 € da chi lo chiede.
      expect(sampleSwap().cashLabel, 'Conguaglio: Luca R. aggiunge 20 €');
      // Chi lo chiede li aggiunge.
      expect(sampleSwap(iAmOwner: false).cashLabel, 'Conguaglio: aggiungi tu 20 €');
      expect(sampleSwap(direction: CashDirection.ownerPays).cashLabel, 'Conguaglio: aggiungi tu 20 €');
      expect(sampleSwap(cashCents: null).cashLabel, isNull);
      expect(sampleSwap().toAnswer, isTrue);
      expect(sampleSwap(fromMe: true).toAnswer, isFalse);
      const SwapOffer offer = SwapOffer(itemIds: <String>['a'], message: '  ciao ');
      expect(offer.toParams(), <String, Object?>{
        'p_items': <String>['a'],
        'p_cash_cents': null,
        'p_cash_direction': null,
        'p_message': 'ciao',
      });
    });

    test('notifiche di scambio', () {
      AppNotification n(NotificationKind k) => AppNotification(
        id: 'n',
        kind: k,
        listingId: 't1',
        listingTitle: 'Console PS4',
        actor: const PersonRef(id: 'u2', username: 'luca_r', publicName: 'Luca R.'),
        createdAt: DateTime(2026, 11, 15),
        proposalId: 'p1',
      );
      expect(n(NotificationKind.swapProposal).text, 'Luca R. ti ha proposto uno scambio per «Console PS4»');
      expect(n(NotificationKind.swapCounter).text, 'Luca R. ha fatto una controproposta per «Console PS4»');
      expect(n(NotificationKind.swapAccepted).text,
          'Luca R. ha accettato la proposta di scambio per «Console PS4»');
      expect(NotificationKind.swapAccepted.isSwap && !NotificationKind.listingLike.isSwap, isTrue);
    });
  });

  group('Schermate', () {
    late FakeMarketRepository repo;

    Future<void> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
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

    setUp(() {
      repo = FakeMarketRepository(listings: <MarketListing>[
        sampleListing(id: 'x', type: MarketType.swap, priceCents: null, cashAdjustment: true,
            title: 'Console PS4 con giochi', wantedInExchange: 'una bici'),
        sampleListing(id: 'y', title: 'Lampada da tavolo'),
      ]);
      repo.candidates = const <SwapItem>[
        SwapItem(id: 'b1', title: 'Bici da città', priceCents: 9000),
        SwapItem(id: 'b2', title: 'Monopattino elettrico', priceCents: 15000),
        SwapItem(id: 'b3', title: 'Casco', priceCents: 2000),
        SwapItem(id: 'b4', title: 'Zaino', priceCents: 1500),
        SwapItem(id: 'b5', title: 'Luci per bici', priceCents: 1000),
        SwapItem(id: 'b6', title: 'Borraccia', priceCents: 500),
      ];
    });

    testWidgets('scheda: «Proponi uno scambio» solo sugli annunci scambiabili altrui', (
      WidgetTester tester,
    ) async {
      await pump(tester, MarketListingScreen(
        listing: repo.listings.first,
        repository: repo,
        catalog: MarketCatalog(builtInMarketCatalog),
      ));
      expect(find.byKey(const ValueKey<String>('scheda_proponi')), findsOneWidget);
      await pump(tester, MarketListingScreen(
        key: const ValueKey<String>('lampada'),
        listing: repo.listings.last,
        repository: repo,
        catalog: MarketCatalog(builtInMarketCatalog),
      ));
      expect(find.byKey(const ValueKey<String>('scheda_proponi')), findsNothing);
    });

    testWidgets('proposta: annunci propri (massimo 5), conguaglio «lo aggiungo io», messaggio', (
      WidgetTester tester,
    ) async {
      await pump(tester, MarketListingScreen(
        listing: repo.listings.first,
        repository: repo,
        catalog: MarketCatalog(builtInMarketCatalog),
      ));
      await tapVisible(tester, find.byKey(const ValueKey<String>('scheda_proponi')));
      expect(find.byType(SwapOfferScreen), findsOneWidget);
      expect(repo.candidateRequests.single, isNull); // i propri annunci

      // Nessun annuncio scelto: si dice cosa manca.
      await tapVisible(tester, find.byKey(const ValueKey<String>('offerta_invia')));
      expect(find.text('Scegli almeno un tuo annuncio da offrire.'), findsOneWidget);

      for (final String id in <String>['b1', 'b2', 'b3', 'b4', 'b5', 'b6']) {
        await tapVisible(tester, find.byKey(ValueKey<String>('offerta_$id')));
      }
      expect(find.text('Al massimo 5 annunci per proposta.'), findsOneWidget);
      for (final String id in <String>['b3', 'b4', 'b5']) {
        await tapVisible(tester, find.byKey(ValueKey<String>('offerta_$id')));
      }

      await tapVisible(tester, find.byKey(const ValueKey<String>('offerta_conguaglio')));
      await tester.enterText(find.byKey(const ValueKey<String>('offerta_importo')), '0,50');
      await tapVisible(tester, find.byKey(const ValueKey<String>('offerta_invia')));
      expect(find.text('Conguaglio da 1 a 999.999 €.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('offerta_importo')), '20');
      await tester.enterText(find.byKey(const ValueKey<String>('offerta_messaggio')), 'Ti do la bici e 20 €');
      await tapVisible(tester, find.byKey(const ValueKey<String>('offerta_invia')));

      final (String target, SwapOffer offer) = repo.proposed.single;
      expect(target, 'x');
      expect(offer.itemIds.toSet(), <String>{'b1', 'b2'});
      expect(offer.cashCents, 2000);
      expect(offer.direction, CashDirection.requesterPays);
      expect(offer.message, 'Ti do la bici e 20 €');
      expect(find.byType(SwapOfferScreen), findsNothing);
      expect(find.textContaining('Proposta inviata'), findsOneWidget);
    });

    testWidgets('annuncio senza conguaglio: l\'opzione non c\'è; errore del server mostrato', (
      WidgetTester tester,
    ) async {
      await pump(tester, SwapOfferScreen(repository: repo, targetTitle: 'Tenda', cashAllowed: false,
          targetListingId: 't'));
      expect(find.byKey(const ValueKey<String>('offerta_conguaglio')), findsNothing);
      await tapVisible(tester, find.byKey(const ValueKey<String>('offerta_b1')));
      repo.failWith = 'Hai già una proposta in attesa per questo annuncio.';
      await tapVisible(tester, find.byKey(const ValueKey<String>('offerta_invia')));
      expect(find.text('Hai già una proposta in attesa per questo annuncio.'), findsOneWidget);
    });

    testWidgets('ricevute: accetta con conferma; poi è nello storico come «Accettata»', (
      WidgetTester tester,
    ) async {
      repo.swaps.add(sampleSwap());
      await pump(tester, SwapProposalsScreen(repository: repo));
      expect(find.text('Ricevute (1)'), findsOneWidget);
      expect(find.text('Luca R. (@luca_r) vuole il tuo annuncio'), findsOneWidget);
      expect(find.text('Conguaglio: Luca R. aggiunge 20 €'), findsOneWidget);
      expect(find.text('Monopattino elettrico · non più disponibile'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('accetta_p1')));
      expect(find.text('Accettare la proposta?'), findsOneWidget);
      await tester.tap(find.text('Accetta').last);
      await tester.pumpAndSettle();
      expect(repo.responses.single, ('p1', true));
      expect(find.text('Ricevute (0)'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('tab_storico')));
      expect(find.byKey(const ValueKey<String>('stato_p1')), findsOneWidget);
      expect(find.text('Accettata'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('accordo_p1')), findsOneWidget);
    });

    testWidgets('ricevute: rifiuta', (WidgetTester tester) async {
      repo.swaps.add(sampleSwap());
      await pump(tester, SwapProposalsScreen(repository: repo));
      await tapVisible(tester, find.byKey(const ValueKey<String>('rifiuta_p1')));
      await tester.tap(find.text('Rifiuta').last);
      await tester.pumpAndSettle();
      expect(repo.responses.single, ('p1', false));
      await tapVisible(tester, find.byKey(const ValueKey<String>('tab_storico')));
      expect(find.text('Rifiutata'), findsOneWidget);
    });

    testWidgets('controproposta: annunci dell\'altra persona, quelli disponibili già scelti', (
      WidgetTester tester,
    ) async {
      repo.swaps.add(sampleSwap());
      await pump(tester, SwapProposalsScreen(repository: repo));
      repo.candidates = const <SwapItem>[
        SwapItem(id: 'i1', title: 'Bici da città', priceCents: 9000),
        SwapItem(id: 'i3', title: 'Casco', priceCents: 2000),
      ];
      await tapVisible(tester, find.byKey(const ValueKey<String>('controproposta_p1')));
      expect(find.text('Controproposta'), findsWidgets);
      expect(repo.candidateRequests.last, 'p1');
      expect(find.text('Cosa chiedi a Luca R. (da 1 a 5 suoi annunci)'), findsOneWidget);
      final CheckboxListTile bike = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey<String>('offerta_i1')),
      );
      expect(bike.value, isTrue);
      await tapVisible(tester, find.byKey(const ValueKey<String>('offerta_i3')));
      await tester.enterText(find.byKey(const ValueKey<String>('offerta_importo')), '10');
      await tapVisible(tester, find.byKey(const ValueKey<String>('offerta_invia')));
      final (String id, SwapOffer offer) = repo.countered.single;
      expect(id, 'p1');
      expect(offer.itemIds.toSet(), <String>{'i1', 'i3'});
      expect(offer.cashCents, 1000);
      expect(find.text('Controproposta inviata.'), findsOneWidget);
    });

    testWidgets('inviate: annulla prima della risposta', (WidgetTester tester) async {
      repo.swaps.add(sampleSwap(id: 'p9', fromMe: true, iAmOwner: false));
      await pump(tester, SwapProposalsScreen(repository: repo));
      await tapVisible(tester, find.byKey(const ValueKey<String>('tab_inviate')));
      expect(find.text('Proposta a Luca R. (@luca_r)'), findsOneWidget);
      expect(find.text('Conguaglio: aggiungi tu 20 €'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('accetta_p9')), findsNothing);
      await tapVisible(tester, find.byKey(const ValueKey<String>('annulla_p9')));
      await tester.tap(find.text('Annulla proposta').last);
      await tester.pumpAndSettle();
      expect(repo.cancelledSwaps.single, 'p9');
      await tapVisible(tester, find.byKey(const ValueKey<String>('tab_storico')));
      expect(find.text('Annullata'), findsOneWidget);
    });
  });
}

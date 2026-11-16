import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/social_models.dart';
import 'package:nexus_social/features/market/market_catalog_data.dart';
import 'package:nexus_social/features/market/market_deals_screen.dart';
import 'package:nexus_social/features/market/market_feedback.dart';
import 'package:nexus_social/features/market/market_listing_screen.dart';
import 'package:nexus_social/features/market/market_models.dart';
import 'package:nexus_social/features/market/my_market_screen.dart';
import 'package:nexus_social/features/market/swap_proposals_screen.dart';

import '../support/fake_market.dart';

/// Fase 5, Blocco 4 · Conclusione confermata da entrambi e feedback a stelle (D6).
void main() {
  group('Regole', () {
    test('stati della conclusione e media', () {
      expect(sampleDeal().toConfirm, isTrue);
      expect(sampleDeal(iAmOwner: true, iConfirmed: true, otherConfirmed: false).canCancel, isTrue);
      expect(sampleDeal(proposalId: 'p', iConfirmed: true, otherConfirmed: false).canCancel, isFalse);
      expect(sampleDeal(completed: true).canLeaveFeedback, isTrue);
      expect(sampleDeal(completed: true, myStars: 4).canLeaveFeedback, isFalse);
      expect(sampleDeal(declined: true).open, isFalse);
      expect(const FeedbackSummary().label, 'Nessun feedback');
      expect(const FeedbackSummary(average: 4.75, count: 12).label, '4,8 · 12 feedback');
    });

    test('notifiche di conclusione e feedback', () {
      AppNotification n(NotificationKind k) => AppNotification(
        id: 'n',
        kind: k,
        listingId: 'l',
        listingTitle: 'Lampada',
        actor: const PersonRef(id: 'u2', username: 'luca_r', publicName: 'Luca R.'),
        createdAt: DateTime(2026, 11, 15),
        dealId: 'd1',
      );
      expect(n(NotificationKind.dealConfirm).text, 'Luca R. chiede di confermare che «Lampada» è concluso');
      expect(n(NotificationKind.dealCompleted).text, '«Lampada» è concluso: lascia un feedback a Luca R.');
      expect(n(NotificationKind.feedbackReceived).text, 'Luca R. ti ha lasciato un feedback per «Lampada»');
      expect(NotificationKind.feedbackReceived.isDeal && !NotificationKind.swapAccepted.isDeal, isTrue);
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

    setUp(() => repo = FakeMarketRepository());

    testWidgets('«Concluso con…»: si sceglie tra chi ha commentato o proposto', (WidgetTester tester) async {
      repo.items.add(sampleMarket(id: 'm1', title: 'Lampada da tavolo'));
      repo.dealPeople = const <DealCandidate>[
        DealCandidate(id: 'u2', username: 'luca_r', publicName: 'Luca R.'),
      ];
      await pump(tester, MyMarketScreen(
        repository: repo,
        catalog: MarketCatalog(builtInMarketCatalog),
        section: MarketSection.sale,
        now: () => DateTime(2026, 11, 15),
      ));
      await tapVisible(tester, find.byKey(const ValueKey<String>('concludi_m1')));
      expect(find.text('Con chi l\'hai concluso?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('controparte_u2')));
      await tester.pumpAndSettle();
      expect(repo.concluded.single, ('m1', 'u2'));
      expect(find.text('Abbiamo chiesto a Luca R. di confermare.'), findsOneWidget);
    });

    testWidgets('«Concluso con…» senza interlocutori: si spiega cosa fare', (WidgetTester tester) async {
      repo.items.add(sampleMarket(id: 'm1'));
      await pump(tester, MyMarketScreen(
        repository: repo,
        catalog: MarketCatalog(builtInMarketCatalog),
        section: MarketSection.sale,
        now: () => DateTime(2026, 11, 15),
      ));
      await tapVisible(tester, find.byKey(const ValueKey<String>('concludi_m1')));
      expect(find.textContaining('Nessuno ha ancora commentato'), findsOneWidget);
    });

    testWidgets('da confermare: conferma, poi «Lascia un feedback» (non modificabile)', (
      WidgetTester tester,
    ) async {
      repo.deals.add(sampleDeal());
      await pump(tester, MarketDealsScreen(repository: repo));
      expect(find.text('Da confermare'), findsOneWidget);
      expect(find.text('Luca R. (@luca_r) ha confermato · manchi tu'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('conferma_d1')));
      await tester.tap(find.text('Confermo'));
      await tester.pumpAndSettle();
      expect(repo.dealAnswers.single, ('d1', true));
      expect(find.text('Concluse'), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey<String>('lascia_feedback_d1')));
      expect(find.byType(LeaveFeedbackScreen), findsOneWidget);
      expect(find.textContaining('non potrai modificarlo'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('feedback_invia')));
      expect(find.text('Scegli da 1 a 5 stelle.'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('stella_4')));
      expect(find.text('Buona'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('feedback_commento')), 'Tutto ok');
      await tapVisible(tester, find.byKey(const ValueKey<String>('feedback_invia')));
      expect(repo.feedbackSent.single, ('d1', 4, 'Tutto ok'));
      expect(find.text('Grazie per il feedback!'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('lascia_feedback_d1')), findsNothing);
    });

    testWidgets('«Non è avvenuto» e annullamento della richiesta', (WidgetTester tester) async {
      repo.deals.addAll(<MarketDeal>[
        sampleDeal(),
        sampleDeal(id: 'd2', iAmOwner: true, iConfirmed: true, otherConfirmed: false, title: 'Tenda'),
      ]);
      await pump(tester, MarketDealsScreen(repository: repo));
      expect(find.text('In attesa dell\'altra persona'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('non_avvenuto_d1')));
      await tester.tap(find.text('Non è avvenuto').last);
      await tester.pumpAndSettle();
      expect(repo.dealAnswers.single, ('d1', false));
      await tapVisible(tester, find.byKey(const ValueKey<String>('annulla_conclusione_d2')));
      expect(repo.cancelledDeals.single, 'd2');
      expect(find.text('Non concluse'), findsOneWidget);
      expect(find.text('Non avvenuto'), findsOneWidget);
      expect(find.text('Richiesta annullata'), findsWidgets);
    });

    testWidgets('scambio accettato: «Confermo: scambio avvenuto» dalle proposte', (WidgetTester tester) async {
      repo.swaps.add(sampleSwap(status: SwapStatus.accepted));
      await pump(tester, SwapProposalsScreen(repository: repo));
      await tapVisible(tester, find.byKey(const ValueKey<String>('tab_storico')));
      await tapVisible(tester, find.byKey(const ValueKey<String>('concluso_p1')));
      await tester.tap(find.text('Confermo'));
      await tester.pumpAndSettle();
      expect(repo.swapConfirmations.single, 'p1');
      expect(find.text('Confermato: aspettiamo Luca R..'), findsOneWidget);
    });

    testWidgets('media nella scheda dell\'annuncio e elenco dei feedback', (WidgetTester tester) async {
      repo = FakeMarketRepository(listings: <MarketListing>[sampleListing(id: 'a')]);
      repo.summary = const FeedbackSummary(average: 4.5, count: 2, completedDeals: 3);
      repo.feedbackEntries = <FeedbackEntry>[sampleFeedback(), sampleFeedback(id: 'f2', stars: 4, comment: '')];
      await pump(tester, MarketListingScreen(
        listing: repo.listings.single,
        repository: repo,
        catalog: MarketCatalog(builtInMarketCatalog),
      ));
      expect(find.text('4,5 · 2 feedback'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey<String>('feedback_di_utente1')));
      expect(find.byType(FeedbackListScreen), findsOneWidget);
      expect(find.text('Feedback di Luca R.'), findsOneWidget);
      expect(find.text('3 scambi e vendite conclusi'), findsOneWidget);
      expect(find.text('Puntuale e gentile'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('voce_f2')), findsOneWidget);
    });

    testWidgets('azienda: niente media dei feedback nella scheda', (WidgetTester tester) async {
      repo = FakeMarketRepository(listings: <MarketListing>[sampleListing(id: 'a', business: true)]);
      await pump(tester, MarketListingScreen(
        listing: repo.listings.single,
        repository: repo,
        catalog: MarketCatalog(builtInMarketCatalog),
      ));
      expect(find.byType(FeedbackSummaryTile), findsNothing);
    });
  });
}

// Fase 6 · Blocco 4: recensioni verificate (solo chi ha usato un coupon in cassa) e avvisi
// delle promozioni vicine (solo se accesi, al massimo 3 al giorno, mai due volte).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/business/business_models.dart';
import 'package:nexus_social/features/business/business_promotions.dart';
import 'package:nexus_social/features/business/business_screens.dart';
import 'package:nexus_social/features/business/promo_alerts.dart';
import 'package:nexus_social/features/business/promotion_models.dart';

import '../support/fake_business.dart';

const String cliente = 'utenteAnna000000000000000001';
const String altro = 'utenteBruno00000000000000002';
const String bar = 'utenteBar00000000000000000002';
final DateTime ora = DateTime(2026, 11, 17, 10, 30);

Widget app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

FakeBusinessRepository barConPremium() => FakeBusinessRepository(me: bar)
  ..clock = (() => ora)
  ..publicNames[cliente] = 'Anna R.'
  ..seed(
    id: bar,
    username: 'barcentrale',
    name: 'Bar Centrale',
    category: BusinessCategory.bar,
    address: const BusinessAddress(street: 'Via Roma', civic: '12', city: 'Porano', cap: '05010', province: 'TR'),
    lat: 42.6851,
    lng: 12.1029,
    status: VerificationStatus.verified,
    premiumUntil: DateTime(2026, 12, 17),
  );

PromotionDraft offerta(String title, {bool coupon = true}) => PromotionDraft(
  kind: PromotionKind.offerta,
  title: title,
  startsAt: ora,
  endsAt: ora.add(const Duration(days: 2)),
  couponText: coupon ? 'Sconto 20%' : '',
);

void main() {
  testWidgets('recensione solo dopo il coupon usato in cassa; il titolare risponde', (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = barConPremium();
    final String promo = await repo.createPromotion(offerta('Colazione -20%'));

    // Chi non è stato cliente non può recensire.
    repo.me = altro;
    await tester.pumpWidget(app(BusinessProfileScreen(repository: repo, id: bar, now: () => ora)));
    await tester.pumpAndSettle();
    expect(find.text('Ancora nessuna recensione.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('recensione_scrivi')), findsNothing);
    await expectLater(repo.saveReview(bar, rating: 1), throwsA(isA<BusinessFailure>()));

    // Prende il coupon: ancora no. Lo usa in cassa: sì.
    repo.me = cliente;
    final String code = await repo.claimCoupon(promo);
    expect((await repo.reviews(bar)).canReview, isFalse);
    repo.me = bar;
    await repo.redeemCoupon(code);
    repo.me = cliente;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(BusinessProfileScreen(repository: repo, id: bar, now: () => ora)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey<String>('recensione_scrivi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('recensione_scrivi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('recensione_pubblica')));
    await tester.pump();
    expect(find.text('Scegli da 1 a 5 stelle.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('stella_4')));
    await tester.enterText(find.byKey(const ValueKey<String>('recensione_testo')), 'Cornetti ottimi');
    await tester.tap(find.byKey(const ValueKey<String>('recensione_pubblica')));
    await tester.pumpAndSettle();
    expect(find.text('4,0 (1)'), findsOneWidget);
    expect(find.text('Cornetti ottimi'), findsOneWidget);
    expect(find.textContaining('Anna R. (tu)'), findsOneWidget);
    expect(find.text('Modifica la tua recensione'), findsOneWidget);

    // Il titolare risponde; il titolare non può recensirsi.
    repo.me = bar;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(BusinessProfileScreen(repository: repo, id: bar, now: () => ora)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('recensione_scrivi')), findsNothing);
    final Finder rispondi = find.textContaining('Rispondi');
    await tester.ensureVisible(rispondi.first);
    await tester.pumpAndSettle();
    await tester.tap(rispondi.first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('recensione_risposta_testo')), 'Grazie, a presto!');
    await tester.tap(find.byKey(const ValueKey<String>('recensione_risposta_invia')));
    await tester.pumpAndSettle();
    expect(find.text('Risposta dell\'attività: Grazie, a presto!'), findsOneWidget);
    await expectLater(repo.saveReview(bar, rating: 5), throwsA(isA<BusinessFailure>()));
  });

  test('avvisi vicini: spenti di default, entro il raggio, mai due volte, al massimo 3 al giorno', () async {
    final FakeBusinessRepository repo = barConPremium();
    for (int i = 1; i <= 5; i++) {
      await repo.createPromotion(offerta('Offerta $i', coupon: i == 1));
    }
    repo.me = cliente;
    final List<String> shown = <String>[];
    DateTime now = ora;
    final PromoAlerts alerts = PromoAlerts(
      notify: (int id, String title, String body) async => shown.add('$title | $body'),
      clock: () => now,
    );
    final List<Promotion> promos = await repo.promotionsNearby(42.6851, 12.1029);
    expect(promos, hasLength(5));

    expect(await alerts.consider(promos, 42.6855, 12.1030), 0, reason: 'spenti finché non li accendi');
    await alerts.setEnabled(true);
    expect(await alerts.consider(promos, 42.7300, 12.1029), 0, reason: 'a 5 km: fuori dal raggio di 1 km');
    expect(await alerts.consider(promos, 42.6855, 12.1030), 3);
    expect(shown.first, '🏷️ Bar Centrale a 50 m | Offerta 1 · coupon: Sconto 20%');
    expect(await alerts.consider(promos, 42.6855, 12.1030), 0, reason: 'al massimo 3 al giorno');

    now = ora.add(const Duration(days: 1));
    expect(await alerts.consider(promos, 42.6855, 12.1030), 2, reason: 'il giorno dopo solo le 2 non ancora avvisate');
    expect(await alerts.consider(promos, 42.6855, 12.1030), 0, reason: 'mai due volte la stessa');

    // Le proprie promozioni non si avvisano.
    repo.me = bar;
    final PromoAlerts mine = PromoAlerts(notify: (int id, String t, String b) async => shown.add(t), clock: () => ora);
    await mine.setEnabled(true);
    expect(await mine.consider(await repo.promotionsNearby(42.6851, 12.1029), 42.6851, 12.1029), 0);
  });

  testWidgets('interruttore degli avvisi nelle promozioni intorno', (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = barConPremium();
    final PromoAlerts alerts = PromoAlerts(notify: (int id, String t, String b) async {});
    PromoAlertsRegistry.current = alerts;
    addTearDown(() => PromoAlertsRegistry.current = null);
    await tester.pumpWidget(app(PromotionsListScreen(repository: repo, promotions: const <Promotion>[], now: () => ora)));
    await tester.pumpAndSettle();
    expect(find.text('Avvisami delle promozioni vicine'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('avvisi_raggio_1000')), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('avvisi_promo_interruttore')));
    await tester.pumpAndSettle();
    expect(alerts.state.enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('avvisi_raggio_3000')));
    await tester.pumpAndSettle();
    expect(alerts.state.radiusM, 3000);
  });
}

// Fase 6 · Blocco 3: promozioni (5 al giorno, massimo 7 giorni), eventi fuori sede, mappa delle
// promozioni, Condividi, coupon con QR e conteggio dei clienti arrivati.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/business/business_models.dart';
import 'package:nexus_social/features/business/business_promotions.dart';
import 'package:nexus_social/features/business/promotion_models.dart';
import 'package:nexus_social/features/map/latest_listings_screen.dart';
import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/listing_sheets.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/map/map_screen.dart';
import 'package:nexus_social/features/market/comuni_italia.dart';
import 'package:nexus_social/features/places/place_search.dart';

import '../support/fake_business.dart';
import '../support/fake_comuni.dart';
import '../support/fake_listings.dart';
import '../support/fake_map.dart';

const String cliente = 'utenteAnna000000000000000001';
const String bar = 'utenteBar00000000000000000002';

/// Martedì 17 novembre 2026, ore 10:30.
final DateTime ora = DateTime(2026, 11, 17, 10, 30);

Widget app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

FakeBusinessRepository barConPremium({bool premium = true}) => FakeBusinessRepository(me: bar)
  ..clock = (() => ora)
  ..seed(
    id: bar,
    username: 'barcentrale',
    name: 'Bar Centrale',
    category: BusinessCategory.bar,
    address: const BusinessAddress(street: 'Via Roma', civic: '12', city: 'Porano', cap: '05010', province: 'TR'),
    lat: 42.6851,
    lng: 12.1029,
    status: VerificationStatus.verified,
    premiumUntil: premium ? DateTime(2026, 12, 17) : null,
  );

PromotionDraft offerta({String title = 'Colazione -20%', int? limit}) => PromotionDraft(
  kind: PromotionKind.offerta,
  title: title,
  startsAt: ora,
  endsAt: ora.add(const Duration(days: 2)),
  couponText: 'Sconto 20%',
  couponLimit: limit,
);

class LuogoFinto implements PlaceLookup {
  @override
  Future<List<PlaceSuggestion>> search(String query, {double? nearLat, double? nearLng}) async =>
      const <PlaceSuggestion>[
        PlaceSuggestion(title: 'Piazza del Popolo', subtitle: 'Orvieto, Umbria', lat: 42.7201, lng: 12.1103),
      ];
}

void main() {
  setUpAll(() => ComuniItalia.testData = fakeComuni());
  tearDownAll(() => ComuniItalia.testData = null);

  test('regole: al massimo 7 giorni, luogo diverso solo per gli eventi, codici letti dal QR', () {
    expect(offerta().check(ora), isNull);
    expect(
      PromotionDraft(kind: PromotionKind.offerta, title: 'Lunga', startsAt: ora, endsAt: ora.add(const Duration(days: 8)))
          .check(ora),
      'Una promozione dura al massimo 7 giorni.',
    );
    expect(
      PromotionDraft(
        kind: PromotionKind.offerta,
        title: 'Fuori',
        startsAt: ora,
        endsAt: ora.add(const Duration(hours: 2)),
        lat: 42.7,
        lng: 12.1,
      ).check(ora),
      'Solo gli eventi possono essere fuori sede.',
    );
    expect(PromotionRules.normalizeCode('PIAZLY-abcd2345'), 'ABCD2345');
    expect(PromotionRules.normalizeCode('abcd 2345'), 'ABCD2345');
    expect(PromotionRules.qrData('ABCD2345'), 'PIAZLY-ABCD2345');
  });

  testWidgets('il titolare pubblica un\'offerta con coupon; al sesto oggi non si può più', (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = barConPremium();
    await tester.pumpWidget(app(MyPromotionsScreen(repository: repo, premiumActive: true, now: () => ora)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Oggi: 0 di 5 promozioni'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('promo_nuova')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('promo_pubblica')));
    await tester.pump();
    expect(find.text('Scrivi un titolo (da 3 a 80 caratteri).'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('promo_titolo')), 'Colazione -20%');
    await tester.tap(find.byKey(const ValueKey<String>('promo_con_coupon')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey<String>('promo_coupon_testo')), 'Sconto 20%');
    await tester.enterText(find.byKey(const ValueKey<String>('promo_coupon_limite')), '50');
    await tester.ensureVisible(find.byKey(const ValueKey<String>('promo_pubblica')));
    await tester.tap(find.byKey(const ValueKey<String>('promo_pubblica')));
    await tester.pumpAndSettle();
    expect(find.text('Colazione -20%'), findsOneWidget);
    expect(find.text('Coupon presi: 0 · Clienti arrivati: 0'), findsOneWidget);
    expect(find.textContaining('Oggi: 1 di 5 promozioni'), findsOneWidget);
    expect(repo.drafts.values.single.couponLimit, 50);
    expect(repo.drafts.values.single.endsAt, ora.add(const Duration(days: 1)));

    for (int i = 2; i <= 5; i++) {
      await repo.createPromotion(offerta(title: 'Offerta $i'));
    }
    await expectLater(repo.createPromotion(offerta(title: 'Sesta')), throwsA(isA<BusinessFailure>()));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(MyPromotionsScreen(repository: repo, premiumActive: true, now: () => ora)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('promo_nuova')), findsNothing, reason: '5 oggi: niente pulsante');
  });

  testWidgets('evento in un altro luogo: la sede resta dov\'è', (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = barConPremium();
    await tester.pumpWidget(app(PromotionFormScreen(repository: repo, now: () => ora, lookup: LuogoFinto())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evento'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey<String>('promo_titolo')), 'Musica in piazza');
    await tester.tap(find.byKey(const ValueKey<String>('promo_fuori_sede')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey<String>('promo_luogo')), 'Piazza del Popolo Orvieto');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.tap(find.text('Piazza del Popolo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey<String>('promo_pubblica')));
    await tester.tap(find.byKey(const ValueKey<String>('promo_pubblica')));
    await tester.pumpAndSettle();
    final PromotionDraft d = repo.drafts.values.single;
    expect((d.kind, d.lat, d.lng), (PromotionKind.evento, 42.7201, 12.1103));
    expect(d.placeLabel, 'Piazza del Popolo · Orvieto, Umbria');
    expect((repo.pages[bar]!.lat, repo.pages[bar]!.lng), (42.6851, 12.1029));
    final Promotion p = (await repo.promotionsNearby(42.69, 12.10)).single;
    expect(p.atSite, isFalse);
    expect(p.whereLabel, 'Piazza del Popolo · Orvieto, Umbria');
  });

  testWidgets('il cliente prende il coupon (QR e codice) e lo condivide; in cassa vale una volta',
      (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = barConPremium();
    final String id = await repo.createPromotion(offerta(limit: 10));
    repo.me = cliente;
    final List<String> shared = <String>[];
    final Promotion p = (await repo.promotionsNearby(42.69, 12.10)).single;
    await tester.pumpWidget(app(PromotionDetailScreen(
      repository: repo,
      promotion: p,
      now: () => ora,
      shareText: (String t) async => shared.add(t),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Fino a gio 19 nov 10:30'), findsOneWidget);
    expect(find.text('Nella sede: Via Roma 12, 05010 Porano (TR)'), findsOneWidget);
    expect(find.text('Ne restano 10.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('promo_prendi_coupon')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('coupon_qr')), findsOneWidget);
    final String code = repo.coupons.keys.single;
    expect(find.text('${code.substring(0, 4)} ${code.substring(4)}'), findsOneWidget);
    expect(await repo.claimCoupon(id), code, reason: 'sempre lo stesso codice');

    await tester.tap(find.byKey(const ValueKey<String>('promo_condividi')));
    await tester.pumpAndSettle();
    expect(shared.single, contains('🏷️ Colazione -20% · Bar Centrale'));
    expect(shared.single, contains('Coupon: Sconto 20%'));
    expect(shared.single, contains('Mappa: https://www.openstreetmap.org/?mlat=42.68510&mlon=12.10290'));
    expect(shared.single, isNot(contains(code)), reason: 'il codice personale non si condivide');

    // In cassa: il titolare inquadra il QR.
    repo.me = bar;
    await tester.pumpWidget(app(CouponRedeemScreen(
      repository: repo,
      scanner: (BuildContext c, ValueChanged<String> onCode) => Center(
        child: TextButton(
          key: const ValueKey<String>('qr_finto'),
          onPressed: () => onCode(PromotionRules.qrData(code)),
          child: const Text('QR'),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('convalida_fotocamera')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('qr_finto')));
    await tester.pumpAndSettle();
    expect(find.text('Coupon valido: Sconto 20%'), findsOneWidget);
    expect(find.text('Clienti arrivati con questa promozione: 1'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('convalida_codice')), code.toLowerCase());
    await tester.tap(find.byKey(const ValueKey<String>('convalida_controlla')));
    await tester.pumpAndSettle();
    expect(find.text('Coupon già usato.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('convalida_codice')), 'ZZZZ9999');
    await tester.tap(find.byKey(const ValueKey<String>('convalida_controlla')));
    await tester.pumpAndSettle();
    expect(find.text('Codice non valido per la tua attività.'), findsOneWidget);

    final Promotion stats = (await repo.myPromotions()).single;
    expect((stats.claimed, stats.redeemed), (1, 1));
  });

  testWidgets('Mappa: promozioni in corso con il conteggio; senza Premium spariscono', (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = barConPremium();
    final String id = await repo.createPromotion(offerta());
    repo.me = cliente;
    final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
    await tester.pumpWidget(app(Scaffold(body: MapScreen(services: map.services, businesses: repo, now: () => ora))));
    await tester.pumpAndSettle();
    map.location.emit(fixAt(42.69, 12.10));
    await tester.pumpAndSettle();
    expect(map.handle.promotions.single.title, 'Colazione -20%');
    expect(find.descendant(of: find.byKey(const ValueKey<String>('mappa_promozioni')), matching: find.text('1')),
        findsOneWidget);
    map.handle.tapPromotion(id);
    await tester.pumpAndSettle();
    expect(find.byType(PromotionDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('mappa_promozioni')));
    await tester.pumpAndSettle();
    expect(find.byType(PromotionsListScreen), findsOneWidget);
    expect(find.textContaining('Fino a gio 19 nov 10:30 · '), findsOneWidget, reason: 'con la distanza');

    repo.subscriptions.clear();
    expect(await repo.promotionsNearby(42.69, 12.10), isEmpty);
    expect(await repo.promotionsOf(bar), isEmpty);
  });

  testWidgets('«Ultimi annunci» › Promozioni mostra anche le promozioni delle attività', (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = barConPremium();
    await repo.createPromotion(offerta());
    repo.me = cliente;
    await tester.pumpWidget(app(LatestListingsScreen(
      services: ListingSheetServices(listings: FakeListingRepository()..nearbyItems = <NearbyListing>[]),
      origin: const GeoPoint(42.69, 12.10),
      filters: const MapFilters(),
      now: () => ora,
      businesses: repo,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Promozioni'));
    await tester.pumpAndSettle();
    expect(find.text('Colazione -20%'), findsOneWidget);
    await tester.tap(find.text('Colazione -20%'));
    await tester.pumpAndSettle();
    expect(find.byType(PromotionDetailScreen), findsOneWidget);
  });
}

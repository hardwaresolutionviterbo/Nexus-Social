// Fase 6 · Blocco 1: registrazione Azienda, profilo attività con sede fissa, orari, verifica
// dell'amministratore e segnaposti fissi sulla Mappa.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/business/business_models.dart';
import 'package:nexus_social/features/business/business_screens.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/map/map_screen.dart';
import 'package:nexus_social/features/market/comuni_italia.dart';
import 'package:nexus_social/features/places/place_search.dart';

import '../support/fake_business.dart';
import '../support/fake_comuni.dart';
import '../support/fake_map.dart';

const String io = 'utenteAnna000000000000000001';
const String bar = 'utenteBar00000000000000000002';

/// Martedì 18 novembre 2026, ore 10:30.
final DateTime martedi = DateTime(2026, 11, 18, 10, 30);

Widget app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Photon finto: un indirizzo completo a Porano.
class AddressLookup implements PlaceLookup {
  @override
  Future<List<PlaceSuggestion>> search(String query, {double? nearLat, double? nearLng}) async =>
      const <PlaceSuggestion>[
        PlaceSuggestion(
          title: 'Via Roma 12',
          subtitle: 'Porano, Umbria',
          lat: 42.6851,
          lng: 12.1029,
          street: 'Via Roma',
          houseNumber: '12',
          city: 'Porano',
          postcode: '05010',
        ),
      ];
}

BusinessHours orariBar() => const BusinessHours(<int, List<HourSlot>>{
  1: <HourSlot>[HourSlot(7 * 60, 13 * 60), HourSlot(16 * 60, 20 * 60)],
  2: <HourSlot>[HourSlot(7 * 60, 13 * 60), HourSlot(16 * 60, 20 * 60)],
  5: <HourSlot>[HourSlot(18 * 60, 26 * 60)], // venerdì fino alle 2 di notte
});

void main() {
  setUpAll(() => ComuniItalia.testData = fakeComuni());
  tearDownAll(() => ComuniItalia.testData = null);

  group('regole', () {
    test('orari: aperto ora, chiusura dopo mezzanotte, prossima apertura', () {
      final BusinessHours h = orariBar();
      expect(h.isOpenAt(martedi), isTrue);
      expect(h.statusLabel(martedi), 'Aperto ora · chiude alle 13:00');
      expect(h.statusLabel(DateTime(2026, 11, 18, 14)), 'Chiuso · apre alle 16:00');
      expect(h.statusLabel(DateTime(2026, 11, 18, 21)), 'Chiuso · apre venerdì alle 18:00');
      // Sabato all'1:30: aperto per la sera del venerdì.
      expect(h.isOpenAt(DateTime(2026, 11, 21, 1, 30)), isTrue);
      expect(h.statusLabel(DateTime(2026, 11, 21, 1, 30)), 'Aperto ora · chiude alle 02:00');
      expect(h.isOpenAt(DateTime(2026, 11, 21, 3)), isFalse);
      expect(BusinessHours.fromJson(h.toJson()).of(5), <HourSlot>[const HourSlot(1080, 1560)]);
      expect(const BusinessHours().statusLabel(martedi), 'Orari non indicati');
    });

    test('indirizzo: civico, CAP e provincia come sul server', () {
      for (final String ok in <String>['12', '12A', '12/3', '7 bis', 'snc']) {
        expect(BusinessAddress.civicError(ok), isNull, reason: ok);
      }
      for (final String bad in <String>['', 'dodici', '12-14-16']) {
        expect(BusinessAddress.civicError(bad), isNotNull, reason: bad);
      }
      expect(BusinessAddress.capError('05010'), isNull);
      expect(BusinessAddress.capError('5010'), isNotNull);
      const BusinessAddress a =
          BusinessAddress(street: 'Via Roma', civic: '12', city: 'Porano', cap: '05010', province: 'TR');
      expect(a.label, 'Via Roma 12, 05010 Porano (TR)');
    });

    test('sede solo in Italia', () {
      const BusinessAddress a = BusinessAddress(street: 'Rue', civic: '1', city: 'Parigi', cap: '75001', province: 'PA');
      expect(const BusinessPageDraft(displayName: 'x', category: BusinessCategory.bar, address: a, lat: 48.85, lng: 2.35).inItaly,
          isFalse);
      expect(const BusinessPageDraft(displayName: 'x', category: BusinessCategory.bar, address: a, lat: 42.68, lng: 12.1).inItaly,
          isTrue);
    });
  });

  testWidgets('un Privato registra l\'attività, crea la pagina con la sede dall\'indirizzo e gli orari',
      (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = FakeBusinessRepository(me: io);
    await tester.pumpWidget(app(MyBusinessScreen(
      repository: repo,
      lookup: AddressLookup(),
      pickImage: () async => Uint8List.fromList(<int>[1, 2, 3]),
      pickDocument: () async => (Uint8List.fromList(<int>[9]), true),
      now: () => martedi,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('azienda_intro')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('azienda_registra')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Il tuo account diventerà «Azienda»'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('azienda_ragione_sociale')), 'Bar Centrale di Rossi');
    await tester.enterText(find.byKey(const ValueKey<String>('azienda_partita_iva')), '12345678901');
    await tester.tap(find.byKey(const ValueKey<String>('azienda_invia')));
    await tester.pump();
    expect(find.text('Partita IVA non valida (11 cifre).'), findsOneWidget);
    expect(find.text('Conferma la dichiarazione qui sopra.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('azienda_partita_iva')), '12345678903');
    await tester.tap(find.byKey(const ValueKey<String>('azienda_dichiarazione')));
    await tester.tap(find.byKey(const ValueKey<String>('azienda_invia')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('azienda_stato_pending')), findsOneWidget);
    expect(find.text('Bar Centrale di Rossi'), findsOneWidget);

    // Documento facoltativo.
    await tester.tap(find.byKey(const ValueKey<String>('azienda_documento')));
    await tester.pumpAndSettle();
    expect(find.text('Documento caricato'), findsOneWidget);

    // Profilo attività.
    await tester.tap(find.byKey(const ValueKey<String>('azienda_crea_pagina')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('pagina_salva')));
    await tester.pump();
    expect(find.text('Scrivi l\'insegna (da 2 a 80 caratteri).'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('pagina_insegna')), 'Bar Centrale');
    await tester.enterText(find.byKey(const ValueKey<String>('pagina_cerca_indirizzo')), 'Via Roma 12 Porano');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.tap(find.text('Via Roma 12'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey<String>('pagina_via'))).controller!.text, 'Via Roma');
    expect(tester.widget<TextField>(find.byKey(const ValueKey<String>('pagina_civico'))).controller!.text, '12');
    expect(tester.widget<TextField>(find.byKey(const ValueKey<String>('pagina_cap'))).controller!.text, '05010');
    expect(tester.widget<TextField>(find.byKey(const ValueKey<String>('pagina_comune'))).controller!.text, 'Porano (TR)');
    expect(find.textContaining('Segnaposto sull\'indirizzo. Resta fisso'), findsOneWidget);

    // Lunedì 7-13, copiato fino al venerdì.
    await tester.ensureVisible(find.byKey(const ValueKey<String>('orari_giorno_1')));
    await tester.tap(find.byKey(const ValueKey<String>('orari_giorno_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('fascia_aggiungi')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('fascia_fatto')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('orari_copia')));
    await tester.pump();
    expect(find.text('09:00–13:00'), findsNWidgets(5));

    await tester.ensureVisible(find.byKey(const ValueKey<String>('pagina_aggiungi_foto')));
    await tester.tap(find.byKey(const ValueKey<String>('pagina_aggiungi_foto')));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('foto_nuova_0')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey<String>('pagina_salva')));
    await tester.tap(find.byKey(const ValueKey<String>('pagina_salva')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('azienda_pagina')), findsOneWidget);
    expect(find.text('Via Roma 12, 05010 Porano (TR)'), findsOneWidget);
    expect(find.textContaining('Visibile sulla Mappa · Aperto ora · chiude alle 13:00'), findsOneWidget);
    final BusinessPage saved = repo.pages[io]!;
    expect((saved.lat, saved.lng), (42.6851, 12.1029));
    expect(saved.photos, hasLength(1));
    expect(saved.hours.of(5), <HourSlot>[const HourSlot(540, 780)]);
    expect(saved.hours.of(6), isEmpty);
  });

  testWidgets('la sede resta fissa: solo il comune scelto a mano sposta il segnaposto al centro',
      (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = FakeBusinessRepository(me: io)
      ..seed(
        id: io,
        username: 'anna.r',
        name: 'Bar Centrale',
        category: BusinessCategory.bar,
        address: const BusinessAddress(street: 'Via Roma', civic: '12', city: 'Porano', cap: '05010', province: 'TR'),
        lat: 42.6851,
        lng: 12.1029,
      );
    await tester.pumpWidget(app(BusinessPageEditScreen(repository: repo, initial: repo.pages[io])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Segnaposto scelto sulla mappa. Resta fisso'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('pagina_descrizione')), 'Colazioni e aperitivi');
    await tester.ensureVisible(find.byKey(const ValueKey<String>('pagina_salva')));
    await tester.tap(find.byKey(const ValueKey<String>('pagina_salva')));
    await tester.pumpAndSettle();
    expect(repo.pages[io]!.description, 'Colazioni e aperitivi');
    expect((repo.pages[io]!.lat, repo.pages[io]!.lng), (42.6851, 12.1029), reason: 'la sede non si è mossa');
  });

  testWidgets('scheda pubblica: aperto ora, indicazioni, prenota, badge solo dopo la verifica',
      (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = FakeBusinessRepository(me: io)
      ..seed(
        id: bar,
        username: 'barcentrale',
        name: 'Bar Centrale',
        category: BusinessCategory.bar,
        address: const BusinessAddress(street: 'Via Roma', civic: '12', city: 'Porano', cap: '05010', province: 'TR'),
        lat: 42.6851,
        lng: 12.1029,
        hours: orariBar(),
        phone: '0763 000000',
        bookingUrl: 'https://esempio.it/prenota',
      );
    await tester.pumpWidget(app(BusinessProfileScreen(repository: repo, id: bar, now: () => martedi)));
    await tester.pumpAndSettle();
    expect(find.text('Aperto ora · chiude alle 13:00'), findsOneWidget);
    expect(find.text('Via Roma 12, 05010 Porano (TR)'), findsOneWidget);
    for (final String k in <String>['attivita_indicazioni', 'attivita_prenota', 'attivita_chiama', 'attivita_scrivi']) {
      expect(find.byKey(ValueKey<String>(k)), findsOneWidget, reason: k);
    }
    expect(find.byKey(const ValueKey<String>('badge_verificato')), findsNothing);
    expect(find.text('Bar Centrale S.r.l.'), findsNothing, reason: 'la ragione sociale resta privata');
    expect(find.text('12345678903'), findsNothing, reason: 'la partita IVA resta privata');

    // L'amministratore approva.
    await tester.pumpWidget(app(BusinessReviewScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('@barcentrale · P.IVA 12345678903'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('verifica_approva_barcentrale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('verifica_conferma')));
    await tester.pumpAndSettle();
    expect(find.text('Verificata'), findsOneWidget);

    await tester.pumpWidget(app(BusinessProfileScreen(repository: repo, id: bar, now: () => martedi)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('badge_verificato')), findsOneWidget);
  });

  testWidgets('Mappa: segnaposti fissi delle attività vicine; toccandoli si apre la scheda',
      (WidgetTester tester) async {
    tall(tester);
    final FakeBusinessRepository repo = FakeBusinessRepository(me: io)
      ..seed(
        id: bar,
        username: 'barcentrale',
        name: 'Bar Centrale',
        category: BusinessCategory.bar,
        address: const BusinessAddress(street: 'Via Roma', civic: '12', city: 'Porano', cap: '05010', province: 'TR'),
        lat: 42.6851,
        lng: 12.1029,
        status: VerificationStatus.verified,
      );
    final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
    await tester.pumpWidget(app(Scaffold(body: MapScreen(services: map.services, businesses: repo, now: () => martedi))));
    await tester.pumpAndSettle();
    map.location.emit(fixAt(42.69, 12.10));
    await tester.pumpAndSettle();
    expect(repo.askedLat, 42.69);
    expect(map.handle.businesses.single.displayName, 'Bar Centrale');
    expect(map.handle.businesses.single.verified, isTrue);
    expect(map.handle.businesses.single.initial, 'B');

    // Il titolare si sposta col GPS: la sede resta dov'è.
    map.location.emit(fixAt(42.72, 12.13));
    await tester.pumpAndSettle();
    expect((map.handle.businesses.single.lat, map.handle.businesses.single.lng), (42.6851, 12.1029));

    map.handle.tapBusiness(bar);
    await tester.pumpAndSettle();
    expect(find.byType(BusinessProfileScreen), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('badge_verificato')), findsOneWidget);
  });
}

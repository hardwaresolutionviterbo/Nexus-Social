import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/contacts/contacts_sync.dart';
import 'package:nexus_social/features/privacy/privacy_screen.dart';

import '../support/fake_contacts.dart';
import '../support/fake_privacy_repository.dart';

/// Rubrica (Fase 2, Blocco 5): R2.6, R2.11, R2.12, S6, P5-P8, P13.
void main() {
  late FakePrivacyRepository privacy;
  late FakeContactsRepository contacts;

  setUp(() {
    privacy = FakePrivacyRepository();
    contacts = FakeContactsRepository(privacy);
  });

  Finder key(String k) => find.byKey(ValueKey<String>(k));

  Future<void> pumpContacts(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PrivacyScreen(repository: privacy, contacts: contacts),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(key('sezione_contacts'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  test('numeri della rubrica: solo cellulari italiani, senza doppioni, al massimo 2.000', () {
    expect(
      normalizeContactNumbers(<String>['+39 300 000 0001', '3000000001', '0039 300-000-0002',
          '06 1234567', 'abc', '+44 7700 900000']),
      <String>['+393000000001', '+393000000002'],
    );
    final List<String> many = <String>[
      for (int i = 0; i < 2500; i++) '3${(100000000 + i).toString()}',
    ];
    expect(normalizeContactNumbers(many).length, ContactsLimits.maxNumbers);
  });

  testWidgets('R2.6 · prima il consenso spiegato; «Non ora» non legge nulla', (tester) async {
    await pumpContacts(tester);
    await tapKey(tester, 'attiva_rubrica');
    expect(find.textContaining('non vengono mai inviati in chiaro'), findsWidgets);
    expect(find.textContaining('30 giorni'), findsWidgets);
    await tester.tap(find.text('Non ora'));
    await tester.pumpAndSettle();
    expect(contacts.calls, isEmpty);
  });

  testWidgets('R2.11 · consenso dato: sincronizzazione e contatti riconosciuti', (tester) async {
    await pumpContacts(tester);
    await tapKey(tester, 'attiva_rubrica');
    await tapKey(tester, 'accetta_rubrica');
    expect(contacts.calls, <String>['enable', 'sync']);
    expect(find.text('2 contatti su Piazly'), findsOneWidget);
    expect(find.textContaining('i dati scadono il 14/12/2026'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(key('permetti_trovarmi')).value, isTrue);

    await tapKey(tester, 'contatti_riconosciuti');
    expect(find.text('@laura_b · +393000000002'), findsOneWidget);
    expect(find.text('@marco_t'), findsOneWidget);
  });

  testWidgets('P8 · «Permetti di trovarmi» si può spegnere', (tester) async {
    await pumpContacts(tester);
    await tapKey(tester, 'attiva_rubrica');
    await tapKey(tester, 'accetta_rubrica');
    await tapKey(tester, 'permetti_trovarmi');
    expect(contacts.calls.last, 'setDiscoverable:false');
    expect(tester.widget<SwitchListTile>(key('permetti_trovarmi')).value, isFalse);
  });

  testWidgets('P7 · «Revoca e cancella» con conferma', (tester) async {
    await pumpContacts(tester);
    await tapKey(tester, 'attiva_rubrica');
    await tapKey(tester, 'accetta_rubrica');
    await tapKey(tester, 'revoca_rubrica');
    expect(find.textContaining('vengono cancellati'), findsOneWidget);
    await tapKey(tester, 'conferma_revoca_rubrica');
    expect(contacts.calls.last, 'revoke');
    expect(key('attiva_rubrica'), findsOneWidget);
  });

  testWidgets('P13 · consenso visibile con la data in Autorizzazioni, con «Revoca»', (tester) async {
    await pumpContacts(tester);
    await tapKey(tester, 'attiva_rubrica');
    await tapKey(tester, 'accetta_rubrica');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'sezione_permissions');
    expect(find.text('Dal 14/11/2026'), findsOneWidget);
    await tester.tap(find.descendant(of: key('consenso_rubrica'), matching: find.text('Revoca')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'conferma_revoca_rubrica');
    expect(contacts.calls.last, 'revoke');
    expect(key('nessun_consenso'), findsOneWidget);
  });
}

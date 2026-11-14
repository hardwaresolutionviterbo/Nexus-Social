import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/app.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/privacy/privacy_checkup_screen.dart';
import 'package:nexus_social/features/privacy/privacy_controller.dart';
import 'package:nexus_social/features/privacy/privacy_repository.dart';
import 'package:nexus_social/features/privacy/privacy_screen.dart';
import 'package:nexus_social/features/profile/profile_models.dart';
import 'package:nexus_social/features/profile/profile_repository.dart';
import 'package:nexus_social/features/profile/public_profile_screen.dart';

import '../support/fake_auth_gateway.dart';
import '../support/fake_privacy_repository.dart';
import '../support/fake_profile_repository.dart';

/// Privacy e blocchi (Fase 2, Blocco 3): R2.7, R2.8, R2.9, P3, P5, P6, P8, P12, P14, P15.
void main() {
  late FakePrivacyRepository privacy;

  setUp(() => privacy = FakePrivacyRepository());

  Finder key(String k) => find.byKey(ValueKey<String>(k));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpPage(WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: PrivacyScreen(repository: privacy)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  testWidgets('R2.8 · pagina Privacy: 7 sezioni con la scelta attuale', (tester) async {
    await pumpPage(tester);
    for (final String title in <String>[
      'Visibilità del profilo', 'Numero di telefono', 'Contatti e rubrica', 'Posizione',
      'GPS in tempo reale', 'Persone bloccate', 'Autorizzazioni',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Contatti riconosciuti dalla rubrica'), findsOneWidget);
    expect(find.text('Bio visibile · social visibili'), findsOneWidget);
    expect(find.text('Spento · nessuna condivisione'), findsOneWidget);
    expect(find.text('Controllo privacy'), findsOneWidget);
  });

  testWidgets('P5, P6 · numero: due sole opzioni, scelta salvata subito', (tester) async {
    await pumpPage(tester);
    await tapKey(tester, 'sezione_phone');
    expect(find.text('Chi può vedere il mio numero?'), findsOneWidget);
    expect(find.textContaining('Agli sconosciuti il numero non si vede mai'), findsOneWidget);
    expect(find.byType(RadioListTile<PhoneVisibility>), findsNWidgets(2));
    await tapKey(tester, 'numero_nessuno');
    expect(privacy.calls, contains('setPhoneVisibility:nobody'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Nessuno'), findsOneWidget);
  });

  testWidgets('P15 · salvataggio non riuscito: la scelta torna com\'era, con messaggio', (tester) async {
    await pumpPage(tester);
    await tapKey(tester, 'sezione_profile');
    privacy.failNextSave = const ProfileFailure('Scelta non salvata. Riprova.');
    await tapKey(tester, 'privacy_mostra_bio');
    expect(find.text('Scelta non salvata. Riprova.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(key('privacy_mostra_bio')).value, isTrue);
    await tapKey(tester, 'privacy_mostra_bio');
    expect(tester.widget<SwitchListTile>(key('privacy_mostra_bio')).value, isFalse);
    expect(privacy.settings.showBio, isFalse);
  });

  testWidgets('P8 · rubrica: interruttori spenti finché non arriva la sincronizzazione', (tester) async {
    await pumpPage(tester);
    await tapKey(tester, 'sezione_contacts');
    final SwitchListTile find1 = tester.widget<SwitchListTile>(key('trova_contatti'));
    expect(find1.value, isFalse);
    expect(find1.onChanged, isNull);
    expect(find.textContaining('30 giorni'), findsOneWidget);
  });

  testWidgets('R2.7 · persone bloccate: elenco e «Sblocca» con conferma', (tester) async {
    privacy.blocked = <BlockedUser>[
      const BlockedUser(id: 'u2', username: 'laura_b', publicName: 'Laura B.'),
    ];
    await pumpPage(tester);
    expect(find.text('1 persona'), findsOneWidget);
    await tapKey(tester, 'sezione_blocked');
    expect(find.text('Laura B.'), findsOneWidget);
    expect(find.text('@laura_b'), findsOneWidget);
    await tester.tap(find.text('Sblocca'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sblocca'));
    await tester.pumpAndSettle();
    expect(privacy.calls, contains('unblock:u2'));
    expect(key('nessun_bloccato'), findsOneWidget);
  });

  testWidgets('R2.9 · Controllo privacy: 8 passi, riepilogo con «Modifica»', (tester) async {
    phone(tester);
    final PrivacyController controller = PrivacyController(privacy);
    addTearDown(controller.dispose);
    await controller.load();
    bool done = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PrivacyCheckupScreen(controller: controller, onDone: () => done = true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Passo 1 di 8'), findsOneWidget);
    for (int i = 2; i <= 8; i++) {
      await tapKey(tester, 'avanti_controllo');
      expect(find.text('Passo $i di 8'), findsOneWidget);
    }
    expect(find.text('Riepilogo'), findsOneWidget);
    expect(find.text('Modifica'), findsNWidgets(7));

    await tester.tap(find.descendant(of: key('riepilogo_phone'), matching: find.text('Modifica')));
    await tester.pumpAndSettle();
    expect(find.text('Passo 2 di 8'), findsOneWidget);
    await tapKey(tester, 'numero_nessuno');
    expect(privacy.calls, contains('setPhoneVisibility:nobody'));

    await tapKey(tester, 'esci_controllo');
    expect(done, isTrue);
  });

  testWidgets('R2.7 · dal profilo di un altro utente: «Blocca» con conferma', (tester) async {
    phone(tester);
    int blocks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PublicProfileScreen(
                      title: 'Profilo',
                      profile: const PublicProfile(
                        id: 'u2', isBusiness: false, username: 'laura_b', publicName: 'Laura B.',
                      ),
                      onBlock: () async => blocks++,
                    ),
                  ),
                ),
                child: const Text('apri'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(key('menu_profilo'));
    await tester.pumpAndSettle();
    await tester.tap(key('blocca_utente'));
    await tester.pumpAndSettle();
    expect(find.text('Bloccare Laura B.?'), findsOneWidget);
    await tester.tap(key('conferma_blocco'));
    await tester.pumpAndSettle();
    expect(blocks, 1);
    expect(find.text('apri'), findsOneWidget);
    expect(find.text('Laura B. è bloccato.'), findsOneWidget);
  });

  testWidgets('P14 · dopo la registrazione: Controllo privacy proposto, si può saltare', (tester) async {
    phone(tester);
    final FakeAuthGateway gateway = FakeAuthGateway(uid: 'utenteProva');
    addTearDown(gateway.close);
    final FakeProfileRepository profiles = FakeProfileRepository();
    await tester.pumpWidget(
      NexusApp(authGateway: gateway, profiles: profiles, privacy: privacy),
    );
    await tester.pumpAndSettle();
    for (final (String k, String text) in <(String, String)>[
      ('nascita', '01/01/1990'),
      ('username', 'carlo_r'),
      ('nome', 'Carlo Rossi'),
    ]) {
      await tester.ensureVisible(key(k));
      await tester.enterText(key(k), text);
    }
    await tapKey(tester, 'salva_profilo');
    expect(find.text('Controllo privacy'), findsOneWidget);
    expect(find.text('Salta'), findsOneWidget);
    await tapKey(tester, 'esci_controllo');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  test('il profilo pubblico non espone dati aziendali (P4)', () {
    final PublicProfile p = PublicProfile.fromJson(<String, dynamic>{
      'id': 'd', 'account_type': 'business', 'username': 'bottega', 'public_name': 'Paolo V.',
      'business_name': 'Bottega Verdi Srl',
    });
    expect(p.isBusiness, isTrue);
    expect(p.publicName, 'Paolo V.');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/app.dart';
import 'package:nexus_social/core/services/device_identity.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/profile/profile_models.dart';
import 'package:nexus_social/features/security/security_screens.dart';

import '../support/app_helpers.dart';
import '../support/fake_auth_gateway.dart';
import '../support/fake_profile_repository.dart';
import '../support/fake_security.dart';

/// Sicurezza dell'account (Fase 2, Blocco 4): R2.5, S2, S3.
void main() {
  late FakeAuthGateway gateway;
  late FakeProfileRepository profiles;
  late FakeSecurityRepository security;
  late FakeBiometricLock lock;

  setUp(() {
    gateway = FakeAuthGateway(uid: 'utenteProva');
    profiles = FakeProfileRepository(
      mine: const MyProfile(
        id: 'utenteProva',
        isBusiness: false,
        username: 'carlo_r',
        publicName: 'Carlo R.',
        fullName: 'Carlo Rossi',
      ),
    );
    security = FakeSecurityRepository();
    lock = FakeBiometricLock();
  });
  tearDown(() => gateway.close());

  Finder key(String k) => find.byKey(ValueKey<String>(k));

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NexusApp(
        authGateway: gateway,
        profiles: profiles,
        security: security,
        biometricLock: lock,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  Future<void> openSecurity(WidgetTester tester) async {
    await openSection(tester, 'Profilo');
    await tapKey(tester, 'apri_sicurezza');
  }

  testWidgets('S2 · telefono nuovo con PIN: niente app finché il PIN non è giusto', (tester) async {
    security
      ..pin = '482913'
      ..trusted = false;
    await pumpApp(tester);
    expect(find.text('Inserisci il PIN'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(profiles.calls, isNot(contains('fetchMine')));

    await tester.enterText(key('pin_accesso'), '000000');
    await tapKey(tester, 'verifica_pin');
    expect(find.text('PIN errato. Riprova.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.enterText(key('pin_accesso'), '482913');
    await tapKey(tester, 'verifica_pin');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('S2 · troppi tentativi: attesa indicata, pulsante disattivato', (tester) async {
    security
      ..pin = '482913'
      ..trusted = false
      ..failures = 4;
    await pumpApp(tester);
    await tester.enterText(key('pin_accesso'), '111111');
    await tapKey(tester, 'verifica_pin');
    expect(find.textContaining('Troppi tentativi'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('verifica_pin')).onPressed, isNull);
  });

  testWidgets('S2 · PIN dimenticato: ripristino richiesto, possibile solo dopo 7 giorni', (tester) async {
    security
      ..pin = '482913'
      ..trusted = false;
    await pumpApp(tester);
    await tapKey(tester, 'pin_dimenticato');
    expect(find.textContaining('solo dopo 7 giorni'), findsOneWidget);
    await tester.tap(find.text('Ho capito'));
    await tester.pumpAndSettle();
    expect(key('ripristino_richiesto'), findsOneWidget);
    expect(security.pin, '482913');

    security.resetAvailableAt = DateTime.now().subtract(const Duration(minutes: 1));
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    await tapKey(tester, 'pin_dimenticato');
    await tapKey(tester, 'conferma_ripristino');
    expect(security.pin, isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('S2 · attivare il PIN: due volte uguale, poi «Attiva»', (tester) async {
    await pumpApp(tester);
    await openSecurity(tester);
    expect(key('stato_pin'), findsOneWidget);
    expect(find.text('Non attiva'), findsOneWidget);
    await tapKey(tester, 'attiva_pin');
    await tester.enterText(key('pin_nuovo'), '735102');
    await tester.enterText(key('pin_ripeti'), '735103');
    await tapKey(tester, 'conferma_pin');
    expect(find.text('I due PIN non coincidono.'), findsOneWidget);
    expect(security.pin, isNull);

    await tester.enterText(key('pin_ripeti'), '735102');
    await tapKey(tester, 'conferma_pin');
    expect(security.pin, '735102');
    expect(find.text('Attiva'), findsOneWidget);
  });

  testWidgets('S2 · cambiare o disattivare il PIN richiede quello attuale', (tester) async {
    security.pin = '482913';
    await pumpApp(tester);
    await openSecurity(tester);
    await tapKey(tester, 'disattiva_pin');
    await tester.enterText(key('pin_attuale'), '999999');
    await tapKey(tester, 'conferma_pin');
    expect(find.text('PIN errato.'), findsOneWidget);
    expect(security.pin, '482913');
    await tester.enterText(key('pin_attuale'), '482913');
    await tapKey(tester, 'conferma_pin');
    expect(security.pin, isNull);
  });

  testWidgets('S3 · impronta facoltativa: si attiva solo dopo averla confermata', (tester) async {
    await pumpApp(tester);
    await openSecurity(tester);
    expect(tester.widget<SwitchListTile>(key('sblocco_impronta')).value, isFalse);
    lock.succeed = false;
    await tapKey(tester, 'sblocco_impronta');
    expect(lock.enabled, isFalse);
    expect(find.text('Impronta o volto non confermati.'), findsOneWidget);
    lock.succeed = true;
    await tapKey(tester, 'sblocco_impronta');
    expect(lock.enabled, isTrue);
  });

  testWidgets('S3 · impronta attiva: all\'apertura l\'app è bloccata fino allo sblocco', (tester) async {
    lock
      ..enabled = true
      ..succeed = false;
    await pumpApp(tester);
    expect(find.text('Piazly è bloccata'), findsOneWidget);
    expect(find.text('Chat e chiamate'), findsNothing);
    lock.succeed = true;
    await tapKey(tester, 'sblocca_app');
    expect(find.text('Chat e chiamate'), findsOneWidget);
  });

  testWidgets('S3 · impronta non disponibile sul telefono: interruttore spento', (tester) async {
    lock.available = false;
    await pumpApp(tester);
    await openSecurity(tester);
    expect(find.text('Non disponibile su questo telefono'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(key('sblocco_impronta')).onChanged, isNull);
  });

  testWidgets('uscita sicura: il telefono non resta attendibile, impronta spenta', (tester) async {
    lock.enabled = true;
    security.pin = '482913';
    await pumpApp(tester);
    expect(lock.prompts, 1);
    await openSection(tester, 'Profilo');
    await tester.ensureVisible(find.text('Esci dall\'account su questo telefono'));
    await tester.tap(find.text('Esci dall\'account su questo telefono'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Esci'));
    await tester.pumpAndSettle();
    expect(security.calls, contains('forgetThisDevice'));
    expect(lock.enabled, isFalse);
  });

  test('codice del telefono: casuale, 48 caratteri ammessi dal server', () {
    final String a = DeviceIdentity.generate();
    final String b = DeviceIdentity.generate();
    expect(a, isNot(b));
    expect(a.length, 48);
    expect(DeviceIdentity.isValid(a), isTrue);
    expect(DeviceIdentity.isValid('corto'), isFalse);
  });

  testWidgets('PinField: solo cifre, al massimo 6', (tester) async {
    final TextEditingController c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: PinField(controller: c, label: 'PIN')),
      ),
    );
    await tester.enterText(find.byType(TextField), '12ab345678');
    expect(c.text, '123456');
  });
}

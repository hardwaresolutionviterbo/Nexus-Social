import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/app.dart';
import 'package:nexus_social/core/services/auth_gateway.dart';
import 'package:nexus_social/features/onboarding/registration_rules.dart';

import '../support/app_helpers.dart';
import '../support/fake_auth_gateway.dart';

/// Controllo d'accesso (Fase 2, Blocco 1): onboarding, collegamento, uscita.
void main() {
  late FakeAuthGateway gateway;

  setUp(() => gateway = FakeAuthGateway());
  tearDown(() => gateway.close());

  testWidgets('senza Firebase (nessun accesso configurato) l\'app resta come in Fase 1', (tester) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Registrati come Privato'), findsNothing);
  });

  testWidgets('nessun utente: si apre la registrazione', (tester) async {
    await tester.pumpWidget(NexusApp(authGateway: gateway));
    await tester.pumpAndSettle();
    expect(find.text('Registrati come Privato'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('utente già collegato: ruolo verificato, poi l\'app si apre su Chat', (tester) async {
    gateway.uid = 'utenteProva';
    await tester.pumpWidget(NexusApp(authGateway: gateway));
    await tester.pumpAndSettle();
    expect(gateway.calls, <String>['ensureLinked']);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Chat e chiamate'), findsOneWidget);
  });

  testWidgets('collegamento non riuscito: messaggio, «Riprova» funziona', (tester) async {
    gateway
      ..uid = 'utenteProva'
      ..failLink = const AuthFailure('Il server non riconosce ancora il tuo accesso. Riprova tra poco.');
    await tester.pumpWidget(NexusApp(authGateway: gateway));
    await tester.pumpAndSettle();
    expect(find.text('Accesso non completato'), findsOneWidget);
    expect(find.textContaining('non riconosce ancora'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    gateway.failLink = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('dal codice SMS all\'app: collegamento automatico', (tester) async {
    await tester.pumpWidget(NexusApp(authGateway: gateway));
    await tester.pumpAndSettle();
    await gateway.confirmCode(const CodeRequest('verifica-prova'), '123456');
    await tester.pumpAndSettle();
    expect(gateway.calls, <String>['confirmCode:123456', 'ensureLinked']);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Profilo: «Esci» con conferma, poi di nuovo la registrazione', (tester) async {
    gateway.uid = 'utenteProva';
    RegistrationDraftStore.current = RegistrationDraft(
      kind: AccountKind.private,
      birthDate: DateTime(2001, 5, 24),
      termsAcceptedAt: DateTime(2026, 11, 14),
    );
    await tester.pumpWidget(NexusApp(authGateway: gateway));
    await tester.pumpAndSettle();
    await openSection(tester, 'Profilo');
    expect(find.text('Accesso effettuato'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Esci'));
    await tester.pumpAndSettle();
    expect(find.text('Uscire da Piazly?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Esci'));
    await tester.pumpAndSettle();

    expect(gateway.calls.last, 'signOut');
    expect(RegistrationDraftStore.current, isNull);
    expect(find.text('Registrati come Privato'), findsOneWidget);
  });
}

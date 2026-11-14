import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/services/auth_gateway.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/onboarding/onboarding_flow.dart';
import 'package:nexus_social/features/onboarding/registration_rules.dart';

import '../support/fake_auth_gateway.dart';

/// Registrazione (Fase 2, Blocco 1): R2.1, R2.2, M2, M6, S7, L3.
void main() {
  late FakeAuthGateway gateway;
  RegistrationDraft? draft;

  setUp(() {
    gateway = FakeAuthGateway();
    draft = null;
  });
  tearDown(() => gateway.close());

  Future<void> pumpFlow(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OnboardingFlow(
          gateway: gateway,
          today: () => DateTime(2026, 11, 14),
          onDraftReady: (RegistrationDraft d) => draft = d,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> enterBirthDate(WidgetTester tester, String date) async {
    await tester.enterText(find.byKey(const ValueKey<String>('data-nascita')), date);
    await tapText(tester, 'Avanti');
  }

  FilledButton filled(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

  testWidgets('R2.1 · schermata iniziale: Privato oppure Azienda', (tester) async {
    await pumpFlow(tester);
    expect(find.text('Registrati come Privato'), findsOneWidget);
    expect(find.text('Registrati come Azienda'), findsOneWidget);
    expect(gateway.calls, isEmpty);
  });

  testWidgets('M2 · sotto i 14 anni: bloccato, nessun dato inviato o conservato', (tester) async {
    await pumpFlow(tester);
    await tapText(tester, 'Registrati come Privato');
    await enterBirthDate(tester, '15/11/2012');

    expect(find.text('Non puoi ancora registrarti'), findsOneWidget);
    expect(find.textContaining('Non abbiamo salvato nessun dato'), findsOneWidget);
    expect(gateway.calls, isEmpty);
    expect(draft, isNull);
    expect(find.byKey(const ValueKey<String>('telefono')), findsNothing);

    await tapText(tester, 'Torna all\'inizio');
    await tapText(tester, 'Registrati come Privato');
    final TextField field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('data-nascita')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('M6 · Azienda con meno di 18 anni: bloccata, si può scegliere Privato', (tester) async {
    await pumpFlow(tester);
    await tapText(tester, 'Registrati come Azienda');
    await enterBirthDate(tester, '15/11/2008');

    expect(find.text('Account Azienda solo per maggiorenni'), findsOneWidget);
    expect(gateway.calls, isEmpty);
    expect(draft, isNull);

    await tapText(tester, 'Registrati come Privato');
    expect(find.text('Data di nascita'), findsOneWidget);
  });

  testWidgets('data non valida: messaggio e nessun avanzamento', (tester) async {
    await pumpFlow(tester);
    await tapText(tester, 'Registrati come Privato');
    await enterBirthDate(tester, '31/02/2001');
    expect(find.byKey(const ValueKey<String>('errore')), findsOneWidget);
    expect(find.text('Termini e Privacy'), findsNothing);
  });

  testWidgets('S7 · bozze con avviso; senza accettazione non si prosegue', (tester) async {
    await pumpFlow(tester);
    await tapText(tester, 'Registrati come Privato');
    await enterBirthDate(tester, '24/05/2001');

    expect(find.text('Termini e Privacy'), findsOneWidget);
    expect(find.textContaining('Bozza non validata'), findsOneWidget);
    expect(filled(tester, 'Accetta e continua').onPressed, isNull);

    await tapText(tester, 'Termini d\'uso');
    expect(find.textContaining('Bozza non validata'), findsNWidgets(2));
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('R2.2 · numero +39 e codice SMS; dati solo in memoria', (tester) async {
    await pumpFlow(tester);
    await tapText(tester, 'Registrati come Privato');
    await enterBirthDate(tester, '24/05/2001');
    await tester.tap(find.byKey(const ValueKey<String>('accetto')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Accetta e continua');

    await tester.enterText(find.byKey(const ValueKey<String>('telefono')), '06 1234567');
    await tapText(tester, 'Invia codice');
    expect(find.byKey(const ValueKey<String>('errore')), findsOneWidget);
    expect(gateway.calls, isEmpty);

    await tester.enterText(find.byKey(const ValueKey<String>('telefono')), '300 000 0001');
    await tapText(tester, 'Invia codice');
    expect(gateway.calls, <String>['sendCode:+393000000001']);
    expect(draft!.kind, AccountKind.private);
    expect(draft!.birthDate, DateTime(2001, 5, 24));
    // Il numero completo non compare sullo schermo.
    expect(find.textContaining('3000000001'), findsNothing);
    expect(find.textContaining('••• 001'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('codice')), '000000');
    await tapText(tester, 'Conferma');
    expect(find.text('Codice errato. Controlla e riprova.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('codice')), '123456');
    await tapText(tester, 'Conferma');
    expect(gateway.calls.last, 'confirmCode:123456');
    expect(gateway.uid, 'utenteProva');
  });

  testWidgets('errore del server all\'invio: messaggio chiaro, si può riprovare', (tester) async {
    gateway.failSend = const AuthFailure('Troppi tentativi. Riprova più tardi.');
    await pumpFlow(tester);
    await tapText(tester, 'Registrati come Privato');
    await enterBirthDate(tester, '24/05/2001');
    await tester.tap(find.byKey(const ValueKey<String>('accetto')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Accetta e continua');
    await tester.enterText(find.byKey(const ValueKey<String>('telefono')), '3331234567');
    await tapText(tester, 'Invia codice');

    expect(find.text('Troppi tentativi. Riprova più tardi.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('telefono')), findsOneWidget);
  });
}

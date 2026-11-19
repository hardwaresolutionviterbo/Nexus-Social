import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/app.dart';
import 'package:nexus_social/core/config/app_config.dart';
import 'package:nexus_social/core/services/backend_bootstrap.dart';
import 'package:nexus_social/features/profile/profile_screen.dart';

import '../support/app_helpers.dart';

/// Regola R2: le funzioni esistenti devono restare intatte prima e dopo il restyling.
void main() {
  testWidgets('F1 · le 5 voci esistono e ognuna apre la propria anteprima', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    for (final MapEntry<String, String> section in sectionMarkers.entries) {
      expect(navItem(section.key), findsOneWidget, reason: section.key);
    }
    for (final MapEntry<String, String> section in sectionMarkers.entries) {
      await openSection(tester, section.key);
      final IndexedStack stack = tester.widget<IndexedStack>(
        find.byType(IndexedStack),
      );
      final int selected = tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .selectedIndex;
      expect(stack.index, selected, reason: section.key);
      expect(
        find.text(section.value),
        findsOneWidget,
        reason: '${section.key} deve mostrare «${section.value}»',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('F2 · la campanella è visibile su ogni scheda e apre le notifiche', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    for (final String label in sectionMarkers.keys) {
      await openSection(tester, label);
      expect(find.byTooltip('Notifiche'), findsOneWidget, reason: label);
    }

    await tester.tap(find.byTooltip('Notifiche'));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna notifica per ora'), findsOneWidget);
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets('F3 · con il telefono in modalità ${brightness.name} l\'app usa '
        'lo stesso tema', (WidgetTester tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(const NexusApp());
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(NavigationBar));
      expect(Theme.of(context).brightness, brightness);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('F4 · il Profilo mostra Privato e Azienda (anteprima, come oggi)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();
    await openSection(tester, 'Profilo');
    await tester.scrollUntilVisible(find.text('Azienda'), 200);

    expect(find.text('Privato'), findsOneWidget);
    expect(find.text('Azienda'), findsOneWidget);
    expect(
      find.text('Badge verificato, promozioni e coupon (9,99 €/mese)'),
      findsOneWidget,
    );
  });

  for (final ServiceState state in ServiceState.values) {
    testWidgets('F5 · indicatori dei servizi: stato «${state.name}»', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        NexusApp(backend: BackendStatus(firebase: state, supabase: state)),
      );
      await tester.pumpAndSettle();
      await openSection(tester, 'Profilo');

      final String label = switch (state) {
        ServiceState.connected => 'Collegato',
        ServiceState.failed => 'Errore',
        ServiceState.notConfigured => 'Non configurato',
      };
      expect(find.text('Supabase'), findsOneWidget);
      expect(find.text('Firebase'), findsOneWidget);
      expect(find.text(label), findsNWidgets(2));
      // Nessun indirizzo o chiave dei servizi sullo schermo.
      expect(find.textContaining('http'), findsNothing);
      expect(find.textContaining('supabase.co'), findsNothing);
      expect(find.textContaining('eyJ'), findsNothing);
    });
  }

  testWidgets('F6 · senza Firebase la voce «Diagnostica push» non compare', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ProfileScreen())));
    await tester.pumpAndSettle();
    if (AppConfig.hasFirebase) return; // coperto da f6_push_diagnostics_test.dart
    expect(find.text('Diagnostica push (debug)'), findsNothing);
  });

  testWidgets('F7 · Versione nello stato dei servizi; niente più riquadro «Informazioni»', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();
    await openSection(tester, 'Profilo');
    await tester.scrollUntilVisible(find.text('Versione'), 200);

    expect(find.text(AppInfo.versionLabel), findsOneWidget);
    // Tolti su richiesta del titolare (19/11/2026).
    expect(find.text('Informazioni'), findsNothing);
    expect(find.text(AppInfo.phaseLabel), findsNothing);
    expect(find.text('Posizione approssimata'), findsNothing);
    expect(find.text('Costruito una fase alla volta'), findsNothing);
  });

  for (final bool admin in <bool>[false, true]) {
    testWidgets('F7 · stato dei servizi e versione ${admin ? 'visibili' : 'nascosti'} '
        '${admin ? 'a un amministratore' : 'a un utente normale'}', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProfileScreen(isAdmin: () async => admin)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Stato dei servizi'), admin ? findsOneWidget : findsNothing);
      expect(find.text('Versione'), admin ? findsOneWidget : findsNothing);
      if (!admin) expect(find.text('Diagnostica push (debug)'), findsNothing);
    });
  }

  testWidgets('F11 · Mappa: raggio 1, 5, 10, 30 km, parte da 10 e si cambia', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();
    await openSection(tester, 'Mappa');
    await tester.scrollUntilVisible(find.text('30 km'), 200);
    // Porta i chip sopra la barra di navigazione, che galleggia sul contenuto.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();

    ChoiceChip chip(String label) => tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, label),
    );

    for (final String label in <String>['1 km', '5 km', '10 km', '30 km']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    expect(chip('10 km').selected, isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, '30 km'));
    await tester.pumpAndSettle();

    expect(chip('30 km').selected, isTrue);
    expect(chip('10 km').selected, isFalse);
  });
}

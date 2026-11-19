import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/app.dart';

void main() {
  testWidgets('la barra ha le cinque sezioni e cambia schermata', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final String label in <String>[
      'Mappa',
      'Chat',
      'Stati',
      'Vendita',
      'Profilo',
    ]) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Vendita'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack).first).index, 3);
    expect(find.text('Annunci vicino a te'), findsOneWidget);
  });

  testWidgets('la campanella apre il foglio delle notifiche vuote', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notifiche'));
    await tester.pumpAndSettle();

    expect(find.text('Nessuna notifica per ora'), findsOneWidget);
  });

  testWidgets('il profilo mostra i servizi non configurati', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profilo'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stato dei servizi'), findsOneWidget);
    expect(find.text('Non configurato'), findsNWidgets(2));

    await tester.drag(find.text('Stato dei servizi'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Versione'), findsOneWidget);
  });

  testWidgets('le icone di sistema seguono il tema chiaro e scuro', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    final AppBar lightBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(
      lightBar.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.dark,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(NavigationBar));
    expect(Theme.of(context).brightness, Brightness.dark);
    final AppBar darkBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(
      darkBar.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.light,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profilo'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Non configurato'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

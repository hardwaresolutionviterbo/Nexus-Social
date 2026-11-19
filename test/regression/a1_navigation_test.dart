import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/app.dart';
import 'package:nexus_social/core/theme/app_theme.dart';

/// Ordine della barra deciso dal titolare il 19/11/2026 (sostituisce A1): Chat, Stati,
/// Mappa al centro in arancio, Vendita con dentro Scambia, Profilo; apertura su Chat.
void main() {
  testWidgets('A1 · ordine: Chat, Stati, Mappa, Vendita, Profilo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    final NavigationBar bar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    final List<String> labels = <String>[
      for (final Widget destination in bar.destinations)
        (destination as NavigationDestination).label,
    ];
    expect(labels, <String>['Chat', 'Stati', 'Mappa', 'Vendita', 'Profilo']);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Community'), findsNothing);
  });

  testWidgets('A1 · all\'apertura l\'app mostra Chat', (WidgetTester tester) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    final NavigationBar bar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(bar.selectedIndex, 0);
    expect(find.text('Chat e chiamate'), findsOneWidget);
    expect(find.text('Mappa Sociale'), findsNothing);
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets('A1 · Mappa è il pulsante centrale arancione (${brightness.name})', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(const NexusApp());
      await tester.pumpAndSettle();

      final Finder orangeCircle = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byWidgetPredicate((Widget widget) {
          if (widget is! DecoratedBox) return false;
          final Decoration decoration = widget.decoration;
          return decoration is BoxDecoration &&
              decoration.shape == BoxShape.circle &&
              decoration.gradient == AppColors.orangeGradient;
        }),
      );
      expect(orangeCircle, findsOneWidget);
      expect(
        find.descendant(of: orangeCircle, matching: find.byIcon(Icons.map_rounded)),
        findsOneWidget,
      );

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Mappa')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.text('Mappa Sociale'), findsOneWidget);

      // Scambia ora è dentro Vendita.
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Vendita')));
      await tester.pumpAndSettle();
      expect(find.text('Annunci vicino a te'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('banner_scambia')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('banner_vendi')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('filtro_regalo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

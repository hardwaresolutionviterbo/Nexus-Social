import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Le cinque sezioni della barra (ordine del titolare, 19/11/2026) con un testo che compare solo nella loro schermata.
/// L'elenco non dipende dall'ordine della barra.
const Map<String, String> sectionMarkers = <String, String>{
  'Mappa': 'Mappa Sociale',
  'Chat': 'Chat e chiamate',
  'Stati': 'Stati dei tuoi contatti',
  'Vendita': 'Vendita tra privati',
  'Profilo': 'Stato dei servizi',
};

Finder navItem(String label) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.text(label),
);

Future<void> openSection(WidgetTester tester, String label) async {
  await tester.tap(navItem(label));
  await tester.pumpAndSettle();
}

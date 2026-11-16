import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/app.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/admin/admin_screen.dart';

import '../support/app_helpers.dart';

/// F10 · Anteprima admin: solo anteprima, non raggiungibile, nessun percorso alternativo.
/// I controlli lato server (E1-E8 di TEST_SUPABASE_RLS.md, regole Firestore) sono
/// nei passaggi 1.7 e 1.8; qui si verifica l'app.
void main() {
  List<File> dartSources() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList();

  String rel(File file) => file.path.replaceAll('\\', '/');

  testWidgets('F10 · l\'anteprima admin non ha pulsanti né azioni attive', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const Scaffold(body: AdminScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gestionale Admin'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byWidgetPredicate((Widget w) => w is ButtonStyleButton), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('F10 · nessuna scheda, né la campanella, porta all\'anteprima admin', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NexusApp());
    await tester.pumpAndSettle();

    for (final String label in sectionMarkers.keys) {
      await openSection(tester, label);
      expect(find.byType(AdminScreen), findsNothing, reason: label);
      expect(find.text('Gestionale Admin'), findsNothing, reason: label);
    }
    await tester.tap(find.byTooltip('Notifiche'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminScreen), findsNothing);
  });

  test('F10 · nel codice AdminScreen non è aperta da nessun altro punto', () {
    final List<String> users = <String>[
      for (final File file in dartSources())
        if (file.readAsStringSync().contains('AdminScreen')) rel(file),
    ];
    expect(users, <String>['lib/features/admin/admin_screen.dart']);
  });

  test('F10 · nessuna rotta con nome o link interno che apra schermate', () {
    for (final File file in dartSources()) {
      final String code = file.readAsStringSync();
      for (final String forbidden in <String>[
        'onGenerateRoute',
        'routes:',
        'initialRoute',
        'pushNamed',
        'GoRouter',
        'uni_links',
        'app_links',
      ]) {
        expect(code.contains(forbidden), isFalse, reason: '${rel(file)}: $forbidden');
      }
    }
  });

  test('F10 · aprire una notifica non porta a schermate interne', () {
    for (final File file in dartSources()) {
      final String code = file.readAsStringSync();
      final bool handlesOpen = code.contains('onMessageOpenedApp') ||
          code.contains('getInitialMessage') ||
          code.contains('onDidReceiveNotificationResponse');
      if (!handlesOpen) continue;
      expect(code.contains('Navigator'), isFalse, reason: rel(file));
      expect(code.contains('Admin'), isFalse, reason: rel(file));
    }
  });

  // Elenco chiuso dei file che navigano: ogni aggiunta va rivista e approvata qui.
  // Fase 1: diagnostica push del Profilo. Fase 2: profilo (Blocco 2), Privacy e blocchi
  // (Blocco 3), sicurezza dell'account (Blocco 4). Fase 3, Blocco 2: annunci della Mappa
  // (pubblica, scegli il punto, i miei annunci); Blocco 3: scheda dell'annuncio, filtri e
  // segnalazione. Blocco 4: commenti, interazioni sotto l'annuncio, notifiche. Fase 5,
  // Blocco 1: Scambia & Vendi (sezioni, categoria, pubblica, i miei annunci). Fase 4, Blocco 1:
  // chat (lista, richieste, nuova chat, conversazione). Nessuno apre l'anteprima admin.
  test('F10 · navigazione esplicita solo nei file rivisti (Profilo e Privacy)', () {
    final List<String> users = <String>[
      for (final File file in dartSources())
        if (file.readAsStringSync().contains('Navigator.')) rel(file),
    ]..sort();
    expect(users, <String>[
      'lib/features/chat/chat_screen.dart',
      'lib/features/chat/chat_thread_screen.dart',
      'lib/features/map/comments_screen.dart',
      'lib/features/map/listing_form_screen.dart',
      'lib/features/map/listing_sheets.dart',
      'lib/features/map/listing_social_panel.dart',
      'lib/features/map/map_screen.dart',
      'lib/features/map/my_listings_screen.dart',
      'lib/features/map/notifications_screen.dart',
      'lib/features/map/point_picker_screen.dart',
      'lib/features/market/category_picker.dart',
      'lib/features/market/market_deals_screen.dart',
      'lib/features/market/market_feedback.dart',
      'lib/features/market/market_filters_screen.dart',
      'lib/features/market/market_listing_screen.dart',
      'lib/features/market/market_publish_screen.dart',
      'lib/features/market/market_section_screen.dart',
      'lib/features/market/my_market_screen.dart',
      'lib/features/market/swap_offer_screen.dart',
      'lib/features/market/swap_proposals_screen.dart',
      'lib/features/privacy/privacy_screen.dart',
      'lib/features/privacy/privacy_sections.dart',
      'lib/features/profile/profile_screen.dart',
      'lib/features/profile/public_profile_screen.dart',
      'lib/features/security/security_screens.dart',
    ]);
  });
}

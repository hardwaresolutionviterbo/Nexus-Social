import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/comments_screen.dart';
import 'package:nexus_social/features/map/listing_models.dart' show ReportReason;
import 'package:nexus_social/features/map/social_models.dart';

import '../support/fake_social.dart';

/// Fase 5, Blocco 5 · Commenti completi (D8, D9), uguali sulla Mappa e in Scambia & Vendi.
void main() {
  late FakeSocialRepository social;

  Future<void> open(WidgetTester tester, List<ListingComment> comments) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    social = FakeSocialRepository()..items.addAll(comments);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: CommentsScreen(
        listingId: 'n1',
        listingTitle: 'Console PS4 con giochi',
        repository: social,
        now: () => DateTime(2026, 11, 15, 11),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String id, String action) async {
    await tester.tap(find.byKey(ValueKey<String>('menu_commento_$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('azione_$action')));
    await tester.pumpAndSettle();
  }

  testWidgets('modifica del proprio commento, poi «modificato»', (WidgetTester tester) async {
    await open(tester, <ListingComment>[
      commentBy('a', 'Io', 'Li scambieresti con dei gialli?', isMine: true, canDelete: true),
      commentBy('b', 'Carlo', 'Interessa anche a me', minute: 5),
    ]);
    // Sul commento altrui non c'è «Modifica».
    await tester.tap(find.byKey(const ValueKey<String>('menu_commento_b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('azione_modifica')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await menu(tester, 'a', 'modifica');
    expect(find.byKey(const ValueKey<String>('modifica_in_corso')), findsOneWidget);
    final TextField field = tester.widget<TextField>(find.byKey(const ValueKey<String>('nuovo_commento')));
    expect(field.controller!.text, 'Li scambieresti con dei gialli?');
    await tester.enterText(find.byKey(const ValueKey<String>('nuovo_commento')), 'Li scambieresti con tre gialli?');
    await tester.tap(find.byKey(const ValueKey<String>('invia_commento')));
    await tester.pumpAndSettle();
    expect(social.calls, contains('edit:a:Li scambieresti con tre gialli?'));
    expect(find.text('Li scambieresti con tre gialli?'), findsOneWidget);
    expect(find.textContaining('modificato'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('modifica_in_corso')), findsNothing);
  });

  testWidgets('chi gestisce l\'annuncio nasconde: niente Mi piace né risposte, poi lo rimostra', (
    WidgetTester tester,
  ) async {
    await open(tester, <ListingComment>[
      commentBy('b', 'Carlo', 'Vendo anche io, scrivimi su un altro sito', canHide: true, canDelete: true),
    ]);
    expect(find.text('Mi piace'), findsOneWidget);
    await menu(tester, 'b', 'nascondi');
    expect(social.calls, contains('hidden:b:true'));
    expect(find.byKey(const ValueKey<String>('nascosto_b')), findsOneWidget);
    expect(find.text('Commento nascosto.'), findsOneWidget);
    expect(find.text('Mi piace'), findsNothing);
    expect(find.text('Rispondi'), findsNothing);
    await menu(tester, 'b', 'nascondi');
    expect(social.calls, contains('hidden:b:false'));
    expect(find.text('Mi piace'), findsOneWidget);
  });

  testWidgets('per gli altri un commento nascosto resta al suo posto, senza testo', (WidgetTester tester) async {
    await open(tester, <ListingComment>[
      commentBy('b', 'Carlo', '', hidden: true),
    ]);
    expect(find.text('Carlo'), findsOneWidget);
    expect(find.text('Commento nascosto dall\'autore dell\'annuncio'), findsOneWidget);
    expect(find.text('Mi piace'), findsNothing);
    expect(find.text('Rispondi'), findsNothing);
  });

  testWidgets('segnalare un commento alla moderazione', (WidgetTester tester) async {
    await open(tester, <ListingComment>[commentBy('b', 'Carlo', 'Pagami fuori dall\'app')]);
    await menu(tester, 'b', 'segnala');
    expect(find.text('Segnala commento'), findsOneWidget);
    await tester.tap(find.text(ReportReason.scam.label));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey<String>('invia_segnalazione')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('invia_segnalazione')));
    await tester.pumpAndSettle();
    expect(social.calls, contains('reportComment:b:${ReportReason.scam.serverValue}'));
    expect(find.textContaining('segnalazione è stata inviata'), findsOneWidget);
  });

  testWidgets('anti-spam: il messaggio del server si vede', (WidgetTester tester) async {
    await open(tester, const <ListingComment>[]);
    social.failWith = 'Stai commentando troppo in fretta: riprova tra un minuto';
    await tester.enterText(find.byKey(const ValueKey<String>('nuovo_commento')), 'Ciao');
    await tester.tap(find.byKey(const ValueKey<String>('invia_commento')));
    await tester.pumpAndSettle();
    expect(find.text('Stai commentando troppo in fretta: riprova tra un minuto'), findsOneWidget);
  });
}

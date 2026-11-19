import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/comments_screen.dart';
import 'package:nexus_social/features/map/listing_form_screen.dart';
import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/listing_share.dart';
import 'package:nexus_social/features/map/listing_sheets.dart';
import 'package:nexus_social/features/map/notifications_screen.dart';
import 'package:nexus_social/features/map/social_models.dart';
import 'package:nexus_social/features/shell/app_shell.dart';

import '../support/fake_listings.dart';
import '../support/fake_map.dart';
import '../support/fake_social.dart';

/// Fase 3, Blocco 4 · Eventi di gruppo e interazioni come Facebook: Partecipo,
/// Mi piace / Non mi piace con elenchi, commenti con risposte, Condividi, notifiche.
void main() {
  final DateTime now = DateTime(2026, 11, 15, 10, 30);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('Regole', () {
    test('«mancano N persone»', () {
      expect(missingLabel(3, 0), 'Mancano 3 persone');
      expect(missingLabel(3, 2), 'Manca 1 persona');
      expect(missingLabel(3, 3), 'Al completo');
      const ListingSocial s = ListingSocial(groupSpots: 4, participants: 1);
      expect(s.isEvent, isTrue);
      expect(s.missing, 3);
      expect(const ListingSocial().isEvent, isFalse);
    });

    test('una sola reazione per persona: si cambia o si toglie', () {
      const ListingSocial s = ListingSocial(likes: 2, dislikes: 1);
      final ListingSocial liked = s.withReaction(Reaction.like);
      expect((liked.likes, liked.dislikes, liked.myReaction), (3, 1, Reaction.like));
      final ListingSocial switched = liked.withReaction(Reaction.dislike);
      expect((switched.likes, switched.dislikes), (2, 2));
      final ListingSocial removed = switched.withReaction(null);
      expect((removed.likes, removed.dislikes, removed.myReaction), (2, 1, null));
    });

    test('commenti in fili: principali in ordine, risposte sotto', () {
      final List<(ListingComment, List<ListingComment>)> t = threadComments(<ListingComment>[
        commentBy('b', 'Bruno', 'secondo', minute: 5),
        commentBy('r1', 'Rita', 'risposta', parentId: 'a', minute: 7),
        commentBy('a', 'Anna', 'primo', minute: 1),
        commentBy('r0', 'Ugo', 'prima risposta', parentId: 'a', minute: 3),
      ]);
      expect(t.map(((ListingComment, List<ListingComment>) e) => e.$1.id), <String>['a', 'b']);
      expect(t.first.$2.map((ListingComment c) => c.id), <String>['r0', 'r1']);
      expect(t.last.$2, isEmpty);
    });

    test('testo delle notifiche, con i Mi piace raggruppati', () {
      expect(notificationOf('1', NotificationKind.listingLike, count: 3).text,
          'Giulia B. e altre 2 persone hanno messo Mi piace al tuo annuncio «Calcetto stasera»');
      expect(notificationOf('2', NotificationKind.listingLike, count: 2).text,
          'Giulia B. e un\'altra persona hanno messo Mi piace al tuo annuncio «Calcetto stasera»');
      expect(notificationOf('3', NotificationKind.listingComment).text,
          'Giulia B. ha commentato il tuo annuncio «Calcetto stasera»');
      expect(notificationOf('4', NotificationKind.commentReply).text,
          'Giulia B. ha risposto al tuo commento su «Calcetto stasera»');
      expect(notificationOf('5', NotificationKind.followedComment).text,
          'Giulia B. ha commentato «Calcetto stasera», che segui');
      expect(notificationOf('6', NotificationKind.commentLike).text,
          'Giulia B. ha messo Mi piace al tuo commento su «Calcetto stasera»');
    });

    test('Condividi: testo dell\'annuncio, mai posizione né distanza', () {
      final NearbyListing l = sampleNearby();
      final String text = ListingShare.text(
        l,
        social: const ListingSocial(groupSpots: 3, participants: 1),
      );
      expect(text, contains('«Ci manca uno per il calcetto, chi viene?»'));
      expect(text, contains('Campo del quartiere, ore 21'));
      expect(text, contains('Mancano 2 persone'));
      expect(text, contains('Piazly'));
      expect(text, isNot(contains('43.77')));
      expect(text, isNot(contains('11.25')));
      expect(text, isNot(contains('km')));
    });
  });

  group('Sotto l\'annuncio', () {
    Future<(FakeSocialRepository, List<String>)> pumpDetail(
      WidgetTester tester, {
      NearbyListing? listing,
      ListingSocial initial = const ListingSocial(likes: 2, dislikes: 1),
    }) async {
      phone(tester);
      final FakeSocialRepository social = FakeSocialRepository(initial: initial);
      final List<String> shared = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListingDetail(
            listing: listing ?? sampleNearby(),
            now: now,
            services: ListingSheetServices(
              listings: FakeListingRepository(),
              social: social,
              share: (String text, {Uint8List? photo}) async => shared.add(text),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return (social, shared);
    }

    String countOf(WidgetTester tester, String key) => tester
        .widget<Text>(find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Text),
        ))
        .data!;

    testWidgets('Mi piace / Non mi piace: una sola reazione, si cambia o si toglie', (
      WidgetTester tester,
    ) async {
      final (FakeSocialRepository social, _) = await pumpDetail(tester);
      expect(countOf(tester, 'conteggio_mi_piace'), '2');

      await tester.tap(find.byKey(const ValueKey<String>('mi_piace')));
      await tester.pumpAndSettle();
      expect(countOf(tester, 'conteggio_mi_piace'), '3');

      await tester.tap(find.byKey(const ValueKey<String>('non_mi_piace')));
      await tester.pumpAndSettle();
      expect(countOf(tester, 'conteggio_mi_piace'), '2');
      expect(countOf(tester, 'conteggio_non_mi_piace'), '2');

      await tester.tap(find.byKey(const ValueKey<String>('non_mi_piace')));
      await tester.pumpAndSettle();
      expect(countOf(tester, 'conteggio_non_mi_piace'), '1');
      expect(social.calls.where((String c) => c.startsWith('react:')),
          <String>['react:like', 'react:dislike', 'react:null']);
    });

    testWidgets('toccando i conteggi si vede chi ha messo Mi piace', (WidgetTester tester) async {
      phone(tester);
      final (FakeSocialRepository social, _) = await pumpDetail(tester);
      social.lists[PeopleList.likes] = const <PersonRef>[
        PersonRef(id: 'a', username: 'anna_v', publicName: 'Anna V.'),
        PersonRef(id: 'b', username: 'bruno_c', publicName: 'Bruno C.'),
      ];
      await tester.tap(find.byKey(const ValueKey<String>('conteggio_mi_piace')));
      await tester.pumpAndSettle();
      expect(find.text('Anna V.'), findsOneWidget);
      expect(find.text('@bruno_c'), findsOneWidget);
    });

    testWidgets('evento di gruppo: Partecipo, «mancano N persone», poi «Non partecipo più»', (
      WidgetTester tester,
    ) async {
      final (FakeSocialRepository social, _) = await pumpDetail(
        tester,
        initial: const ListingSocial(groupSpots: 3, participants: 1),
      );
      expect(find.text('Mancano 2 persone'), findsOneWidget);
      expect(find.text('1 su 3 partecipa'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey<String>('partecipo')));
      await tester.tap(find.byKey(const ValueKey<String>('partecipo')));
      await tester.pumpAndSettle();
      expect(social.calls, contains('join'));
      expect(find.text('Manca 1 persona'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('non_partecipo')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('non_partecipo')));
      await tester.pumpAndSettle();
      expect(social.calls, contains('leave'));
      expect(find.text('Mancano 2 persone'), findsOneWidget);
    });

    testWidgets('evento al completo: «Partecipo» non si può toccare', (WidgetTester tester) async {
      await pumpDetail(tester, initial: const ListingSocial(groupSpots: 2, participants: 2));
      expect(find.text('Al completo'), findsWidgets);
      final FilledButton b = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('partecipo')),
      );
      expect(b.onPressed, isNull);
    });

    testWidgets('il proprio evento: nessun «Partecipo», ma «Disattiva notifiche per questo post»', (
      WidgetTester tester,
    ) async {
      final (FakeSocialRepository social, _) = await pumpDetail(
        tester,
        listing: sampleNearby(isMine: true),
        initial: const ListingSocial(groupSpots: 3, participants: 2, following: true),
      );
      expect(find.byKey(const ValueKey<String>('partecipo')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey<String>('silenzia_post')));
      await tester.tap(find.byKey(const ValueKey<String>('silenzia_post')));
      await tester.pumpAndSettle();
      expect(social.calls, contains('muted:true'));
      expect(find.text('Riattiva notifiche per questo post'), findsOneWidget);
    });

    testWidgets('Condividi: apre la condivisione con il testo dell\'annuncio', (
      WidgetTester tester,
    ) async {
      final (_, List<String> shared) = await pumpDetail(tester);
      await tester.tap(find.byKey(const ValueKey<String>('condividi')));
      await tester.pumpAndSettle();
      expect(shared.single, contains('«Ci manca uno per il calcetto, chi viene?»'));
      expect(shared.single, isNot(contains('43.77')));
    });

    testWidgets('senza server delle interazioni resta solo «Condividi»', (
      WidgetTester tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListingDetail(
            listing: sampleNearby(),
            now: now,
            services: ListingSheetServices(listings: FakeListingRepository()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('condividi')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('mi_piace')), findsNothing);
    });

    testWidgets('«Commenta» apre i commenti; al ritorno il conteggio è aggiornato', (
      WidgetTester tester,
    ) async {
      final (FakeSocialRepository social, _) = await pumpDetail(tester);
      await tester.tap(find.byKey(const ValueKey<String>('commenta')));
      await tester.pumpAndSettle();
      expect(find.text('Commenti'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('nuovo_commento')), 'Io ci sono!');
      await tester.tap(find.byKey(const ValueKey<String>('invia_commento')));
      await tester.pumpAndSettle();
      expect(social.calls, contains('comment:Io ci sono!:-'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(countOf(tester, 'conteggio_commenti'), '1 commento');
    });
  });

  group('Commenti', () {
    Future<FakeSocialRepository> pumpComments(WidgetTester tester, {String? highlight}) async {
      phone(tester);
      final FakeSocialRepository social = FakeSocialRepository();
      social.items.addAll(<ListingComment>[
        commentBy('a', 'Anna', 'Io ci sono!', minute: 1, likes: 2),
        commentBy('r', 'Bruno', 'Anche io', parentId: 'a', minute: 3, canDelete: true),
        commentBy('b', 'Carlo', 'A che ora?', minute: 5),
      ]);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: CommentsScreen(
          listingId: 'n1',
          listingTitle: 'Calcetto stasera',
          repository: social,
          highlightCommentId: highlight,
          now: () => now,
        ),
      ));
      await tester.pumpAndSettle();
      return social;
    }

    testWidgets('commenti e risposte sotto il commento principale', (WidgetTester tester) async {
      await pumpComments(tester);
      expect(find.text('Calcetto stasera'), findsOneWidget);
      final double anna = tester.getTopLeft(find.text('Io ci sono!')).dy;
      final double bruno = tester.getTopLeft(find.text('Anche io')).dy;
      final double carlo = tester.getTopLeft(find.text('A che ora?')).dy;
      expect(anna < bruno && bruno < carlo, isTrue);
      // La risposta è rientrata rispetto al commento principale.
      expect(tester.getTopLeft(find.text('Anche io')).dx,
          greaterThan(tester.getTopLeft(find.text('Io ci sono!')).dx));
      expect(find.text('Mi piace · 2'), findsOneWidget);
    });

    testWidgets('«Rispondi»: la risposta va nel filo del commento', (WidgetTester tester) async {
      final FakeSocialRepository social = await pumpComments(tester);
      await tester.tap(find.text('Rispondi').at(1)); // risposta di Bruno, nel filo di Anna
      await tester.pumpAndSettle();
      expect(find.text('Rispondi a Bruno'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('nuovo_commento')), 'A stasera');
      await tester.tap(find.byKey(const ValueKey<String>('invia_commento')));
      await tester.pumpAndSettle();
      expect(social.calls, contains('comment:A stasera:a'));
      expect(find.byKey(const ValueKey<String>('risposta_a')), findsNothing);
    });

    testWidgets('Mi piace a un commento ed eliminazione con conferma', (
      WidgetTester tester,
    ) async {
      final FakeSocialRepository social = await pumpComments(tester);
      await tester.tap(find.text('Mi piace').first);
      await tester.pumpAndSettle();
      expect(social.calls, contains('likeComment:r:true'));

      expect(find.text('Elimina'), findsOneWidget); // solo dove è permesso
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Elimina'));
      await tester.pumpAndSettle();
      expect(social.calls, contains('delete:r'));
      expect(find.text('Anche io'), findsNothing);
    });

    testWidgets('aperto da una notifica: il commento è evidenziato', (WidgetTester tester) async {
      await pumpComments(tester, highlight: 'b');
      final Container box = tester.widget<Container>(
        find.byKey(const ValueKey<String>('commento_b')),
      );
      final BoxDecoration d = box.decoration! as BoxDecoration;
      expect(d.color, AppColors.brandAmber.withValues(alpha: 0.25));
    });
  });

  group('Notifiche', () {
    testWidgets('campanella: contatore, elenco, lette all\'apertura, tocco sul post', (
      WidgetTester tester,
    ) async {
      phone(tester);
      final FakeSocialRepository social = FakeSocialRepository();
      social.inbox.addAll(<AppNotification>[
        notificationOf('1', NotificationKind.listingLike, count: 3),
        notificationOf('2', NotificationKind.commentReply, commentId: 'b'),
        notificationOf('3', NotificationKind.listingComment, read: true),
      ]);
      social.items.add(commentBy('b', 'Giulia', 'Ci vediamo alle 21'));
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: AppShell(social: social)));
      await tester.pumpAndSettle();

      final Badge badge = tester.widget<Badge>(
        find.descendant(of: find.byTooltip('Notifiche'), matching: find.byType(Badge)),
      );
      expect(badge.isLabelVisible, isTrue);
      expect((badge.label! as Text).data, '2');

      await tester.tap(find.byTooltip('Notifiche'));
      await tester.pumpAndSettle();
      expect(find.text('Notifiche'), findsWidgets);
      expect(
        find.text('Giulia B. e altre 2 persone hanno messo Mi piace al tuo annuncio «Calcetto stasera»'),
        findsOneWidget,
      );
      expect(social.calls, contains('markAllRead'));

      await tester.tap(find.text('Giulia B. ha risposto al tuo commento su «Calcetto stasera»'));
      await tester.pumpAndSettle();
      expect(find.text('Ci vediamo alle 21'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final Badge after = tester.widget<Badge>(
        find.descendant(of: find.byTooltip('Notifiche'), matching: find.byType(Badge)),
      );
      expect(after.isLabelVisible, isFalse);
    });

    testWidgets('Fase 4 · notifica toccata ad app chiusa: si apre subito il commento', (WidgetTester tester) async {
      phone(tester);
      final FakeSocialRepository social = FakeSocialRepository()
        ..inbox.addAll(<AppNotification>[
          notificationOf('2', NotificationKind.commentReply, commentId: 'b'),
        ]);
      social.items.add(commentBy('b', 'Giulia', 'Ci vediamo alle 21'));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: NotificationsScreen(repository: social, now: () => now, openId: '2'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Ci vediamo alle 21'), findsOneWidget);
      expect(social.calls, contains('markAllRead'));
    });

    testWidgets('nessuna notifica: messaggio vuoto', (WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: NotificationsScreen(repository: FakeSocialRepository(), now: () => now),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Nessuna notifica per ora'), findsOneWidget);
    });
  });

  group('Pubblicare un evento', () {
    testWidgets('«Evento di gruppo» con le persone cercate', (WidgetTester tester) async {
      phone(tester);
      final FakeListingRepository repo = FakeListingRepository();
      final List<Object?> results = <Object?>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => TextButton(
              onPressed: () async => results.add(await Navigator.of(ctx).push<Object?>(
                MaterialPageRoute<Object?>(
                  builder: (_) => ListingFormScreen(
                    repository: repo,
                    surface: FakeMap().services.surface,
                    currentPosition: const GeoPoint(43.7696, 11.2558),
                    now: () => now,
                  ),
                ),
              )),
              child: const Text('apri'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('annuncio_testo')), 'Ci mancano due per il calcetto');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final Finder toggle = find.byKey(const ValueKey<String>('evento_gruppo'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('evento_posti')), findsOneWidget);
      await tester.tap(find.byTooltip('Una persona in meno'));
      await tester.pumpAndSettle();

      final Finder publish = find.byKey(const ValueKey<String>('annuncio_pubblica'));
      await tester.ensureVisible(publish);
      await tester.pumpAndSettle();
      await tester.tap(publish);
      await tester.pumpAndSettle();
      expect(repo.published.single.groupSpots, 2);
      expect(results, <Object?>[true]);
    });
  });
}

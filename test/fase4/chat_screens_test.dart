// Fase 4 · Blocco 1: schermate della chat (lista, conversazione, richieste, nuova chat,
// «Contatta» dagli annunci) con un server finto e una cifratura finta.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_screen.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_thread_screen.dart';

import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String dario = 'utenteDario00000000000000004';

Widget app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void main() {
  late FakeChatHub hub;
  final DateTime now = DateTime(2026, 11, 16, 19);

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..addPerson(dario, 'dario88', 'Dario V.')
      ..contacts[io] = <String>{bruno}
      ..contacts[bruno] = <String>{io};
  });

  /// Smonta le schermate e poi chiude i telefoni finti (nessun timer rimasto).
  Future<void> finish(WidgetTester tester, List<ChatService> phones) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    for (final ChatService p in phones) {
      p.dispose();
    }
  }

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('senza server: resta l\'anteprima della Fase 4', (WidgetTester tester) async {
    await tester.pumpWidget(app(const Scaffold(body: ChatScreen())));
    expect(find.text('Chat e chiamate'), findsOneWidget);
  });

  testWidgets('lista vuota, poi «Nuova chat» dalla rubrica e primo messaggio', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    await tester.pumpWidget(app(Scaffold(body: ChatScreen(service: me, now: () => now))));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna chat per ora'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('chat_nuova')));
    await tester.pumpAndSettle();
    expect(find.text('Contatti su Piazly'), findsOneWidget);
    expect(find.text('@bruno_b'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('contatto_$bruno')));
    await tester.pumpAndSettle();

    // Conversazione aperta: nessun numero, solo nome e @nome utente.
    expect(find.text('Bruno B.'), findsOneWidget);
    expect(find.textContaining('cifrati end-to-end'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('chat_testo')), 'Ciao Bruno!');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('chat_invia')));
    await tester.pumpAndSettle();
    expect(find.text('Ciao Bruno!'), findsOneWidget);
    expect(find.byIcon(Icons.done_rounded), findsOneWidget, reason: 'una spunta: inviato');

    await b.refresh();
    expect(b.messages(b.threads.single.conversation.id).single.body, 'Ciao Bruno!');
    await me.refresh();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget, reason: 'due spunte: consegnato');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Ciao Bruno!'), findsOneWidget, reason: 'anteprima nella lista');
    await finish(tester, <ChatService>[me, b]);
  });

  testWidgets('messaggio in arrivo: contatore, apertura e «letto» per chi scrive', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final String conv = await b.openDirect(io);
    await b.send(conv, 'Ci sei domani?');
    await me.refresh();
    await tester.pumpWidget(app(Scaffold(body: ChatScreen(service: me, now: () => now))));
    await tester.pumpAndSettle();
    expect(find.text('Ci sei domani?'), findsOneWidget);
    expect(me.unreadTotal, 1);

    await tester.tap(find.byKey(ValueKey<String>('chat_$conv')));
    await tester.pumpAndSettle();
    expect(me.unreadTotal, 0);
    await b.refresh();
    expect(b.messages(conv).single.ticksFor(b.conversation(conv)), MessageTicks.read);
    await finish(tester, <ChatService>[me, b]);
  });

  testWidgets('richiesta da uno sconosciuto: banner, Accetta', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService d = await fakePhone(hub, dario);
    final String conv = await d.openDirect(io);
    await d.send(conv, 'Ciao, è ancora disponibile la bici?');
    await me.refresh();
    await tester.pumpWidget(app(Scaffold(body: ChatScreen(service: me, now: () => now))));
    await tester.pumpAndSettle();
    expect(find.text('Richieste di messaggio'), findsOneWidget);
    expect(find.text('Nessuna chat per ora'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('chat_richieste')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('chat_$conv')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('richiesta_banner')), findsOneWidget);
    expect(find.text('Dario V. vuole scriverti'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('richiesta_accetta')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('richiesta_banner')), findsNothing);
    expect(me.requests, isEmpty);
    expect(me.threads.single.conversation.id, conv);
    await finish(tester, <ChatService>[me, d]);
  });

  testWidgets('richiesta rifiutata: si chiude e sparisce', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService d = await fakePhone(hub, dario);
    final String conv = await d.openDirect(io);
    await d.send(conv, 'Messaggio indesiderato');
    await me.refresh();
    await tester.pumpWidget(app(Scaffold(
      body: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => ChatThreadScreen.open(context, chat: me, conversationId: conv),
          child: const Text('apri'),
        ),
      ),
    )));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('richiesta_rifiuta')));
    await tester.pumpAndSettle();
    expect(find.text('apri'), findsOneWidget);
    expect(me.requests, isEmpty);
    await finish(tester, <ChatService>[me, d]);
  });

  testWidgets('«Contatta» da un annuncio apre la chat con l\'autore', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService d = await fakePhone(hub, dario);
    ChatRegistry.current = me;
    addTearDown(() => ChatRegistry.current = null);
    await tester.pumpWidget(app(Scaffold(
      body: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => openChatWith(context, userId: dario, name: 'Dario V.'),
          child: const Text('Contatta'),
        ),
      ),
    )));
    await tester.tap(find.text('Contatta'));
    await tester.pumpAndSettle();
    expect(find.text('Dario V.'), findsOneWidget);
    expect(find.text('@dario88'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('chat_testo')), 'Ciao, mi interessa');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('chat_invia')));
    await tester.pumpAndSettle();
    await d.refresh();
    // Dario non ha Anna in rubrica: per lui è una richiesta.
    expect(d.requests.single.last?.body, 'Ciao, mi interessa');
    await finish(tester, <ChatService>[me, d]);
  });

  testWidgets('Blocco 2 · tieni premuto: rispondi, reazione, elimina per tutti, inoltra', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final String conv = await b.openDirect(io);
    await b.send(conv, 'Domani alle 18?');
    await me.refresh();
    await tester.pumpWidget(app(Scaffold(
      body: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => ChatThreadScreen.open(context, chat: me, conversationId: conv),
          child: const Text('apri'),
        ),
      ),
    )));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    // Rispondi.
    await tester.longPress(find.text('Domani alle 18?'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('azione_inoltra')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reazione_👍')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('azione_rispondi')));
    await tester.pumpAndSettle();
    expect(find.text('Rispondi a Bruno B.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('chat_testo')), 'Perfetto');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('chat_invia')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('risposta_barra')), findsNothing);
    expect(find.text('Domani alle 18?'), findsNWidgets(2), reason: 'messaggio e citazione');
    await b.refresh();
    expect(b.messages(conv).last.quote?.authorId, bruno);

    // Reazione al messaggio di Bruno (l'ultimo trovato: la lista parte dal basso e il primo
    // è la citazione dentro la risposta).
    await tester.longPress(find.text('Domani alle 18?').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reazione_❤️')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('reazioni')), findsOneWidget);
    await b.refresh();
    expect(b.messages(conv).first.peerReaction, '❤️');

    // Elimina per tutti il proprio messaggio.
    await tester.longPress(find.text('Perfetto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('azione_elimina')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('elimina_per_tutti')));
    await tester.pumpAndSettle();
    expect(find.text('Hai eliminato questo messaggio'), findsOneWidget);
    await b.refresh();
    expect(b.messages(conv).last.deleted, isTrue);

    // Inoltra: si sceglie la chat e si invia.
    await tester.longPress(find.text('Domani alle 18?').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('azione_inoltra')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('inoltra_$conv')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('inoltra_invia')));
    await tester.pumpAndSettle();
    expect(find.text('Messaggio inoltrato'), findsOneWidget);
    expect(find.text('Inoltrato'), findsOneWidget);
    await finish(tester, <ChatService>[me, b]);
  });

  test('etichette dell\'ora come WhatsApp', () {
    final DateTime n = DateTime(2026, 11, 16, 19);
    expect(chatTimeLabel(DateTime(2026, 11, 16, 8, 5), n), '08:05');
    expect(chatTimeLabel(DateTime(2026, 11, 15, 23), n), 'Ieri');
    expect(chatTimeLabel(DateTime(2026, 11, 2), n), '2/11');
    expect(chatTimeLabel(DateTime(2025, 3, 9), n), '9/3/25');
  });
}

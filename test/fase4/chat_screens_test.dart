// Fase 4 · Blocco 1: schermate della chat (lista, conversazione, richieste, nuova chat,
// «Contatta» dagli annunci) con un server finto e una cifratura finta.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/chat/chat_group_screens.dart';
import 'package:nexus_social/features/chat/chat_media.dart';
import 'package:nexus_social/features/chat/chat_media_picker.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_screen.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_thread_screen.dart';

import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String dario = 'utenteDario00000000000000004';

/// Telefono finto: niente fotocamera vera, niente microfono vero.
class FakeDevice implements ChatDevice {
  FakeDevice({this.micAllowed = true});

  final bool micAllowed;
  int voiceStarts = 0;
  bool cancelled = false;

  @override
  Future<PickedMedia?> pickImage({required bool camera}) async => null;

  @override
  Future<PickedMedia?> pickVideo() async => throw const ChatFailure('Video troppo pesante (80,0 MB): massimo 50 MB.');

  @override
  Future<PickedMedia?> pickFile() async => PickedMedia(
    kind: MediaKind.file,
    bytes: Uint8List.fromList(<int>[1, 2, 3]),
    mime: 'application/pdf',
    name: 'preventivo.pdf',
  );

  @override
  Future<bool> startVoice() async {
    voiceStarts++;
    return micAllowed;
  }

  @override
  Future<PickedMedia?> stopVoice() async => PickedMedia(
    kind: MediaKind.audio,
    bytes: Uint8List.fromList(<int>[4, 5, 6]),
    mime: 'audio/mp4',
    durationMs: 3000,
  );

  @override
  Future<void> cancelVoice() async => cancelled = true;
}

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
    // Anche i messaggi a comparsa (4 secondi) devono chiudersi.
    await tester.pump(const Duration(seconds: 5));
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

  testWidgets('Blocco 3 · graffetta e microfono: scelta, anteprima, registrazione', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final String conv = await me.openDirect(bruno);
    final FakeDevice device = FakeDevice();
    await tester.pumpWidget(app(ChatThreadScreen(chat: me, conversationId: conv, device: device)));
    await tester.pumpAndSettle();

    // Campo vuoto: microfono al posto di «Invia».
    expect(find.byKey(const ValueKey<String>('chat_vocale')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chat_invia')), findsNothing);

    // Graffetta → le quattro scelte.
    await tester.tap(find.byKey(const ValueKey<String>('chat_allega')));
    await tester.pumpAndSettle();
    for (final String k in <String>['galleria', 'fotocamera', 'video', 'documento']) {
      expect(find.byKey(ValueKey<String>('allega_$k')), findsOneWidget);
    }
    expect(find.textContaining('Massimo 50 MB'), findsOneWidget);

    // Video troppo pesante: messaggio chiaro, nessun invio.
    await tester.tap(find.byKey(const ValueKey<String>('allega_video')));
    await tester.pumpAndSettle();
    expect(find.textContaining('massimo 50 MB'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Documento → anteprima con nome e peso → Invia.
    await tester.tap(find.byKey(const ValueKey<String>('chat_allega')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('allega_documento')));
    await tester.pumpAndSettle();
    expect(find.text('Invia a Bruno B.'), findsOneWidget);
    expect(find.textContaining('preventivo.pdf'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('anteprima_invia')));
    await tester.pumpAndSettle();
    // In questo test il telefono finto non ha la cartella degli allegati.
    expect(find.text('Allegati non disponibili.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Vocale: barra di registrazione, annulla.
    await tester.tap(find.byKey(const ValueKey<String>('chat_vocale')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('registrazione')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey<String>('registrazione_annulla')));
    await tester.pump();
    expect(device.cancelled, isTrue);
    expect(find.byKey(const ValueKey<String>('registrazione')), findsNothing);
    await finish(tester, <ChatService>[me, b]);
  });

  testWidgets('Blocco 3 · microfono negato: si spiega come attivarlo', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final String conv = await me.openDirect(bruno);
    await tester.pumpWidget(app(
      ChatThreadScreen(chat: me, conversationId: conv, device: FakeDevice(micAllowed: false)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('chat_vocale')));
    await tester.pumpAndSettle();
    expect(find.textContaining('permesso del microfono'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('registrazione')), findsNothing);
    await finish(tester, <ChatService>[me, b]);
  });

  testWidgets('Blocco 4 · nuovo gruppo, nomi nei fumetti, info e codice d\'invito', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final ChatService d = await fakePhone(hub, dario);
    await tester.pumpWidget(app(Scaffold(body: ChatScreen(service: me, now: () => now))));
    await tester.pumpAndSettle();

    // Nuova chat → Nuovo gruppo → nome e persone → Crea.
    await tester.tap(find.byKey(const ValueKey<String>('chat_nuova')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('entra_codice')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('nuovo_gruppo')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('gruppo_nome')), 'Calcetto giovedì');
    await tester.tap(find.byKey(const ValueKey<String>('scegli_$bruno')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('gruppo_crea')));
    await tester.pumpAndSettle();
    expect(find.text('Calcetto giovedì'), findsOneWidget);
    expect(find.textContaining('2 membri'), findsOneWidget);
    final String g = me.threads.single.conversation.id;

    // Bruno scrive: nel fumetto c'è il suo nome.
    await b.refresh();
    await b.send(g, 'Porto io il pallone');
    await me.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Porto io il pallone'), findsOneWidget);
    expect(find.text('Bruno B.'), findsOneWidget, reason: 'nome di chi scrive nel gruppo');

    // Info gruppo: membri, amministratore, codice d'invito.
    await tester.tap(find.byKey(const ValueKey<String>('chat_intestazione')));
    await tester.pumpAndSettle();
    expect(find.text('Info gruppo'), findsOneWidget);
    expect(find.text('Amministratore'), findsOneWidget);
    expect(find.byKey(ValueKey<String>('membro_$bruno')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('gruppo_codice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('codice_mostrato')), findsOneWidget);
    final String code = hub.invites.keys.single;
    Navigator.of(tester.element(find.byKey(const ValueKey<String>('codice_mostrato')))).pop();
    await tester.pumpAndSettle();

    // Dario entra con il codice dalla sua app.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(Scaffold(
      body: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => joinGroupWithCode(context, d),
          child: const Text('codice'),
        ),
      ),
    )));
    await tester.tap(find.text('codice'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('codice_invito')), code);
    await tester.tap(find.byKey(const ValueKey<String>('codice_verifica')));
    await tester.pumpAndSettle();
    expect(find.text('Calcetto giovedì'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('codice_entra')));
    await tester.pumpAndSettle();
    expect(d.conversation(g)?.myMlsState, 'to_add');
    await me.refresh();
    await d.refresh();
    expect(d.conversation(g)?.myMlsState, 'in', reason: 'l\'amministratore lo ha aggiunto da solo');
    await finish(tester, <ChatService>[me, b, d]);
  });

  testWidgets('Blocco 5 · «Silenzia» una chat: menu, campanella barrata, riattiva', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final String conv = await b.openDirect(io);
    await b.send(conv, 'Ciao!');
    await me.refresh();
    await tester.pumpWidget(app(Scaffold(body: ChatScreen(service: me, now: () => now))));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey<String>('silenziata_$conv')), findsNothing);

    await tester.tap(find.byKey(ValueKey<String>('chat_$conv')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('silenzia_chat')));
    await tester.pumpAndSettle();
    expect(find.text('Silenzia per 8 ore'), findsOneWidget);
    expect(find.text('Riattiva le notifiche'), findsNothing);
    await tester.tap(find.text('Silenzia per 8 ore'));
    await tester.pumpAndSettle();
    expect(find.text('Chat silenziata'), findsOneWidget);
    expect(me.conversation(conv)!.isMuted, isTrue);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey<String>('silenziata_$conv')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey<String>('chat_$conv')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('silenzia_chat')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Silenziata fino'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('riattiva_notifiche')));
    await tester.pumpAndSettle();
    expect(me.conversation(conv)!.isMuted, isFalse);
    expect(find.text('Notifiche riattivate'), findsOneWidget);
    await finish(tester, <ChatService>[me, b]);
  });

  test('Blocco 5 · testo «Silenziata fino…»', () {
    final DateTime n = DateTime(2026, 11, 18, 10);
    expect(mutedLabel(DateTime(9999), n), 'Silenziata per sempre');
    expect(mutedLabel(DateTime(2026, 11, 18, 18, 5), n), 'Silenziata fino alle 18:05');
    expect(mutedLabel(DateTime(2026, 11, 25, 10, 0), n), 'Silenziata fino al 25/11 alle 10:00');
  });

  testWidgets('Blocco 4 · invito a un gruppo da chi non è in rubrica: Entra', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService d = await fakePhone(hub, dario);
    final String g = await d.createGroup('Mercatino', <String>[io]);
    await me.refresh();
    expect(me.requests.single.conversation.title, 'Mercatino');
    await tester.pumpWidget(app(ChatThreadScreen(chat: me, conversationId: g)));
    await tester.pumpAndSettle();
    expect(find.text('Invito al gruppo «Mercatino»'), findsOneWidget);
    expect(find.textContaining('Dario V. ti ha aggiunto'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('richiesta_accetta')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('gruppo_attesa')), findsOneWidget);
    await d.refresh();
    await me.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('gruppo_attesa')), findsNothing);
    await finish(tester, <ChatService>[me, d]);
  });

  test('etichette dell\'ora come WhatsApp', () {
    final DateTime n = DateTime(2026, 11, 16, 19);
    expect(chatTimeLabel(DateTime(2026, 11, 16, 8, 5), n), '08:05');
    expect(chatTimeLabel(DateTime(2026, 11, 15, 23), n), 'Ieri');
    expect(chatTimeLabel(DateTime(2026, 11, 2), n), '2/11');
    expect(chatTimeLabel(DateTime(2025, 3, 9), n), '9/3/25');
  });
}

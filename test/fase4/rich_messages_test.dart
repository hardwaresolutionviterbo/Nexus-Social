// Fase 4 · Blocco 18: graffetta come WhatsApp (posizione, contatto, sondaggio, evento,
// Immagini IA), «Condividi l'incontro» anche fuori da Piazly e luoghi suggeriti mentre si scrive.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/ai/ai_screens.dart';
import 'package:nexus_social/features/ai/ai_service.dart';
import 'package:nexus_social/features/chat/chat_media.dart';
import 'package:nexus_social/features/chat/chat_media_picker.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_rich.dart';
import 'package:nexus_social/features/chat/chat_rich_widgets.dart';
import 'package:nexus_social/features/chat/chat_safety_screens.dart';
import 'package:nexus_social/features/chat/chat_screen.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_thread_screen.dart';
import 'package:nexus_social/features/market/comuni_italia.dart';
import 'package:nexus_social/features/places/place_search.dart';

import '../support/fake_comuni.dart';
import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String giulia = 'utenteGiulia0000000000000003';

Widget app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

class RichDevice implements ChatDevice {
  @override
  Future<PickedMedia?> pickImage({required bool camera}) async => null;

  @override
  Future<PickedMedia?> pickVideo() async => null;

  @override
  Future<PickedMedia?> pickFile() async => null;

  @override
  Future<bool> startVoice() async => false;

  @override
  Future<PickedMedia?> stopVoice() async => null;

  @override
  Future<void> cancelVoice() async {}

  @override
  Future<(double, double)?> currentFix() async => (42.6893, 12.0991);

  @override
  Future<List<(String, List<String>)>?> contactEntries() async => <(String, List<String>)>[
    ('Zia Carla', <String>['+39 333 000 0000']),
    ('Idraulico', <String>['+39 333 000 0001']),
  ];
}

/// Photon finto: risponde come il servizio vero, senza rete.
class FakeLookup implements PlaceLookup {
  final List<String> asked = <String>[];

  @override
  Future<List<PlaceSuggestion>> search(String query, {double? nearLat, double? nearLng}) async {
    asked.add(query);
    return const <PlaceSuggestion>[
      PlaceSuggestion(title: 'Bar Centrale', subtitle: 'Piazza Roma 1, Porano, Umbria', lat: 42.68, lng: 12.10),
    ];
  }
}

class FakeAiServer implements AiServer {
  final List<List<AiTurn>> chats = <List<AiTurn>>[];
  bool fail = false;

  @override
  Future<String> chat(List<AiTurn> history) async {
    if (fail) throw const AiFailure('Hai raggiunto il limite di oggi. Riprova domani.');
    chats.add(history);
    return 'Ciao! Sono Piazly AI.';
  }

  @override
  Future<Uint8List> image(String prompt) async => Uint8List.fromList(_png);
}

// PNG 1×1 valido (per Image.memory).
const List<int> _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late FakeChatHub hub;

  setUpAll(() => ComuniItalia.testData = fakeComuni());
  tearDownAll(() => ComuniItalia.testData = null);

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..addPerson(giulia, 'giulia.m', 'Giulia M.')
      ..contacts[io] = <String>{bruno, giulia}
      ..contacts[bruno] = <String>{io}
      ..contacts[giulia] = <String>{io};
  });

  Future<void> finish(WidgetTester tester, List<ChatService> phones) async {
    await tester.pumpWidget(const SizedBox());
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

  group('contenuti ricchi', () {
    test('si codificano e si rileggono; quelli strani si rifiutano', () {
      const RichPoll poll = RichPoll(question: 'Pizza o sushi?', options: <String>['Pizza', 'Sushi'], multiple: true);
      final RichPayload? back = RichPayload.decode(poll.encode());
      expect(back, isA<RichPoll>());
      expect((back! as RichPoll).options, <String>['Pizza', 'Sushi']);
      expect((back as RichPoll).multiple, isTrue);
      final RichEvent ev = RichEvent(title: 'Cena', at: DateTime(2026, 11, 22, 20, 30), place: 'Porano (TR)');
      final RichEvent ev2 = RichPayload.decode(ev.encode())! as RichEvent;
      expect(ev2.at, DateTime(2026, 11, 22, 20, 30));
      expect(RichPayload.decode('{"k":"loc","lat":200,"lng":10}'), isNull, reason: 'coordinate impossibili');
      expect(RichPayload.decode('{"k":"poll","q":"Sì?","o":["solo una"]}'), isNull, reason: 'servono 2 risposte');
      expect(RichPayload.decode('{"k":"contact","n":"X","p":["<script>"]}')?.preview, '👤 X');
      expect((RichPayload.decode('{"k":"contact","n":"X","p":["<script>"]}')! as RichContact).phones, isEmpty);
      expect(RichPayload.decode('non json'), isNull);
      expect(poll.counts(<String, String>{'': '0,1', 'peer': '1', 'x': '9'}), <int>[1, 2]);
    });

    test('sondaggio ed evento cifrati: voti e «Ci sono» arrivano agli altri', () async {
      final ChatService a = await fakePhone(hub, io);
      final ChatService b = await fakePhone(hub, bruno);
      final String ab = await a.openDirect(bruno);
      await a.sendRich(ab, const RichPoll(question: 'Dove andiamo?', options: <String>['Mare', 'Montagna']));
      await a.sendRich(ab, RichEvent(title: 'Pizza da Mario', at: DateTime(2026, 11, 22, 20)));
      await a.sendRich(ab, const RichLocation(lat: 42.68, lng: 12.10, name: 'Porano (TR)'));
      await a.sendRich(ab, const RichContact(name: 'Zia Carla', phones: <String>['+39 333 000 0000']));
      expect(chatPreview(a.messages(ab).last), '👤 Zia Carla');
      for (final String s in hub.payloads) {
        expect(s, isNot(contains('Montagna')), reason: 'sul server non c\'è il testo in chiaro');
      }

      await b.refresh();
      final List<ChatMessage> got = b.messages(ab);
      expect(got.map((ChatMessage m) => m.kind).toSet(), <MessageKind>{MessageKind.rich});
      expect(<String>[for (final ChatMessage m in got) chatPreview(m)], <String>[
        '📊 Sondaggio: Dove andiamo?',
        '📅 Evento: Pizza da Mario',
        '📍 Porano (TR)',
        '👤 Zia Carla',
      ]);

      await b.answer(got[0], '1');
      await b.answer(got[1], RichEvent.yes);
      expect(b.messages(ab)[0].answers, <String, String>{'': '1'});
      await a.refresh();
      expect(a.messages(ab)[0].answers.values.toList(), <String>['1']);
      expect(a.messages(ab)[1].answers.values.toList(), <String>[RichEvent.yes]);
      expect(a.threads.single.last?.kind, MessageKind.rich, reason: 'i voti non sono messaggi nuovi');

      // Voto cambiato e tolto.
      await b.answer(b.messages(ab)[0], '');
      await a.refresh();
      expect(a.messages(ab)[0].answers.values.toList(), <String>['']);
      a.dispose();
      b.dispose();
    });
  });

  testWidgets('graffetta: nove scelte, sondaggio inviato e votato dallo schermo', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final String conv = await me.openDirect(bruno);
    await tester.pumpWidget(app(ChatThreadScreen(chat: me, conversationId: conv, device: RichDevice())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('chat_allega')));
    await tester.pumpAndSettle();
    for (final String k in <String>[
      'galleria', 'fotocamera', 'video', 'documento', 'posizione', 'contatto', 'sondaggio', 'evento', 'immagini_ia',
    ]) {
      expect(find.byKey(ValueKey<String>('allega_$k')), findsOneWidget, reason: k);
    }
    await tester.tap(find.byKey(const ValueKey<String>('allega_sondaggio')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('sondaggio_invia')));
    await tester.pump();
    expect(find.text('Scrivi la domanda.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('sondaggio_domanda')), 'Che giorno?');
    await tester.enterText(find.byKey(const ValueKey<String>('sondaggio_risposta_0')), 'Sabato');
    await tester.enterText(find.byKey(const ValueKey<String>('sondaggio_risposta_1')), 'Domenica');
    await tester.tap(find.byKey(const ValueKey<String>('sondaggio_invia')));
    await tester.pumpAndSettle();
    expect(find.text('Che giorno?'), findsOneWidget);
    expect(find.text('0 voti'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('voto_1')));
    await tester.pumpAndSettle();
    expect(find.text('1 voto'), findsOneWidget);
    await b.refresh();
    expect(b.messages(conv).single.answers.values.toList(), <String>['1']);

    // Contatto dalla rubrica.
    await tester.tap(find.byKey(const ValueKey<String>('chat_allega')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('allega_contatto')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('contatto_cerca')), 'zia');
    await tester.pump();
    expect(find.text('Idraulico'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('contatto_0')));
    await tester.pumpAndSettle();
    expect(find.text('Zia Carla'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('ricco_chiama')), findsOneWidget);

    // Posizione attuale.
    await tester.tap(find.byKey(const ValueKey<String>('chat_allega')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('allega_posizione')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('posizione_tempo_reale')), findsNothing,
        reason: 'senza GPS in tempo reale collegato la scelta non compare');
    await tester.tap(find.byKey(const ValueKey<String>('posizione_attuale')));
    await tester.pumpAndSettle();
    expect(find.text('Posizione attuale'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('ricco_apri_mappa')), findsOneWidget);
    await b.refresh();
    expect(b.messages(conv).map((ChatMessage m) => chatPreview(m)).toList(),
        <String>['📊 Sondaggio: Che giorno?', '👤 Zia Carla', '📍 Posizione attuale']);
    await finish(tester, <ChatService>[me, b]);
  });

  testWidgets('evento con il luogo suggerito mentre si scrive', (WidgetTester tester) async {
    tall(tester);
    final FakeLookup lookup = FakeLookup();
    RichPayload? sent;
    await tester.pumpWidget(app(Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async => sent = await Navigator.of(context).push<RichPayload>(
              MaterialPageRoute<RichPayload>(
                builder: (_) => EventComposerScreen(now: () => DateTime(2026, 11, 19, 15), lookup: lookup),
              ),
            ),
            child: const Text('apri'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('evento_titolo')), 'Aperitivo');
    await tester.enterText(find.byKey(const ValueKey<String>('evento_dove')), 'Poran');
    await tester.pump();
    // Subito il comune dall'elenco nell'app, poi (dopo una pausa) i posti da OpenStreetMap.
    expect(find.text('Porano (TR)'), findsOneWidget);
    expect(find.text('Umbria'), findsOneWidget);
    expect(lookup.asked, isEmpty, reason: 'si aspetta una pausa nella scrittura');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(lookup.asked, <String>['Poran']);
    expect(find.text('Bar Centrale'), findsOneWidget);
    expect(find.text('Luoghi © OpenStreetMap'), findsOneWidget);
    await tester.tap(find.text('Bar Centrale'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('evento_invia')));
    await tester.pumpAndSettle();
    final RichEvent ev = sent! as RichEvent;
    expect(ev.title, 'Aperitivo');
    expect(ev.place, 'Bar Centrale · Piazza Roma 1, Porano, Umbria');
    expect(ev.lat, 42.68);
    expect(ev.at, DateTime(2026, 11, 19, 17));
  });

  test('risposta di Photon trasformata in suggerimenti italiani', () {
    const String body = '{"features":['
        '{"geometry":{"coordinates":[12.1037,42.6843]},"properties":{"name":"Porano","county":"Terni",'
        '"state":"Umbria","countrycode":"IT","osm_value":"village"}},'
        '{"geometry":{"coordinates":[12.1,42.68]},"properties":{"street":"Via Roma","housenumber":"3",'
        '"city":"Orvieto","state":"Umbria","countrycode":"IT"}},'
        '{"geometry":{"coordinates":[2.3,48.8]},"properties":{"name":"Paris","countrycode":"FR"}}]}';
    final List<PlaceSuggestion> s = PhotonPlaceLookup.parsePhoton(body);
    expect(s.map((PlaceSuggestion x) => x.label).toList(), <String>[
      'Porano · Terni, Umbria',
      'Via Roma 3 · Orvieto, Umbria',
    ]);
  });

  testWidgets('Condividi l\'incontro: senza altri contatti, avviso chiaro e invio con SMS o altra app',
      (WidgetTester tester) async {
    tall(tester);
    hub.contacts[io] = <String>{bruno};
    final ChatService me = await fakePhone(hub, io);
    final List<String> shared = <String>[];
    await tester.pumpWidget(app(ShareMeetingScreen(
      chat: me,
      withName: 'Bruno B. (@bruno_b)',
      excludeId: bruno,
      now: () => DateTime(2026, 11, 19, 15),
      shareText: (String t) async => shared.add(t),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nessun contatto della rubrica è su Piazly'), findsNothing);
    expect(find.textContaining('Non hai altri contatti su Piazly oltre a Bruno B.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('incontro_luogo')), 'Poran');
    await tester.pump();
    await tester.tap(find.text('Porano (TR)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey<String>('incontro_altra_app')));
    await tester.tap(find.byKey(const ValueKey<String>('incontro_altra_app')));
    await tester.pumpAndSettle();
    expect(shared, hasLength(1));
    expect(shared.single, contains('Dove: Porano (TR) · Umbria'));
    expect(shared.single, contains('Mappa: https://www.openstreetmap.org/?mlat=42.68430&mlon=12.10370'));
    expect(shared.single, contains('Vedo: Bruno B. (@bruno_b)'));
    await finish(tester, <ChatService>[me]);
  });

  testWidgets('Piazly AI fissata in cima alle chat; risposta e limite spiegato', (WidgetTester tester) async {
    tall(tester);
    final FakeAiServer server = FakeAiServer();
    final AiService ai = AiService(server: server);
    AiRegistry.current = ai;
    addTearDown(() => AiRegistry.current = null);
    final ChatService me = await fakePhone(hub, io);
    await tester.pumpWidget(app(Scaffold(body: ChatScreen(service: me, now: () => DateTime(2026, 11, 19, 15)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('chat_piazly_ai')), findsOneWidget);
    expect(find.text('Chiedimi qualcosa o crea un\'immagine'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('chat_piazly_ai')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('ai_avviso')), findsOneWidget);
    expect(find.textContaining('non è cifrato come le chat'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('ai_campo')), 'Ciao');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('ai_invia')));
    await tester.pumpAndSettle();
    expect(find.text('Ciao! Sono Piazly AI.'), findsOneWidget);
    expect(server.chats.single.single.text, 'Ciao');

    server.fail = true;
    await tester.enterText(find.byKey(const ValueKey<String>('ai_campo')), 'Ancora');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('ai_invia')));
    await tester.pumpAndSettle();
    expect(find.text('Hai raggiunto il limite di oggi. Riprova domani.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Ancora'), findsOneWidget, reason: 'l\'ultima domanda nella riga fissata');
    await finish(tester, <ChatService>[me]);
    ai.dispose();
  });

  testWidgets('Immagini IA dalla graffetta: anteprima e invio come foto cifrata', (WidgetTester tester) async {
    tall(tester);
    final AiService ai = AiService(server: FakeAiServer());
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final String conv = await me.openDirect(bruno);
    await tester.pumpWidget(app(ChatThreadScreen(chat: me, conversationId: conv, device: RichDevice(), ai: ai)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('chat_allega')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('allega_immagini_ia')));
    await tester.pumpAndSettle();
    expect(find.byType(AiImageScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('ia_crea')));
    await tester.pumpAndSettle();
    expect(find.text('Descrivi l\'immagine con qualche parola in più.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('ia_descrizione')), 'un gatto in piazza');
    await tester.tap(find.byKey(const ValueKey<String>('ia_crea')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('ia_anteprima')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('ia_invia')));
    // La foto si prepara fuori dal tempo finto dei test (compute).
    for (int i = 0; i < 30 && me.messages(conv).isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(me.messages(conv).single.media?.kind, MediaKind.image);
    await finish(tester, <ChatService>[me, b]);
    ai.dispose();
  });
}

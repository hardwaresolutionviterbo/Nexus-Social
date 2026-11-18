// Fase 4 · Blocco 8: chiamate tra due telefoni con il server finto e l'audio/video finto.
// Offerta, risposta e chiusura passano dalla chat cifrata.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/calls/call_screen.dart';
import 'package:nexus_social/features/calls/call_service.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_thread_screen.dart';

import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String giulia = 'utenteGiulia0000000000000003';
const String dario = 'utenteDario00000000000000004';

/// I passaggi della chiamata arrivano un attimo dopo la sincronizzazione.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late FakeChatHub hub;

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..addPerson(giulia, 'giulia.m', 'Giulia M.')
      ..addPerson(dario, 'dario88', 'Dario V.')
      ..contacts[io] = <String>{bruno, giulia}
      ..contacts[bruno] = <String>{io, giulia}
      ..contacts[giulia] = <String>{io, bruno};
  });

  Future<(ChatService, ChatService, String)> pair({Duration ring = const Duration(seconds: 45)}) async {
    final ChatService a = await fakePhone(hub, io, calls: fakeCalls(ring: ring));
    final ChatService b = await fakePhone(hub, bruno, calls: fakeCalls(ring: ring));
    final String conv = await a.openDirect(bruno);
    await a.send(conv, 'Ciao');
    await b.refresh();
    await settle();
    await b.send(conv, 'Ciao Anna');
    await a.refresh();
    await settle();
    return (a, b, conv);
  }

  List<String> notices(ChatService s, String conv) =>
      s.messages(conv).where((ChatMessage m) => m.kind == MessageKind.notice).map((ChatMessage m) => m.body).toList();

  test('A chiama B, B risponde, A chiude: squillo una volta, registro su entrambi', () async {
    final (ChatService a, ChatService b, String conv) = await pair();
    await a.calls!.start(conv, video: false);
    expect(a.calls!.state!.phase, CallPhase.outgoing);
    expect(hub.rings, <(String, String, bool)>[(io, conv, false)]);

    await b.refresh();
    await settle();
    expect(b.calls!.state!.phase, CallPhase.incoming);
    expect(b.calls!.state!.peerName, 'Anna R.');
    await b.calls!.accept();
    await settle();
    await Future<void>.delayed(Duration.zero);
    expect(b.calls!.state!.phase, CallPhase.active);
    expect(hub.rings, hasLength(1), reason: 'la risposta non fa squillare');

    await a.refresh();
    await settle();
    await Future<void>.delayed(Duration.zero);
    expect(a.calls!.state!.phase, CallPhase.active);

    await a.calls!.toggleMic();
    expect(a.calls!.state!.micOn, isFalse);
    await a.calls!.hangUp();
    await settle();
    expect(a.calls!.state!.phase, CallPhase.ended);
    await b.refresh();
    await settle();
    expect(b.calls!.state!.phase, CallPhase.ended);
    expect(b.calls!.state!.endReason, 'Chiamata terminata');
    expect(notices(a, conv).single, startsWith('Chiamata vocale · '));
    expect(notices(b, conv).single, startsWith('Chiamata vocale · '));
    a.calls!.dismiss();
    expect(a.calls!.state, isNull);
    a.dispose();
    b.dispose();
  });

  test('videochiamata rifiutata; chiamata con il telefono occupato', () async {
    final (ChatService a, ChatService b, String conv) = await pair();
    await a.calls!.start(conv, video: true);
    expect(hub.rings.single.$3, isTrue);
    await b.refresh();
    await settle();
    expect(b.calls!.state!.video, isTrue);
    await b.calls!.reject();
    await settle();
    await a.refresh();
    await settle();
    expect(a.calls!.state!.endReason, 'Chiamata rifiutata');
    expect(notices(b, conv).single, 'Videochiamata rifiutata');
    a.calls!.dismiss();
    b.calls!.dismiss();

    // Giulia chiama Bruno mentre Bruno è al telefono con Anna.
    final ChatService g = await fakePhone(hub, giulia, calls: fakeCalls());
    final String gb = await g.openDirect(bruno);
    await g.send(gb, 'Ehi');
    await b.refresh();
    await settle();
    await b.send(gb, 'Dimmi');
    await g.refresh();
    await settle();
    await a.calls!.start(conv, video: false);
    await b.refresh();
    await settle();
    await b.calls!.accept();
    await settle();
    await g.calls!.start(gb, video: false);
    await b.refresh();
    await settle();
    expect(b.calls!.state!.conversationId, conv, reason: 'resta la chiamata con Anna');
    expect(notices(b, gb).single, 'Chiamata persa');
    await g.refresh();
    await settle();
    expect(g.calls!.state!.endReason, 'Occupato');
    a.dispose();
    b.dispose();
    g.dispose();
  });

  test('offerta vecchia (telefono spento): chiamata persa, niente squillo sullo schermo', () async {
    final (ChatService a, ChatService b, String conv) = await pair();
    await a.calls!.start(conv, video: false);
    hub.clock = hub.clock.add(const Duration(minutes: 3));
    await b.refresh();
    await settle();
    expect(b.calls!.state, isNull);
    expect(notices(b, conv).single, 'Chiamata persa');
    a.dispose();
    b.dispose();
  });

  test('nessuna risposta: dopo il tempo d\'attesa la chiamata si chiude', () async {
    final (ChatService a, ChatService b, String conv) = await pair(ring: const Duration(milliseconds: 50));
    await a.calls!.start(conv, video: false);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(a.calls!.state!.phase, CallPhase.ended);
    expect(a.calls!.state!.endReason, 'Nessuna risposta');
    expect(notices(a, conv).single, 'Chiamata senza risposta');
    a.dispose();
    b.dispose();
  });

  test('da una richiesta di messaggio non si chiama', () async {
    final ChatService a = await fakePhone(hub, io, calls: fakeCalls());
    final ChatService d = await fakePhone(hub, dario, calls: fakeCalls());
    final String conv = await d.openDirect(io);
    await d.send(conv, 'Ciao');
    await d.refresh();
    await settle();
    await expectLater(d.calls!.start(conv, video: false), throwsA(isA<ChatFailure>()));
    expect(hub.rings, isEmpty);
    a.dispose();
    d.dispose();
  });

  test('segnale della chiamata: si legge solo se completo', () {
    const CallSignal s = CallSignal(action: CallAction.offer, callId: 'abc', video: true, sdp: 'v=0');
    final CallSignal back = CallSignal.decode(s.encode())!;
    expect((back.action, back.callId, back.video, back.sdp), (CallAction.offer, 'abc', true, 'v=0'));
    expect(CallSignal.decode('{"a":"offer","c":"abc"}'), isNull, reason: 'offerta senza descrizione');
    expect(CallSignal.decode('{"a":"saluta","c":"abc"}'), isNull);
    expect(CallSignal.decode('non json'), isNull);
    expect(callDuration(const Duration(seconds: 151)), '2:31');
    expect(callDuration(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
  });

  testWidgets('schermata: pulsanti di chiamata nella chat e chiamata in arrivo a tutto schermo', (WidgetTester tester) async {
    final (ChatService a, ChatService b, String conv) = (await tester.runAsync(pair))!;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: ChatThreadScreen(chat: a, conversationId: conv)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('chiama_voce')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chiama_video')), findsOneWidget);
    await tester.runAsync(() => a.calls!.start(conv, video: false));
    await tester.runAsync(() async {
      await b.refresh();
      await settle();
    });

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: CallScreen(calls: b.calls!)));
    await tester.pump();
    expect(find.text('Anna R.'), findsOneWidget);
    expect(find.text('Chiamata in arrivo'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey<String>('chiamata_rispondi')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('chiamata_chiudi')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chiamata_altoparlante')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey<String>('chiamata_chiudi')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('Chiamata terminata'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    a.dispose();
    b.dispose();
  });
}

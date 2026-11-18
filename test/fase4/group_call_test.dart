// Fase 4 · Blocco 10: chiamate di gruppo, con il server finto e l'audio/video finto.
// Chi entra chiama chi c'è già; ognuno è collegato a tutti gli altri (fino a 4 persone).
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/features/calls/call_service.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';

import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String giulia = 'utenteGiulia0000000000000003';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  late FakeChatHub hub;

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..addPerson(giulia, 'giulia.m', 'Giulia M.')
      ..contacts[io] = <String>{bruno, giulia}
      ..contacts[bruno] = <String>{io, giulia}
      ..contacts[giulia] = <String>{io, bruno};
  });

  Future<void> sync(List<ChatService> phones) async {
    for (int i = 0; i < 3; i++) {
      for (final ChatService p in phones) {
        await p.refresh();
      }
    }
    await settle();
  }

  test('Anna chiama il gruppo: entrano Bruno e poi Giulia, tutti collegati a tutti', () async {
    final ChatService a = await fakePhone(hub, io, calls: fakeCalls());
    final ChatService b = await fakePhone(hub, bruno, calls: fakeCalls());
    final ChatService g = await fakePhone(hub, giulia, calls: fakeCalls());
    final String conv = await a.createGroup('Calcetto', <String>[bruno, giulia]);
    await sync(<ChatService>[a, b, g]);
    expect(a.conversation(conv)!.myMlsState, 'in');
    expect(b.conversation(conv)!.myMlsState, 'in');

    await a.calls!.startGroup(conv, video: true);
    expect(hub.rings, <(String, String, bool)>[(io, conv, true)]);
    await sync(<ChatService>[b, g]);
    expect(b.calls!.state!.phase, CallPhase.incoming);
    expect(b.calls!.state!.group, isTrue);
    expect(g.calls!.state!.phase, CallPhase.incoming);

    await b.calls!.accept();
    await sync(<ChatService>[a, b, g]);
    expect(a.calls!.state!.phase, CallPhase.active);
    expect(a.calls!.state!.peers, <String>[bruno]);
    expect(b.calls!.state!.phase, CallPhase.active);

    await g.calls!.accept();
    await sync(<ChatService>[a, b, g]);
    expect(g.calls!.state!.peers.toSet(), <String>{io, bruno});
    expect(a.calls!.state!.peers.toSet(), <String>{bruno, giulia});
    expect(b.calls!.state!.peers.toSet(), <String>{io, giulia});
    expect(hub.rings, hasLength(1), reason: 'entrare e collegarsi non fa squillare');

    // Bruno esce: gli altri due restano.
    await b.calls!.hangUp();
    await sync(<ChatService>[a, g]);
    expect(a.calls!.state!.peers, <String>[giulia]);
    expect(g.calls!.state!.peers, <String>[io]);
    expect(a.calls!.state!.phase, CallPhase.active);

    // Giulia esce: Anna resta sola e la chiamata finisce.
    await g.calls!.hangUp();
    await sync(<ChatService>[a]);
    expect(a.calls!.state!.phase, CallPhase.ended);
    expect(a.messages(conv).where((ChatMessage m) => m.kind == MessageKind.notice).last.body,
        startsWith('Videochiamata di gruppo · '));
    a.dispose();
    b.dispose();
    g.dispose();
  });

  test('nessuno risponde: la chiamata di gruppo si chiude; chi non ha risposto la vede persa', () async {
    final ChatService a = await fakePhone(hub, io, calls: fakeCalls(ring: const Duration(milliseconds: 80)));
    final ChatService b = await fakePhone(hub, bruno, calls: fakeCalls(ring: const Duration(seconds: 45)));
    final String conv = await a.createGroup('Calcetto', <String>[bruno]);
    await sync(<ChatService>[a, b]);
    await a.calls!.startGroup(conv, video: false);
    await sync(<ChatService>[b]);
    expect(b.calls!.state!.phase, CallPhase.incoming);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(a.calls!.state!.endReason, 'Nessuna risposta');
    await sync(<ChatService>[b]);
    expect(b.calls!.state!.phase, CallPhase.ended);
    expect(b.messages(conv).where((ChatMessage m) => m.kind == MessageKind.notice).last.body, 'Chiamata di gruppo persa');
    a.dispose();
    b.dispose();
  });

  test('segnale rivolto a una persona: si legge con il destinatario', () {
    const CallSignal s = CallSignal(action: CallAction.offer, callId: 'abc', sdp: 'v=0', to: 'utenteB');
    expect(CallSignal.decode(s.encode())!.to, 'utenteB');
    expect(CallSignal.decode('{"a":"join","c":"abc"}')!.action, CallAction.join);
  });
}

// Fase 4 · Blocco 9: con il tempo reale i messaggi e le chiamate arrivano subito, senza
// aspettare il controllo periodico (qui disattivato: un giorno).
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/features/calls/call_service.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';

import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late FakeChatHub hub;

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..contacts[io] = <String>{bruno}
      ..contacts[bruno] = <String>{io}
      ..live = true;
  });

  test('messaggio: arriva da solo con il tocco del server', () async {
    final ChatService a = await fakePhone(hub, io, calls: fakeCalls());
    final ChatService b = await fakePhone(hub, bruno, calls: fakeCalls());
    final String conv = await a.openDirect(bruno);
    await a.send(conv, 'Ciao Bruno');
    await settle();
    expect(b.messages(conv).where((ChatMessage m) => m.isText).single.body, 'Ciao Bruno',
        reason: 'nessun refresh a mano: è bastato il tocco');
    await b.send(conv, 'Eccomi');
    await settle();
    expect(a.messages(conv).last.body, 'Eccomi');

    // Anche la chiamata squilla subito.
    await a.calls!.start(conv, video: false);
    await settle();
    expect(b.calls!.state!.phase, CallPhase.incoming);
    await b.calls!.accept();
    await settle();
    expect(a.calls!.state!.phase, CallPhase.active);
    await a.calls!.hangUp();
    await settle();
    expect(b.calls!.state!.phase, CallPhase.ended);
    a.dispose();
    b.dispose();
  });

  test('tempo reale spento: serve il controllo periodico (come prima)', () async {
    hub.live = false;
    final ChatService a = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final String conv = await a.openDirect(bruno);
    await a.send(conv, 'Ciao');
    await settle();
    expect(b.messages(conv), isEmpty);
    await b.refresh();
    expect(b.messages(conv).single.body, 'Ciao');
    a.dispose();
    b.dispose();
  });
}

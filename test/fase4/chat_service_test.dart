// Fase 4 · Blocco 1: il motore della chat con la cifratura MLS vera e un server in memoria
// con le regole della migrazione 0019. Ogni «telefono» ha le sue chiavi e i suoi messaggi.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/features/chat/chat_crypto.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_store.dart';

import 'fake_chat.dart';

const String anna = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String dario = 'utenteDario00000000000000004';

Future<ChatService> phone(FakeChatHub hub, String uid, {ChatStore? store}) async {
  final ChatService s = ChatService(
    server: hub.serverFor(uid),
    crypto: () => MlsChatCrypto.open(uid: uid, dbPath: ':memory:'),
    store: store ?? MemoryChatStore(),
    myId: uid,
    // Nessun controllo automatico: nei test si aggiorna a mano.
    fastPoll: const Duration(days: 1),
    slowPoll: const Duration(days: 1),
  );
  await s.start();
  expect(s.ready, isTrue, reason: s.startError);
  return s;
}

void main() {
  late FakeChatHub hub;

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(anna, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..addPerson(dario, 'dario88', 'Dario V.')
      // Bruno ha Anna in rubrica; Anna non ha Dario.
      ..contacts[bruno] = <String>{anna};
  });

  test('A scrive a B: cifrato sul server, spunte inviato → consegnato → letto', () async {
    final ChatService a = await phone(hub, anna);
    final ChatService b = await phone(hub, bruno);
    expect(hub.packages[anna]!.length, ChatService.keyPackageTarget);

    final String conv = await a.openDirect(bruno);
    await a.send(conv, 'Ciao Bruno, la bici è ancora disponibile?');
    final ChatMessage mine = a.messages(conv).single;
    expect(mine.ticksFor(a.conversation(conv)), MessageTicks.sent);

    // Sul server solo testo cifrato: nessuna parola del messaggio.
    for (final String p in hub.payloads) {
      expect(utf8.decode(base64Decode(p), allowMalformed: true).contains('bici'), isFalse);
    }

    await b.refresh();
    expect(b.threads.single.conversation.peerName, 'Anna R.');
    expect(b.threads.single.unread, 1);
    expect(b.messages(conv).single.body, 'Ciao Bruno, la bici è ancora disponibile?');
    expect(hub.storedMessages, 0, reason: 'ricevuto: il server non conserva più nulla');

    await a.refresh();
    expect(a.messages(conv).single.ticksFor(a.conversation(conv)), MessageTicks.delivered);

    b.setOpenConversation(conv);
    await b.markRead(conv);
    expect(b.threads.single.unread, 0);
    await a.refresh();
    expect(a.messages(conv).single.ticksFor(a.conversation(conv)), MessageTicks.read);

    await b.send(conv, 'Sì, passa domani alle 18');
    await a.refresh();
    expect(a.messages(conv).map((m) => m.body).toList(), <String>[
      'Ciao Bruno, la bici è ancora disponibile?',
      'Sì, passa domani alle 18',
    ]);
    a.dispose();
    b.dispose();
  });

  test('Uno sconosciuto scrive come richiesta: niente spunte finché non viene accettata', () async {
    final ChatService a = await phone(hub, anna);
    final ChatService d = await phone(hub, dario);

    final String conv = await d.openDirect(anna);
    await d.send(conv, 'Ciao, ho visto il tuo annuncio');
    await a.refresh();
    expect(a.threads, isEmpty);
    expect(a.requests.single.conversation.peerUsername, 'dario88');
    expect(a.messages(conv).single.body, 'Ciao, ho visto il tuo annuncio');

    await d.refresh();
    expect(d.messages(conv).single.ticksFor(d.conversation(conv)), MessageTicks.sent,
        reason: 'finché è una richiesta, niente «consegnato»');

    await a.respondRequest(conv, true);
    expect(a.requests, isEmpty);
    expect(a.threads.single.conversation.id, conv);
    await d.refresh();
    expect(d.messages(conv).single.ticksFor(d.conversation(conv)), MessageTicks.delivered);
    a.dispose();
    d.dispose();
  });

  test('Richiesta rifiutata: sparisce e i messaggi successivi non arrivano', () async {
    final ChatService a = await phone(hub, anna);
    final ChatService d = await phone(hub, dario);
    final String conv = await d.openDirect(anna);
    await d.send(conv, 'Primo messaggio');
    await a.refresh();
    await a.respondRequest(conv, false);
    expect(a.requests, isEmpty);
    await d.send(conv, 'Secondo messaggio');
    await a.refresh();
    expect(a.requests, isEmpty);
    expect(a.threads, isEmpty);
    expect(a.messages(conv), isEmpty);
    a.dispose();
    d.dispose();
  });

  test('B cambia telefono: la chat si riapre da sola e i nuovi messaggi arrivano', () async {
    final ChatService a = await phone(hub, anna);
    final ChatService b1 = await phone(hub, bruno);
    final String conv = await a.openDirect(bruno);
    await a.send(conv, 'Prima del cambio');
    await b1.refresh();
    expect(b1.messages(conv).single.body, 'Prima del cambio');
    b1.dispose();

    // Telefono nuovo: chiavi nuove e nessun messaggio salvato.
    final ChatService b2 = await phone(hub, bruno);
    await a.refresh();
    expect(a.conversation(conv)!.peerChangedPhone, isTrue);

    await a.send(conv, 'Dopo il cambio');
    expect(a.messages(conv).where((m) => m.kind == MessageKind.notice), hasLength(1));
    await b2.refresh();
    expect(b2.messages(conv).where((m) => m.kind == MessageKind.text).single.body, 'Dopo il cambio');

    // E si risponde senza problemi.
    await b2.send(conv, 'Eccomi sul telefono nuovo');
    await a.refresh();
    expect(a.messages(conv).last.body, 'Eccomi sul telefono nuovo');
    a.dispose();
    b2.dispose();
  });

  test('Entrambi scrivono per primi insieme: nessun messaggio perso', () async {
    final ChatService a = await phone(hub, anna);
    final ChatService b = await phone(hub, bruno);
    final String conv = await a.openDirect(bruno);
    await b.openDirect(anna);
    await a.send(conv, 'Ciao da Anna');
    // Bruno non ha ancora aggiornato: la sua prima scrittura trova la chat già aperta.
    await b.send(conv, 'Ciao da Bruno');
    await a.refresh();
    await b.refresh();
    expect(b.messages(conv).map((m) => m.body), contains('Ciao da Anna'));
    expect(a.messages(conv).map((m) => m.body), contains('Ciao da Bruno'));
    a.dispose();
    b.dispose();
  });

  test('Blocco 2 · risposta, reazione, inoltro ed elimina per tutti, cifrati', () async {
    final ChatService a = await phone(hub, anna);
    final ChatService b = await phone(hub, bruno);
    final ChatService d = await phone(hub, dario);
    final String ab = await a.openDirect(bruno);
    await a.send(ab, 'La bici costa 120 euro');
    await b.refresh();
    final ChatMessage price = b.messages(ab).single;

    // B risponde citando il messaggio di A.
    await b.send(ab, 'Va bene, la prendo', replyTo: price);
    await a.refresh();
    final ChatMessage reply = a.messages(ab).last;
    expect(reply.quote?.text, 'La bici costa 120 euro');
    expect(reply.quote?.authorId, anna, reason: 'A vede che la citazione è sua');

    // A reagisce; B vede la reazione; toccandola di nuovo si toglie.
    await a.react(reply, '👍');
    expect(a.messages(ab).last.myReaction, '👍');
    await b.refresh();
    expect(b.messages(ab).last.peerReaction, '👍');
    await a.react(a.messages(ab).last, '👍');
    await b.refresh();
    expect(b.messages(ab).last.peerReaction, '');

    // A elimina per tutti il suo messaggio: sparisce il testo anche da B.
    final ChatMessage first = a.messages(ab).first;
    await a.deleteForEveryone(first);
    expect(a.messages(ab).first.deleted, isTrue);
    await b.refresh();
    expect(b.messages(ab).first.deleted, isTrue);
    expect(b.messages(ab).first.body, isEmpty);
    // B non può eliminare per tutti un messaggio di A.
    await expectLater(b.deleteForEveryone(b.messages(ab).first), throwsA(isA<ChatFailure>()));

    // B inoltra la sua risposta a D (richiesta, perché D non ha B in rubrica).
    await b.forward(b.messages(ab).last, <String>[await b.openDirect(dario)]);
    await d.refresh();
    final ChatMessage fwd = d.requests.single.last!;
    expect(fwd.forwarded, isTrue);
    expect(fwd.body, 'Va bene, la prendo');

    // Elimina per me: solo su questo telefono.
    await a.deleteForMe(a.messages(ab).last);
    expect(a.messages(ab).where((m) => m.body == 'Va bene, la prendo'), isEmpty);
    expect(b.messages(ab).where((m) => m.body == 'Va bene, la prendo'), hasLength(1));

    // Le reazioni e le eliminazioni non contano come messaggi non letti: per B resta solo
    // il primo messaggio di A (mai aperto).
    expect(b.threads.firstWhere((t) => t.conversation.id == ab).unread, 1);
    a.dispose();
    b.dispose();
    d.dispose();
  });
}

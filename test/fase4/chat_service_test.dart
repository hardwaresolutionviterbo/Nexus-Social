// Fase 4 · Blocco 1: il motore della chat con la cifratura MLS vera e un server in memoria
// con le regole della migrazione 0019. Ogni «telefono» ha le sue chiavi e i suoi messaggi.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/features/chat/chat_crypto.dart';
import 'package:nexus_social/features/chat/chat_media.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_store.dart';

import 'fake_chat.dart';

const String anna = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String dario = 'utenteDario00000000000000004';

Future<ChatService> phone(FakeChatHub hub, String uid, {ChatStore? store}) async {
  final Directory files = Directory.systemTemp.createTempSync('piazly_allegati_');
  addTearDown(() => files.deleteSync(recursive: true));
  final ChatService s = ChatService(
    media: hub.media,
    files: ChatMediaFiles(Future<Directory>.value(files)),
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

  test('Blocco 3 · foto e documento cifrati: il server vede solo byte illeggibili', () async {
    final ChatService a = await phone(hub, anna);
    final ChatService b = await phone(hub, bruno);
    final ChatService d = await phone(hub, dario);
    final String ab = await a.openDirect(bruno);
    final Uint8List photo = Uint8List.fromList(List<int>.generate(70000, (int i) => (i * 7) % 251));
    await a.sendMedia(ab, kind: MediaKind.image, bytes: photo, mime: 'image/jpeg',
        width: 1200, height: 900, thumb: base64Encode(<int>[1, 2, 3]), caption: 'La bici');
    final ChatMessage sent = a.messages(ab).single;
    expect(sent.serverId, isNotNull);
    expect(sent.media!.path, startsWith('$ab/$anna/'));
    expect((await a.localFileOf(sent))!.readAsBytesSync(), photo, reason: 'chi invia ha la sua copia');

    // Sul server: cifrato (diverso, più lungo di 28 byte) e nessuna chiave in chiaro.
    final Uint8List onServer = hub.media.files[sent.media!.path]!;
    expect(onServer.length, photo.length + 28);
    expect(onServer.sublist(12, 112), isNot(photo.sublist(0, 100)));

    await b.refresh();
    final ChatMessage got = b.messages(ab).single;
    expect(got.body, 'La bici');
    expect(got.media!.kind, MediaKind.image);
    expect(got.media!.width, 1200);
    final File file = await b.download(got);
    expect(file.readAsBytesSync(), photo);
    expect(hub.media.files.containsKey(sent.media!.path), isFalse, reason: 'scaricato: via dal server');
    expect(b.messages(ab).single.localFile, isNotEmpty);

    // Documento, poi inoltro a D: nuova chiave e nuovo percorso, nella chat con D.
    final Uint8List pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 contratto di prova'));
    await b.sendMedia(ab, kind: MediaKind.file, bytes: pdf, mime: 'application/pdf', name: 'contratto.pdf');
    await a.refresh();
    final ChatMessage doc = a.messages(ab).last;
    expect(doc.media!.name, 'contratto.pdf');
    await expectLater(a.forward(doc, <String>[await a.openDirect(dario)]), throwsA(isA<ChatFailure>()),
        reason: 'prima va scaricato');
    await a.download(doc);
    final String ad = await a.openDirect(dario);
    await a.forward(a.messages(ab).last, <String>[ad]);
    await d.refresh();
    final ChatMessage fwd = d.requests.single.last!;
    expect(fwd.forwarded, isTrue);
    expect(fwd.media!.path, startsWith('$ad/$anna/'));
    expect(fwd.media!.key, isNot(doc.media!.key));
    expect((await d.download(fwd)).readAsBytesSync(), pdf);

    // Allegato manomesso sul server: rifiutato.
    await a.sendMedia(ab, kind: MediaKind.audio, bytes: Uint8List.fromList(List<int>.filled(5000, 9)),
        mime: 'audio/mp4', durationMs: 4200);
    final ChatMessage voice = a.messages(ab).last;
    hub.media.files[voice.media!.path]![40] ^= 0xFF;
    await b.refresh();
    await expectLater(b.download(b.messages(ab).last), throwsA(isA<ChatFailure>()));

    // Elimina per tutti: l'allegato sparisce anche dal server.
    await a.sendMedia(ab, kind: MediaKind.video, bytes: Uint8List.fromList(List<int>.filled(9000, 3)),
        mime: 'video/mp4');
    final ChatMessage video = a.messages(ab).last;
    await a.deleteForEveryone(video);
    expect(hub.media.files.containsKey(video.media!.path), isFalse);
    await b.refresh();
    expect(b.messages(ab).last.deleted, isTrue);
    expect(b.messages(ab).last.media, isNull);

    // Troppo pesante: rifiutato prima di partire.
    await expectLater(
      a.sendMedia(ab, kind: MediaKind.file, bytes: Uint8List(MediaLimits.maxBytes + 1), mime: 'application/zip'),
      throwsA(isA<ChatFailure>()),
    );
    a.dispose();
    b.dispose();
    d.dispose();
  });

  test('Blocco 4 · gruppo cifrato: creazione, invito, aggiunta, uscita, telefono nuovo, codice', () async {
    const String elena = 'utenteElena00000000000000006';
    hub.addPerson(elena, 'elena.p', 'Elena P.');
    final ChatService a = await phone(hub, anna);
    final ChatService b = await phone(hub, bruno);
    final ChatService d = await phone(hub, dario);
    final ChatService e = await phone(hub, elena);

    // Anna crea il gruppo: Bruno (ha Anna in rubrica) entra, Dario riceve un invito.
    final String g = await a.createGroup('Gita al lago', <String>[bruno, dario]);
    expect(a.conversation(g)!.isGroup, isTrue);
    expect(a.conversation(g)!.generation, 1);
    await b.refresh();
    expect(b.conversation(g)!.title, 'Gita al lago');
    expect(b.messages(g).single.body, 'Anna R. ha creato il gruppo con te · Anna R. ha invitato Dario V.');
    await a.refresh();
    expect(a.messages(g).single.body, 'Hai creato il gruppo con Bruno B. · Hai invitato Dario V.');
    await d.refresh();
    expect(d.requests.single.conversation.id, g, reason: 'l\'invito compare tra le richieste');
    expect(d.messages(g), isEmpty, reason: 'nessun contenuto prima di accettare');

    // Messaggi cifrati tra Anna e Bruno, con il mittente.
    await a.send(g, 'Partenza alle 9');
    await b.refresh();
    expect(b.messages(g).last.body, 'Partenza alle 9');
    expect(b.messages(g).last.senderId, anna);
    expect(b.memberName(g, anna), 'Anna R.');
    for (final String p in hub.payloads) {
      expect(utf8.decode(base64Decode(p), allowMalformed: true).contains('Partenza'), isFalse);
    }
    await b.send(g, 'Ci sono!');
    await a.refresh();
    expect(a.messages(g).last.body, 'Ci sono!');

    // Dario accetta: Anna (amministratrice) lo aggiunge al gruppo cifrato da sola.
    await d.respondRequest(g, true);
    await a.refresh();
    await b.refresh();
    await d.refresh();
    expect(d.conversation(g)!.myMlsState, 'in');
    expect(d.messages(g).where((m) => m.body == 'Partenza alle 9'), isEmpty, reason: 'niente messaggi di prima');
    await d.send(g, 'Eccomi anche io');
    await a.refresh();
    await b.refresh();
    expect(a.messages(g).last.body, 'Eccomi anche io');
    expect(b.messages(g).last.body, 'Eccomi anche io');

    // Letto da tutti → spunte blu per Anna.
    await a.send(g, 'Portate il pranzo');
    await b.refresh();
    await d.refresh();
    await b.markRead(g);
    await a.refresh();
    expect(a.messages(g).last.ticksFor(a.conversation(g)), MessageTicks.delivered, reason: 'Dario non l\'ha letto');
    await d.markRead(g);
    await a.refresh();
    expect(a.messages(g).last.ticksFor(a.conversation(g)), MessageTicks.read);

    // Bruno esce: viene tolto dal gruppo cifrato e non riceve più nulla.
    await b.leaveGroup(g);
    expect(b.conversation(g), isNull);
    await a.refresh();
    await d.refresh();
    await a.send(g, 'Bruno è uscito');
    await d.refresh();
    expect(d.messages(g).last.body, 'Bruno è uscito');
    await b.refresh();
    expect(b.messages(g), isEmpty);

    // Dario cambia telefono: Anna lo riaggiunge e la chat continua.
    d.dispose();
    final ChatService d2 = await phone(hub, dario);
    await a.refresh();
    await d2.refresh();
    expect(d2.conversation(g)!.myMlsState, 'in');
    await d2.send(g, 'Telefono nuovo, tutto ok');
    await a.refresh();
    expect(a.messages(g).last.body, 'Telefono nuovo, tutto ok');

    // Elena entra con il codice d'invito.
    final String code = await a.inviteCode(g);
    expect((await e.inviteInfo(code)).title, 'Gita al lago');
    await e.joinWithCode(code);
    await a.refresh();
    await e.refresh();
    await a.send(g, 'Benvenuta Elena');
    await e.refresh();
    await d2.refresh();
    expect(e.messages(g).last.body, 'Benvenuta Elena');
    expect(d2.messages(g).last.body, 'Benvenuta Elena');

    // Un membro non amministratore non può aggiungere né nominare.
    await expectLater(e.addToGroup(g, <String>[bruno]), throwsA(isA<ChatFailure>()));
    await a.setGroupAdmin(g, elena, true);
    await e.refresh();
    expect(e.conversation(g)!.isAdmin, isTrue);
    for (final ChatService p in <ChatService>[a, b, d2, e]) {
      p.dispose();
    }
  });
}

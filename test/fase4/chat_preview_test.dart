// Fase 4 · Blocco 10: testo del messaggio nella notifica, cifrato per chi riceve.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/features/chat/chat_media.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_preview.dart';
import 'package:nexus_social/features/chat/chat_service.dart';

import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';

void main() {
  test('anteprima: cifrata, si apre solo con la chiave giusta', () async {
    final List<int> key = PreviewCipher.newKey();
    final String sealed = await PreviewCipher.seal(key, 'Ci vediamo alle 18?');
    expect(utf8.decode(base64Decode(sealed), allowMalformed: true), isNot(contains('vediamo')));
    expect(await PreviewCipher.open(key, sealed), 'Ci vediamo alle 18?');
    expect(await PreviewCipher.open(PreviewCipher.newKey(), sealed), isNull);
    expect(await PreviewCipher.open(key, 'rovinato'), isNull);
  });

  test('testo dell\'anteprima: corto, una riga, gli allegati a parole', () {
    expect(previewOf(body: 'Ciao\ncome   stai?'), 'Ciao come stai?');
    expect(previewOf(body: 'x' * 300).length, previewMaxChars);
    expect(previewOf(body: '', media: MediaKind.image), '📷 Foto');
    expect(previewOf(body: 'La bici', media: MediaKind.image), '📷 Foto · La bici');
    expect(previewOf(body: '', media: MediaKind.audio), '🎤 Messaggio vocale');
  });

  test('la chiave arriva a chi riceve dentro la chat; il server vede solo l\'anteprima cifrata', () async {
    final FakeChatHub hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..contacts[io] = <String>{bruno}
      ..contacts[bruno] = <String>{io};
    final MemoryPreviewKeyStore annaKeys = MemoryPreviewKeyStore();
    final MemoryPreviewKeyStore brunoKeys = MemoryPreviewKeyStore();
    final ChatService a = await fakePhone(hub, io, previews: annaKeys);
    final ChatService b = await fakePhone(hub, bruno, previews: brunoKeys);
    final String conv = await a.openDirect(bruno);
    await a.send(conv, 'Ci vediamo alle 18?');
    await a.send(conv, 'Porto la bici');
    expect(hub.previews, hasLength(2));
    expect(hub.previews.every(((String, String, String) p) => p.$1 == io && p.$2 == conv), isTrue);
    expect(hub.previews.first.$3, isNot(contains('vediamo')));

    await b.refresh();
    // La chiave non diventa un messaggio nella chat.
    expect(b.messages(conv).map((ChatMessage m) => m.body), <String>['Ci vediamo alle 18?', 'Porto la bici']);
    final PreviewKeys keys = PreviewKeys(brunoKeys);
    expect(await keys.open(conv, io, hub.previews.first.$3), 'Ci vediamo alle 18?');
    expect(await keys.open(conv, io, hub.previews.last.$3), 'Porto la bici');
    expect(await keys.open(conv, bruno, hub.previews.last.$3), isNull, reason: 'chiave di un\'altra persona');

    // Anche la risposta di Bruno ha l'anteprima, che Anna sa leggere.
    await b.send(conv, 'Perfetto!');
    await a.refresh();
    expect(await PreviewKeys(annaKeys).open(conv, bruno, hub.previews.last.$3), 'Perfetto!');
    a.dispose();
    b.dispose();
  });
}

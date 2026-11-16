// Fase 4: messaggi ed eventi salvati sul telefono restano dopo la riapertura dell'app.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_store.dart';

void main() {
  test('file della chat: messaggi, citazioni, reazioni ed eliminazioni dopo la riapertura', () async {
    final Directory dir = Directory.systemTemp.createTempSync('piazly_chat_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final DateTime at = DateTime(2026, 11, 16, 18);
    final FileChatStore first = FileChatStore(Future<Directory>.value(dir));
    await first.setCursor(42);
    await first.setSession('c1', const LocalSession(2, 'Z3JvdXA='));
    await first.append(ChatMessage(
      localId: 'm1', conversationId: 'c1', serverId: 10, mine: false,
      kind: MessageKind.text, body: 'Ciao', at: at,
    ));
    await first.append(ChatMessage(
      localId: 'm2', conversationId: 'c1', serverId: 11, mine: true,
      kind: MessageKind.text, body: 'Ciao a te', at: at,
      quote: const ChatQuote(localId: 'm1', authorId: 'altro', text: 'Ciao'), forwarded: true,
    ));
    await first.append(ChatMessage(
      localId: 'm3', conversationId: 'c1', serverId: 12, mine: true,
      kind: MessageKind.text, body: 'Da cancellare', at: at,
    ));
    await first.appendEvent(ChatEvent(conversationId: 'c1', kind: ChatEventKind.react, target: 'm2',
        byMe: false, at: at, emoji: '❤️', serverId: 13));
    await first.appendEvent(ChatEvent(conversationId: 'c1', kind: ChatEventKind.delete, target: 'm3',
        byMe: true, at: at, serverId: 14));
    await first.appendEvent(ChatEvent(conversationId: 'c1', kind: ChatEventKind.hide, target: 'm1',
        byMe: true, at: at));
    // Un messaggio altrui non si elimina per tutti con un evento «mio».
    await first.appendEvent(ChatEvent(conversationId: 'c1', kind: ChatEventKind.delete, target: 'm1',
        byMe: true, at: at));

    final FileChatStore again = FileChatStore(Future<Directory>.value(dir));
    expect(await again.cursor(), 42);
    expect((await again.session('c1'))?.generation, 2);
    final List<ChatMessage> list = await again.messages('c1');
    expect(list.map((m) => m.localId), <String>['m2', 'm3']);
    expect(list[0].quote?.text, 'Ciao');
    expect(list[0].forwarded, isTrue);
    expect(list[0].peerReaction, '❤️');
    expect(list[1].deleted, isTrue);
    expect(list[1].body, isEmpty);
    expect(await again.hasServerId('c1', 13), isTrue);
    expect(await again.hasServerId('c1', 99), isFalse);

    await again.deleteConversation('c1');
    expect(await again.messages('c1'), isEmpty);
    expect(await again.session('c1'), isNull);
  });
}

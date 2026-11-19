// Fase 4 · Blocco 7: «Segnala» (solo i messaggi scelti) e «Condividi l'incontro».
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_thread_screen.dart';

import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String giulia = 'utenteGiulia0000000000000003';
const String dario = 'utenteDario00000000000000004';

Widget app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void main() {
  late FakeChatHub hub;

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..addPerson(giulia, 'giulia.m', 'Giulia M.')
      ..addPerson(dario, 'dario88', 'Dario V.')
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
    tester.view.physicalSize = const Size(1170, 3400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  test('testo dell\'incontro e dei messaggi allegati alla segnalazione', () {
    final String t = ChatService.meetingText(
      withName: 'Dario V. (@dario88)',
      place: ' Bar Centrale, piazza Roma ',
      when: DateTime(2026, 11, 19, 18, 30),
      note: 'Per la bici',
    );
    expect(t, '📍 Incontro condiviso con te\nVedo: Dario V. (@dario88)\nQuando: giovedì 19/11 alle 18:30\n'
        'Dove: Bar Centrale, piazza Roma\nNota: Per la bici\nSe non ti scrivo dopo l\'incontro, contattami.');
  });

  testWidgets('Segnala: si mandano solo i messaggi scelti; con il blocco la chat sparisce', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService d = await fakePhone(hub, dario);
    final String conv = await d.openDirect(io);
    await d.send(conv, 'Ciao, mandami 50 euro di ricarica e ti porto la bici');
    await d.send(conv, 'Fai presto');
    await d.send(conv, 'Buona giornata');
    await me.refresh();
    await tester.pumpWidget(app(ChatThreadScreen(chat: me, conversationId: conv)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('chat_altro')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('menu_incontro')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('menu_segnala')));
    await tester.pumpAndSettle();
    expect(find.textContaining('solo i messaggi che selezioni'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('segnala_invia')));
    await tester.pump();
    expect(find.text('Scegli un motivo.'), findsOneWidget);
    expect(hub.reports, isEmpty);

    final List<ChatMessage> msgs = me.messages(conv).where((ChatMessage m) => m.isText).toList();
    await tester.tap(find.byKey(const ValueKey<String>('motivo_truffa')));
    await tester.tap(find.byKey(ValueKey<String>('allega_${msgs[0].localId}')));
    await tester.tap(find.byKey(ValueKey<String>('allega_${msgs[1].localId}')));
    await tester.enterText(find.byKey(const ValueKey<String>('segnala_dettagli')), 'Vuole soldi prima');
    await tester.tap(find.byKey(const ValueKey<String>('segnala_blocca')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey<String>('segnala_invia')));
    await tester.tap(find.byKey(const ValueKey<String>('segnala_invia')));
    await tester.pumpAndSettle();

    expect(hub.reports, hasLength(1));
    final (String who, String c, String reason, String details, List<Map<String, String>> sent) = hub.reports.single;
    expect((who, c, reason, details), (io, conv, 'truffa', 'Vuole soldi prima'));
    expect(sent.map((Map<String, String> m) => m['t']),
        <String>['Ciao, mandami 50 euro di ricarica e ti porto la bici', 'Fai presto']);
    expect(sent.first['da'], dario);
    expect(hub.blocked(io, dario), isTrue);
    expect(find.byType(ChatThreadScreen), findsNothing, reason: 'persona bloccata: si torna indietro');
    await finish(tester, <ChatService>[me, d]);
  });

  testWidgets('Condividi l\'incontro: luogo e orario arrivano cifrati alla persona fidata', (WidgetTester tester) async {
    tall(tester);
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    final ChatService g = await fakePhone(hub, giulia);
    final String conv = await b.openDirect(io);
    await b.send(conv, 'Ci vediamo per la bici?');
    await me.refresh();
    await tester.pumpWidget(app(ChatThreadScreen(chat: me, conversationId: conv)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('chat_altro')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu_incontro')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('fidato_$bruno')), findsNothing, reason: 'non chi si incontra');

    await tester.tap(find.byKey(const ValueKey<String>('incontro_invia')));
    await tester.pump();
    expect(find.text('Scegli a chi mandarlo.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('fidato_$giulia')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('incontro_invia')));
    await tester.pump();
    expect(find.text('Scrivi dove vi incontrate.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('incontro_luogo')), 'Bar Centrale, piazza Roma');
    await tester.tap(find.byKey(const ValueKey<String>('incontro_invia')));
    await tester.pumpAndSettle();
    expect(find.text('Incontro condiviso con Giulia M.'), findsOneWidget);

    await g.refresh();
    final String text = g.messages(g.threads.single.conversation.id).single.body;
    expect(text, startsWith('📍 Incontro condiviso con te\nVedo: Bruno B. (@bruno_b)'));
    expect(text, contains('Dove: Bar Centrale, piazza Roma'));
    await finish(tester, <ChatService>[me, b, g]);
  });
}

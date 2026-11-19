// Fase 4 · Blocco 11: sezione «Chiamate» (perse, fatte, ricevute) e nomi della rubrica.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/calls/call_log.dart';
import 'package:nexus_social/features/calls/call_service.dart';
import 'package:nexus_social/features/calls/calls_list.dart';
import 'package:nexus_social/features/chat/chat_screen.dart';
import 'package:nexus_social/features/chat/chat_service.dart';

import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  late FakeChatHub hub;

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..contacts[io] = <String>{bruno}
      ..contacts[bruno] = <String>{io};
  });

  Future<(ChatService, ChatService, String)> pair() async {
    final ChatService a = await fakePhone(hub, io, calls: fakeCalls(), localNames: <String, String>{bruno: 'Bruno meccanico'});
    final ChatService b = await fakePhone(hub, bruno, calls: fakeCalls());
    final String conv = await a.openDirect(bruno);
    await a.send(conv, 'Ciao');
    await b.refresh();
    await b.send(conv, 'Ciao Anna');
    await a.refresh();
    return (a, b, conv);
  }

  test('nomi della rubrica: vincono su quelli di Piazly, nelle chat e nei contatti', () async {
    final (ChatService a, ChatService b, String conv) = await pair();
    expect(a.conversation(conv)!.displayName, 'Bruno meccanico');
    expect(b.conversation(conv)!.displayName, 'Anna R.', reason: 'Bruno non ha Anna in rubrica con un altro nome');
    expect((await a.contacts()).single.name, 'Bruno meccanico');
    expect(a.memberName(conv, bruno), 'Bruno meccanico');
    a.dispose();
    b.dispose();
  });

  test('registro: in uscita con durata, in arrivo risposta, persa; le perse nuove si contano', () async {
    final (ChatService a, ChatService b, String conv) = await pair();
    await a.calls!.start(conv, video: false);
    await b.refresh();
    await settle();
    await b.calls!.accept();
    await settle();
    await a.refresh();
    await settle();
    hub.clock = hub.clock.add(const Duration(minutes: 2, seconds: 31));
    await a.calls!.hangUp();
    await b.refresh();
    await settle();
    final CallRecord out = a.calls!.log.records.single;
    expect((out.outgoing, out.answered, out.name), (true, true, 'Bruno meccanico'));
    expect(out.duration, isNotNull);
    final CallRecord inc = b.calls!.log.records.single;
    expect((inc.outgoing, inc.answered, inc.missed), (false, true, false));

    a.calls!.dismiss();
    b.calls!.dismiss();
    await a.calls!.start(conv, video: true);
    await b.refresh();
    await settle();
    await b.calls!.reject();
    await settle();
    expect(b.calls!.log.records.first.missed, isTrue);
    expect(b.calls!.log.records.first.video, isTrue);
    expect(b.calls!.log.unseenMissed, 1);
    await b.calls!.log.markSeen(DateTime.now().add(const Duration(days: 1)));
    expect(b.calls!.log.unseenMissed, 0);
    a.dispose();
    b.dispose();
  });

  test('registro salvato sul telefono e riletto', () async {
    final Directory d = Directory.systemTemp.createTempSync('piazly_chiamate_');
    addTearDown(() => d.deleteSync(recursive: true));
    final FileCallLogStore store = FileCallLogStore(Future<Directory>.value(d));
    final CallLog log = CallLog(store);
    await log.add(CallRecord(
      id: 'x1',
      conversationId: '00000000-0000-4000-8000-000000000001',
      peerId: bruno,
      name: 'Bruno',
      at: DateTime(2026, 11, 19, 7, 30),
      outgoing: false,
      answered: false,
      video: true,
    ));
    final CallLog again = CallLog(FileCallLogStore(Future<Directory>.value(d)));
    await again.load();
    expect(again.records.single.missed, isTrue);
    expect(again.records.single.video, isTrue);
    expect(callTimeLabel(DateTime(2026, 11, 19, 7, 5), DateTime(2026, 11, 19, 9)), 'Oggi, 07:05');
    expect(callTimeLabel(DateTime(2026, 11, 18, 21, 40), DateTime(2026, 11, 19, 9)), 'Ieri, 21:40');
  });

  testWidgets('sezione «Chiamate»: elenco con persa e richiama', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final (ChatService a, ChatService b, String conv) = (await tester.runAsync(pair))!;
    await tester.runAsync(() async {
      await b.calls!.start(conv, video: false);
      await a.refresh();
      await settle();
      await a.calls!.reject();
      await settle();
      a.calls!.dismiss();
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: ChatScreen(service: a))));
    await tester.pumpAndSettle();
    expect(find.text('Chiamate · 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('sezione_chiamate')));
    await tester.pumpAndSettle();
    expect(find.text('Bruno meccanico'), findsOneWidget);
    expect(find.text('Chiamata persa'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('nuova_chiamata_vocale')), findsOneWidget);
    expect(find.text('Chiamate'), findsOneWidget, reason: 'aperta la sezione, le perse non sono più nuove');
    final CallRecord r = a.calls!.log.records.single;
    await tester.tap(find.byKey(ValueKey<String>('chiamata_menu_${r.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('richiama_${r.id}')));
    await tester.pump();
    await tester.runAsync(settle);
    await tester.pumpAndSettle();
    expect(a.calls!.state!.phase, CallPhase.outgoing);
    expect(hub.rings.last.$1, io);
    await tester.runAsync(() => a.calls!.hangUp());
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() async {
      a.dispose();
      b.dispose();
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
}

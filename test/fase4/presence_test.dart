// Fase 4 · Blocco 12: «online» e «ultimo accesso», con la scelta in Privacy.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_thread_screen.dart';
import 'package:nexus_social/features/privacy/privacy_controller.dart';
import 'package:nexus_social/features/privacy/privacy_repository.dart';
import 'package:nexus_social/features/privacy/privacy_sections.dart';

import '../support/fake_privacy_repository.dart';
import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';

void main() {
  test('testo dello stato: online, oggi, ieri, data', () {
    final DateTime now = DateTime(2026, 11, 19, 10);
    expect(presenceLabel(const Presence(online: true), now), 'online');
    expect(presenceLabel(Presence(online: false, lastSeen: DateTime(2026, 11, 19, 8, 5)), now), 'ultimo accesso oggi alle 08:05');
    expect(presenceLabel(Presence(online: false, lastSeen: DateTime(2026, 11, 18, 21, 40)), now), 'ultimo accesso ieri alle 21:40');
    expect(presenceLabel(Presence(online: false, lastSeen: DateTime(2026, 11, 12, 9, 0)), now), 'ultimo accesso il 12/11 alle 09:00');
    expect(presenceLabel(null, now), isNull);
  });

  testWidgets('nella chat: «online» sotto il nome, poi l\'ultimo accesso', (WidgetTester tester) async {
    final FakeChatHub hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..contacts[io] = <String>{bruno}
      ..contacts[bruno] = <String>{io};
    final ChatService a = (await tester.runAsync(() => fakePhone(hub, io)))!;
    final ChatService b = (await tester.runAsync(() => fakePhone(hub, bruno)))!;
    final String conv = (await tester.runAsync(() async {
      final String c = await a.openDirect(bruno);
      await a.send(c, 'Ciao');
      return c;
    }))!;
    expect(hub.presence[bruno]?.online, isTrue, reason: 'all\'avvio l\'app dice «sono online»');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: ChatThreadScreen(chat: a, conversationId: conv, now: () => hub.clock),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('online'), findsOneWidget);

    await tester.runAsync(() async => b.setForeground(false));
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.textContaining('ultimo accesso oggi alle'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    a.dispose();
    b.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Privacy → Ultimo accesso e online: tre scelte, salvate subito', (WidgetTester tester) async {
    final FakePrivacyRepository repo = FakePrivacyRepository();
    final PrivacyController c = PrivacyController(repo);
    await c.load();
    expect(PrivacySection.lastSeen.summary(c), 'I miei contatti');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: PrivacySectionBody(section: PrivacySection.lastSeen, controller: c))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('non vedi nemmeno quello degli altri'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('accesso_nessuno')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('setLastSeen:nessuno'));
    expect(c.settings.lastSeen, LastSeenVisibility.nobody);
    expect(PrivacySettings.fromJson(<String, dynamic>{'last_seen': 'tutti'}).lastSeen, LastSeenVisibility.everyone);
  });
}

// Fase 4 · Blocco 6: schermate del backup (attiva, ripristina dalla lista, «Non ora»).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/chat/chat_backup.dart';
import 'package:nexus_social/features/chat/chat_backup_screen.dart';
import 'package:nexus_social/features/chat/chat_backup_service.dart';
import 'package:nexus_social/features/chat/chat_screen.dart';
import 'package:nexus_social/features/chat/chat_service.dart';

import 'fake_chat.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';

Widget app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void main() {
  late FakeChatHub hub;

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..contacts[io] = <String>{bruno}
      ..contacts[bruno] = <String>{io};
  });

  Future<void> finish(WidgetTester tester, List<ChatService> phones) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    for (final ChatService p in phones) {
      p.dispose();
    }
  }

  testWidgets('attiva: password diverse rifiutate, poi backup fatto', (WidgetTester tester) async {
    final FakeBackupServer cloud = FakeBackupServer();
    final ChatService me = (await tester.runAsync(() => fakePhone(hub, io, backup: cloud)))!;
    await tester.runAsync(() => me.backup!.load(auto: false));
    await tester.pumpWidget(app(ChatBackupScreen(backup: me.backup!)));
    await tester.pumpAndSettle();
    expect(find.text('Nessun backup'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('backup_password')), 'Bici2026!');
    await tester.enterText(find.byKey(const ValueKey<String>('backup_password_ripeti')), 'Bici2027!');
    await tester.tap(find.byKey(const ValueKey<String>('backup_attiva')));
    await tester.pump();
    expect(find.text('Le due password non sono uguali.'), findsOneWidget);
    expect(cloud.uploads, 0);

    await tester.enterText(find.byKey(const ValueKey<String>('backup_password_ripeti')), 'Bici2026!');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey<String>('backup_attiva')));
      for (int i = 0; i < 50 && cloud.uploads == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();
    expect(cloud.uploads, 1);
    expect(find.byKey(const ValueKey<String>('backup_ora')), findsOneWidget);
    expect(find.textContaining('si aggiorna da solo'), findsOneWidget);
    await finish(tester, <ChatService>[me]);
  });

  testWidgets('telefono nuovo: la lista propone il ripristino; «Non ora» lo nasconde', (WidgetTester tester) async {
    final FakeBackupServer cloud = FakeBackupServer();
    final ChatService me = (await tester.runAsync(() => fakePhone(hub, io, backup: cloud)))!;
    final ChatBackup old = ChatBackup(chat: me, server: cloud, keys: MemoryBackupKeyStore(), kdf: fastKdfForTests());
    await tester.runAsync(() => old.enable('Bici2026!'));
    await tester.runAsync(() => me.backup!.load(auto: false));
    await tester.pumpWidget(app(Scaffold(body: ChatScreen(service: me))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('backup_offerta_ripristino')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('backup_apri_ripristino')));
    await tester.pumpAndSettle();
    expect(find.text('Recupera le chat'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('backup_ripristina')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('backup_non_ora')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('backup_offerta_ripristino')), findsNothing);
    old.dispose();
    await finish(tester, <ChatService>[me]);
  });

  test('data del backup in parole', () {
    final DateTime n = DateTime(2026, 11, 18, 10);
    expect(backupDateLabel(DateTime(2026, 11, 18, 8, 5), n), 'oggi alle 08:05');
    expect(backupDateLabel(DateTime(2026, 11, 17, 23, 5), n), '17/11 alle 23:05');
    expect(backupDateLabel(DateTime(2025, 12, 1, 9, 0), n), '1/12/2025 alle 09:00');
  });
}

// Anteprime per il titolare (Fase 4, Blocco 1): la chat con dati finti.
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/chat/chat_backup.dart';
import 'package:nexus_social/features/chat/chat_backup_screen.dart';
import 'package:nexus_social/features/chat/chat_backup_service.dart';
import 'package:nexus_social/features/chat/chat_group_screens.dart';
import 'package:nexus_social/features/chat/chat_media.dart';
import 'package:nexus_social/features/chat/chat_media_picker.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_screen.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_thread_screen.dart';
import 'package:nexus_social/features/notifications/notification_settings.dart';
import 'package:nexus_social/features/shell/app_shell.dart';

import '../../test/fase4/fake_chat.dart';

Future<void> _loadFonts() async {
  final String root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final Directory dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final FontLoader roboto = FontLoader('Roboto');
  final FontLoader fallback = FontLoader('FlutterTest');
  final FontLoader ahem = FontLoader('Ahem');
  final FontLoader icons = FontLoader('MaterialIcons');
  for (final FileSystemEntity f in dir.listSync()) {
    final String name = f.uri.pathSegments.last;
    final Future<ByteData> data =
        File(f.path).readAsBytes().then((Uint8List b) => ByteData.view(b.buffer));
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) {
      roboto.addFont(data);
      fallback.addFont(data);
      ahem.addFont(data);
    }
    if (name.startsWith('MaterialIcons-Regular')) icons.addFont(data);
  }
  // Emoji a colori (installate dal workflow delle anteprime, se disponibili).
  final File emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emoji.existsSync()) {
    final FontLoader e = FontLoader('NotoColorEmoji')
      ..addFont(emoji.readAsBytes().then((Uint8List b) => ByteData.view(b.buffer)));
    await e.load();
  }
  await roboto.load();
  await fallback.load();
  await ahem.load();
  await icons.load();
}

ThemeData _withRoboto(ThemeData base) => _withRobotoOnly(
  base.copyWith(textTheme: base.textTheme.apply(fontFamilyFallback: const <String>['NotoColorEmoji'])),
);

ThemeData _withRobotoOnly(ThemeData t) => t.copyWith(
  filledButtonTheme: FilledButtonThemeData(
    style: t.filledButtonTheme.style?.copyWith(
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w800),
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: (t.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700),
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      textStyle: const TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700),
    ),
  ),
  chipTheme: t.chipTheme.copyWith(
    labelStyle: (t.chipTheme.labelStyle ?? const TextStyle()).copyWith(fontFamily: 'Roboto'),
  ),
  listTileTheme: t.listTileTheme.copyWith(
    titleTextStyle: (t.listTileTheme.titleTextStyle ?? t.textTheme.bodyLarge)
        ?.copyWith(fontFamily: 'Roboto'),
    subtitleTextStyle: (t.listTileTheme.subtitleTextStyle ?? t.textTheme.bodyMedium)
        ?.copyWith(fontFamily: 'Roboto'),
  ),
);

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String giulia = 'utenteGiulia0000000000000003';
const String marco = 'utenteMarco00000000000000005';
const String dario = 'utenteDario00000000000000004';

/// Dati di prova: tre chat (una letta, una con messaggi nuovi, una di ieri) e una richiesta.
Future<(ChatService, Map<String, ChatService>, Map<String, String>)> _scene({BackupServer? backup}) async {
  final FakeChatHub hub = FakeChatHub()
    ..addPerson(io, 'anna.r', 'Anna R.')
    ..addPerson(bruno, 'bruno_b', 'Bruno B.')
    ..addPerson(giulia, 'giulia.m', 'Giulia M.')
    ..addPerson(marco, 'marco_t', 'Marco T.')
    ..addPerson(dario, 'dario88', 'Dario V.')
    ..contacts[io] = <String>{bruno, giulia, marco}
    ..contacts[bruno] = <String>{io}
    ..contacts[giulia] = <String>{io}
    ..contacts[marco] = <String>{io};
  final ChatService me = await fakePhone(hub, io, backup: backup);
  final Map<String, ChatService> others = <String, ChatService>{
    for (final String id in <String>[bruno, giulia, marco, dario]) id: await fakePhone(hub, id),
  };
  final Map<String, String> conv = <String, String>{};

  hub.clock = DateTime(2026, 11, 15, 21, 10);
  conv[marco] = await me.openDirect(marco);
  await me.send(conv[marco]!, 'Grazie ancora per il passaggio!');
  await others[marco]!.refresh();
  await others[marco]!.send(conv[marco]!, 'Figurati, alla prossima!');

  hub.clock = DateTime(2026, 11, 16, 17, 40);
  conv[bruno] = await me.openDirect(bruno);
  await me.send(conv[bruno]!, 'Ciao Bruno, la bici è ancora disponibile?');
  await others[bruno]!.refresh();
  await others[bruno]!.send(conv[bruno]!, 'Sì! È in ottimo stato, gomme nuove.');
  await others[bruno]!.send(conv[bruno]!, 'Se vuoi puoi passare a vederla domani.');
  await me.refresh();
  await me.markRead(conv[bruno]!);
  await me.send(conv[bruno]!, 'Perfetto, domani alle 18 va bene?');
  await others[bruno]!.refresh();
  await others[bruno]!.markRead(conv[bruno]!);
  await me.send(conv[bruno]!, 'Ti scrivo quando parto.');
  await others[bruno]!.refresh();

  hub.clock = DateTime(2026, 11, 16, 18, 20);
  conv[giulia] = await others[giulia]!.openDirect(io);
  await others[giulia]!.send(conv[giulia]!, 'Hai visto il mercatino in piazza sabato?');
  await others[giulia]!.send(conv[giulia]!, 'Ci andiamo insieme?');

  hub.clock = DateTime(2026, 11, 16, 18, 45);
  conv[dario] = await others[dario]!.openDirect(io);
  await others[dario]!.send(conv[dario]!, 'Ciao, ho visto il tuo annuncio della lampada: è ancora disponibile?');

  await me.refresh();
  return (me, others, conv);
}

/// Telefono finto per le anteprime: il microfono «registra» subito.
class _Device implements ChatDevice {
  @override
  Future<PickedMedia?> pickImage({required bool camera}) async => null;
  @override
  Future<PickedMedia?> pickVideo() async => null;
  @override
  Future<PickedMedia?> pickFile() async => null;
  @override
  Future<bool> startVoice() async => true;
  @override
  Future<PickedMedia?> stopVoice() async => null;
  @override
  Future<void> cancelVoice() async {}
}

/// Foto di prova: un tramonto sfumato con una «bici» stilizzata.
Uint8List _photo() {
  final img.Image p = img.Image(width: 1200, height: 900);
  for (int y = 0; y < 900; y++) {
    final int r = 255 - y ~/ 8, g = 140 + y ~/ 12, b = 90 + y ~/ 5;
    img.drawLine(p, x1: 0, y1: y, x2: 1199, y2: y, color: img.ColorRgb8(r, g.clamp(0, 255), b.clamp(0, 255)));
  }
  img.fillCircle(p, x: 900, y: 260, radius: 110, color: img.ColorRgb8(255, 230, 150));
  for (final int cx in <int>[420, 780]) {
    img.drawCircle(p, x: cx, y: 640, radius: 150, color: img.ColorRgb8(30, 35, 60));
    img.drawCircle(p, x: cx, y: 640, radius: 146, color: img.ColorRgb8(30, 35, 60));
  }
  img.drawLine(p, x1: 420, y1: 640, x2: 600, y2: 440, color: img.ColorRgb8(30, 35, 60), thickness: 14);
  img.drawLine(p, x1: 600, y1: 440, x2: 780, y2: 640, color: img.ColorRgb8(30, 35, 60), thickness: 14);
  img.drawLine(p, x1: 420, y1: 640, x2: 600, y2: 640, color: img.ColorRgb8(30, 35, 60), thickness: 14);
  return img.encodeJpg(p, quality: 85);
}

void main() {
  setUpAll(_loadFonts);
  final DateTime now = DateTime(2026, 11, 16, 19);

  Future<void> shoot(WidgetTester tester, String name, Widget home,
      {Future<void> Function()? before}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // Nei test le ombre diventano bordi neri: qui si disegnano come sul telefono.
    debugDisableShadows = false;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _withRoboto(AppTheme.light),
      home: home,
    ));
    await tester.pumpAndSettle();
    if (before != null) await before();
    await tester.pumpAndSettle();
    // Le foto si decodificano solo fuori dal tempo finto dei test.
    await tester.runAsync(() async {
      for (final Element e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();
    try {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('chat 1 · lista delle chat con richiesta', (tester) async {
    final (ChatService me, Map<String, ChatService> others, _) = (await tester.runAsync(_scene))!;
    await shoot(tester, 'chat_1_lista', AppShell(chat: me));
    me.dispose();
    for (final ChatService o in others.values) {
      o.dispose();
    }
  });

  testWidgets('chat 2 · conversazione con le spunte', (tester) async {
    final (ChatService me, Map<String, ChatService> others, Map<String, String> conv) =
        (await tester.runAsync(_scene))!;
    await shoot(tester, 'chat_2_conversazione',
        ChatThreadScreen(chat: me, conversationId: conv[bruno]!, now: () => now));
    me.dispose();
    for (final ChatService o in others.values) {
      o.dispose();
    }
  });

  testWidgets('chat 3 · richiesta da uno sconosciuto', (tester) async {
    final (ChatService me, Map<String, ChatService> others, Map<String, String> conv) =
        (await tester.runAsync(_scene))!;
    await shoot(tester, 'chat_3_richiesta',
        ChatThreadScreen(chat: me, conversationId: conv[dario]!, now: () => now));
    me.dispose();
    for (final ChatService o in others.values) {
      o.dispose();
    }
  });

  testWidgets('chat 4 · nuova chat dalla rubrica', (tester) async {
    final (ChatService me, Map<String, ChatService> others, _) = (await tester.runAsync(_scene))!;
    await shoot(tester, 'chat_4_nuova', NewChatScreen(chat: me));
    me.dispose();
    for (final ChatService o in others.values) {
      o.dispose();
    }
  });

  testWidgets('chat 5 · prima volta, nessuna chat', (tester) async {
    final FakeChatHub hub = FakeChatHub()..addPerson(io, 'anna.r', 'Anna R.');
    final ChatService me = (await tester.runAsync(() => fakePhone(hub, io)))!;
    await shoot(tester, 'chat_5_vuota', AppShell(chat: me));
    me.dispose();
  });

  Future<(ChatService, ChatService, String)> scene2() async {
    final FakeChatHub hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..contacts[io] = <String>{bruno}
      ..contacts[bruno] = <String>{io};
    final ChatService me = await fakePhone(hub, io);
    final ChatService b = await fakePhone(hub, bruno);
    hub.clock = DateTime(2026, 11, 16, 18, 2);
    final String conv = await b.openDirect(io);
    await b.send(conv, 'La bici costa 120 euro, ma si può trattare.');
    await me.refresh();
    await me.send(conv, 'Facciamo 100?', replyTo: me.messages(conv).first);
    await b.refresh();
    await b.react(b.messages(conv).last, '👍');
    await b.send(conv, 'Affare fatto! Ti giro l\'indirizzo');
    await b.send(conv, 'Via Roma 10, citofono Bianchi. Dalle 17 in poi.', forwarded: true);
    await me.refresh();
    await me.react(me.messages(conv).last, '❤️');
    await me.send(conv, 'Ops, chat sbagliata');
    await me.deleteForEveryone(me.messages(conv).last);
    await me.send(conv, 'A domani allora!');
    await b.refresh();
    await b.markRead(conv);
    await me.refresh();
    return (me, b, conv);
  }

  testWidgets('chat 6 · risposta, reazioni, inoltrato, eliminato', (tester) async {
    final (ChatService me, ChatService b, String conv) = (await tester.runAsync(scene2))!;
    await shoot(tester, 'chat_6_risposte_reazioni',
        ChatThreadScreen(chat: me, conversationId: conv, now: () => now));
    me.dispose();
    b.dispose();
  });

  testWidgets('chat 7 · tieni premuto un messaggio', (tester) async {
    final (ChatService me, ChatService b, String conv) = (await tester.runAsync(scene2))!;
    await shoot(tester, 'chat_7_azioni',
        ChatThreadScreen(chat: me, conversationId: conv, now: () => now), before: () async {
      await tester.longPress(find.textContaining('Via Roma 10'));
      await tester.pumpAndSettle();
    });
    me.dispose();
    b.dispose();
  });

  /// Decodifica in anticipo, fuori dal tempo finto, le foto già salvate sul telefono:
  /// così il fumetto le trova pronte.
  Future<void> warm(ChatService me, String conv) async {
    for (final ChatMessage m in me.messages(conv)) {
      if (m.media?.kind != MediaKind.image) continue;
      final File? f = await me.localFileOf(m);
      if (f == null) continue;
      final Completer<void> done = Completer<void>();
      final ImageStream stream = FileImage(f).resolve(ImageConfiguration.empty);
      late final ImageStreamListener l;
      l = ImageStreamListener((ImageInfo _, bool _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(l);
      }, onError: (Object _, StackTrace? _) {
        if (!done.isCompleted) done.complete();
      });
      stream.addListener(l);
      await done.future;
    }
  }

  Future<(ChatService, ChatService, String)> scene3() async {
    final FakeChatHub hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..contacts[io] = <String>{bruno}
      ..contacts[bruno] = <String>{io};
    final ChatService me = await fakePhone(hub, io, files: Directory.systemTemp.createTempSync('anna_'));
    final ChatService b = await fakePhone(hub, bruno, files: Directory.systemTemp.createTempSync('bruno_'));
    hub.clock = DateTime(2026, 11, 18, 10, 2);
    final String conv = await b.openDirect(io);
    final PickedMedia? photo = await prepareImage(_photo());
    await b.sendMedia(conv, kind: MediaKind.image, bytes: photo!.bytes, mime: 'image/jpeg',
        width: photo.width, height: photo.height, thumb: photo.thumb, caption: 'Eccola, appena lavata');
    await me.refresh();
    await me.download(me.messages(conv).last);
    await me.sendMedia(conv, kind: MediaKind.audio, bytes: Uint8List.fromList(List<int>.filled(30000, 1)),
        mime: 'audio/mp4', durationMs: 14000);
    await b.refresh();
    await b.sendMedia(conv, kind: MediaKind.file, bytes: Uint8List.fromList(List<int>.filled(245000, 2)),
        mime: 'application/pdf', name: 'Preventivo_bici.pdf');
    await b.sendMedia(conv, kind: MediaKind.video, bytes: Uint8List.fromList(List<int>.filled(8400000, 3)),
        mime: 'video/mp4', name: 'giro_prova.mp4');
    await me.refresh();
    await b.refresh();
    await b.markRead(conv);
    await me.refresh();
    await warm(me, conv);
    return (me, b, conv);
  }

  testWidgets('chat 8 · foto, vocale, documento e video cifrati', (tester) async {
    final (ChatService me, ChatService b, String conv) = (await tester.runAsync(scene3))!;
    await shoot(tester, 'chat_8_allegati',
        ChatThreadScreen(chat: me, conversationId: conv, now: () => now, device: _Device()));
    me.dispose();
    b.dispose();
  });

  testWidgets('chat 9 · graffetta: cosa allegare', (tester) async {
    final (ChatService me, ChatService b, String conv) = (await tester.runAsync(scene3))!;
    await shoot(tester, 'chat_9_allega',
        ChatThreadScreen(chat: me, conversationId: conv, now: () => now, device: _Device()), before: () async {
      await tester.tap(find.byKey(const ValueKey<String>('chat_allega')));
      await tester.pumpAndSettle();
    });
    me.dispose();
    b.dispose();
  });

  Future<(ChatService, List<ChatService>, String)> scene4() async {
    final FakeChatHub hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..addPerson(giulia, 'giulia.m', 'Giulia M.')
      ..addPerson(marco, 'marco_t', 'Marco T.')
      ..addPerson(dario, 'dario88', 'Dario V.')
      ..contacts[io] = <String>{bruno, giulia, marco}
      ..contacts[bruno] = <String>{io}
      ..contacts[giulia] = <String>{io}
      ..contacts[marco] = <String>{io};
    final ChatService me = await fakePhone(hub, io);
    final List<ChatService> others = <ChatService>[
      for (final String id in <String>[bruno, giulia, marco, dario]) await fakePhone(hub, id),
    ];
    hub.clock = DateTime(2026, 11, 18, 17, 30);
    final String g = await me.createGroup('Gita al lago', <String>[bruno, giulia, marco, dario]);
    for (final ChatService o in others) {
      await o.refresh();
    }
    await me.send(g, 'Allora confermato sabato? Partenza alle 9 dal parcheggio');
    for (final ChatService o in others.take(3)) {
      await o.refresh();
    }
    await others[0].send(g, 'Ci sono! Porto io il pallone');
    await others[1].send(g, 'Anche io, con la macchina: 3 posti liberi');
    await me.refresh();
    await me.react(me.messages(g).last, '❤️');
    await others[2].refresh();
    await others[2].send(g, 'Prenoto io il tavolo per pranzo, siamo in 4?',
        replyTo: others[2].messages(g).firstWhere((m) => m.body.startsWith('Allora')));
    await me.refresh();
    for (final ChatService o in others.take(3)) {
      await o.refresh();
      await o.markRead(g);
    }
    await me.refresh();
    return (me, others, g);
  }

  testWidgets('chat 11 · gruppo con nomi, citazione e reazione', (tester) async {
    final (ChatService me, List<ChatService> others, String g) = (await tester.runAsync(scene4))!;
    await shoot(tester, 'chat_11_gruppo', ChatThreadScreen(chat: me, conversationId: g, now: () => now));
    me.dispose();
    for (final ChatService o in others) {
      o.dispose();
    }
  });

  testWidgets('chat 12 · info del gruppo', (tester) async {
    final (ChatService me, List<ChatService> others, String g) = (await tester.runAsync(scene4))!;
    await tester.runAsync(() => me.groupMembers(g));
    await shoot(tester, 'chat_12_info_gruppo', GroupInfoScreen(chat: me, conversationId: g));
    me.dispose();
    for (final ChatService o in others) {
      o.dispose();
    }
  });

  testWidgets('chat 13 · nuovo gruppo', (tester) async {
    final (ChatService me, List<ChatService> others, String _) = (await tester.runAsync(scene4))!;
    await shoot(tester, 'chat_13_nuovo_gruppo', NewGroupScreen(chat: me), before: () async {
      await tester.enterText(find.byKey(const ValueKey<String>('gruppo_nome')), 'Calcetto giovedì');
      await tester.tap(find.byKey(ValueKey<String>('scegli_$bruno')));
      await tester.tap(find.byKey(ValueKey<String>('scegli_$marco')));
      await tester.pumpAndSettle();
    });
    me.dispose();
    for (final ChatService o in others) {
      o.dispose();
    }
  });

  testWidgets('chat 14 · lista con il gruppo e l\'invito', (tester) async {
    final (ChatService me, List<ChatService> others, String _) = (await tester.runAsync(scene4))!;
    await shoot(tester, 'chat_14_lista_gruppi', AppShell(chat: me));
    // Dario (non in rubrica di Anna) vede l'invito tra le richieste.
    await shoot(tester, 'chat_15_invito_gruppo',
        ChatThreadScreen(chat: others[3], conversationId: others[3].requests.single.conversation.id, now: () => now));
    me.dispose();
    for (final ChatService o in others) {
      o.dispose();
    }
  });

  testWidgets('chat 16 · Silenzia una chat', (tester) async {
    final (ChatService me, Map<String, ChatService> others, Map<String, String> conv) =
        (await tester.runAsync(_scene))!;
    await tester.runAsync(() => me.setMute(conv[bruno]!));
    await shoot(tester, 'chat_16_silenzia',
        ChatThreadScreen(chat: me, conversationId: conv[bruno]!, now: () => now), before: () async {
      await tester.tap(find.byKey(const ValueKey<String>('silenzia_chat')));
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(const SizedBox());
    await shoot(tester, 'chat_17_lista_silenziata', AppShell(chat: me));
    me.dispose();
    for (final ChatService o in others.values) {
      o.dispose();
    }
  });

  testWidgets('chat 19-22 · backup delle chat', (tester) async {
    final FakeBackupServer cloud = FakeBackupServer(now: () => DateTime(2026, 11, 17, 23, 5));
    final (ChatService me, Map<String, ChatService> others, _) =
        (await tester.runAsync(() => _scene(backup: cloud)))!;
    final ChatBackup fresh = me.backup!;
    await tester.runAsync(() => fresh.load(auto: false));
    await shoot(tester, 'chat_19_backup_attiva', ChatBackupScreen(backup: fresh, now: () => now));

    // Backup fatto dal vecchio telefono: quello nuovo propone di ripristinarlo.
    final ChatBackup old = ChatBackup(chat: me, server: cloud, keys: MemoryBackupKeyStore(), kdf: fastKdfForTests());
    await tester.runAsync(() => old.enable('Bici2026!'));
    await tester.runAsync(() => fresh.load(auto: false));
    await tester.pumpWidget(const SizedBox());
    await shoot(tester, 'chat_20_ripristina_lista', AppShell(chat: me));
    await tester.pumpWidget(const SizedBox());
    await shoot(tester, 'chat_21_ripristino', ChatBackupScreen(backup: fresh, now: () => now));
    await tester.pumpWidget(const SizedBox());
    await shoot(tester, 'chat_22_backup_attivo', ChatBackupScreen(backup: old, now: () => now));
    old.dispose();
    me.dispose();
    for (final ChatService o in others.values) {
      o.dispose();
    }
  });

  testWidgets('chat 18 · Profilo → Notifiche', (tester) async {
    await shoot(tester, 'chat_18_notifiche',
        NotificationSettingsScreen(repository: _Prefs()));
  });
}

class _Prefs implements PushSettingsRepository {
  @override
  Future<PushSettings> load() async => const PushSettings(dndEnabled: true, comments: false);

  @override
  Future<void> save(PushSettings settings) async {}
}

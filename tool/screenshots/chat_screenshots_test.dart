// Anteprime per il titolare (Fase 4, Blocco 1): la chat con dati finti.
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/chat/chat_screen.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_thread_screen.dart';
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
Future<(ChatService, Map<String, ChatService>, Map<String, String>)> _scene() async {
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
}

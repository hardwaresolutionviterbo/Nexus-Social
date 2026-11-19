// Fase 4 · Blocco 13: Stati di 24 ore (testo, foto, video) e chi li vede.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/status/status_screens.dart';
import 'package:nexus_social/features/status/status_service.dart';
import 'package:nexus_social/features/status/status_tab.dart';

import 'fake_chat.dart';
import 'fake_status.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String carla = 'utenteCarla00000000000000003';
const String dario = 'utenteDario00000000000000004';

class _Picker implements StatusPicker {
  _Picker(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List?> pickImage({required bool camera}) async => bytes;

  @override
  Future<Uint8List?> pickVideo() async => null;
}

void main() {
  late FakeChatHub hub;
  late FakeStatusHub stati;

  setUp(() {
    hub = FakeChatHub()
      ..addPerson(io, 'anna.r', 'Anna R.')
      ..addPerson(bruno, 'bruno_b', 'Bruno B.')
      ..addPerson(carla, 'carla', 'Carla C.')
      ..addPerson(dario, 'dario88', 'Dario V.')
      // Anna ha in rubrica Bruno e Carla; Bruno e Carla hanno Anna.
      ..contacts[io] = <String>{bruno, carla}
      ..contacts[bruno] = <String>{io}
      ..contacts[carla] = <String>{io};
    stati = FakeStatusHub(hub);
  });

  Future<ChatService> phone(String uid, {Map<String, String>? names, StatusPrefsStore? prefs}) =>
      fakePhone(hub, uid, statuses: stati.serviceFor(uid, prefs: prefs), localNames: names);

  test('«I miei contatti»: lo vede chi ho in rubrica, non chi mi ha solo lui in rubrica', () async {
    final ChatService a = await phone(io);
    final ChatService b = await phone(bruno, names: <String, String>{io: 'Annina'});
    final ChatService d = await phone(dario);
    hub.contacts[dario] = <String>{io};
    await a.statuses!.postText('  Al mare oggi!  ', 2);
    expect(a.statuses!.mine.single.body, 'Al mare oggi!');
    expect(a.statuses!.myGroup!.items, hasLength(1));
    await b.statuses!.load();
    await d.statuses!.load();
    expect(b.statuses!.recent.single.name, 'Annina', reason: 'il nome come scritto nella rubrica di Bruno');
    expect(b.statuses!.unseenCount, 1);
    expect(d.statuses!.recent, isEmpty, reason: 'Anna non ha Dario in rubrica');
    for (final ChatService s in <ChatService>[a, b, d]) {
      s.dispose();
    }
  });

  test('«Tranne…» e «Solo con…»: la scelta resta per i prossimi stati', () async {
    final MemoryStatusPrefsStore prefs = MemoryStatusPrefsStore();
    final ChatService a = await phone(io, prefs: prefs);
    final ChatService b = await phone(bruno);
    final ChatService c = await phone(carla);
    await a.statuses!.setAudience(StatusAudience.except, <String>[bruno]);
    await a.statuses!.postText('Non per Bruno', 0);
    await b.statuses!.load();
    await c.statuses!.load();
    expect(b.statuses!.recent, isEmpty);
    expect(c.statuses!.recent.single.items.single.body, 'Non per Bruno');
    expect(prefs.audience, StatusAudience.except);
    expect(prefs.people, <String>[bruno]);

    await a.statuses!.setAudience(StatusAudience.only, <String>[bruno]);
    await a.statuses!.postText('Solo per Bruno', 1);
    await b.statuses!.load();
    await c.statuses!.load();
    expect(b.statuses!.recent.single.items.single.body, 'Solo per Bruno');
    expect(c.statuses!.recent.single.items.map((StatusItem s) => s.body), <String>['Non per Bruno']);

    await a.statuses!.setAudience(StatusAudience.only, const <String>[]);
    await expectLater(a.statuses!.postText('Per nessuno', 0), throwsA(isA<ChatFailure>()));
    await expectLater(a.statuses!.postText('   ', 0), throwsA(isA<ChatFailure>()));
    await a.statuses!.setAudience(StatusAudience.contacts, <String>[bruno]);
    expect(a.statuses!.people, isEmpty, reason: '«I miei contatti» non ha eccezioni');
    for (final ChatService s in <ChatService>[a, b, c]) {
      s.dispose();
    }
  });

  test('visto: passa in «Già visti»; chi l\'ha visto lo sa solo l\'autore', () async {
    final ChatService a = await phone(io);
    final ChatService b = await phone(bruno);
    final ChatService c = await phone(carla);
    await a.statuses!.postText('Primo', 0);
    await a.statuses!.postText('Secondo', 3);
    await b.statuses!.load();
    final StatusGroup g = b.statuses!.recent.single;
    expect(g.items.map((StatusItem s) => s.body), <String>['Primo', 'Secondo']);
    await b.statuses!.markSeen(g.items.first);
    expect(b.statuses!.recent.single.firstUnseen, 1, reason: 'si riprende dal primo non visto');
    await b.statuses!.markSeen(b.statuses!.recent.single.items.last);
    expect(b.statuses!.recent, isEmpty);
    expect(b.statuses!.viewed.single.userId, io);
    await b.statuses!.load();
    expect(b.statuses!.viewed, hasLength(1), reason: 'anche dopo aver ricaricato');

    await a.statuses!.load();
    final StatusItem first = a.statuses!.mine.first;
    expect(first.views, 1);
    expect((await a.statuses!.viewers(first)).single.name, 'Bruno B.');
    await c.statuses!.load();
    expect(await c.statuses!.viewers(c.statuses!.recent.single.items.first), isEmpty);
    for (final ChatService s in <ChatService>[a, b, c]) {
      s.dispose();
    }
  });

  test('foto: caricata nella mia cartella, la apre solo chi può vederla; dopo 24 ore sparisce', () async {
    final ChatService a = await phone(io);
    final ChatService b = await phone(bruno);
    final ChatService d = await phone(dario);
    final Uint8List jpg = Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 1, 2, 3]);
    await a.statuses!.postMedia(kind: StatusKind.photo, bytes: jpg, caption: 'Tramonto');
    final StatusItem mine = a.statuses!.mine.single;
    expect(mine.mediaPath, startsWith('$io/'));
    expect(mine.mediaPath, endsWith('.jpg'));
    expect(stati.files, contains(mine.mediaPath));
    await b.statuses!.load();
    expect(await b.statuses!.media(b.statuses!.recent.single.items.single), jpg);
    final StatusService other = StatusService(server: stati.serverFor(dario), myId: dario);
    await expectLater(other.media(mine), throwsA(isA<ChatFailure>()));

    stati.failCreate = true;
    await expectLater(a.statuses!.postMedia(kind: StatusKind.photo, bytes: jpg), throwsA(isA<ChatFailure>()));
    expect(stati.files, hasLength(1), reason: 'il file caricato per lo stato non riuscito si toglie');
    stati.failCreate = false;
    await expectLater(
      a.statuses!.postMedia(kind: StatusKind.video, bytes: Uint8List(StatusService.maxBytes + 1)),
      throwsA(isA<ChatFailure>()),
    );

    hub.clock = hub.clock.add(const Duration(hours: 24, minutes: 1));
    await b.statuses!.load();
    expect(b.statuses!.recent, isEmpty);
    expect(a.statuses!.mine, isEmpty, reason: 'scaduto anche senza ricaricare');
    final ChatService a2 = await phone(io);
    await a2.statuses!.load();
    expect(stati.rows, isEmpty, reason: 'all\'avvio si cancellano i miei stati scaduti');
    expect(stati.files, isEmpty, reason: '…e i loro file');
    for (final ChatService s in <ChatService>[a, a2, b, d]) {
      s.dispose();
    }
  });

  test('elimina: sparisce per tutti, con il file', () async {
    final ChatService a = await phone(io);
    final ChatService b = await phone(bruno);
    await a.statuses!.postMedia(kind: StatusKind.photo, bytes: Uint8List.fromList(<int>[1, 2, 3]));
    await a.statuses!.delete(a.statuses!.mine.single);
    expect(a.statuses!.mine, isEmpty);
    expect(stati.files, isEmpty);
    await b.statuses!.load();
    expect(b.statuses!.recent, isEmpty);
    a.dispose();
    b.dispose();
  });

  test('scelta del pubblico salvata sul telefono', () async {
    final Directory dir = Directory.systemTemp.createTempSync('piazly_stati_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final FileStatusPrefsStore store = FileStatusPrefsStore(Future<Directory>.value(dir));
    expect((await store.load()).$1, StatusAudience.contacts);
    await store.save(StatusAudience.only, <String>[bruno, carla]);
    final (StatusAudience a, List<String> p) = await FileStatusPrefsStore(Future<Directory>.value(dir)).load();
    expect(a, StatusAudience.only);
    expect(p, <String>[bruno, carla]);
    final DateTime now = DateTime(2026, 11, 19, 18, 30);
    expect(statusTimeLabel(now.subtract(const Duration(seconds: 20)), now), 'Adesso');
    expect(statusTimeLabel(now.subtract(const Duration(minutes: 12)), now), '12 minuti fa');
    expect(statusTimeLabel(DateTime(2026, 11, 19, 9, 5), now), 'Oggi, 09:05');
    expect(statusTimeLabel(DateTime(2026, 11, 18, 21, 40), now), 'Ieri, 21:40');
  });

  Future<void> big(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('sezione «Stati»: scrivo uno stato, Bruno lo vede, apre e passa in «Già visti»',
      (WidgetTester tester) async {
    await big(tester);
    final (ChatService a, ChatService b) = (await tester.runAsync(() async => (await phone(io), await phone(bruno))))!;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: StatusTab(chat: a))));
    await tester.pumpAndSettle();
    expect(find.text('Crea un aggiornamento con testo, foto o video'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('stati_avviso')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('stato_testo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('stato_colore')));
    await tester.enterText(find.byKey(const ValueKey<String>('stato_scrivi')), 'Buongiorno a tutti');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('stato_pubblica')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 aggiornamento'), findsOneWidget);
    expect(a.statuses!.mine.single.color, 1);

    await tester.pumpWidget(const SizedBox());
    // Sul telefono si ricaricano all'avvio e quando l'app torna in primo piano.
    await tester.runAsync(() => b.statuses!.load());
    expect(b.statuses!.unseenCount, 1, reason: 'il numero sulla scheda «Stati» della barra');
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: StatusTab(chat: b))));
    await tester.pumpAndSettle();
    expect(find.text('Aggiornamenti recenti'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('stato_di_$io')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Buongiorno a tutti'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('stato_visto_da')), findsNothing, reason: 'non è mio');
    // Dopo 5 secondi si chiude da solo (era l'unico).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Già visti'), findsOneWidget);
    expect(find.text('Aggiornamenti recenti'), findsNothing);
    expect(stati.rows.single.views.keys, <String>[bruno]);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      a.dispose();
      b.dispose();
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('foto con didascalia, «Solo con…», poi «Visto da» ed elimina', (WidgetTester tester) async {
    await big(tester);
    final (ChatService a, ChatService b) = (await tester.runAsync(() async => (await phone(io), await phone(bruno))))!;
    final Uint8List png = base64Png;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: StatusTab(chat: a, picker: _Picker(png))),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('stati_privacy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('pubblico_solo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('pubblico_fatto')));
    await tester.pumpAndSettle();
    expect(find.text('Scegli almeno una persona.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('persona_$bruno')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('pubblico_fatto')));
    await tester.pumpAndSettle();
    expect(find.text('Solo 1 persona'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('stato_foto')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('stato_galleria')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('stato_didascalia')), 'Che vista');
    await tester.tap(find.byKey(const ValueKey<String>('stato_pubblica')));
    await tester.pumpAndSettle();
    final FakeStatusRow row = stati.rows.single;
    expect((row.kind, row.body, row.audience), (StatusKind.photo, 'Che vista', StatusAudience.only));
    expect(row.people, <String>{bruno});

    await tester.runAsync(() async {
      await b.statuses!.load();
      await b.statuses!.markSeen(b.statuses!.recent.single.items.single);
      await a.statuses!.load();
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('il_mio_stato')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Che vista'), findsOneWidget);
    expect(find.text('Visto da 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('stato_visto_da')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Visto da 1 persona'), findsOneWidget);
    expect(find.text('Bruno B.'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey<String>('stato_elimina')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey<String>('stato_elimina_conferma')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(stati.rows, isEmpty);
    expect(stati.files, isEmpty);
    expect(find.text('Crea un aggiornamento con testo, foto o video'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      a.dispose();
      b.dispose();
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// Immagine PNG 1×1 valida.
final Uint8List base64Png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

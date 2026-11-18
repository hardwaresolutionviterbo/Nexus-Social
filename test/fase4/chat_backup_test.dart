// Fase 4 · Blocco 6: backup della chat cifrato con password, con la cifratura MLS vera.
// Un telefono fa il backup, il telefono nuovo lo ripristina con la password giusta.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/features/chat/chat_backup.dart';
import 'package:nexus_social/features/chat/chat_backup_service.dart';
import 'package:nexus_social/features/chat/chat_crypto.dart';
import 'package:nexus_social/features/chat/chat_media.dart';
import 'package:nexus_social/features/chat/chat_models.dart';
import 'package:nexus_social/features/chat/chat_service.dart';
import 'package:nexus_social/features/chat/chat_store.dart';

import 'fake_chat.dart';

const String anna = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';

Future<ChatService> phone(
  FakeChatHub hub,
  String uid, {
  BackupServer? backup,
  BackupKeyStore? keys,
  ChatStore? store,
}) async {
  final Directory files = Directory.systemTemp.createTempSync('piazly_backup_');
  addTearDown(() => files.deleteSync(recursive: true));
  final ChatService s = ChatService(
    media: hub.media,
    files: ChatMediaFiles(Future<Directory>.value(files)),
    server: hub.serverFor(uid),
    crypto: () => MlsChatCrypto.open(uid: uid, dbPath: ':memory:'),
    store: store ?? MemoryChatStore(),
    myId: uid,
    fastPoll: const Duration(days: 1),
    slowPoll: const Duration(days: 1),
    backupServer: backup,
    backupKeys: backup == null ? null : (keys ?? MemoryBackupKeyStore()),
    backupKdf: fastKdfForTests(),
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
      ..contacts[anna] = <String>{bruno}
      ..contacts[bruno] = <String>{anna};
  });

  group('cifratura del file', () {
    test('si apre solo con la password giusta; il server vede solo byte illeggibili', () async {
      final BackupKey key = await BackupCipher.deriveKey('Bici2026!', kdf: fastKdfForTests());
      final Uint8List plain = utf8.encode('{"v":1,"segreto":"Ci vediamo alle 18 in piazza"}');
      final Uint8List file = await BackupCipher.seal(key, plain);
      expect(utf8.decode(file, allowMalformed: true), isNot(contains('piazza')));
      expect(file.sublist(0, 4), utf8.encode('PZBK'));

      final opened = await BackupCipher.open('Bici2026!', file);
      expect(opened.plain, plain);
      expect(opened.key.key, key.key, reason: 'stessa chiave dalla stessa password e dallo stesso sale');
      await expectLater(BackupCipher.open('bici2026!', file),
          throwsA(isA<ChatFailure>().having((ChatFailure f) => f.message, 'messaggio', 'Password sbagliata.')));
    });

    test('file manomesso o con costi troppo bassi: rifiutato', () async {
      final BackupKey key = await BackupCipher.deriveKey('Bici2026!', kdf: fastKdfForTests());
      final Uint8List file = await BackupCipher.seal(key, utf8.encode('ciao'));
      final Uint8List broken = Uint8List.fromList(file)..[file.length - 20] ^= 1;
      await expectLater(BackupCipher.open('Bici2026!', broken), throwsA(isA<ChatFailure>()));
      await expectLater(BackupCipher.open('Bici2026!', Uint8List.fromList(utf8.encode('non è un backup'))),
          throwsA(isA<ChatFailure>()));

      // Intestazione cambiata per rendere la chiave facile da indovinare.
      final int len = (file[5] << 8) | file[6];
      final Map<String, dynamic> header = jsonDecode(utf8.decode(file.sublist(7, 7 + len))) as Map<String, dynamic>;
      header['kdf'] = <String, int>{'m': 8, 't': 1, 'p': 1};
      final Uint8List h = utf8.encode(jsonEncode(header));
      final Uint8List weak = Uint8List.fromList(<int>[
        ...file.sublist(0, 5), h.length >> 8, h.length & 0xff, ...h, ...file.sublist(7 + len),
      ]);
      await expectLater(BackupCipher.open('Bici2026!', weak), throwsA(isA<ChatFailure>()));
    });

    test('password: almeno 8 caratteri, una lettera e un numero o un simbolo', () {
      expect(backupPasswordProblem('abc1'), 'Usa almeno 8 caratteri.');
      expect(backupPasswordProblem('12345678'), 'Metti almeno una lettera.');
      expect(backupPasswordProblem('solamente'), 'Aggiungi almeno un numero o un simbolo.');
      expect(backupPasswordProblem('bicicletta7'), isNull);
      expect(backupPasswordProblem('bici-rossa'), isNull);
    });

    test('costo di Argon2id sul telefono: quello consigliato (19 MiB, 2 passaggi)', () {
      const BackupKdf k = BackupKdf();
      expect(k.memory, 19456);
      expect(k.iterations, 2);
      expect(k.acceptable, isTrue);
    });
  });

  test('telefono nuovo: il backup riporta i messaggi, poi la chat continua', () async {
    final FakeBackupServer cloud = FakeBackupServer();
    final ChatService a = await phone(hub, anna);
    final ChatService b1 = await phone(hub, bruno, backup: cloud);
    final String conv = await a.openDirect(bruno);
    await a.send(conv, 'Ciao Bruno, la bici è ancora disponibile?');
    await b1.refresh();
    await b1.send(conv, 'Sì, domani alle 18?');
    await b1.sendMedia(conv, kind: MediaKind.image, bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        mime: 'image/jpeg', width: 10, height: 10);
    await a.refresh();
    await a.react(a.messages(conv).firstWhere((ChatMessage m) => !m.mine && m.isText), '👍');
    await b1.refresh();
    final List<ChatMessage> before = b1.messages(conv);
    expect(before.where((ChatMessage m) => m.isText), hasLength(2));

    final ChatBackup backup1 = b1.backup!;
    await backup1.load(auto: false);
    expect(backup1.enabled, isFalse);
    await expectLater(backup1.enable('corta'), throwsA(isA<ChatFailure>()));
    await backup1.enable('Bici2026!');
    expect(backup1.enabled, isTrue);
    expect(cloud.uploads, 1);
    expect(utf8.decode(cloud.file!, allowMalformed: true), isNot(contains('bici')));
    b1.dispose();

    // Telefono nuovo di Bruno: chiavi nuove, nessun messaggio, il backup è sul server.
    final ChatService b2 = await phone(hub, bruno, backup: cloud);
    final ChatBackup backup2 = b2.backup!;
    await backup2.load(auto: false);
    expect(backup2.offersRestore, isTrue);
    expect(b2.messages(conv).where((ChatMessage m) => m.isText), isEmpty);

    await expectLater(backup2.restore('Bici2025!'), throwsA(isA<ChatFailure>()));
    expect(backup2.error, 'Password sbagliata.');
    final int added = await backup2.restore('Bici2026!');
    expect(added, greaterThanOrEqualTo(3));
    expect(backup2.enabled, isTrue);
    expect(backup2.offersRestore, isFalse);
    final List<ChatMessage> after = b2.messages(conv);
    expect(after.where((ChatMessage m) => m.isText).map((ChatMessage m) => m.body),
        <String>['Ciao Bruno, la bici è ancora disponibile?', 'Sì, domani alle 18?']);
    expect(after.firstWhere((ChatMessage m) => m.mine && m.isText).allReactions, <String>['👍']);

    // L'allegato è nella cronologia ma il file non è nel backup.
    final ChatMessage photo = after.firstWhere((ChatMessage m) => m.media != null);
    expect(photo.fromBackup, isTrue);
    await expectLater(b2.download(photo), throwsA(isA<ChatFailure>()));

    // Un secondo ripristino non crea doppioni.
    expect(await backup2.restore('Bici2026!'), 0);
    expect(b2.messages(conv), hasLength(after.length));

    // La chat continua sul telefono nuovo.
    await a.refresh();
    await a.send(conv, 'Perfetto!');
    await b2.refresh();
    expect(b2.messages(conv).where((ChatMessage m) => m.isText).last.body, 'Perfetto!');
    await b2.send(conv, 'Ho ritrovato tutto');
    await a.refresh();
    expect(a.messages(conv).last.body, 'Ho ritrovato tutto');
    a.dispose();
    b2.dispose();
  });

  test('backup da solo una volta al giorno; «Non ora»; disattiva cancella dal server', () async {
    DateTime clock = DateTime(2026, 11, 18, 10);
    final FakeBackupServer cloud = FakeBackupServer(now: () => clock);
    final MemoryBackupKeyStore keys = MemoryBackupKeyStore();
    final ChatService a = await phone(hub, anna);
    final ChatService b = await phone(hub, bruno, backup: cloud, keys: keys);
    final String conv = await a.openDirect(bruno);
    await a.send(conv, 'Uno');
    await b.refresh();

    final ChatBackup auto = ChatBackup(chat: b, server: cloud, keys: keys, kdf: fastKdfForTests(), now: () => clock);
    await auto.enable('Bici2026!');
    expect(cloud.uploads, 1);
    clock = clock.add(const Duration(hours: 5));
    await auto.load();
    expect(cloud.uploads, 1, reason: 'meno di un giorno: niente backup');
    clock = clock.add(const Duration(hours: 20));
    await auto.load();
    expect(cloud.uploads, 2, reason: 'passato un giorno: backup da solo');

    // Telefono nuovo che sceglie «Non ora»: non lo chiede più.
    final MemoryBackupKeyStore newKeys = MemoryBackupKeyStore();
    final ChatBackup other = ChatBackup(chat: b, server: cloud, keys: newKeys, kdf: fastKdfForTests());
    await other.load(auto: false);
    expect(other.offersRestore, isTrue);
    await other.skipRestore();
    await other.load(auto: false);
    expect(other.offersRestore, isFalse);
    expect(other.enabled, isFalse);

    await auto.disable();
    expect(cloud.file, isNull);
    expect(keys.value, isNull);
    expect(auto.enabled, isFalse);
    auto.dispose();
    other.dispose();
    a.dispose();
    b.dispose();
  });

  test('senza rete: errore chiaro e nessuna chiave persa', () async {
    final FakeBackupServer cloud = FakeBackupServer();
    final MemoryBackupKeyStore keys = MemoryBackupKeyStore();
    final ChatService b = await phone(hub, bruno, backup: cloud, keys: keys);
    await b.backup!.load(auto: false);
    cloud.offline = true;
    await expectLater(b.backup!.enable('Bici2026!'), throwsA(isA<ChatFailure>()));
    expect(b.backup!.error, 'Backup non caricato. Riprova.');
    expect(keys.value, isNotNull, reason: 'la password resta: si riprova più tardi');
    cloud.offline = false;
    await b.backup!.backupNow();
    expect(cloud.uploads, 1);
    b.dispose();
  });

  test('file sul telefono: esporta e reimporta senza doppioni', () async {
    final Directory d = Directory.systemTemp.createTempSync('piazly_store_');
    addTearDown(() => d.deleteSync(recursive: true));
    final FileChatStore s1 = FileChatStore(Future<Directory>.value(Directory('${d.path}/uno')));
    final DateTime at = DateTime(2026, 11, 18, 9);
    const String c = '00000000-0000-4000-8000-000000000001';
    await s1.append(ChatMessage(localId: 'm1', conversationId: c, mine: true, kind: MessageKind.text, body: 'Ciao', at: at, serverId: 1));
    await s1.appendEvent(ChatEvent(conversationId: c, kind: ChatEventKind.react, target: 'm1', byMe: false, at: at, emoji: '❤️', serverId: 2));
    final Map<String, List<Map<String, Object?>>> exported = await s1.exportAll();
    expect(exported.keys, <String>[c]);

    final FileChatStore s2 = FileChatStore(Future<Directory>.value(Directory('${d.path}/due')));
    expect(await s2.importAll(exported), 1);
    expect(await s2.importAll(exported), 0);
    final FileChatStore reopened = FileChatStore(Future<Directory>.value(Directory('${d.path}/due')));
    final List<ChatMessage> m = await reopened.messages(c);
    expect(m.single.body, 'Ciao');
    expect(m.single.peerReaction, '❤️');
    expect(await reopened.hasServerId(c, 2), isTrue, reason: 'evento già elaborato: non si riapplica');
  });
}

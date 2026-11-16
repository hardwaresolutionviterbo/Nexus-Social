// Fase 4 · Blocco 1: prova di base della cifratura MLS (RFC 9420).
// Due persone (due «motori» separati, come due telefoni) aprono una chat,
// si scrivono in entrambe le direzioni e un estraneo non riesce a leggere.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmls/openmls.dart';

final _suite = MlsCiphersuite.mls128DhkemX25519Aes128GcmSha256Ed25519;

class _Persona {
  _Persona(this.engine, this.signer, this.publicKey, this.identity);
  final MlsEngine engine;
  final Uint8List signer;
  final Uint8List publicKey;
  final Uint8List identity;

  static Future<_Persona> crea(String id) async {
    final rng = Random.secure();
    final key = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    final engine = await MlsEngine.create(dbPath: ':memory:', encryptionKey: key);
    final pair = MlsSignatureKeyPair.generate(ciphersuite: _suite);
    final signer = serializeSigner(
      ciphersuite: _suite,
      privateKey: pair.privateKey(),
      publicKey: pair.publicKey(),
    );
    return _Persona(engine, signer, pair.publicKey(), Uint8List.fromList(utf8.encode(id)));
  }
}

MlsGroupConfig _config() => MlsGroupConfig.defaultConfig(ciphersuite: _suite);

void main() {
  setUpAll(() async {
    await Openmls.init();
  });

  test('due telefoni si scrivono cifrato e un estraneo non legge', () async {
    final anna = await _Persona.crea('utente-a');
    final bruno = await _Persona.crea('utente-b');
    final estraneo = await _Persona.crea('utente-x');

    // Bruno pubblica un «pacchetto chiave» (sul server andrà solo questo).
    final kp = await bruno.engine.createKeyPackage(
      ciphersuite: _suite,
      signerBytes: bruno.signer,
      credentialIdentity: bruno.identity,
      signerPublicKey: bruno.publicKey,
    );

    final chat = await anna.engine.createGroup(
      config: _config(),
      signerBytes: anna.signer,
      credentialIdentity: anna.identity,
      signerPublicKey: anna.publicKey,
    );
    final add = await anna.engine.addMembers(
      groupIdBytes: chat.groupId,
      signerBytes: anna.signer,
      keyPackagesBytes: [kp.keyPackageBytes],
    );
    await anna.engine.mergePendingCommit(groupIdBytes: chat.groupId);
    await bruno.engine.joinGroupFromWelcome(
      config: _config(),
      welcomeBytes: add.welcome,
      signerBytes: bruno.signer,
    );

    final testo = Uint8List.fromList(utf8.encode('Ciao, ci vediamo alle 18?'));
    final cifrato = await anna.engine.createMessage(
      groupIdBytes: chat.groupId,
      signerBytes: anna.signer,
      message: testo,
    );
    // Il server vede solo byte illeggibili.
    expect(utf8.decode(cifrato.ciphertext, allowMalformed: true).contains('Ciao'), isFalse);

    final ricevuto = await bruno.engine.processMessage(
      groupIdBytes: chat.groupId,
      messageBytes: cifrato.ciphertext,
    );
    expect(ricevuto.messageType, ProcessedMessageType.application);
    expect(utf8.decode(ricevuto.applicationMessage!), 'Ciao, ci vediamo alle 18?');

    // Risposta nell'altra direzione.
    final risposta = await bruno.engine.createMessage(
      groupIdBytes: chat.groupId,
      signerBytes: bruno.signer,
      message: Uint8List.fromList(utf8.encode('Sì, perfetto')),
    );
    final letta = await anna.engine.processMessage(
      groupIdBytes: chat.groupId,
      messageBytes: risposta.ciphertext,
    );
    expect(utf8.decode(letta.applicationMessage!), 'Sì, perfetto');

    // Un estraneo che intercetta il messaggio non ha la chat e non può leggerlo.
    await expectLater(
      estraneo.engine.processMessage(
        groupIdBytes: chat.groupId,
        messageBytes: cifrato.ciphertext,
      ),
      throwsA(anything),
    );

    for (final p in [anna, bruno, estraneo]) {
      await p.engine.close();
    }
  });
}

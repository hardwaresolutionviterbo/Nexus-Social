import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openmls/openmls.dart';

import 'chat_models.dart';

/// Chiave di firma di questo telefono per la chat.
class ChatIdentity {
  const ChatIdentity(this.signatureKey, {required this.isNew});

  /// Chiave pubblica (base64): la sola cosa che va sul server.
  final String signatureKey;

  /// Appena creata: il telefono è nuovo per la chat.
  final bool isNew;
}

/// Chat cifrata appena aperta: identificativo del gruppo e invito per l'altra persona.
class StartedGroup {
  const StartedGroup(this.groupId, this.welcome);

  final String groupId;
  final String welcome;
}

/// Cifratura end-to-end della chat con MLS (RFC 9420, decisione docs/fase4/DECISIONI.md).
/// Le chiavi private restano sul telefono; fuori escono solo dati pubblici e testo cifrato.
abstract class ChatCrypto {
  Future<ChatIdentity> ensureIdentity();

  Future<List<String>> newKeyPackages(int count);

  /// Apre la chat con il pacchetto chiave dell'altra persona, dopo aver verificato che sia
  /// davvero suo (identità e chiave di firma registrate sul server).
  Future<StartedGroup> startGroup({
    required String peerId,
    required String peerPackage,
    required String peerSignatureKey,
  });

  /// Entra nella chat dall'invito; verifica che l'altra persona sia [peerId].
  Future<String> joinGroup(String welcome, {required String peerId});

  Future<String> encrypt(String groupId, List<int> plain);

  /// null se il messaggio non si può leggere con questa chat.
  Future<List<int>?> decrypt(String groupId, String payload);

  Future<void> dropGroup(String groupId);
}

final MlsCiphersuite _suite = MlsCiphersuite.mls128DhkemX25519Aes128GcmSha256Ed25519;

MlsGroupConfig _config() => MlsGroupConfig.defaultConfig(ciphersuite: _suite);

/// Implementazione reale con OpenMLS. Il database delle chiavi è cifrato (SQLCipher) con una
/// chiave casuale custodita nell'archivio sicuro del telefono.
class MlsChatCrypto implements ChatCrypto {
  MlsChatCrypto._(this._engine, this._signer, this._publicKey, this._uid, this._isNew);

  final MlsEngine _engine;
  final Uint8List _signer;
  final Uint8List _publicKey;
  final String _uid;
  final bool _isNew;

  Uint8List get _identity => Uint8List.fromList(utf8.encode(_uid));

  /// [dbPath] ':memory:' nei test. [secrets] archivio sicuro (null nei test: tutto in memoria).
  static Future<MlsChatCrypto> open({
    required String uid,
    required String dbPath,
    FlutterSecureStorage? secrets,
  }) async {
    await Openmls.init();
    final String prefix = 'piazly_chat_${_safe(uid)}';
    String? dbKey = await secrets?.read(key: '${prefix}_db');
    String? signer = await secrets?.read(key: '${prefix}_signer');
    String? public = await secrets?.read(key: '${prefix}_public');
    bool isNew = false;
    if (dbKey == null || signer == null || public == null) {
      // Telefono nuovo per la chat (o chiavi perse): si riparte da zero.
      isNew = true;
      if (dbPath != ':memory:') {
        final File db = File(dbPath);
        if (db.existsSync()) db.deleteSync();
      }
      final Random rng = Random.secure();
      dbKey = base64Encode(List<int>.generate(32, (_) => rng.nextInt(256)));
      final MlsSignatureKeyPair pair = MlsSignatureKeyPair.generate(ciphersuite: _suite);
      final Uint8List pub = pair.publicKey();
      signer = base64Encode(serializeSigner(
        ciphersuite: _suite,
        privateKey: pair.privateKey(),
        publicKey: pub,
      ));
      public = base64Encode(pub);
      await secrets?.write(key: '${prefix}_db', value: dbKey);
      await secrets?.write(key: '${prefix}_signer', value: signer);
      await secrets?.write(key: '${prefix}_public', value: public);
    }
    if (dbPath != ':memory:') Directory(File(dbPath).parent.path).createSync(recursive: true);
    final MlsEngine engine = await MlsEngine.create(
      dbPath: dbPath,
      encryptionKey: base64Decode(dbKey),
    );
    return MlsChatCrypto._(engine, base64Decode(signer), base64Decode(public), uid, isNew);
  }

  static String _safe(String uid) => uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  @override
  Future<ChatIdentity> ensureIdentity() async =>
      ChatIdentity(base64Encode(_publicKey), isNew: _isNew);

  @override
  Future<List<String>> newKeyPackages(int count) async => <String>[
    for (int i = 0; i < count; i++)
      base64Encode((await _engine.createKeyPackage(
        ciphersuite: _suite,
        signerBytes: _signer,
        credentialIdentity: _identity,
        signerPublicKey: _publicKey,
      )).keyPackageBytes),
  ];

  /// L'altra persona nella chat [groupId] ha l'identità e la chiave attese.
  Future<bool> _peerIs(Uint8List groupId, String peerId, String? signatureKey) async {
    final int me = await _engine.groupOwnIndex(groupIdBytes: groupId);
    final List<MlsMemberInfo> members = await _engine.groupMembers(groupIdBytes: groupId);
    if (members.length != 2) return false;
    final MlsMemberInfo other = members.firstWhere((m) => m.index != me);
    final String identity = utf8.decode(
      MlsCredential.deserialize(bytes: other.credential).identity(),
      allowMalformed: true,
    );
    if (identity != peerId) return false;
    return signatureKey == null || base64Encode(other.signatureKey) == signatureKey;
  }

  @override
  Future<StartedGroup> startGroup({
    required String peerId,
    required String peerPackage,
    required String peerSignatureKey,
  }) async {
    final CreateGroupResult group = await _engine.createGroup(
      config: _config(),
      signerBytes: _signer,
      credentialIdentity: _identity,
      signerPublicKey: _publicKey,
    );
    try {
      final AddMembersResult added = await _engine.addMembers(
        groupIdBytes: group.groupId,
        signerBytes: _signer,
        keyPackagesBytes: <Uint8List>[base64Decode(peerPackage)],
      );
      await _engine.mergePendingCommit(groupIdBytes: group.groupId);
      if (!await _peerIs(group.groupId, peerId, peerSignatureKey)) {
        throw const ChatFailure('Chiave dell\'altra persona non valida: chat non aperta.');
      }
      return StartedGroup(base64Encode(group.groupId), base64Encode(added.welcome));
    } catch (e) {
      await _engine.deleteGroup(groupIdBytes: group.groupId);
      if (e is ChatFailure) rethrow;
      throw const ChatFailure('Chat non aperta: riprova.');
    }
  }

  @override
  Future<String> joinGroup(String welcome, {required String peerId}) async {
    final JoinGroupResult joined = await _engine.joinGroupFromWelcome(
      config: _config(),
      welcomeBytes: base64Decode(welcome),
      signerBytes: _signer,
    );
    if (!await _peerIs(joined.groupId, peerId, null)) {
      await _engine.deleteGroup(groupIdBytes: joined.groupId);
      throw const ChatFailure('Invito non valido.');
    }
    return base64Encode(joined.groupId);
  }

  @override
  Future<String> encrypt(String groupId, List<int> plain) async => base64Encode((await _engine
          .createMessage(
            groupIdBytes: base64Decode(groupId),
            signerBytes: _signer,
            message: Uint8List.fromList(plain),
          ))
      .ciphertext);

  @override
  Future<List<int>?> decrypt(String groupId, String payload) async {
    try {
      final ProcessedMessageResult r = await _engine.processMessage(
        groupIdBytes: base64Decode(groupId),
        messageBytes: base64Decode(payload),
      );
      return r.messageType == ProcessedMessageType.application ? r.applicationMessage : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dropGroup(String groupId) async {
    try {
      await _engine.deleteGroup(groupIdBytes: base64Decode(groupId));
    } catch (_) {
      // Già assente.
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../config/app_config.dart';
import 'push_device_registry.dart';

/// Errore mostrabile all'utente, senza dettagli tecnici o dati personali.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Richiesta del codice SMS in corso.
class CodeRequest {
  const CodeRequest(this.verificationId, {this.autoSignedIn = false});

  final String verificationId;

  /// Su Android il codice può essere letto in automatico: l'accesso è già fatto.
  final bool autoSignedIn;
}

/// Accesso con numero di telefono (Fase 2, Blocco 1).
///
/// In produzione è [FirebaseAuthGateway]; nei test si usa una simulazione in memoria,
/// così nessun test contatta Firebase o Supabase reali (regola F8).
abstract class AuthGateway {
  /// Utente collegato a ogni cambio (null se nessuno).
  Stream<String?> uidChanges();

  String? get currentUid;

  /// Invia il codice SMS al numero in formato internazionale (+39…).
  Future<CodeRequest> sendCode(String phoneE164);

  /// Conferma il codice ricevuto ed entra.
  Future<void> confirmCode(CodeRequest request, String code);

  /// Dopo l'accesso: ruolo `authenticated` (S1) e verifica che Supabase riconosca l'utente.
  Future<void> ensureLinked();

  /// Uscita sicura: scollega il dispositivo push, poi esce.
  Future<void> signOut();
}

class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Regione della Cloud Function `assegnaRuolo`.
  static const String functionsRegion = 'europe-west1';

  @override
  Stream<String?> uidChanges() => _auth.authStateChanges().map((User? u) => u?.uid);

  @override
  String? get currentUid => _auth.currentUser?.uid;

  @override
  Future<CodeRequest> sendCode(String phoneE164) {
    final Completer<CodeRequest> completer = Completer<CodeRequest>();
    _auth
        .verifyPhoneNumber(
          phoneNumber: phoneE164,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (PhoneAuthCredential credential) async {
            try {
              await _auth.signInWithCredential(credential);
              if (!completer.isCompleted) {
                completer.complete(const CodeRequest('', autoSignedIn: true));
              }
            } on FirebaseAuthException catch (error) {
              if (!completer.isCompleted) completer.completeError(_failure(error));
            }
          },
          verificationFailed: (FirebaseAuthException error) {
            if (!completer.isCompleted) completer.completeError(_failure(error));
          },
          codeSent: (String verificationId, int? _) {
            if (!completer.isCompleted) completer.complete(CodeRequest(verificationId));
          },
          codeAutoRetrievalTimeout: (String _) {},
        )
        .catchError((Object error) {
          if (!completer.isCompleted) {
            completer.completeError(
              error is FirebaseAuthException ? _failure(error) : _generic,
            );
          }
        });
    return completer.future;
  }

  @override
  Future<void> confirmCode(CodeRequest request, String code) async {
    if (request.autoSignedIn) return;
    try {
      await _auth.signInWithCredential(
        PhoneAuthProvider.credential(
          verificationId: request.verificationId,
          smsCode: code,
        ),
      );
    } on FirebaseAuthException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> ensureLinked() async {
    final User? user = _auth.currentUser;
    if (user == null) throw const AuthFailure('Accesso non trovato: riprova.');
    // S1 in pausa: senza server l'utente entra; il collegamento a Supabase si fa dopo.
    if (!AppConfig.serverLinkEnabled) return;

    final IdTokenResult current = await user.getIdTokenResult();
    if (current.claims?['role'] != 'authenticated') {
      await _callAssignRole(await user.getIdToken() ?? '');
      // Il nuovo ruolo compare solo in un token rinnovato.
      await user.getIdToken(true);
    }

    if (AppConfig.hasSupabase) {
      final Object? uid;
      try {
        uid = await Supabase.instance.client
            .rpc<Object?>('current_uid')
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        throw const AuthFailure(
          'Non riesco a raggiungere il server. Controlla la connessione e riprova.',
        );
      }
      if (uid != user.uid) {
        throw const AuthFailure(
          'Il server non riconosce ancora il tuo accesso. Riprova tra poco.',
        );
      }
    }
  }

  @override
  Future<void> signOut() => PushDeviceRegistry.signOut();

  Future<void> _callAssignRole(String idToken) async {
    final String project = Firebase.app().options.projectId;
    final Uri url = Uri.https(
      '$functionsRegion-$project.cloudfunctions.net',
      '/assegnaRuolo',
    );
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest request = await client.postUrl(url);
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
      request.write(jsonEncode(<String, Object>{'data': <String, Object>{}}));
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      await response.drain<void>();
      if (response.statusCode != 200) {
        throw const AuthFailure(
          'Non è stato possibile completare l\'accesso. Riprova tra poco.',
        );
      }
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(
        'Non riesco a raggiungere il server. Controlla la connessione e riprova.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static const AuthFailure _generic = AuthFailure(
    'Qualcosa non ha funzionato. Riprova.',
  );

  static AuthFailure _failure(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-phone-number':
        return const AuthFailure('Numero non valido. Controlla e riprova.');
      case 'invalid-verification-code':
        return const AuthFailure('Codice errato. Controlla e riprova.');
      case 'session-expired':
      case 'code-expired':
        return const AuthFailure('Il codice è scaduto: chiedine uno nuovo.');
      case 'too-many-requests':
        return const AuthFailure('Troppi tentativi. Riprova più tardi.');
      case 'quota-exceeded':
        return const AuthFailure('Limite di SMS raggiunto. Riprova più tardi.');
      case 'network-request-failed':
        return const AuthFailure('Connessione assente. Riprova.');
      case 'billing-not-enabled':
      case 'operation-not-allowed':
        return const AuthFailure(
          'L\'accesso con numero di telefono non è ancora attivo sul server.',
        );
      default:
        return _generic;
    }
  }
}

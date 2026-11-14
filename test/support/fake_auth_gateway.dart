import 'dart:async';

import 'package:nexus_social/core/services/auth_gateway.dart';

/// Accesso simulato in memoria: nessun Firebase o Supabase reale (regola F8).
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.uid});

  final StreamController<String?> _changes = StreamController<String?>.broadcast();
  final List<String> calls = <String>[];

  String? uid;
  AuthFailure? failSend;
  AuthFailure? failConfirm;
  AuthFailure? failLink;
  String expectedCode = '123456';

  @override
  Stream<String?> uidChanges() => _changes.stream;

  @override
  String? get currentUid => uid;

  @override
  Future<CodeRequest> sendCode(String phoneE164) async {
    calls.add('sendCode:$phoneE164');
    if (failSend != null) throw failSend!;
    return const CodeRequest('verifica-prova');
  }

  @override
  Future<void> confirmCode(CodeRequest request, String code) async {
    calls.add('confirmCode:$code');
    if (failConfirm != null) throw failConfirm!;
    if (code != expectedCode) {
      throw const AuthFailure('Codice errato. Controlla e riprova.');
    }
    uid = 'utenteProva';
    _changes.add(uid);
  }

  @override
  Future<void> ensureLinked() async {
    calls.add('ensureLinked');
    if (failLink != null) throw failLink!;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    uid = null;
    _changes.add(null);
  }

  Future<void> close() => _changes.close();
}

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'push_device_registry.dart';

/// Collega il telefono all'account anche sul nostro server (Supabase), da cui partono le
/// notifiche (Fase 4, Blocco 5). L'autenticazione resta quella di Firebase; il documento
/// Firestore della Fase 1 si aggiorna come prima, senza bloccare se non riesce.
class SupabasePushDeviceBackend implements PushDeviceBackend {
  SupabasePushDeviceBackend(this._client, {PushDeviceBackend? firebase})
    : _firebase = firebase ?? const FirebasePushDeviceBackend();

  final SupabaseClient _client;
  final PushDeviceBackend _firebase;

  @override
  Stream<String?> authUidChanges() => _firebase.authUidChanges();

  @override
  String? get currentUid => _firebase.currentUid;

  @override
  Future<void> link({required String uid, required String fid, required String platform}) async {
    await _client.rpc('push_register', params: <String, Object?>{'p_fid': fid, 'p_platform': platform});
    try {
      await _firebase.link(uid: uid, fid: fid, platform: platform);
    } catch (error) {
      debugPrint('NEXUS_DEVICE firestore=skipped (${error.runtimeType})');
    }
  }

  @override
  Future<void> unlink({required String uid, required String fid}) async {
    try {
      await _client.rpc('push_unregister', params: <String, Object?>{'p_fid': fid});
    } catch (error) {
      debugPrint('NEXUS_DEVICE unlink=failed (${error.runtimeType})');
    }
    try {
      await _firebase.unlink(uid: uid, fid: fid);
    } catch (_) {
      // Già assente.
    }
  }

  @override
  Future<void> signOut() => _firebase.signOut();
}

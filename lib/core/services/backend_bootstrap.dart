import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Stato di un servizio esterno mostrato nel Profilo.
enum ServiceState { notConfigured, connected, failed }

@immutable
class BackendStatus {
  const BackendStatus({
    this.firebase = ServiceState.notConfigured,
    this.supabase = ServiceState.notConfigured,
    this.message,
  });

  const BackendStatus.unconfigured()
    : firebase = ServiceState.notConfigured,
      supabase = ServiceState.notConfigured,
      message = null;

  final ServiceState firebase;
  final ServiceState supabase;

  /// Ultimo errore di connessione, se c'è stato.
  final String? message;

  bool get anyConnected =>
      firebase == ServiceState.connected || supabase == ServiceState.connected;
}

/// Collega i backend all'avvio. Senza chiavi l'app resta utilizzabile e mostra lo stato
/// nel Profilo: nessuna schermata bianca e nessun crash dovuto alla configurazione mancante.
abstract final class BackendBootstrap {
  static Future<BackendStatus> initialize() async {
    var firebase = ServiceState.notConfigured;
    var supabase = ServiceState.notConfigured;
    final messages = <String>[];

    if (AppConfig.hasFirebase) {
      try {
        await Firebase.initializeApp();
        firebase = ServiceState.connected;
      } catch (error) {
        firebase = ServiceState.failed;
        messages.add('Firebase: ${_short(error)}');
      }
    }

    if (AppConfig.hasSupabase) {
      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          publishableKey: AppConfig.supabaseKey,
          // Fase 2: Supabase riconosce l'utente dal token Firebase (Third-Party Auth).
          // Senza utente collegato si usa solo la chiave pubblica, come prima.
          accessToken: firebase == ServiceState.connected
              ? () async => FirebaseAuth.instance.currentUser?.getIdToken()
              : null,
        );
        // initialize() prepara solo il client locale: una lettura minima dimostra
        // che URL, chiave e schema rispondono davvero.
        await Supabase.instance.client
            .from('profiles')
            .select('id')
            .limit(1)
            .timeout(const Duration(seconds: 5));
        supabase = ServiceState.connected;
      } catch (error) {
        supabase = ServiceState.failed;
        messages.add('Supabase: ${_short(error)}');
      }
    }

    return BackendStatus(
      firebase: firebase,
      supabase: supabase,
      message: messages.isEmpty ? null : messages.join(' · '),
    );
  }

  static String _short(Object error) {
    final text = error.toString().replaceAll('\n', ' ');
    return text.length <= 120 ? text : '${text.substring(0, 120)}…';
  }
}

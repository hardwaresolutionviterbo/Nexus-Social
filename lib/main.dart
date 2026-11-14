import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/services/auth_gateway.dart';
import 'core/services/backend_bootstrap.dart';
import 'core/services/firebase_services.dart';
import 'features/profile/profile_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final BackendStatus backend = await BackendBootstrap.initialize();

  if (AppConfig.hasFirebase) {
    FirebaseServices.registerBackgroundHandler();
    unawaited(FirebaseServices.warmUp());
  }

  if (kDebugMode) {
    // Marker usato dal job di verifica runtime: nessun dato sensibile.
    debugPrint(
      'NEXUS_BOOTSTRAP firebase=${backend.firebase.name} '
      'supabase=${backend.supabase.name}',
    );
  }

  final bool firebaseReady =
      AppConfig.hasFirebase && backend.firebase == ServiceState.connected;
  // Profilo su Supabase (Blocco 2): solo con il collegamento al server attivo (S1).
  final bool profilesReady = firebaseReady &&
      AppConfig.serverLinkEnabled &&
      backend.supabase == ServiceState.connected;
  runApp(
    NexusApp(
      backend: backend,
      authGateway: firebaseReady ? FirebaseAuthGateway() : null,
      profiles: profilesReady
          ? SupabaseProfileRepository(
              Supabase.instance.client,
              uid: () => FirebaseAuth.instance.currentUser?.uid ?? '',
            )
          : null,
    ),
  );
}

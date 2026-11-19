import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/services/auth_gateway.dart';
import 'core/services/backend_bootstrap.dart';
import 'core/services/firebase_services.dart';
import 'core/services/push_device_registry.dart';
import 'core/services/supabase_push_backend.dart';
import 'features/calls/call_log.dart';
import 'features/calls/call_service.dart';
import 'features/calls/webrtc_call_media.dart';
import 'features/chat/chat_backup.dart';
import 'features/chat/chat_crypto.dart';
import 'features/chat/chat_media.dart';
import 'features/chat/chat_preview.dart';
import 'features/chat/chat_models.dart';
import 'features/chat/chat_server.dart';
import 'features/chat/chat_service.dart';
import 'features/chat/chat_store.dart';
import 'features/contacts/contacts_sync.dart';
import 'features/map/listing_repository.dart';
import 'features/map/live_location.dart';
import 'features/map/map_location.dart';
import 'features/map/map_screen.dart';
import 'features/map/social_repository.dart';
import 'features/market/market_repository.dart';
import 'features/notifications/notification_settings.dart';
import 'features/privacy/privacy_repository.dart';
import 'features/profile/profile_repository.dart';
import 'features/security/app_lock.dart';
import 'features/security/security_repository.dart';
import 'features/status/status_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final BackendStatus backend = await BackendBootstrap.initialize();

  if (AppConfig.hasFirebase) {
    FirebaseServices.registerBackgroundHandler();
    // Con il server collegato il telefono si registra anche su Supabase (notifiche).
    if (AppConfig.serverLinkEnabled && backend.supabase == ServiceState.connected) {
      PushDeviceRegistry.useBackend(SupabasePushDeviceBackend(Supabase.instance.client));
    }
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
  // GPS in tempo reale (Blocco 15): uno per l'app, solo con il server collegato.
  if (profilesReady) {
    LiveRegistry.current = LiveLocationService(
      server: SupabaseLiveLocationServer(Supabase.instance.client),
      location: const GeolocatorDeviceLocation(),
    );
  }
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
      social: profilesReady ? SupabaseSocialRepository(Supabase.instance.client) : null,
      // Stato dei servizi e diagnostica: solo per gli amministratori (tabella admin_users).
      isAdmin: profilesReady
          ? () async {
              try {
                return await Supabase.instance.client.rpc('is_admin') == true;
              } catch (_) {
                return false;
              }
            }
          : null,
      market: profilesReady
          ? SupabaseMarketRepository(
              Supabase.instance.client,
              uid: () => FirebaseAuth.instance.currentUser?.uid ?? '',
            )
          : null,
      privacy: profilesReady ? SupabasePrivacyRepository(Supabase.instance.client) : null,
      pushSettings: profilesReady ? SupabasePushSettingsRepository(Supabase.instance.client) : null,
      security: profilesReady ? SupabaseSecurityRepository(Supabase.instance.client) : null,
      biometricLock: profilesReady ? DeviceBiometricLock() : null,
      contacts: profilesReady ? SupabaseContactsRepository(Supabase.instance.client) : null,
      // La mappa non usa il server: funziona anche senza accesso e senza Blaze.
      map: MapServices.device(),
      listings: profilesReady
          ? SupabaseMapListingRepository(
              Supabase.instance.client,
              uid: () => FirebaseAuth.instance.currentUser?.uid ?? '',
            )
          : null,
      chat: profilesReady ? _chatFor : null,
    ),
  );
}

/// Chat cifrata (Fase 4): chiavi e messaggi nella cartella privata dell'app, una per account.
ChatService _chatFor(String uid) {
  final String safe = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final Future<Directory> folder = getApplicationSupportDirectory()
      .then((Directory d) => Directory('${d.path}/chat/$safe'));
  final SupabaseContactsRepository contacts = SupabaseContactsRepository(Supabase.instance.client);
  final ChatService chat = ChatService(
    server: SupabaseChatServer(Supabase.instance.client),
    crypto: () async => MlsChatCrypto.open(
      uid: uid,
      dbPath: '${(await folder).path}/chiavi.db',
      secrets: const FlutterSecureStorage(),
    ),
    store: FileChatStore(folder),
    media: SupabaseChatMediaServer(Supabase.instance.client),
    files: ChatMediaFiles(folder.then((Directory d) => Directory('${d.path}/allegati'))),
    myId: uid,
    // Testo nelle notifiche, cifrato per chi riceve (Blocco 10).
    previews: const SecurePreviewKeyStore(),
    // Chiamate vocali e video (Blocco 8): ponte TURN dalla funzione `chiamate`.
    calls: (ChatService chat) => CallService(
      chat: chat,
      ice: SupabaseIceProvider(Supabase.instance.client),
      media: WebRtcCallMedia.new,
      groupMedia: WebRtcGroupCallMedia.new,
      // Registro delle chiamate, solo su questo telefono (Blocco 11).
      logStore: FileCallLogStore(folder),
      ringer: SystemCallRinger(),
    ),
    // Stati di 24 ore (Blocco 13): regole sul server, la scelta del pubblico sul telefono.
    statuses: (ChatService chat) => StatusService(
      server: SupabaseStatusServer(Supabase.instance.client),
      myId: uid,
      prefs: FileStatusPrefsStore(folder),
      localName: chat.localName,
    ),
    // Backup cifrato con password (Blocco 6): la chiave resta nell'archivio sicuro del telefono.
    backupServer: SupabaseBackupServer(Supabase.instance.client, uid: () => uid),
    backupKeys: SecureBackupKeyStore(const FlutterSecureStorage(), uid: uid),
    // Nomi come scritti nella rubrica del telefono (Blocco 11).
    localNames: contacts.localNames,
    contactsLoader: () async {
      try {
        return <ChatContact>[
          for (final RecognizedContact c in await contacts.contacts())
            ChatContact(id: c.id, name: c.publicName, username: c.username, avatarPath: c.avatarThumbPath),
        ];
      } catch (_) {
        return const <ChatContact>[];
      }
    },
  );
  // Rubrica aggiornata: i nomi nelle chat si rileggono subito.
  ContactsEvents.namesChanged.addListener(chat.reloadNames);
  return chat;
}

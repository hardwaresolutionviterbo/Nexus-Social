import 'package:material_ui/material_ui.dart';

import 'core/config/app_config.dart';
import 'core/services/auth_gateway.dart';
import 'core/services/backend_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'features/chat/chat_service.dart';
import 'features/onboarding/auth_gate.dart';
import 'features/contacts/contacts_sync.dart';
import 'features/map/listing_repository.dart';
import 'features/map/map_screen.dart';
import 'features/map/social_repository.dart';
import 'features/market/market_repository.dart';
import 'features/notifications/notification_settings.dart';
import 'features/privacy/privacy_repository.dart';
import 'features/profile/profile_repository.dart';
import 'features/security/app_lock.dart';
import 'features/security/security_repository.dart';
import 'features/shell/app_shell.dart';

class NexusApp extends StatelessWidget {
  const NexusApp({
    super.key,
    this.backend = const BackendStatus.unconfigured(),
    this.authGateway,
    this.profiles,
    this.privacy,
    this.pushSettings,
    this.security,
    this.biometricLock,
    this.contacts,
    this.map,
    this.listings,
    this.social,
    this.market,
    this.chat,
    this.isAdmin,
  });

  /// Vero solo per gli amministratori di Piazly: vedono lo stato dei servizi e la diagnostica.
  final Future<bool> Function()? isAdmin;


  /// Stato dei servizi collegati all'avvio (Firebase, Supabase).
  final BackendStatus backend;

  /// Accesso con numero di telefono (Fase 2). Senza Firebase resta null e l'app mostra
  /// direttamente le anteprime, come nella Fase 1.
  final AuthGateway? authGateway;

  /// Profilo su Supabase (Fase 2, Blocco 2): null finché il server non è collegato.
  final ProfileRepository? profiles;

  /// Impostazioni privacy e blocchi (Blocco 3): null finché il server non è collegato.
  final PrivacyRepository? privacy;

  /// Preferenze delle notifiche (Fase 4, Blocco 5): con il server collegato.
  final PushSettingsRepository? pushSettings;

  /// Verifica in due passaggi e sblocco con impronta (Blocco 4).
  final SecurityRepository? security;
  final BiometricLock? biometricLock;

  /// Rubrica (Blocco 5).
  final ContactsRepository? contacts;

  /// Mappa e posizione del telefono (Fase 3): null nei test di interfaccia.
  final MapServices? map;

  /// Annunci della Mappa (Fase 3, Blocco 2): null finché il server non è collegato.
  final MapListingRepository? listings;

  /// Interazioni e notifiche (Fase 3, Blocco 4).
  final SocialRepository? social;

  /// Scambia & Vendi (Fase 5).
  final MarketRepository? market;

  /// Chat cifrata (Fase 4): si crea per l'account collegato.
  final ChatService Function(String uid)? chat;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      locale: const Locale('it'),
      supportedLocales: const [Locale('it'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: authGateway == null
          ? AppShell(backend: backend, map: map)
          : AuthGate(
              gateway: authGateway!,
              backend: backend,
              profiles: profiles,
              privacy: privacy,
              pushSettings: pushSettings,
              security: security,
              biometricLock: biometricLock,
              contacts: contacts,
              map: map,
              listings: listings,
              social: social,
              market: market,
              chat: chat,
              isAdmin: isAdmin,
            ),
    );
  }
}

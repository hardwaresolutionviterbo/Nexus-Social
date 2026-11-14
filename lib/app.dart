import 'package:material_ui/material_ui.dart';

import 'core/config/app_config.dart';
import 'core/services/auth_gateway.dart';
import 'core/services/backend_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/auth_gate.dart';
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
    this.security,
    this.biometricLock,
  });

  /// Stato dei servizi collegati all'avvio (Firebase, Supabase).
  final BackendStatus backend;

  /// Accesso con numero di telefono (Fase 2). Senza Firebase resta null e l'app mostra
  /// direttamente le anteprime, come nella Fase 1.
  final AuthGateway? authGateway;

  /// Profilo su Supabase (Fase 2, Blocco 2): null finché il server non è collegato.
  final ProfileRepository? profiles;

  /// Impostazioni privacy e blocchi (Blocco 3): null finché il server non è collegato.
  final PrivacyRepository? privacy;

  /// Verifica in due passaggi e sblocco con impronta (Blocco 4).
  final SecurityRepository? security;
  final BiometricLock? biometricLock;

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
          ? AppShell(backend: backend)
          : AuthGate(
              gateway: authGateway!,
              backend: backend,
              profiles: profiles,
              privacy: privacy,
              security: security,
              biometricLock: biometricLock,
            ),
    );
  }
}

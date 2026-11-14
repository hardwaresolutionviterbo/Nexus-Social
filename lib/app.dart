import 'package:material_ui/material_ui.dart';

import 'core/config/app_config.dart';
import 'core/services/auth_gateway.dart';
import 'core/services/backend_bootstrap.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/auth_gate.dart';
import 'features/shell/app_shell.dart';

class NexusApp extends StatelessWidget {
  const NexusApp({
    super.key,
    this.backend = const BackendStatus.unconfigured(),
    this.authGateway,
  });

  /// Stato dei servizi collegati all'avvio (Firebase, Supabase).
  final BackendStatus backend;

  /// Accesso con numero di telefono (Fase 2). Senza Firebase resta null e l'app mostra
  /// direttamente le anteprime, come nella Fase 1.
  final AuthGateway? authGateway;

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
          : AuthGate(gateway: authGateway!, backend: backend),
    );
  }
}

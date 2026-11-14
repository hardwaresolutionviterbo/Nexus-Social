/// Configurazione compilata con `--dart-define` o `--dart-define-from-file=env.json`.
///
/// I valori non finiscono mai nel repository: le chiavi si passano in locale e nelle
/// variabili d'ambiente di Codemagic.
abstract final class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Chiave pubblica del progetto Supabase (anon o publishable): è pensata per stare
  /// nell'app, la sicurezza la fanno le policy RLS.
  static const String supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const bool firebaseEnabled = bool.fromEnvironment('FIREBASE_ENABLED');

  /// Supabase è pronto solo con entrambi i valori.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Firebase si attiva quando i file di configurazione sono stati aggiunti.
  static bool get hasFirebase => firebaseEnabled;

  /// Collegamento degli utenti Firebase a Supabase (Fase 2, S1): richiede la Cloud
  /// Function `assegnaRuolo` pubblicata e Third-Party Auth attivo su Supabase.
  /// In pausa finché il titolare non attiva Blaze: spento, l'utente entra comunque e
  /// il collegamento resta «in attesa».
  static const bool serverLinkEnabled = bool.fromEnvironment('SERVER_LINK_ENABLED');
}

/// Identità dell'app mostrata nell'interfaccia.
abstract final class AppInfo {
  static const String name = 'Nexus Social';
  static const String version = '0.1.0';
  static const int phase = 1;
  static const String phaseLabel = 'Fase 1 · Fondamenta';

  /// Identificativi inseriti dalla build (GitHub Actions) con `--dart-define`.
  /// Nelle build locali restano vuoti e la riga Versione lo dice chiaramente.
  static const String buildNumber = String.fromEnvironment('BUILD_NUMBER');
  static const String gitCommit = String.fromEnvironment('GIT_COMMIT');
  static const String gitBranch = String.fromEnvironment('GIT_BRANCH');

  /// Testo della riga «Versione» in Profilo → Informazioni,
  /// es. `0.1.0 (1202) · a1b2c3d · fase1/blocco1`.
  static String get versionLabel => formatVersion(
    version: version,
    buildNumber: buildNumber,
    gitCommit: gitCommit,
    gitBranch: gitBranch,
  );

  static String formatVersion({
    required String version,
    required String buildNumber,
    required String gitCommit,
    required String gitBranch,
  }) {
    final String build = buildNumber.isEmpty ? 'build locale' : buildNumber;
    final String commit = gitCommit.isEmpty
        ? 'commit n/d'
        : gitCommit.substring(0, gitCommit.length < 7 ? gitCommit.length : 7);
    final String branch = gitBranch.isEmpty ? 'ramo n/d' : gitBranch;
    return '$version ($build) · $commit · $branch';
  }
}

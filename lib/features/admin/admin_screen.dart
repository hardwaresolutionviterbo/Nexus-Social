import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/piazly_ui.dart';
import '../business/business_repository.dart';
import '../business/business_screens.dart';
import '../security/app_lock.dart';
import 'admin_models.dart';
import 'admin_reports.dart';
import 'admin_repository.dart';
import 'admin_users.dart';

/// Ingresso del gestionale (Fase 7): solo amministratori, con PIN attivo e, se il telefono la
/// ha, impronta o volto a ogni apertura. Il server ricontrolla tutto a ogni richiesta.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.repository, this.biometric, this.business});

  final AdminRepository repository;
  final BiometricLock? biometric;
  final BusinessRepository? business;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

enum _Gate { checking, notAdmin, needsPin, locked, open, failed }

class _AdminScreenState extends State<AdminScreen> {
  _Gate _gate = _Gate.checking;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    setState(() => _gate = _Gate.checking);
    try {
      final AdminAccess a = await widget.repository.access();
      if (!a.admin) {
        _set(_Gate.notAdmin);
        return;
      }
      if (!a.pin) {
        _set(_Gate.needsPin);
        return;
      }
      final BiometricLock? lock = widget.biometric;
      if (lock != null && await lock.isAvailable()) {
        final bool ok = await lock.authenticate('Apri il gestionale di Piazly');
        if (!ok) {
          _set(_Gate.locked);
          return;
        }
      }
      _set(_Gate.open);
    } on AdminFailure catch (f) {
      _error = f.message;
      _set(_Gate.failed);
    }
  }

  void _set(_Gate g) {
    if (mounted) setState(() => _gate = g);
  }

  @override
  Widget build(BuildContext context) {
    if (_gate == _Gate.open) {
      return AdminHomeScreen(repository: widget.repository, business: widget.business);
    }
    final (IconData icon, String title, String text, bool retry) = switch (_gate) {
      _Gate.checking => (Icons.admin_panel_settings_outlined, 'Controllo dell\'accesso…', '', false),
      _Gate.notAdmin => (
        Icons.lock_outline_rounded,
        'Area riservata',
        'Il gestionale è solo per gli amministratori di Piazly.',
        false,
      ),
      _Gate.needsPin => (
        Icons.pin_outlined,
        'Serve la verifica in due passaggi',
        'Per aprire il gestionale attiva il PIN in Profilo › Sicurezza dell\'account. '
            'Così nessuno può entrare dal tuo account senza il PIN.',
        true,
      ),
      _Gate.locked => (
        Icons.fingerprint_rounded,
        'Sblocco non riuscito',
        'Per aprire il gestionale usa impronta, volto o il blocco schermo del telefono.',
        true,
      ),
      _Gate.failed || _Gate.open => (Icons.cloud_off_rounded, 'Non è stato possibile', _error ?? '', true),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Gestionale')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_gate == _Gate.checking)
                const CircularProgressIndicator()
              else
                IconTile(icon, color: AppColors.brandViolet, size: 64),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              if (text.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(text, textAlign: TextAlign.center, key: const ValueKey<String>('gestionale_messaggio')),
              ],
              if (retry) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  key: const ValueKey<String>('gestionale_riprova'),
                  onPressed: _check,
                  child: const Text('Riprova'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pagina principale del gestionale.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key, required this.repository, this.business});

  final AdminRepository repository;
  final BusinessRepository? business;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int? _open;

  @override
  void initState() {
    super.initState();
    unawaited(_count());
  }

  Future<void> _count() async {
    try {
      final List<AdminReport> r = await widget.repository.reports();
      if (mounted) setState(() => _open = r.length);
    } on AdminFailure {
      // Il numero è solo un aiuto: la coda si apre comunque.
    }
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    await _count();
  }

  @override
  Widget build(BuildContext context) {
    final int? open = _open;
    final BusinessRepository? biz = widget.business;
    return Scaffold(
      appBar: AppBar(title: const Text('Gestionale')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        children: [
          MenuCard(
            key: const ValueKey<String>('gestionale_segnalazioni'),
            icon: Icons.flag_outlined,
            color: AppColors.brandCoral,
            title: 'Segnalazioni',
            subtitle: open == null
                ? 'Annunci, commenti e chat segnalati'
                : open == 0
                ? 'Nessuna da gestire'
                : open == 1
                ? '1 da gestire'
                : '$open da gestire',
            onTap: () => _go(ReportsScreen(repository: widget.repository)),
          ),
          MenuCard(
            key: const ValueKey<String>('gestionale_utenti'),
            icon: Icons.people_outline_rounded,
            color: AppColors.brandViolet,
            title: 'Utenti',
            subtitle: 'Cerca, storico, avvisi, ban e sblocco',
            onTap: () => _go(UsersScreen(repository: widget.repository)),
          ),
          if (biz != null)
            MenuCard(
              key: const ValueKey<String>('gestionale_aziende'),
              icon: Icons.verified_user_outlined,
              color: const Color(0xFF1D9BF0),
              title: 'Aziende da verificare',
              subtitle: 'Approva o rifiuta, Premium manuale',
              onTap: () => _go(BusinessReviewScreen(repository: biz)),
            ),
        ],
      ),
    );
  }
}

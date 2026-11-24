import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/piazly_ui.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// Per la persona (Fase 7): se l'account è sospeso mostra «Account sospeso» con il motivo e la
/// scadenza; altrimenti, all'apertura e al ritorno nell'app, mostra gli avvisi del Team Piazly
/// non ancora letti. Senza rete l'app resta com'è: il server blocca comunque le scritture.
class ModerationGate extends StatefulWidget {
  const ModerationGate({
    super.key,
    required this.repository,
    required this.child,
    this.onSignOut,
    this.now = DateTime.now,
  });

  final ModerationRepository repository;
  final Widget child;
  final Future<void> Function()? onSignOut;
  final DateTime Function() now;

  @override
  State<ModerationGate> createState() => _ModerationGateState();
}

class _ModerationGateState extends State<ModerationGate> with WidgetsBindingObserver {
  ModerationState? _state;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    ModerationState? s;
    try {
      s = await widget.repository.mine();
    } on AdminFailure {
      return;
    }
    if (!mounted || s == null) return;
    setState(() => _state = s);
    if (!s.bannedAt(widget.now()) && s.notices.isNotEmpty) await _showNotices(s.notices);
  }

  Future<void> _showNotices(List<ModerationNotice> notices) async {
    if (_showing) return;
    _showing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        key: const ValueKey<String>('avvisi_team'),
        title: Text(notices.length == 1 ? notices.first.title : 'Avvisi del Team Piazly'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final ModerationNotice n in notices) ...[
                if (notices.length > 1) Text(n.title, style: Theme.of(ctx).textTheme.titleSmall),
                Text(n.message),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey<String>('avvisi_ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
    _showing = false;
    try {
      await widget.repository.markRead();
    } on AdminFailure {
      // Riappariranno alla prossima apertura.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ModerationState? s = _state;
    if (s != null && s.bannedAt(widget.now())) {
      return BannedScreen(until: s.bannedUntil!, reason: s.banReason, onSignOut: widget.onSignOut, onRetry: _check);
    }
    return widget.child;
  }
}

class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key, required this.until, this.reason, this.onSignOut, this.onRetry});

  final DateTime until;
  final String? reason;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool forever = until.year >= 9999;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IconTile(Icons.block_rounded, color: AppColors.brandCoral, size: 72),
                const SizedBox(height: AppSpacing.md),
                Text('Account sospeso', style: theme.textTheme.headlineSmall, key: const ValueKey<String>('account_sospeso')),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  forever
                      ? 'Il tuo account è stato sospeso in modo definitivo.'
                      : 'Il tuo account è sospeso fino al ${adminDateTime(until)}.',
                  textAlign: TextAlign.center,
                ),
                if ((reason ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  SoftCard(
                    margin: EdgeInsets.zero,
                    child: Text('Motivo: $reason', key: const ValueKey<String>('account_sospeso_motivo')),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Durante la sospensione non puoi usare Piazly. Le regole della community valgono per tutti.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (onRetry != null && !forever)
                  OutlinedButton(onPressed: onRetry, child: const Text('Controlla di nuovo')),
                if (onSignOut != null)
                  TextButton(
                    key: const ValueKey<String>('account_sospeso_esci'),
                    onPressed: onSignOut,
                    child: const Text('Esci dall\'account'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/app_config.dart';
import '../../core/services/backend_bootstrap.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import 'avatar_view.dart';
import 'profile_form_screen.dart';
import 'profile_models.dart';
import 'profile_repository.dart';
import 'public_profile_screen.dart';
import 'push_diagnostics_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.backend = const BackendStatus.unconfigured(),
    this.onSignOut,
    this.profile,
    this.profiles,
    this.onProfileChanged,
  });

  final BackendStatus backend;

  /// Profilo completo (Blocco 2): presente quando il server è collegato.
  final MyProfile? profile;
  final ProfileRepository? profiles;
  final Future<void> Function()? onProfileChanged;

  /// Presente solo con un utente collegato (Fase 2): mostra «Esci».
  final Future<void> Function()? onSignOut;

  bool get _signedIn => onSignOut != null;

  Future<void> _confirmSignOut(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Uscire da Piazly?'),
        content: const Text(
          'Su questo telefono non riceverai più notifiche finché non entri di nuovo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    if (ok == true) await onSignOut?.call();
  }

  void _openEditor(BuildContext context) {
    final MyProfile? p = profile;
    final ProfileRepository? repo = profiles;
    if (p == null || repo == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext route) => ProfileFormScreen(
          repository: repo,
          initial: p,
          onSaved: () {
            Navigator.of(route).pop();
            onProfileChanged?.call();
          },
        ),
      ),
    );
  }

  void _openPreview(BuildContext context) {
    final MyProfile? p = profile;
    if (p == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfileScreen(profile: p.asSeenByOthers(), repository: profiles),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final MyProfile? me = profile;

    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        FadeSlideIn(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient(AppColors.brandViolet),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandViolet.withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar con anello arancio luminoso.
                if (me != null)
                  AvatarView(
                    name: me.publicName.isEmpty ? me.username : me.publicName,
                    repository: profiles,
                    path: me.avatarThumbPath,
                    size: 64,
                  )
                else
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.orangeGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brandOrange.withValues(alpha: 0.5),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.22),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (me != null) ...[
                        Text(
                          me.isBusiness && me.businessName != null
                              ? me.businessName!
                              : me.publicName,
                          key: const ValueKey<String>('mio_nome_pubblico'),
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${me.username}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ] else ...[
                      Text(
                        _signedIn ? 'Accesso effettuato' : 'Profilo non configurato',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _signedIn
                            ? AppConfig.serverLinkEnabled
                                  ? 'Nome, foto e bio si completano nel prossimo aggiornamento.'
                                  : 'Collegamento al server in attesa. Nome, foto e bio '
                                        'arriveranno nei prossimi aggiornamenti.'
                            : 'Registrati con il numero di telefono per iniziare.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      ],
                      const SizedBox(height: 10),
                      const PhaseChip(phase: 2, onAccent: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (me != null) ...[
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey<String>('modifica_profilo'),
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Modifica profilo'),
                  subtitle: const Text('Foto, nome utente, bio e social'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openEditor(context),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const ValueKey<String>('anteprima_profilo'),
                  leading: const Icon(Icons.visibility_outlined),
                  title: const Text('Come ti vedono gli altri'),
                  subtitle: const Text('Anteprima del profilo pubblico'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openPreview(context),
                ),
              ],
            ),
          ),
        ],
        if (_signedIn) ...[
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Esci'),
              subtitle: const Text('Esci dall\'account su questo telefono'),
              onTap: () => _confirmSignOut(context),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_queue_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Stato dei servizi', style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 14),
              _ServiceRow(
                name: 'Supabase',
                detail: 'Annunci, distanza, foto, segnalazioni',
                state: backend.supabase,
              ),
              const Divider(height: 22),
              _ServiceRow(
                name: 'Firebase',
                detail: 'Accesso SMS, chat, chiamate, notifiche',
                state: backend.firebase,
              ),
              if (!backend.anyConnected) ...[
                const SizedBox(height: 14),
                Text(
                  'Aggiungi le chiavi in env.json (o nei segreti di GitHub Actions '
                  'e Codemagic) per collegare i servizi.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (backend.message != null) ...[
                const SizedBox(height: 10),
                Text(
                  backend.message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (kDebugMode && AppConfig.hasFirebase) ...[
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.notifications_active_outlined,
                color: scheme.primary,
              ),
              title: const Text('Diagnostica push (debug)'),
              subtitle: const Text('FID, permessi e canale notifiche'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PushDiagnosticsScreen(),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Il tuo account', style: theme.textTheme.titleSmall),
              const SizedBox(height: 14),
              _AccountTypeRow(
                icon: Icons.person_outline_rounded,
                color: AppColors.brandBlue,
                title: 'Privato',
                detail: 'Annunci, scambi, feedback e media delle stelle',
              ),
              const Divider(height: 22),
              _AccountTypeRow(
                icon: Icons.storefront_outlined,
                color: AppColors.brandOrange,
                title: 'Azienda',
                detail: 'Badge verificato, promozioni e coupon (9,99 €/mese)',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Informazioni', style: theme.textTheme.titleSmall),
              const SizedBox(height: 14),
              _InfoRow(label: 'Versione', value: AppInfo.versionLabel),
              const SizedBox(height: 10),
              _InfoRow(label: 'Fase', value: AppInfo.phaseLabel),
              const SizedBox(height: 10),
              _InfoRow(label: 'Privacy', value: 'Posizione approssimata'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Costruito una fase alla volta',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.name,
    required this.detail,
    required this.state,
  });

  final String name;
  final String detail;
  final ServiceState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _StatusBadge(state: state),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Etichetta compatta dello stato di un servizio.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final ServiceState state;

  String get _label => switch (state) {
    ServiceState.connected => 'Collegato',
    ServiceState.failed => 'Errore',
    ServiceState.notConfigured => 'Non configurato',
  };

  Color _color(ColorScheme scheme) => switch (state) {
    ServiceState.connected => scheme.secondary,
    ServiceState.failed => scheme.error,
    ServiceState.notConfigured => scheme.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = _color(theme.colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTypeRow extends StatelessWidget {
  const _AccountTypeRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient(color),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.30),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 21, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  /// Oltre questa lunghezza il valore va sotto l'etichetta, a tutta larghezza:
  /// la versione con commit e ramo resta su una riga senza spezzare il ramo.
  static const int _inlineLimit = 26;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Text labelText = Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final TextStyle? valueStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
    );

    if (value.length > _inlineLimit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          labelText,
          const SizedBox(height: 4),
          Text(value, style: valueStyle),
        ],
      );
    }
    return Row(
      children: [
        labelText,
        const SizedBox(width: 16),
        Expanded(
          child: Text(value, textAlign: TextAlign.end, style: valueStyle),
        ),
      ],
    );
  }
}

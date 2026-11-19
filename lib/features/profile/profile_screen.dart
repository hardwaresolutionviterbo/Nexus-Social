import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/app_config.dart';
import '../../core/services/backend_bootstrap.dart';
import '../../core/theme/app_theme.dart';
import '../market/market_repository.dart';
import '../market/market_models.dart';
import '../../core/widgets/piazly_ui.dart';
import '../../core/widgets/nexus_ui.dart';
import '../contacts/contacts_sync.dart';
import '../chat/chat_backup_screen.dart';
import '../chat/chat_thread_screen.dart' show ChatRegistry;
import '../notifications/notification_settings.dart';
import '../privacy/privacy_repository.dart';
import '../privacy/privacy_screen.dart';
import '../security/app_lock.dart';
import '../security/security_repository.dart';
import '../security/security_screens.dart';
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
    this.privacy,
    this.pushSettings,
    this.security,
    this.biometricLock,
    this.contacts,
    this.feedback,
    this.isAdmin,
    this.market,
  });

  /// Per i numeri in alto (feedback, annunci, scambi, conclusi).
  final MarketRepository? market;

  /// Vero solo per gli amministratori di Piazly: vedono lo stato dei servizi e la diagnostica.
  final Future<bool> Function()? isAdmin;


  final BackendStatus backend;

  /// Media dei feedback (Fase 5, Blocco 4): solo per i privati con il server collegato.
  final Widget? feedback;

  /// Profilo completo (Blocco 2): presente quando il server è collegato.
  final MyProfile? profile;
  final ProfileRepository? profiles;
  final Future<void> Function()? onProfileChanged;

  /// Pagina Privacy (Blocco 3): presente quando il server è collegato.
  final PrivacyRepository? privacy;

  /// Preferenze delle notifiche (Fase 4, Blocco 5).
  final PushSettingsRepository? pushSettings;

  /// Sicurezza dell'account (Blocco 4).
  final SecurityRepository? security;
  final BiometricLock? biometricLock;

  /// Rubrica (Blocco 5).
  final ContactsRepository? contacts;

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

  void _openPrivacy(BuildContext context) {
    final PrivacyRepository? repo = privacy;
    if (repo == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivacyScreen(
          repository: repo,
          profiles: profiles,
          profile: profile,
          onChanged: () => onProfileChanged?.call(),
          contacts: contacts,
        ),
      ),
    );
  }

  void _openSecurity(BuildContext context) {
    final SecurityRepository? repo = security;
    final BiometricLock? lock = biometricLock;
    if (repo == null || lock == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SecuritySettingsScreen(repository: repo, lock: lock),
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
        FadeSlideIn(child: _ProfileHeader(me: me, profiles: profiles, signedIn: _signedIn, onEdit: me == null ? null : () => _openEditor(context))),
        if (me != null && market != null)
          Transform.translate(
            offset: const Offset(0, -26),
            child: _ProfileStats(repository: market!, userId: me.id),
          ),
        if (feedback != null) ...[
          SectionCard(
            key: const ValueKey<String>('miei_feedback'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('I tuoi feedback', style: theme.textTheme.titleSmall),
                feedback!,
              ],
            ),
          ),
        ],
        if (me != null) ...[
          const SizedBox(height: AppSpacing.sm),
          MenuCard(
            key: const ValueKey<String>('modifica_profilo'),
            icon: Icons.person_outline_rounded,
            title: 'Modifica profilo',
            subtitle: 'Foto, nome, bio e social',
            onTap: () => _openEditor(context),
          ),
          MenuCard(
            key: const ValueKey<String>('anteprima_profilo'),
            icon: Icons.visibility_outlined,
            color: AppColors.brandOrange,
            title: 'Il mio profilo pubblico',
            subtitle: 'Anteprima di come ti vedono gli altri',
            onTap: () => _openPreview(context),
          ),
          if (privacy != null)
            MenuCard(
              key: const ValueKey<String>('apri_privacy'),
              icon: Icons.shield_outlined,
              title: 'Privacy',
              subtitle: 'Numero, blocchi, GPS e autorizzazioni',
              onTap: () => _openPrivacy(context),
            ),
          if (security != null && biometricLock != null)
            MenuCard(
              key: const ValueKey<String>('apri_sicurezza'),
              icon: Icons.lock_outline_rounded,
              color: PiazlyColors.green,
              title: 'Sicurezza dell\'account',
              subtitle: 'PIN di verifica e sblocco con impronta o volto',
              onTap: () => _openSecurity(context),
            ),
          if (ChatRegistry.current?.backup != null)
            MenuCard(
              key: const ValueKey<String>('apri_backup_chat'),
              icon: Icons.cloud_upload_outlined,
              color: AppColors.brandBlue,
              title: 'Backup delle chat',
              subtitle: 'Salva i tuoi messaggi',
              onTap: () => ChatBackupScreen.open(context, ChatRegistry.current!.backup!),
            ),
          if (pushSettings != null)
            MenuCard(
              key: const ValueKey<String>('apri_notifiche'),
              icon: Icons.notifications_none_rounded,
              color: AppColors.brandOrange,
              title: 'Notifiche',
              subtitle: 'Messaggi, commenti, scambi e altro',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NotificationSettingsScreen(repository: pushSettings!),
                ),
              ),
            ),
        ],
        if (_signedIn) ...[
          const SizedBox(height: AppSpacing.sm),
          MenuCard(
            icon: Icons.logout_rounded,
            color: AppColors.brandCoral,
            title: 'Esci',
            subtitle: 'Esci dall\'account su questo telefono',
            onTap: () => _confirmSignOut(context),
          ),
        ],
        // Stato dei servizi, versione e diagnostica: solo per gli amministratori (decisione del
        // titolare, 19/11/2026). Senza account (configurazione iniziale) restano visibili.
        _AdminOnly(
          isAdmin: isAdmin,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                    const Divider(height: 22),
                    _InfoRow(label: 'Versione', value: AppInfo.versionLabel),
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
            ],
          ),
        ),
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
      ],
    );
  }
}

/// Mostra il contenuto solo se il server dice che l'utente è amministratore.
/// Intestazione viola con onde leggere, foto grande con l'anello arancio e la fotocamera.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.me, required this.profiles, required this.signedIn, this.onEdit});

  final MyProfile? me;
  final ProfileRepository? profiles;
  final bool signedIn;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MyProfile? p = me;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 48),
        decoration: const BoxDecoration(gradient: PiazlyColors.violetGradient),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Onde leggere sullo sfondo.
            Positioned(
              right: -60,
              top: -70,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            Positioned(
              left: -40,
              bottom: -110,
              child: Container(
                width: 260,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(120),
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Row(
              children: [
                GestureDetector(
                  key: const ValueKey<String>('profilo_foto'),
                  onTap: onEdit,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.orangeGradient,
                          boxShadow: [BoxShadow(color: AppColors.brandOrange.withValues(alpha: 0.5), blurRadius: 18)],
                        ),
                        child: p != null
                            ? AvatarView(
                                name: p.publicName.isEmpty ? p.username : p.publicName,
                                repository: profiles,
                                path: p.avatarThumbPath,
                                size: 96,
                              )
                            : Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                                child: const Icon(Icons.person_rounded, color: Colors.white, size: 48),
                              ),
                      ),
                      if (p != null)
                        const Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 17,
                            backgroundColor: Colors.white,
                            child: Icon(Icons.photo_camera_rounded, size: 19, color: Color(0xFF1F2937)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p != null) ...[
                        Text(
                          p.isBusiness && p.businessName != null ? p.businessName! : p.publicName,
                          key: const ValueKey<String>('mio_nome_pubblico'),
                          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '@${p.username}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ] else ...[
                        Text(
                          signedIn ? 'Accesso effettuato' : 'Profilo non configurato',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          signedIn
                              ? AppConfig.serverLinkEnabled
                                    ? 'Nome, foto e bio si completano nel prossimo aggiornamento.'
                                    : 'Collegamento al server in attesa. Nome, foto e bio '
                                          'arriveranno nei prossimi aggiornamenti.'
                              : 'Registrati con il numero di telefono per iniziare.',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bar_chart_rounded, color: PiazlyColors.violet, size: 20),
                            SizedBox(width: 6),
                            Text('Fase 2', style: TextStyle(color: PiazlyColors.violet, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// I numeri in alto: feedback ricevuti, annunci attivi, proposte di scambio, affari conclusi.
class _ProfileStats extends StatefulWidget {
  const _ProfileStats({required this.repository, required this.userId});

  final MarketRepository repository;
  final String userId;

  @override
  State<_ProfileStats> createState() => _ProfileStatsState();
}

class _ProfileStatsState extends State<_ProfileStats> {
  int? _feedback;
  int? _listings;
  int? _swaps;
  int? _deals;

  @override
  void initState() {
    super.initState();
    widget.repository.feedbackSummary(widget.userId).then((FeedbackSummary s) {
      if (mounted) setState(() => _feedback = s.count);
    }, onError: (Object _) {});
    widget.repository.mine().then((List<MyMarketListing> l) {
      if (mounted) setState(() => _listings = l.where((MyMarketListing x) => x.state == MarketListingState.active).length);
    }, onError: (Object _) {});
    widget.repository.mySwaps().then((List<SwapProposal> l) {
      if (mounted) setState(() => _swaps = l.length);
    }, onError: (Object _) {});
    widget.repository.myDeals().then((List<MarketDeal> l) {
      if (mounted) setState(() => _deals = l.length);
    }, onError: (Object _) {});
  }

  Widget _stat(String key, IconData icon, int? n, String label, Color color) => Expanded(
    child: SoftCard(
      key: ValueKey<String>('statistica_$key'),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      radius: 18,
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(n == null ? '–' : '$n', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        _stat('feedback', Icons.star_outline_rounded, _feedback, 'Feedback', AppColors.brandOrange),
        _stat('annunci', Icons.article_outlined, _listings, 'Annunci', PiazlyColors.violet),
        _stat('scambi', Icons.swap_horiz_rounded, _swaps, 'Scambi', PiazlyColors.violet),
        _stat('conclusi', Icons.handshake_outlined, _deals, 'Conclusi', AppColors.brandCoral),
      ],
    ),
  );
}

class _AdminOnly extends StatefulWidget {
  const _AdminOnly({required this.isAdmin, required this.child});

  final Future<bool> Function()? isAdmin;
  final Widget child;

  @override
  State<_AdminOnly> createState() => _AdminOnlyState();
}

class _AdminOnlyState extends State<_AdminOnly> {
  late bool _show = widget.isAdmin == null;

  @override
  void initState() {
    super.initState();
    final Future<bool> Function()? check = widget.isAdmin;
    if (check != null) {
      check().then((bool ok) {
        if (mounted && ok) setState(() => _show = true);
      }, onError: (Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) => _show ? widget.child : const SizedBox.shrink();
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

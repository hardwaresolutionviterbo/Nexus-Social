import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import 'avatar_view.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// Profilo sociale come lo vedono gli altri utenti autenticati (R2.10).
///
/// Mostra solo: nome abbreviato, @username, foto, bio e social secondo gli interruttori
/// (P3). Mai nome completo, numero, data di nascita o dati aziendali (P4).
/// Apre un link fuori dall'app: l'app del social se installata, altrimenti il browser.
typedef OpenLink = Future<bool> Function(Uri uri);

Future<bool> openExternally(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

class PublicProfileView extends StatelessWidget {
  const PublicProfileView({
    super.key,
    required this.profile,
    this.repository,
    this.openLink = openExternally,
  });

  final PublicProfile profile;
  final ProfileRepository? repository;
  final OpenLink openLink;

  Future<void> _open(BuildContext context, SocialNetwork network, String handle) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    bool ok = false;
    try {
      ok = await openLink(Uri.parse(network.profileUrl(handle)));
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Non è stato possibile aprire ${network.label}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? bio = profile.bio?.trim().isEmpty ?? true ? null : profile.bio!.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AvatarView(
            name: profile.publicName.isEmpty ? profile.username : profile.publicName,
            repository: repository,
            path: profile.avatarPath ?? profile.avatarThumbPath,
            size: 104,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          profile.publicName,
          key: const ValueKey<String>('nome_pubblico'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '@${profile.username}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (profile.isBusiness) ...[
          const SizedBox(height: 10),
          const Center(
            child: Chip(
              avatar: Icon(Icons.storefront_outlined, size: 18),
              label: Text('Azienda'),
            ),
          ),
        ],
        if (bio != null) ...[
          const SizedBox(height: 16),
          SectionCard(
            child: Text(bio, key: const ValueKey<String>('bio_pubblica')),
          ),
        ],
        if (profile.social.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Social', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final MapEntry<SocialNetwork, String> e in profile.social.entries)
                  ListTile(
                    key: ValueKey<String>('apri_${e.key.key}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.link_rounded, color: AppColors.brandOrange),
                    title: Text('${e.key.label} · @${e.value}'),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => _open(context, e.key, e.value),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Anteprima del proprio profilo pubblico («Come ti vedono gli altri»).
class PublicProfileScreen extends StatelessWidget {
  const PublicProfileScreen({
    super.key,
    required this.profile,
    this.repository,
    this.title = 'Come ti vedono gli altri',
    this.openLink = openExternally,
    this.onBlock,
  });

  final PublicProfile profile;
  final ProfileRepository? repository;
  final String title;
  final OpenLink openLink;

  /// Profilo di un altro utente: «Blocca» (R2.7). Assente nell'anteprima del proprio profilo.
  final Future<void> Function()? onBlock;

  Future<void> _confirmBlock(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Bloccare ${profile.publicName}?'),
        content: const Text(
          'Non vedrà più il tuo profilo e non potrà scriverti, chiamarti o commentare i tuoi '
          'annunci. Non riceverà nessun avviso. Puoi sbloccarlo da Privacy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const ValueKey<String>('conferma_blocco'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Blocca'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await onBlock!();
      messenger?.showSnackBar(SnackBar(content: Text('${profile.publicName} è bloccato.')));
      nav.pop();
    } on ProfileFailure catch (f) {
      messenger?.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (onBlock != null)
            PopupMenuButton<String>(
              key: const ValueKey<String>('menu_profilo'),
              onSelected: (_) => _confirmBlock(context),
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  key: ValueKey<String>('blocca_utente'),
                  value: 'blocca',
                  child: Text('Blocca'),
                ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          NexusBackdrop(isDark: theme.brightness == Brightness.dark),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                PublicProfileView(profile: profile, repository: repository, openLink: openLink),
                const SizedBox(height: 18),
                if (onBlock == null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 16, color: theme.colorScheme.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Nome completo, numero di telefono e data di nascita non sono mai '
                        'visibili agli altri.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

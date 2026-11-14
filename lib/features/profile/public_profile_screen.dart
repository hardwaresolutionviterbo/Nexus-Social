import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import 'avatar_view.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// Profilo sociale come lo vedono gli altri utenti autenticati (R2.10).
///
/// Mostra solo: nome abbreviato, @username, foto, bio e social secondo gli interruttori
/// (P3), ragione sociale per le Aziende. Mai nome completo, numero, data di nascita o
/// partita IVA.
class PublicProfileView extends StatelessWidget {
  const PublicProfileView({super.key, required this.profile, this.repository});

  final PublicProfile profile;
  final ProfileRepository? repository;

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
          profile.isBusiness && profile.businessName != null
              ? profile.businessName!
              : profile.publicName,
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
          Center(
            child: Chip(
              avatar: const Icon(Icons.storefront_outlined, size: 18),
              label: Text('Azienda · ${profile.publicName}'),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.link_rounded, size: 18, color: AppColors.brandOrange),
                        const SizedBox(width: 8),
                        Text('${e.key.label} · @${e.value}'),
                      ],
                    ),
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
  });

  final PublicProfile profile;
  final ProfileRepository? repository;
  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Stack(
        children: [
          NexusBackdrop(isDark: theme.brightness == Brightness.dark),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                PublicProfileView(profile: profile, repository: repository),
                const SizedBox(height: 18),
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

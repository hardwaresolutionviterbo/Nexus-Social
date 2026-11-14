import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../profile/profile_models.dart';
import '../profile/profile_repository.dart';
import '../profile/public_profile_screen.dart';
import 'privacy_checkup_screen.dart';
import 'privacy_controller.dart';
import 'privacy_repository.dart';
import 'privacy_sections.dart';

/// Pagina «Privacy» (R2.8): una voce per sezione con la scelta attuale; toccandola si apre
/// il dettaglio. In cima il percorso guidato «Controllo privacy» (R2.9).
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({
    super.key,
    required this.repository,
    this.profiles,
    this.profile,
    this.onChanged,
  });

  final PrivacyRepository repository;
  final ProfileRepository? profiles;
  final MyProfile? profile;

  /// Chiamata quando cambia qualcosa che si vede nel profilo (bio e social).
  final VoidCallback? onChanged;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late final PrivacyController _controller = PrivacyController(widget.repository)
    ..addListener(_changed);
  PrivacySettings? _last;

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  void _changed() {
    if (_controller.loading) return;
    final PrivacySettings s = _controller.settings;
    final PrivacySettings? old = _last;
    _last = s;
    if (old != null && (old.showBio != s.showBio || old.showSocial != s.showSocial)) {
      widget.onChanged?.call();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  VoidCallback? _previewFor(BuildContext context) {
    final MyProfile? p = widget.profile;
    if (p == null) return null;
    return () {
      final PrivacySettings s = _controller.settings;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PublicProfileScreen(
            profile: PublicProfile(
              id: p.id,
              isBusiness: p.isBusiness,
              username: p.username,
              publicName: p.publicName,
              avatarPath: p.avatarPath,
              avatarThumbPath: p.avatarThumbPath,
              bio: s.showBio ? p.bio : null,
              social: s.showSocial ? p.social : const <SocialNetwork, String>{},
            ),
            repository: widget.profiles,
          ),
        ),
      );
    };
  }

  void _open(PrivacySection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext route) => Scaffold(
          appBar: AppBar(title: Text(section.title)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              PrivacySectionBody(
                section: section,
                controller: _controller,
                profiles: widget.profiles,
                onPreview: _previewFor(route),
              ),
              _ErrorLine(controller: _controller),
            ],
          ),
        ),
      ),
    );
  }

  void _openCheckup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext route) => PrivacyCheckupScreen(
          controller: _controller,
          profiles: widget.profiles,
          onPreview: _previewFor(route),
          onDone: () => Navigator.of(route).pop(),
        ),
      ),
    );
  }

  void _openDoc(String title, String asset) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LegalDraftScreen(title: title, asset: asset)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, _) {
          if (_controller.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              SectionCard(
                child: ListTile(
                  key: const ValueKey<String>('apri_controllo_privacy'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.health_and_safety_outlined,
                      color: AppColors.brandOrange),
                  title: const Text('Controllo privacy'),
                  subtitle: const Text('Rivedi le tue scelte in pochi passi'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openCheckup,
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  children: [
                    for (final PrivacySection s in PrivacySection.values)
                      ListTile(
                        key: ValueKey<String>('sezione_${s.name}'),
                        leading: Icon(s.icon, color: s.color),
                        title: Text(s.title),
                        subtitle: Text(s.summary(_controller)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _open(s),
                      ),
                  ],
                ),
              ),
              _ErrorLine(controller: _controller),
              const SizedBox(height: 14),
              SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Informativa sulla privacy'),
                      onTap: () =>
                          _openDoc('Privacy', 'docs/fase0/BOZZA_PRIVACY_POLICY.md'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.gavel_outlined),
                      title: const Text('Termini d\'uso'),
                      onTap: () => _openDoc('Termini d\'uso', 'docs/fase0/BOZZA_TERMINI_USO.md'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: const Text('Regole della community'),
                      onTap: () => _openDoc(
                        'Regole della community',
                        'docs/fase0/BOZZA_REGOLE_COMMUNITY.md',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Le scelte si salvano subito e le applica il server.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.controller});

  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final String? e = controller.error;
        if (e == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            e,
            key: const ValueKey<String>('errore_privacy'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
      },
    );
  }
}

/// Testo delle bozze legali, con l'avviso «bozza non validata» (S7).
class LegalDraftScreen extends StatelessWidget {
  const LegalDraftScreen({super.key, required this.title, required this.asset});

  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(asset),
        builder: (BuildContext context, AsyncSnapshot<String> snap) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Bozza non validata: il testo definitivo sarà rivisto da un professionista.',
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(snap.data ?? ''),
          ],
        ),
      ),
    );
  }
}

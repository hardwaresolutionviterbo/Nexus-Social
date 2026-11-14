import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_repository.dart';
import 'privacy_controller.dart';
import 'privacy_repository.dart';

/// Le 7 sezioni della pagina Privacy (R2.8, `docs/fase0/PRIVACY_IMPOSTAZIONI.md` §3).
/// Le stesse schermate compongono i passi del Controllo privacy (§4).
enum PrivacySection {
  profile('Visibilità del profilo', Icons.person_outline_rounded, AppColors.brandBlue),
  phone('Numero di telefono', Icons.phone_outlined, AppColors.brandOrange),
  contacts('Contatti e rubrica', Icons.contacts_outlined, AppColors.brandViolet),
  location('Posizione', Icons.place_outlined, AppColors.brandMint),
  gps('GPS in tempo reale', Icons.my_location_rounded, AppColors.brandCyan),
  blocked('Persone bloccate', Icons.block_rounded, AppColors.brandCoral),
  permissions('Autorizzazioni', Icons.verified_user_outlined, AppColors.brandAmber);

  const PrivacySection(this.title, this.icon, this.color);

  final String title;
  final IconData icon;
  final Color color;

  /// Scelta attuale, mostrata sotto il titolo (come le impostazioni di WhatsApp).
  String summary(PrivacyController c) => switch (this) {
    PrivacySection.profile =>
      'Bio ${c.settings.showBio ? 'visibile' : 'nascosta'} · '
          'social ${c.settings.showSocial ? 'visibili' : 'nascosti'}',
    PrivacySection.phone => c.settings.phoneVisibility.label,
    PrivacySection.contacts => 'Rubrica non attiva',
    PrivacySection.location => 'Posizione esatta mai visibile',
    PrivacySection.gps => 'Spento · nessuna condivisione',
    PrivacySection.blocked => switch (c.blocked.length) {
      0 => 'Nessuno',
      1 => '1 persona',
      final int n => '$n persone',
    },
    PrivacySection.permissions => 'Permessi del telefono e consensi',
  };
}

/// Contenuto di una sezione.
class PrivacySectionBody extends StatelessWidget {
  const PrivacySectionBody({
    super.key,
    required this.section,
    required this.controller,
    this.profiles,
    this.onPreview,
  });

  final PrivacySection section;
  final PrivacyController controller;
  final ProfileRepository? profiles;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => switch (section) {
        PrivacySection.profile => _ProfileBody(controller: controller, onPreview: onPreview),
        PrivacySection.phone => _PhoneBody(controller: controller),
        PrivacySection.contacts => const _ContactsBody(),
        PrivacySection.location => const _LocationBody(),
        PrivacySection.gps => const _GpsBody(),
        PrivacySection.blocked => _BlockedBody(controller: controller, profiles: profiles),
        PrivacySection.permissions => const _PermissionsBody(),
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.icon = Icons.info_outline_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Soon extends StatelessWidget {
  const _Soon(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brandOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.controller, this.onPreview});

  final PrivacyController controller;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nome abbreviato, @username e foto sono sempre visibili agli utenti registrati: '
            'servono a riconoscere chi pubblica o commenta.',
          ),
          SwitchListTile(
            key: const ValueKey<String>('privacy_mostra_bio'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostra la bio'),
            value: controller.settings.showBio,
            onChanged: controller.saving ? null : controller.setShowBio,
          ),
          SwitchListTile(
            key: const ValueKey<String>('privacy_mostra_social'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostra i social'),
            value: controller.settings.showSocial,
            onChanged: controller.saving ? null : controller.setShowSocial,
          ),
          if (onPreview != null)
            TextButton.icon(
              key: const ValueKey<String>('privacy_anteprima'),
              onPressed: onPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Come ti vedono gli altri'),
            ),
        ],
      ),
    );
  }
}

class _PhoneBody extends StatelessWidget {
  const _PhoneBody({required this.controller});

  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chi può vedere il mio numero?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          RadioGroup<PhoneVisibility>(
            groupValue: controller.settings.phoneVisibility,
            onChanged: (PhoneVisibility? v) {
              if (v != null && !controller.saving) controller.setPhoneVisibility(v);
            },
            child: const Column(
              children: [
                RadioListTile<PhoneVisibility>(
                  key: ValueKey<String>('numero_contatti'),
                  contentPadding: EdgeInsets.zero,
                  value: PhoneVisibility.contacts,
                  title: Text('Contatti riconosciuti dalla rubrica'),
                  subtitle: Text('Solo chi ha il tuo numero salvato in rubrica'),
                ),
                RadioListTile<PhoneVisibility>(
                  key: ValueKey<String>('numero_nessuno'),
                  contentPadding: EdgeInsets.zero,
                  value: PhoneVisibility.nobody,
                  title: Text('Nessuno'),
                ),
              ],
            ),
          ),
          const _Note(
            'Agli sconosciuti il numero non si vede mai. Accettare una chat non lo rende '
            'visibile: chi non ha il tuo numero ti scrive tramite @username.',
            icon: Icons.lock_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _ContactsBody extends StatelessWidget {
  const _ContactsBody();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: ValueKey<String>('trova_contatti'),
            contentPadding: EdgeInsets.zero,
            title: Text('Trova i contatti iscritti'),
            subtitle: Text('Spento'),
            value: false,
            onChanged: null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Permetti a chi ha il mio numero di trovarmi'),
            subtitle: Text('Si accende quando attivi la rubrica; poi puoi spegnerlo'),
            value: false,
            onChanged: null,
          ),
          _Note(
            'La rubrica è facoltativa e revocabile. I numeri non vengono mai inviati in '
            'chiaro e i dati derivati si cancellano dopo 30 giorni senza una nuova '
            'sincronizzazione.',
            icon: Icons.lock_outline_rounded,
          ),
          _Soon('Disponibile con il prossimo aggiornamento (Fase 2, Blocco 5).'),
        ],
      ),
    );
  }
}

class _LocationBody extends StatelessWidget {
  const _LocationBody();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'La tua posizione esatta non è mai visibile agli altri. I tuoi annunci '
            'compaiono in una zona approssimata.',
            key: ValueKey<String>('posizione_info'),
          ),
          _Note(
            'Per ogni annuncio potrai scegliere: zona approssimata (proposta di partenza), '
            'GPS in tempo reale oppure un punto scelto a mano (bar, punto d\'incontro). '
            'La scelta vale solo per quell\'annuncio.',
          ),
          _Soon('Annunci e Mappa arrivano nella Fase 3.'),
        ],
      ),
    );
  }
}

class _GpsBody extends StatelessWidget {
  const _GpsBody();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nessuna condivisione attiva.', key: ValueKey<String>('gps_info')),
          _Note(
            'Il GPS in tempo reale è spento di partenza. Quando lo userai sarà temporaneo '
            '(al massimo 8 ore), revocabile in ogni momento e visibile solo alle persone '
            'che autorizzi. Alla fine l\'ultima posizione viene cancellata.',
            icon: Icons.lock_outline_rounded,
          ),
          _Soon('Disponibile con la Mappa (Fase 3).'),
        ],
      ),
    );
  }
}

class _BlockedBody extends StatelessWidget {
  const _BlockedBody({required this.controller, this.profiles});

  final PrivacyController controller;
  final ProfileRepository? profiles;

  Future<void> _confirm(BuildContext context, BlockedUser user) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Sbloccare ${user.publicName}?'),
        content: const Text('Potrà di nuovo vedere il tuo profilo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sblocca'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.unblock(user);
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.blocked.isEmpty)
            const Text('Non hai bloccato nessuno.', key: ValueKey<String>('nessun_bloccato'))
          else
            for (final BlockedUser u in controller.blocked)
              ListTile(
                key: ValueKey<String>('bloccato_${u.id}'),
                contentPadding: EdgeInsets.zero,
                leading: AvatarView(
                  name: u.publicName,
                  repository: profiles,
                  path: u.avatarThumbPath,
                  size: 40,
                ),
                title: Text(u.publicName),
                subtitle: Text('@${u.username}'),
                trailing: TextButton(
                  onPressed: controller.saving ? null : () => _confirm(context, u),
                  child: const Text('Sblocca'),
                ),
              ),
          const _Note(
            'Chi è bloccato non vede il tuo profilo e non viene avvisato. Non potrà '
            'scriverti, chiamarti, commentare i tuoi annunci né vedere le tue reazioni '
            '(con chat e commenti, nelle prossime fasi).',
          ),
        ],
      ),
    );
  }
}

class _PermissionsBody extends StatelessWidget {
  const _PermissionsBody();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    Widget row(IconData icon, String name, String state) => ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(name),
      subtitle: Text(state),
    );
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Permessi del telefono', style: theme.textTheme.titleSmall),
          row(Icons.notifications_outlined, 'Notifiche',
              'Gestite nelle impostazioni del telefono'),
          row(Icons.photo_library_outlined, 'Foto',
              'Nessun accesso alla galleria: scegli tu ogni singola foto'),
          row(Icons.contacts_outlined, 'Contatti', 'Non usato (servirà alla rubrica)'),
          row(Icons.place_outlined, 'Posizione', 'Non usata (servirà alla Mappa, Fase 3)'),
          row(Icons.mic_none_rounded, 'Microfono', 'Non usato (vocali e chiamate, Fase 4)'),
          const Divider(height: 24),
          Text('Consensi dati nell\'app', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          const Text(
            'Nessun consenso attivo.',
            key: ValueKey<String>('nessun_consenso'),
          ),
          const _Note(
            'Qui compariranno, con la data e il pulsante «Revoca», i consensi per la rubrica, '
            'il GPS in tempo reale e le notifiche delle promozioni vicine.',
          ),
        ],
      ),
    );
  }
}

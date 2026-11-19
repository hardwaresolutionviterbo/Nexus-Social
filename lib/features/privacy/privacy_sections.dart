import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../contacts/contacts_sync.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_repository.dart';
import 'privacy_controller.dart';
import 'privacy_repository.dart';

/// Le 7 sezioni della pagina Privacy (R2.8, `docs/fase0/PRIVACY_IMPOSTAZIONI.md` §3).
/// Le stesse schermate compongono i passi del Controllo privacy (§4).
enum PrivacySection {
  profile('Visibilità del profilo', Icons.person_outline_rounded, AppColors.brandBlue),
  phone('Numero di telefono', Icons.phone_outlined, AppColors.brandOrange),
  lastSeen('Ultimo accesso e online', Icons.access_time_rounded, AppColors.brandBlue),
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
    PrivacySection.lastSeen => c.settings.lastSeen.label,
    PrivacySection.contacts => c.settings.contactsEnabled
        ? 'Attiva · ${c.contacts.length == 1 ? '1 contatto' : '${c.contacts.length} contatti'}'
        : 'Rubrica non attiva',
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
        PrivacySection.lastSeen => _LastSeenBody(controller: controller),
        PrivacySection.contacts => controller.contactsRepository == null
            ? const _ContactsBody()
            : _LiveContactsBody(controller: controller, profiles: profiles),
        PrivacySection.location => const _LocationBody(),
        PrivacySection.gps => const _GpsBody(),
        PrivacySection.blocked => _BlockedBody(controller: controller, profiles: profiles),
        PrivacySection.permissions => _PermissionsBody(controller: controller),
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

/// «Ultimo accesso e online» (Fase 4, Blocco 12), come su WhatsApp.
class _LastSeenBody extends StatelessWidget {
  const _LastSeenBody({required this.controller});

  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chi può vedere quando sono online e il mio ultimo accesso?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          RadioGroup<LastSeenVisibility>(
            groupValue: controller.settings.lastSeen,
            onChanged: (LastSeenVisibility? v) {
              if (v != null && !controller.saving) controller.setLastSeen(v);
            },
            child: const Column(
              children: [
                RadioListTile<LastSeenVisibility>(
                  key: ValueKey<String>('accesso_tutti'),
                  contentPadding: EdgeInsets.zero,
                  value: LastSeenVisibility.everyone,
                  title: Text('Tutti'),
                  subtitle: Text('Chi ha una chat con te'),
                ),
                RadioListTile<LastSeenVisibility>(
                  key: ValueKey<String>('accesso_contatti'),
                  contentPadding: EdgeInsets.zero,
                  value: LastSeenVisibility.contacts,
                  title: Text('I miei contatti'),
                  subtitle: Text('Solo chi hai in rubrica'),
                ),
                RadioListTile<LastSeenVisibility>(
                  key: ValueKey<String>('accesso_nessuno'),
                  contentPadding: EdgeInsets.zero,
                  value: LastSeenVisibility.nobody,
                  title: Text('Nessuno'),
                ),
              ],
            ),
          ),
          const _Note(
            'Come su WhatsApp: se non mostri il tuo, non vedi nemmeno quello degli altri. '
            'Con le persone bloccate non si vede in nessuna delle due direzioni.',
            icon: Icons.sync_alt_rounded,
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
  const _PermissionsBody({required this.controller});

  final PrivacyController controller;

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
          row(Icons.contacts_outlined, 'Contatti', 'Letti solo con la rubrica attiva, mai inviati in chiaro'),
          row(Icons.place_outlined, 'Posizione', 'Non usata (servirà alla Mappa, Fase 3)'),
          row(Icons.mic_none_rounded, 'Microfono', 'Non usato (vocali e chiamate, Fase 4)'),
          const Divider(height: 24),
          Text('Consensi dati nell\'app', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          if (controller.settings.contactsEnabled)
            ListTile(
              key: const ValueKey<String>('consenso_rubrica'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.contacts_outlined),
              title: const Text('Rubrica'),
              subtitle: Text(
                controller.settings.contactsConsentAt == null
                    ? 'Attivo'
                    : 'Dal ${formatDay(controller.settings.contactsConsentAt!)}',
              ),
              trailing: TextButton(
                onPressed: controller.saving ? null : () => confirmRevokeContacts(context, controller),
                child: const Text('Revoca'),
              ),
            )
          else
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


String formatDay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

Future<void> confirmRevokeContacts(BuildContext context, PrivacyController controller) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('Revocare la rubrica?'),
      content: const Text(
        'La sincronizzazione si ferma e i dati ricavati dalla tua rubrica vengono cancellati '
        'subito dal server. Potrai riattivarla quando vuoi.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          key: const ValueKey<String>('conferma_revoca_rubrica'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Revoca e cancella'),
        ),
      ],
    ),
  );
  if (ok == true) await controller.revokeContacts();
}

/// Consenso esplicito alla rubrica (R2.6, P7, P13): cosa succede ai numeri, prima del
/// permesso del sistema.
Future<bool> askContactsConsent(BuildContext context) async {
  final bool? ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) {
      final ThemeData theme = Theme.of(context);
      Widget point(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.brandOrange),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Trova i contatti iscritti', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              point(Icons.lock_outline_rounded,
                  'I numeri della tua rubrica non vengono mai inviati in chiaro: il telefono '
                  'li trasforma in codici protetti prima di inviarli.'),
              point(Icons.person_search_outlined,
                  'Scopri quali tuoi contatti usano Piazly. Chi ha il tuo numero potrà '
                  'trovarti: puoi spegnerlo in qualsiasi momento.'),
              point(Icons.sync_rounded,
                  'La rubrica si aggiorna da sola quando salvi un nuovo contatto o apri l\'app '
                  '(al massimo 3 volte al giorno, 2.000 numeri): chi usa Piazly viene '
                  'riconosciuto subito.'),
              point(Icons.timer_outlined,
                  'Se smetti di usare l\'app, i dati ricavati dalla rubrica si cancellano da '
                  'soli dopo 30 giorni.'),
              point(Icons.undo_rounded,
                  'Puoi revocare in ogni momento: i dati ricavati dalla rubrica vengono '
                  'cancellati subito.'),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey<String>('accetta_rubrica'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.brandOrange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Accetto e continua'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Non ora'),
              ),
            ],
          ),
        ),
      );
    },
  );
  return ok ?? false;
}

class _LiveContactsBody extends StatelessWidget {
  const _LiveContactsBody({required this.controller, this.profiles});

  final PrivacyController controller;
  final ProfileRepository? profiles;

  Future<void> _activate(BuildContext context) async {
    if (await askContactsConsent(context)) await controller.enableContacts();
  }

  void _openList(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContactsListScreen(contacts: controller.contacts, profiles: profiles),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PrivacySettings s = controller.settings;
    final double? progress = controller.syncProgress;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!s.contactsEnabled) ...[
            const Text(
              'Attiva la rubrica per scoprire quali tuoi contatti usano Piazly. È facoltativa '
              'e puoi revocarla quando vuoi.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('attiva_rubrica'),
              onPressed: controller.saving ? null : () => _activate(context),
              icon: const Icon(Icons.contacts_outlined),
              label: const Text('Trova i contatti iscritti'),
            ),
          ] else ...[
            ListTile(
              key: const ValueKey<String>('contatti_riconosciuti'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.people_alt_outlined),
              title: Text(
                controller.contacts.length == 1
                    ? '1 contatto su Piazly'
                    : '${controller.contacts.length} contatti su Piazly',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openList(context),
            ),
            if (s.contactsSyncedAt != null)
              Text(
                'Ultima sincronizzazione: ${formatDay(s.contactsSyncedAt!)}'
                '${s.contactsExpireAt != null ? ' · i dati scadono il ${formatDay(s.contactsExpireAt!)}' : ''}',
                key: const ValueKey<String>('date_rubrica'),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey<String>('sincronizza_ora'),
              onPressed: controller.saving ? null : controller.syncContacts,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sincronizza ora'),
            ),
            SwitchListTile(
              key: const ValueKey<String>('permetti_trovarmi'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Permetti a chi ha il mio numero di trovarmi'),
              value: s.discoverable,
              onChanged: controller.saving ? null : controller.setDiscoverable,
            ),
            TextButton(
              key: const ValueKey<String>('revoca_rubrica'),
              onPressed: controller.saving ? null : () => confirmRevokeContacts(context, controller),
              child: const Text('Revoca e cancella'),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              key: const ValueKey<String>('avanzamento_rubrica'),
              value: progress,
              color: AppColors.brandOrange,
            ),
            const SizedBox(height: 4),
            Text('Protezione dei numeri in corso…', style: theme.textTheme.bodySmall),
          ],
          const _Note(
            'Si aggiorna da sola quando salvi un nuovo contatto o apri l\'app. I numeri non '
            'vengono mai inviati in chiaro. Se smetti di usare l\'app, i dati si cancellano '
            'dopo 30 giorni.',
            icon: Icons.lock_outline_rounded,
          ),
        ],
      ),
    );
  }
}

/// Contatti della rubrica che usano Piazly: dati pubblici, e il numero solo se consentito.
class ContactsListScreen extends StatelessWidget {
  const ContactsListScreen({super.key, required this.contacts, this.profiles});

  final List<RecognizedContact> contacts;
  final ProfileRepository? profiles;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contatti su Piazly')),
      body: contacts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nessun tuo contatto usa ancora Piazly, oppure non vuole farsi trovare.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final RecognizedContact c in contacts)
                  ListTile(
                    key: ValueKey<String>('contatto_${c.id}'),
                    leading: AvatarView(
                      name: c.publicName,
                      repository: profiles,
                      path: c.avatarThumbPath,
                      size: 44,
                    ),
                    title: Text(c.publicName),
                    subtitle: Text(c.phone == null ? '@${c.username}' : '@${c.username} · ${c.phone}'),
                  ),
              ],
            ),
    );
  }
}

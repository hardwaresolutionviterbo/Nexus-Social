import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../contacts/contacts_sync.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_repository.dart';
import 'live_location.dart';

String _hm(DateTime t) {
  final DateTime l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// «Fino alle 18:40» oppure «fino a domani alle 02:10».
String liveUntilLabel(DateTime until, DateTime now) {
  final DateTime l = until.toLocal();
  final bool today = l.year == now.year && l.month == now.month && l.day == now.day;
  return today ? 'fino alle ${_hm(l)}' : 'fino a domani alle ${_hm(l)}';
}

/// «Aggiornata adesso», «aggiornata 3 minuti fa».
String liveAgoLabel(DateTime at, DateTime now) {
  final int m = now.difference(at).inMinutes;
  if (m < 1) return 'aggiornata adesso';
  return m == 1 ? 'aggiornata 1 minuto fa' : 'aggiornata $m minuti fa';
}

/// Riassunto per la pagina Privacy.
String liveSummary(LiveLocationService? s) {
  if (s == null || !s.sharing) return 'Spento · nessuna condivisione';
  final int n = s.shares.length;
  return 'Attivo con ${n == 1 ? '1 persona' : '$n persone'} ${liveUntilLabel(s.until!, s.now)}';
}

/// Privacy → GPS in tempo reale: stato, persone, «Smetti di condividere».
class LiveShareCard extends StatelessWidget {
  const LiveShareCard({super.key, required this.service, required this.contacts, this.profiles});

  final LiveLocationService service;

  /// Persone della rubrica che usano Piazly (null se la rubrica non è attiva).
  final List<RecognizedContact>? contacts;
  final ProfileRepository? profiles;

  Future<void> _stop(BuildContext context, {String? viewer, String? name}) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(viewer == null ? 'Smettere di condividere?' : 'Smettere con $name?'),
        content: Text(viewer == null
            ? 'Nessuno vedrà più dove sei e l\'ultima posizione si cancella subito.'
            : '$name non vedrà più dove sei.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annulla')),
          FilledButton(
            key: const ValueKey<String>('gps_stop_conferma'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Smetti'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await service.stop(viewer: viewer);
    } on LiveFailure catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: service,
      builder: (BuildContext context, _) {
        final List<LiveShare> shares = service.shares;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (shares.isEmpty)
              const Text('Nessuna condivisione attiva.', key: ValueKey<String>('gps_info'))
            else ...[
              Row(
                children: [
                  const Icon(Icons.my_location_rounded, color: Color(0xFF15803D), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stai condividendo la posizione ${liveUntilLabel(service.until!, service.now)}',
                      key: const ValueKey<String>('gps_attivo'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final LiveShare s in shares)
                ListTile(
                  key: ValueKey<String>('gps_con_${s.viewerId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: AvatarView(
                    name: service.nameOf(s.viewerId, s.name),
                    repository: profiles,
                    path: s.avatarPath,
                    size: 36,
                  ),
                  title: Text(service.nameOf(s.viewerId, s.name)),
                  subtitle: Text(liveUntilLabel(s.expiresAt, service.now)),
                  trailing: IconButton(
                    key: ValueKey<String>('gps_togli_${s.viewerId}'),
                    tooltip: 'Smetti con questa persona',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _stop(context, viewer: s.viewerId, name: service.nameOf(s.viewerId, s.name)),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey<String>('gps_condividi'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => LiveShareStartScreen(service: service, contacts: contacts, profiles: profiles),
                    ),
                  ),
                  icon: const Icon(Icons.share_location_rounded),
                  label: Text(shares.isEmpty ? 'Condividi la posizione' : 'Aggiungi persone'),
                ),
                if (shares.isNotEmpty)
                  OutlinedButton.icon(
                    key: const ValueKey<String>('gps_stop'),
                    onPressed: () => _stop(context),
                    icon: const Icon(Icons.location_disabled_rounded),
                    label: const Text('Smetti di condividere'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Scelta delle persone e della durata.
class LiveShareStartScreen extends StatefulWidget {
  const LiveShareStartScreen({super.key, required this.service, required this.contacts, this.profiles});

  final LiveLocationService service;
  final List<RecognizedContact>? contacts;
  final ProfileRepository? profiles;

  @override
  State<LiveShareStartScreen> createState() => _LiveShareStartScreenState();
}

class _LiveShareStartScreenState extends State<LiveShareStartScreen> {
  final Set<String> _chosen = <String>{};
  LiveDuration _duration = LiveDuration.hour;
  bool _busy = false;

  Future<void> _start() async {
    if (_chosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scegli almeno una persona.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.start(_chosen.toList(), _duration);
      if (mounted) Navigator.of(context).pop();
    } on LiveFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<RecognizedContact>? list = widget.contacts;
    return Scaffold(
      appBar: AppBar(title: const Text('Condividi la posizione')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Text('Per quanto tempo', style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SegmentedButton<LiveDuration>(
              key: const ValueKey<String>('gps_durata'),
              showSelectedIcon: false,
              segments: <ButtonSegment<LiveDuration>>[
                for (final LiveDuration d in LiveDuration.values)
                  ButtonSegment<LiveDuration>(
                    value: d,
                    label: Text(d.label, key: ValueKey<String>('gps_durata_${d.minutes}')),
                  ),
              ],
              selected: <LiveDuration>{_duration},
              onSelectionChanged: (Set<LiveDuration> v) => setState(() => _duration = v.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
            child: Text('Con chi', style: theme.textTheme.titleSmall),
          ),
          if (list == null)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Per scegliere le persone attiva la rubrica in Privacy → Contatti e rubrica: '
                'puoi condividere solo con chi hai in rubrica.',
                key: ValueKey<String>('gps_serve_rubrica'),
              ),
            )
          else if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Nessun contatto della rubrica usa ancora Piazly.'),
            )
          else
            for (final RecognizedContact c in list)
              CheckboxListTile(
                key: ValueKey<String>('gps_persona_${c.id}'),
                value: _chosen.contains(c.id),
                onChanged: (bool? v) => setState(() {
                  if (v == true) {
                    _chosen.add(c.id);
                  } else {
                    _chosen.remove(c.id);
                  }
                }),
                secondary: AvatarView(
                  name: widget.service.nameOf(c.id, c.publicName),
                  repository: widget.profiles,
                  path: c.avatarThumbPath,
                  size: 36,
                ),
                title: Text(widget.service.nameOf(c.id, c.publicName.isEmpty ? '@${c.username}' : c.publicName)),
                subtitle: Text('@${c.username}'),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'La vedono solo le persone scelte, sulla loro Mappa. Si aggiorna mentre Piazly è '
                    'aperta. Puoi smettere quando vuoi; alla fine l\'ultima posizione si cancella. '
                    'Non è cifrata end-to-end come i messaggi: la proteggono le regole del server.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey<String>('gps_avvia'),
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        onPressed: _busy ? null : _start,
        icon: _busy
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : const Icon(Icons.share_location_rounded),
        label: Text('Condividi per ${_duration.label}'),
      ),
    );
  }
}

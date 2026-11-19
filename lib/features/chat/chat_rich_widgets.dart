import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/piazly_ui.dart';
import '../map/live_location.dart';
import '../places/place_search.dart';
import 'chat_models.dart';
import 'chat_rich.dart';
import 'chat_service.dart';

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const List<String> _giorni = <String>['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];
const List<String> _mesi = <String>['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];

/// «sab 22 nov · 20:30».
String richDateLabel(DateTime t) => '${_giorni[t.weekday - 1]} ${t.day} ${_mesi[t.month - 1]} · ${_hm(t)}';

/// Apre un punto nell'app delle mappe del telefono.
Future<void> openInMaps(double lat, double lng, String label) async {
  final String q = Uri.encodeComponent(label.isEmpty ? 'Posizione' : label);
  final Uri geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng($q)');
  try {
    if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Nessuna app per «geo:»: si prova con il browser.
  }
  await launchUrl(
    Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng'),
    mode: LaunchMode.externalApplication,
  );
}

/// Contenuto di un messaggio ricco dentro il fumetto.
class RichMessageCard extends StatelessWidget {
  const RichMessageCard({super.key, required this.chat, required this.message, this.now});

  final ChatService chat;
  final ChatMessage message;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final RichPayload? p = RichPayload.decode(message.body);
    final ThemeData theme = Theme.of(context);
    return switch (p) {
      null => Text('Messaggio non disponibile su questo telefono', style: theme.textTheme.bodyMedium),
      RichLocation() => _LocationCard(p: p, now: now ?? DateTime.now()),
      RichContact() => _ContactCard(p: p),
      RichPoll() => _PollCard(chat: chat, message: message, p: p),
      RichEvent() => _EventCard(chat: chat, message: message, p: p),
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.color, required this.title, this.subtitle});

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.p, required this.now});

  final RichLocation p;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final DateTime? live = p.liveUntil;
    final bool active = live != null && live.isAfter(now);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            icon: live != null ? Icons.share_location_rounded : Icons.location_on_rounded,
            color: live != null ? PiazlyColors.green : const Color(0xFFE53935),
            title: live != null ? 'Posizione in tempo reale' : (p.name.isEmpty ? 'Posizione' : p.name),
            subtitle: live != null
                ? (active ? 'Fino alle ${_hm(live)} · la vedi nella Mappa' : 'Condivisione terminata')
                : p.address,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey<String>('ricco_apri_mappa'),
            onPressed: () => unawaited(openInMaps(p.lat, p.lng, p.name)),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Apri nelle mappe'),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.p});

  final RichContact p;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            icon: Icons.person_rounded,
            color: PiazlyColors.violet,
            title: p.name.isEmpty ? 'Contatto' : p.name,
            subtitle: p.phones.join('\n'),
          ),
          if (p.phones.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey<String>('ricco_chiama'),
                  onPressed: () => unawaited(launchUrl(Uri(scheme: 'tel', path: p.phones.first))),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Chiama'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('ricco_copia'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.phones.first));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numero copiato')));
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copia'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({required this.chat, required this.message, required this.p});

  final ChatService chat;
  final ChatMessage message;
  final RichPoll p;

  Future<void> _vote(BuildContext context, int i) async {
    final List<int> mine = RichPoll.parseVote(message.answers[''] ?? '', p.options.length);
    final List<int> next;
    if (p.multiple) {
      next = mine.contains(i) ? (mine.toList()..remove(i)) : (<int>[...mine, i]..sort());
    } else {
      next = mine.contains(i) ? <int>[] : <int>[i];
    }
    try {
      await chat.answer(message, next.join(','));
    } on ChatFailure catch (f) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<int> counts = p.counts(message.answers);
    final int voters = message.answers.values.where((String v) => v.isNotEmpty).length;
    final List<int> mine = RichPoll.parseVote(message.answers[''] ?? '', p.options.length);
    final int top = counts.isEmpty ? 0 : counts.reduce((int a, int b) => a > b ? a : b);
    final bool canVote = message.serverId != null && !message.deleted;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            icon: Icons.poll_rounded,
            color: const Color(0xFFF59E0B),
            title: p.question,
            subtitle: p.multiple ? 'Puoi scegliere più risposte' : 'Scegli una risposta',
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < p.options.length; i++)
            InkWell(
              key: ValueKey<String>('voto_$i'),
              borderRadius: BorderRadius.circular(10),
              onTap: canVote ? () => unawaited(_vote(context, i)) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          mine.contains(i)
                              ? (p.multiple ? Icons.check_box_rounded : Icons.radio_button_checked_rounded)
                              : (p.multiple ? Icons.check_box_outline_blank_rounded : Icons.radio_button_off_rounded),
                          size: 20,
                          color: mine.contains(i) ? PiazlyColors.violet : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(p.options[i])),
                        Text('${counts[i]}', style: theme.textTheme.labelLarge),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: voters == 0 ? 0 : counts[i] / voters,
                          minHeight: 6,
                          color: counts[i] == top && top > 0 ? PiazlyColors.violet : PiazlyColors.violet.withValues(alpha: 0.5),
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            voters == 1 ? '1 voto' : '$voters voti',
            key: const ValueKey<String>('sondaggio_voti'),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.chat, required this.message, required this.p});

  final ChatService chat;
  final ChatMessage message;
  final RichEvent p;

  Future<void> _answer(BuildContext context, String v) async {
    final String mine = message.answers[''] ?? '';
    try {
      await chat.answer(message, mine == v ? '' : v);
    } on ChatFailure catch (f) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int yes = message.answers.values.where((String v) => v == RichEvent.yes).length;
    final int no = message.answers.values.where((String v) => v == RichEvent.no).length;
    final String mine = message.answers[''] ?? '';
    final bool canAnswer = message.serverId != null && !message.deleted;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            icon: Icons.event_rounded,
            color: PiazlyColors.violet,
            title: p.title,
            subtitle: richDateLabel(p.at),
          ),
          if (p.place.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                key: const ValueKey<String>('evento_luogo'),
                onTap: p.lat != null && p.lng != null ? () => unawaited(openInMaps(p.lat!, p.lng!, p.place)) : null,
                child: Row(
                  children: [
                    Icon(Icons.place_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(child: Text(p.place)),
                  ],
                ),
              ),
            ),
          if (p.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.note)),
          const SizedBox(height: 8),
          Text('Ci sono: $yes · Non ci sono: $no', key: const ValueKey<String>('evento_conti'),
              style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey<String>('evento_si'),
                label: const Text('Ci sono'),
                selected: mine == RichEvent.yes,
                onSelected: canAnswer ? (_) => unawaited(_answer(context, RichEvent.yes)) : null,
              ),
              ChoiceChip(
                key: const ValueKey<String>('evento_no'),
                label: const Text('Non ci sono'),
                selected: mine == RichEvent.no,
                onSelected: canAnswer ? (_) => unawaited(_answer(context, RichEvent.no)) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nuovo sondaggio: domanda, da 2 a 12 risposte, una o più scelte.
class PollComposerScreen extends StatefulWidget {
  const PollComposerScreen({super.key});

  @override
  State<PollComposerScreen> createState() => _PollComposerScreenState();
}

class _PollComposerScreenState extends State<PollComposerScreen> {
  final TextEditingController _q = TextEditingController();
  final List<TextEditingController> _o = <TextEditingController>[TextEditingController(), TextEditingController()];
  bool _multiple = false;
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    for (final TextEditingController c in _o) {
      c.dispose();
    }
    super.dispose();
  }

  void _done() {
    final List<String> options = <String>[for (final TextEditingController c in _o) if (c.text.trim().isNotEmpty) c.text.trim()];
    if (_q.text.trim().isEmpty) {
      setState(() => _error = 'Scrivi la domanda.');
      return;
    }
    if (options.length < 2) {
      setState(() => _error = 'Servono almeno due risposte.');
      return;
    }
    Navigator.of(context).pop(RichPoll(question: _q.text.trim(), options: options, multiple: _multiple));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuovo sondaggio')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            key: const ValueKey<String>('sondaggio_domanda'),
            controller: _q,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Domanda'),
          ),
          for (int i = 0; i < _o.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey<String>('sondaggio_risposta_$i'),
                controller: _o[i],
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: 'Risposta ${i + 1}',
                  counterText: '',
                  suffixIcon: _o.length > 2
                      ? IconButton(
                          tooltip: 'Togli',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() => _o.removeAt(i).dispose()),
                        )
                      : null,
                ),
              ),
            ),
          if (_o.length < RichPoll.maxOptions)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey<String>('sondaggio_aggiungi'),
                onPressed: () => setState(() => _o.add(TextEditingController())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Aggiungi una risposta'),
              ),
            ),
          SwitchListTile(
            key: const ValueKey<String>('sondaggio_multiple'),
            contentPadding: EdgeInsets.zero,
            value: _multiple,
            onChanged: (bool v) => setState(() => _multiple = v),
            title: const Text('Consenti più risposte'),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey<String>('sondaggio_invia'),
            onPressed: _done,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Invia sondaggio'),
          ),
        ],
      ),
    );
  }
}

/// Nuovo evento: titolo, giorno e ora, luogo (con i suggerimenti), nota.
class EventComposerScreen extends StatefulWidget {
  const EventComposerScreen({super.key, this.now = DateTime.now, this.lookup});

  final DateTime Function() now;
  final PlaceLookup? lookup;

  @override
  State<EventComposerScreen> createState() => _EventComposerScreenState();
}

class _EventComposerScreenState extends State<EventComposerScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _place = TextEditingController();
  final TextEditingController _note = TextEditingController();
  PlaceSuggestion? _spot;
  late DateTime _when;
  String? _error;

  @override
  void initState() {
    super.initState();
    final DateTime n = widget.now();
    _when = DateTime(n.year, n.month, n.day, n.hour + 2);
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime n = widget.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(n.year, n.month, n.day),
      lastDate: n.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final TimeOfDay? t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (t != null) setState(() => _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
  }

  void _done() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Scrivi il nome dell\'evento.');
      return;
    }
    Navigator.of(context).pop(RichEvent(
      title: _title.text.trim(),
      at: _when,
      place: _place.text.trim(),
      note: _note.text.trim(),
      lat: _spot?.lat,
      lng: _spot?.lng,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuovo evento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            key: const ValueKey<String>('evento_titolo'),
            controller: _title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Nome dell\'evento', hintText: 'Per esempio «Pizza da Mario»'),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('evento_giorno'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('${_when.day}/${_when.month}/${_when.year}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('evento_ora'),
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(_hm(_when)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PlaceField(
            fieldKey: const ValueKey<String>('evento_dove'),
            controller: _place,
            lookup: widget.lookup,
            label: 'Dove (facoltativo)',
            onSelected: (PlaceSuggestion? s) => _spot = s,
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey<String>('evento_nota'),
            controller: _note,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Descrizione (facoltativa)'),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey<String>('evento_invia'),
            onPressed: _done,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Invia evento'),
          ),
        ],
      ),
    );
  }
}

/// Cosa si è scelto nella schermata «Posizione».
class LocationChoice {
  const LocationChoice({required this.location, this.live});

  final RichLocation location;

  /// Se è «in tempo reale»: per quanto (la condivisione parte con il GPS in tempo reale).
  final LiveDuration? live;
}

/// «Posizione»: quella attuale, in tempo reale, oppure un posto cercato.
class LocationShareScreen extends StatefulWidget {
  const LocationShareScreen({super.key, required this.currentFix, this.liveAvailable = true, this.lookup});

  /// La posizione del telefono adesso (lancia [ChatFailure] con il motivo se non si può).
  final Future<(double, double)?> Function() currentFix;
  final bool liveAvailable;
  final PlaceLookup? lookup;

  @override
  State<LocationShareScreen> createState() => _LocationShareScreenState();
}

class _LocationShareScreenState extends State<LocationShareScreen> {
  final TextEditingController _place = TextEditingController();
  bool _busy = false;
  String? _error;
  LiveDuration _duration = LiveDuration.hour;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  Future<void> _current({required bool live}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (double, double)? fix = await widget.currentFix();
      if (!mounted) return;
      if (fix == null) {
        setState(() => _error = 'Posizione non trovata. Riprova all\'aperto.');
        return;
      }
      Navigator.of(context).pop(LocationChoice(
        location: RichLocation(
          lat: fix.$1,
          lng: fix.$2,
          name: live ? '' : 'Posizione attuale',
          liveUntil: live ? DateTime.now().add(Duration(minutes: _duration.minutes)) : null,
        ),
        live: live ? _duration : null,
      ));
    } on ChatFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Posizione non disponibile.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Invia posizione')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SoftCard(
            child: ListTile(
              key: const ValueKey<String>('posizione_attuale'),
              contentPadding: EdgeInsets.zero,
              leading: const IconTile(Icons.my_location_rounded, color: Color(0xFFE53935)),
              title: const Text('Posizione attuale'),
              subtitle: const Text('Dove sei adesso, una volta sola'),
              onTap: _busy ? null : () => _current(live: false),
            ),
          ),
          if (widget.liveAvailable)
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    key: const ValueKey<String>('posizione_tempo_reale'),
                    contentPadding: EdgeInsets.zero,
                    leading: const IconTile(Icons.share_location_rounded, color: PiazlyColors.green),
                    title: const Text('Posizione in tempo reale'),
                    subtitle: Text('Ti segue sulla Mappa per ${_duration.label}. La spegni quando vuoi.'),
                    onTap: _busy ? null : () => _current(live: true),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final LiveDuration d in LiveDuration.values)
                        ChoiceChip(
                          key: ValueKey<String>('durata_${d.name}'),
                          label: Text(d.label),
                          selected: _duration == d,
                          onSelected: (_) => setState(() => _duration = d),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(_error!, key: const ValueKey<String>('posizione_errore'),
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text('Oppure cerca un posto', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PlaceField(
              fieldKey: const ValueKey<String>('posizione_cerca'),
              controller: _place,
              lookup: widget.lookup,
              label: 'Paese, locale o indirizzo',
              onSelected: (PlaceSuggestion? s) {
                if (s == null) return;
                Navigator.of(context).pop(LocationChoice(
                  location: RichLocation(
                    lat: s.lat,
                    lng: s.lng,
                    name: s.title,
                    address: s.subtitle,
                  ),
                ));
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Scelta di un contatto della rubrica da inviare (nome e numeri restano cifrati).
class ContactPickScreen extends StatefulWidget {
  const ContactPickScreen({super.key, required this.load});

  /// null se manca il permesso della rubrica.
  final Future<List<(String, List<String>)>?> Function() load;

  @override
  State<ContactPickScreen> createState() => _ContactPickScreenState();
}

class _ContactPickScreenState extends State<ContactPickScreen> {
  List<(String, List<String>)>? _all;
  bool _denied = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    widget.load().then((List<(String, List<String>)>? list) {
      if (!mounted) return;
      setState(() {
        _denied = list == null;
        _all = (list ?? <(String, List<String>)>[])
            .where(((String, List<String>) e) => e.$2.isNotEmpty)
            .toList()
          ..sort(((String, List<String>) a, (String, List<String>) b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _all = <(String, List<String>)>[]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<(String, List<String>)>? all = _all;
    final String q = _q.trim().toLowerCase();
    final List<(String, List<String>)> shown = all == null
        ? const <(String, List<String>)>[]
        : <(String, List<String>)>[for (final (String, List<String>) e in all) if (q.isEmpty || e.$1.toLowerCase().contains(q)) e];
    return Scaffold(
      appBar: AppBar(title: const Text('Invia contatto')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const ValueKey<String>('contatto_cerca'),
              onChanged: (String v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Cerca nella rubrica', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: all == null
                ? const Center(child: CircularProgressIndicator())
                : _denied
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Per inviare un contatto serve il permesso della rubrica.'),
                  )
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (BuildContext context, int i) => ListTile(
                      key: ValueKey<String>('contatto_$i'),
                      leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                      title: Text(shown[i].$1),
                      subtitle: Text(shown[i].$2.first),
                      onTap: () => Navigator.of(context).pop(
                        RichContact(name: shown[i].$1, phones: shown[i].$2.take(5).toList()),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

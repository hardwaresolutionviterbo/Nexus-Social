import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../core/theme/app_theme.dart';

/// Preferenze delle notifiche (Fase 4, Blocco 5). Le applica il server prima di inviare.
class PushSettings {
  const PushSettings({
    this.messages = true,
    this.comments = true,
    this.market = true,
    this.preview = true,
    this.dndEnabled = false,
    this.dndFrom = const TimeOfDay(hour: 22, minute: 0),
    this.dndTo = const TimeOfDay(hour: 7, minute: 0),
    this.timeZone = 'Europe/Rome',
  });

  final bool messages;
  final bool comments;
  final bool market;

  /// Nella notifica il nome di chi scrive (o del gruppo); spento: solo «Hai un nuovo messaggio».
  final bool preview;
  final bool dndEnabled;
  final TimeOfDay dndFrom;
  final TimeOfDay dndTo;
  final String timeZone;

  PushSettings copyWith({
    bool? messages,
    bool? comments,
    bool? market,
    bool? preview,
    bool? dndEnabled,
    TimeOfDay? dndFrom,
    TimeOfDay? dndTo,
  }) => PushSettings(
    messages: messages ?? this.messages,
    comments: comments ?? this.comments,
    market: market ?? this.market,
    preview: preview ?? this.preview,
    dndEnabled: dndEnabled ?? this.dndEnabled,
    dndFrom: dndFrom ?? this.dndFrom,
    dndTo: dndTo ?? this.dndTo,
    timeZone: timeZone,
  );

  static TimeOfDay _time(Object? v, TimeOfDay fallback) {
    final List<String> p = '$v'.split(':');
    if (p.length < 2) return fallback;
    final int? h = int.tryParse(p[0]);
    final int? m = int.tryParse(p[1]);
    return h == null || m == null ? fallback : TimeOfDay(hour: h, minute: m);
  }

  static String hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  factory PushSettings.fromRow(Map<String, dynamic> r) => PushSettings(
    messages: r['messages'] != false,
    comments: r['comments'] != false,
    market: r['market'] != false,
    preview: r['preview'] != false,
    dndEnabled: r['dnd_enabled'] == true,
    dndFrom: _time(r['dnd_from'], const TimeOfDay(hour: 22, minute: 0)),
    dndTo: _time(r['dnd_to'], const TimeOfDay(hour: 7, minute: 0)),
    timeZone: (r['time_zone'] as String?) ?? 'Europe/Rome',
  );
}

abstract class PushSettingsRepository {
  Future<PushSettings> load();

  Future<void> save(PushSettings settings);
}

class SupabasePushSettingsRepository implements PushSettingsRepository {
  SupabasePushSettingsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PushSettings> load() async {
    final Object? r = await _client.rpc('push_get_settings');
    final Object? row = r is List && r.isNotEmpty ? r.first : r;
    return row is Map ? PushSettings.fromRow(Map<String, dynamic>.from(row)) : const PushSettings();
  }

  @override
  Future<void> save(PushSettings s) async {
    await _client.rpc('push_set_settings', params: <String, Object?>{
      'p_messages': s.messages,
      'p_comments': s.comments,
      'p_market': s.market,
      'p_preview': s.preview,
      'p_dnd_enabled': s.dndEnabled,
      'p_dnd_from': PushSettings.hhmm(s.dndFrom),
      'p_dnd_to': PushSettings.hhmm(s.dndTo),
      'p_time_zone': s.timeZone,
    });
  }
}

/// Profilo → Notifiche.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.repository});

  final PushSettingsRepository repository;

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  PushSettings? _s;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final PushSettings s = await widget.repository.load();
      if (mounted) setState(() => _s = s);
    } catch (_) {
      if (mounted) setState(() => _error = 'Preferenze non caricate. Controlla la connessione.');
    }
  }

  Future<void> _update(PushSettings next) async {
    final PushSettings? before = _s;
    setState(() {
      _s = next;
      _saving = true;
    });
    try {
      await widget.repository.save(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _s = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Non salvato. Riprova.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pick(bool from) async {
    final PushSettings s = _s!;
    final TimeOfDay? t = await showTimePicker(context: context, initialTime: from ? s.dndFrom : s.dndTo);
    if (t == null) return;
    await _update(from ? s.copyWith(dndFrom: t) : s.copyWith(dndTo: t));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PushSettings? s = _s;
    Widget body;
    if (_error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    } else if (s == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Le notifiche non contengono mai il testo dei messaggi: sono cifrati e solo il '
              'tuo telefono li legge. Per i Mi piace non arrivano notifiche.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          SwitchListTile(
            key: const ValueKey<String>('notifiche_messaggi'),
            value: s.messages,
            onChanged: _saving ? null : (bool v) => _update(s.copyWith(messages: v)),
            secondary: const Icon(Icons.forum_outlined),
            title: const Text('Messaggi delle chat'),
            subtitle: const Text('Chat a due, gruppi e richieste di messaggio'),
          ),
          SwitchListTile(
            key: const ValueKey<String>('notifiche_anteprima'),
            value: s.preview,
            onChanged: _saving || !s.messages ? null : (bool v) => _update(s.copyWith(preview: v)),
            secondary: const Icon(Icons.visibility_outlined),
            title: const Text('Mostra chi scrive'),
            subtitle: Text(s.preview ? '«Anna R. · Nuovo messaggio»' : '«Piazly · Hai un nuovo messaggio»'),
          ),
          SwitchListTile(
            key: const ValueKey<String>('notifiche_commenti'),
            value: s.comments,
            onChanged: _saving ? null : (bool v) => _update(s.copyWith(comments: v)),
            secondary: const Icon(Icons.mode_comment_outlined),
            title: const Text('Commenti'),
            subtitle: const Text('Ai tuoi annunci, risposte e annunci che segui'),
          ),
          SwitchListTile(
            key: const ValueKey<String>('notifiche_scambi'),
            value: s.market,
            onChanged: _saving ? null : (bool v) => _update(s.copyWith(market: v)),
            secondary: const Icon(Icons.swap_horiz_rounded),
            title: const Text('Scambi e vendite'),
            subtitle: const Text('Proposte, conferme e feedback'),
          ),
          const Divider(height: 28),
          SwitchListTile(
            key: const ValueKey<String>('notifiche_non_disturbare'),
            value: s.dndEnabled,
            onChanged: _saving ? null : (bool v) => _update(s.copyWith(dndEnabled: v)),
            secondary: const Icon(Icons.do_not_disturb_on_outlined),
            title: const Text('Non disturbare'),
            subtitle: Text('Nessuna notifica dalle ${PushSettings.hhmm(s.dndFrom)} alle ${PushSettings.hhmm(s.dndTo)}'),
          ),
          if (s.dndEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey<String>('non_disturbare_dalle'),
                      onPressed: _saving ? null : () => _pick(true),
                      icon: const Icon(Icons.bedtime_outlined),
                      label: Text('Dalle ${PushSettings.hhmm(s.dndFrom)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey<String>('non_disturbare_alle'),
                      onPressed: _saving ? null : () => _pick(false),
                      icon: const Icon(Icons.wb_sunny_outlined),
                      label: Text('Alle ${PushSettings.hhmm(s.dndTo)}'),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.notifications_off_outlined, size: 18, color: AppColors.brandBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Per silenziare una sola chat: aprila e tocca la campanella in alto.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Notifiche')), body: body);
  }
}

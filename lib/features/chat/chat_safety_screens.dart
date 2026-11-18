import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'chat_models.dart';
import 'chat_screen.dart' show chatPreview, chatTimeLabel;
import 'chat_service.dart';

/// «Segnala»: motivo, messaggi da allegare (li sceglie chi segnala), descrizione, blocco.
class ReportChatScreen extends StatefulWidget {
  const ReportChatScreen({super.key, required this.chat, required this.conversationId, this.now = DateTime.now});

  final ChatService chat;
  final String conversationId;
  final DateTime Function() now;

  static Future<bool?> open(BuildContext context, ChatService chat, String conversationId) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => ReportChatScreen(chat: chat, conversationId: conversationId)),
      );

  @override
  State<ReportChatScreen> createState() => _ReportChatScreenState();
}

class _ReportChatScreenState extends State<ReportChatScreen> {
  String? _reason;
  final Set<String> _chosen = <String>{};
  final TextEditingController _details = TextEditingController();
  bool _block = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  /// Ultimi 50 messaggi con un testo (o un allegato), dal più recente.
  List<ChatMessage> get _candidates => widget.chat
      .messages(widget.conversationId)
      .where((ChatMessage m) => !m.deleted && (m.isText || m.hasMedia))
      .toList()
      .reversed
      .take(50)
      .toList();

  Future<void> _send() async {
    final String? reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Scegli un motivo.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final List<ChatMessage> chosen = <ChatMessage>[
      for (final ChatMessage m in _candidates.reversed)
        if (_chosen.contains(m.localId)) m,
    ];
    try {
      await widget.chat.report(
        widget.conversationId,
        reason: reason,
        details: _details.text,
        messages: chosen,
        block: _block,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_block ? 'Segnalazione inviata e persona bloccata' : 'Segnalazione inviata')),
      );
      Navigator.of(context).pop(true);
    } on ChatFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Segnalazione non inviata. Controlla la connessione e riprova.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChatConversation? c = widget.chat.conversation(widget.conversationId);
    final bool group = c?.isGroup ?? false;
    final List<ChatMessage> list = _candidates;
    final DateTime now = widget.now();
    return Scaffold(
      appBar: AppBar(title: Text(group ? 'Segnala il gruppo' : 'Segnala ${c?.displayName ?? ''}')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Gli amministratori di Piazly vedranno solo i messaggi che selezioni qui sotto, '
              'nient\'altro della chat. Chi segnali non lo saprà.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Motivo', style: theme.textTheme.titleMedium),
          ),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (String? v) => setState(() => _reason = v),
            child: Column(
              children: [
                for (final MapEntry<String, String> r in ChatService.reportReasons.entries)
                  RadioListTile<String>(
                    key: ValueKey<String>('motivo_${r.key}'),
                    value: r.key,
                    title: Text(r.value),
                    dense: true,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              list.isEmpty ? 'Nessun messaggio da allegare' : 'Messaggi da allegare (${_chosen.length})',
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final ChatMessage m in list)
            CheckboxListTile(
              key: ValueKey<String>('allega_${m.localId}'),
              value: _chosen.contains(m.localId),
              onChanged: (bool? v) => setState(() => v == true ? _chosen.add(m.localId) : _chosen.remove(m.localId)),
              dense: true,
              title: Text(chatPreview(m), maxLines: 3, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${m.mine ? 'Tu' : (group ? widget.chat.memberName(widget.conversationId, m.senderId) : (c?.displayName ?? ''))}'
                ' · ${chatTimeLabel(m.at, now)}',
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              key: const ValueKey<String>('segnala_dettagli'),
              controller: _details,
              maxLength: 1000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Vuoi aggiungere qualcosa? (facoltativo)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (!group)
            CheckboxListTile(
              key: const ValueKey<String>('segnala_blocca'),
              value: _block,
              onChanged: (bool? v) => setState(() => _block = v == true),
              title: const Text('Blocca anche questa persona'),
              subtitle: const Text('Non potrà più scriverti né vedere i tuoi annunci'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey<String>('segnala_invia'),
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.flag_outlined),
              label: Text(_sending ? 'Invio…' : 'Invia la segnalazione'),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Condividi l'incontro»: luogo e orario a una persona fidata prima di vedersi.
class ShareMeetingScreen extends StatefulWidget {
  const ShareMeetingScreen({
    super.key,
    required this.chat,
    required this.withName,
    this.excludeId,
    this.now = DateTime.now,
  });

  final ChatService chat;

  /// Chi si incontra («Dario V. (@dario88)»).
  final String withName;

  /// La persona che si incontra non compare tra le persone fidate.
  final String? excludeId;
  final DateTime Function() now;

  static Future<void> open(BuildContext context, ChatService chat, {required String withName, String? excludeId}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ShareMeetingScreen(chat: chat, withName: withName, excludeId: excludeId),
        ),
      );

  @override
  State<ShareMeetingScreen> createState() => _ShareMeetingScreenState();
}

class _ShareMeetingScreenState extends State<ShareMeetingScreen> {
  List<ChatContact>? _contacts;
  ChatContact? _trusted;
  final TextEditingController _place = TextEditingController();
  final TextEditingController _note = TextEditingController();
  late DateTime _when;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final DateTime n = widget.now();
    _when = DateTime(n.year, n.month, n.day, n.hour + 1);
    _load();
  }

  Future<void> _load() async {
    final List<ChatContact> list = await widget.chat.contacts();
    if (!mounted) return;
    setState(() => _contacts = list.where((ChatContact c) => c.id != widget.excludeId).toList());
  }

  @override
  void dispose() {
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
      lastDate: n.add(const Duration(days: 60)),
    );
    if (d != null) setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final TimeOfDay? t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (t != null) setState(() => _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
  }

  Future<void> _send() async {
    final ChatContact? to = _trusted;
    if (to == null) {
      setState(() => _error = 'Scegli a chi mandarlo.');
      return;
    }
    if (_place.text.trim().isEmpty) {
      setState(() => _error = 'Scrivi dove vi incontrate.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.chat.shareMeeting(
        trustedId: to.id,
        withName: widget.withName,
        place: _place.text,
        when: _when,
        note: _note.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Incontro condiviso con ${to.name}')));
      Navigator.of(context).pop();
    } on ChatFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Non inviato. Controlla la connessione e riprova.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ChatContact>? contacts = _contacts;
    final String date = '${_when.day}/${_when.month}';
    final String time = '${_when.hour.toString().padLeft(2, '0')}:${_when.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Condividi l\'incontro')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.brandBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Prima di vederti con ${widget.withName}, manda luogo e orario a una persona di cui ti '
                    'fidi. Il messaggio è cifrato come tutte le chat: lo legge solo lei.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              key: const ValueKey<String>('incontro_luogo'),
              controller: _place,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Dove (per esempio «Bar Centrale, piazza Roma»)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('incontro_giorno'),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(date),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('incontro_ora'),
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(time),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              key: const ValueKey<String>('incontro_nota'),
              controller: _note,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Nota (facoltativa)', border: OutlineInputBorder()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('A chi lo mandi', style: theme.textTheme.titleMedium),
          ),
          if (contacts == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessun contatto della rubrica è su Piazly.'),
            )
          else
            RadioGroup<String>(
              groupValue: _trusted?.id,
              onChanged: (String? id) => setState(() => _trusted = contacts.firstWhere((ChatContact c) => c.id == id)),
              child: Column(
                children: [
                  for (final ChatContact c in contacts)
                    RadioListTile<String>(
                      key: ValueKey<String>('fidato_${c.id}'),
                      value: c.id,
                      title: Text(c.name),
                      subtitle: Text('@${c.username}'),
                    ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey<String>('incontro_invia'),
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Invio…' : 'Manda'),
            ),
          ),
        ],
      ),
    );
  }
}

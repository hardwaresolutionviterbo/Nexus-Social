import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/piazly_ui.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'admin_users.dart';

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

IconData _kindIcon(ReportKind k) => switch (k) {
  ReportKind.listing => Icons.campaign_outlined,
  ReportKind.comment => Icons.mode_comment_outlined,
  ReportKind.chat => Icons.chat_bubble_outline_rounded,
};

/// Coda delle segnalazioni: da gestire e gestite negli ultimi 30 giorni.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.repository});

  final AdminRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Segnalazioni'),
          bottom: const TabBar(
            tabs: [
              Tab(key: ValueKey<String>('segnalazioni_aperte'), text: 'Da gestire'),
              Tab(key: ValueKey<String>('segnalazioni_chiuse'), text: 'Gestite'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReportList(repository: repository, closed: false),
            _ReportList(repository: repository, closed: true),
          ],
        ),
      ),
    );
  }
}

class _ReportList extends StatefulWidget {
  const _ReportList({required this.repository, required this.closed});

  final AdminRepository repository;
  final bool closed;

  @override
  State<_ReportList> createState() => _ReportListState();
}

class _ReportListState extends State<_ReportList> {
  List<AdminReport>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<AdminReport> items = await widget.repository.reports(closed: widget.closed);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on AdminFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _open(AdminReport r) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReportDetailScreen(repository: widget.repository, report: r, readOnly: widget.closed),
      ),
    );
    if (changed ?? false) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<AdminReport>? items = _items;
    if (items == null) {
      return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          widget.closed ? 'Nessuna segnalazione gestita negli ultimi 30 giorni.' : 'Nessuna segnalazione da gestire.',
          key: const ValueKey<String>('segnalazioni_vuote'),
        ),
      );
    }
    final ThemeData theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          for (final AdminReport r in items)
            SoftCard(
              key: ValueKey<String>('segnalazione_${r.id}'),
              onTap: () => _open(r),
              child: Row(
                children: [
                  IconTile(_kindIcon(r.kind), color: AppColors.brandCoral),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.headline, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                        Text(
                          '${r.kind.label} · ${r.reasons.map(reasonLabel).join(', ')}'
                          '${r.count > 1 ? ' · ${r.count} segnalazioni' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          '${r.author != null ? '@${r.author!.username} · ' : ''}${adminDateTime(r.lastAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Dettaglio: contenuto, motivi, autore e azioni (ignora, elimina, avvisa, banna).
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.repository, required this.report, this.readOnly = false});

  final AdminRepository repository;
  final AdminReport report;
  final bool readOnly;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  bool _busy = false;

  AdminReport get r => widget.report;

  Future<void> _act(ReportAction action) async {
    String? message;
    BanLength? ban;
    bool remove = false;
    if (action == ReportAction.warn || action == ReportAction.ban) {
      final ModerationChoice? c = await showDialog<ModerationChoice>(
        context: context,
        builder: (_) => ModerationDialog(
          ban: action == ReportAction.ban,
          canRemove: r.kind != ReportKind.chat && !r.gone && !r.removed,
        ),
      );
      if (c == null) return;
      (message, ban, remove) = (c.message, c.length, c.removeContent);
    } else {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(action == ReportAction.ignore ? 'Ignorare la segnalazione?' : 'Eliminare il contenuto?'),
          content: Text(
            action == ReportAction.ignore
                ? 'Il contenuto resta visibile e la segnalazione esce dalla coda.'
                : 'Il contenuto non sarà più visibile. La persona riceve un avviso.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
            FilledButton(
              key: const ValueKey<String>('segnalazione_conferma'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(action.label),
            ),
          ],
        ),
      );
      if (!(ok ?? false)) return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.resolve(r, action, message: message, ban: ban, removeContent: remove);
      if (!mounted) return;
      _toast(context, switch (action) {
        ReportAction.ignore => 'Segnalazione ignorata.',
        ReportAction.remove => 'Contenuto tolto.',
        ReportAction.warn => 'Avviso inviato.',
        ReportAction.ban => 'Utente bannato.',
      });
      Navigator.of(context).pop(true);
    } on AdminFailure catch (f) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(context, f.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdminPerson? author = r.author;
    return Scaffold(
      appBar: AppBar(title: Text('${r.kind.label} segnalato')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.kind == ReportKind.comment && r.contextTitle != null)
                  Text('Sotto l\'annuncio «${r.contextTitle}»', style: theme.textTheme.bodySmall),
                Text(r.headline, key: const ValueKey<String>('segnalazione_titolo'), style: theme.textTheme.titleMedium),
                if (r.kind == ReportKind.listing && (r.text ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(r.text!),
                ],
                if (r.removed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Già tolto', style: TextStyle(color: theme.colorScheme.error)),
                  ),
                if (r.kind == ReportKind.chat) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Solo i messaggi scelti da chi ha segnalato. Il resto della chat è cifrato e non si vede.',
                    style: theme.textTheme.bodySmall,
                  ),
                  for (final ReportedMessage m in r.messages)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${m.fromReporter ? 'Chi segnala' : 'Altra persona'}'
                        '${m.at != null ? ' · ${adminDateTime(m.at!)}' : ''}: ${m.text}',
                      ),
                    ),
                ],
              ],
            ),
          ),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.count > 1 ? '${r.count} segnalazioni' : '1 segnalazione',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final String reason in r.reasons) Chip(label: Text(reasonLabel(reason)))],
                ),
                for (final String d in r.details)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('«$d»')),
                const SizedBox(height: 6),
                Text('Ultima: ${adminDateTime(r.lastAt)}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (author != null)
            SoftCard(
              key: const ValueKey<String>('segnalazione_autore'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => UserDetailScreen(repository: widget.repository, userId: author.id)),
              ),
              child: Row(
                children: [
                  const IconTile(Icons.person_outline_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(author.name, style: theme.textTheme.titleSmall),
                        Text(
                          '@${author.username}'
                          '${author.bannedAt(DateTime.now()) ? ' · bannato ${banLabel(author.bannedUntil!)}' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const ValueKey<String>('segnalazione_ignora'),
                    onPressed: _busy ? null : () => _act(ReportAction.ignore),
                    child: const Text('Ignora'),
                  ),
                  if (r.kind != ReportKind.chat && !r.gone && !r.removed)
                    OutlinedButton(
                      key: const ValueKey<String>('segnalazione_elimina'),
                      onPressed: _busy ? null : () => _act(ReportAction.remove),
                      child: const Text('Elimina'),
                    ),
                  if (author != null) ...[
                    FilledButton.tonal(
                      key: const ValueKey<String>('segnalazione_avvisa'),
                      onPressed: _busy ? null : () => _act(ReportAction.warn),
                      child: const Text('Avvisa'),
                    ),
                    FilledButton(
                      key: const ValueKey<String>('segnalazione_banna'),
                      style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                      onPressed: _busy ? null : () => _act(ReportAction.ban),
                      child: const Text('Banna'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Scelta per avviso o ban: testo per la persona, durata e se togliere il contenuto.
class ModerationChoice {
  const ModerationChoice({required this.message, this.length, this.removeContent = false});

  final String message;
  final BanLength? length;
  final bool removeContent;
}

class ModerationDialog extends StatefulWidget {
  const ModerationDialog({super.key, required this.ban, this.canRemove = false});

  final bool ban;
  final bool canRemove;

  @override
  State<ModerationDialog> createState() => _ModerationDialogState();
}

class _ModerationDialogState extends State<ModerationDialog> {
  final TextEditingController _text = TextEditingController();
  BanLength _length = BanLength.week;
  bool _remove = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool ok = _text.text.trim().length >= 3;
    return AlertDialog(
      title: Text(widget.ban ? 'Banna l\'utente' : 'Invia un avviso'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (String label, String text) in moderationTemplates)
                  ActionChip(
                    key: ValueKey<String>('modello_$label'),
                    label: Text(label),
                    onPressed: () => _text.text = text,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey<String>('moderazione_testo'),
              controller: _text,
              maxLength: 500,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                labelText: widget.ban ? 'Motivo (lo legge la persona)' : 'Testo dell\'avviso',
              ),
            ),
            if (widget.ban) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final BanLength l in BanLength.values)
                    ChoiceChip(
                      key: ValueKey<String>('durata_${l.days ?? 'definitivo'}'),
                      label: Text(l.label),
                      selected: _length == l,
                      onSelected: (_) => setState(() => _length = l),
                    ),
                ],
              ),
            ],
            if (widget.canRemove)
              CheckboxListTile(
                key: const ValueKey<String>('moderazione_togli'),
                contentPadding: EdgeInsets.zero,
                value: _remove,
                onChanged: (bool? v) => setState(() => _remove = v ?? false),
                title: const Text('Togli anche il contenuto'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),
        FilledButton(
          key: const ValueKey<String>('moderazione_invia'),
          onPressed: ok
              ? () => Navigator.of(context).pop(
                  ModerationChoice(
                    message: _text.text.trim(),
                    length: widget.ban ? _length : null,
                    removeContent: _remove,
                  ),
                )
              : null,
          child: Text(widget.ban ? 'Banna' : 'Invia'),
        ),
      ],
    );
  }
}

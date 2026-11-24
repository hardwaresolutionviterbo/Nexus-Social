import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/widgets/piazly_ui.dart';
import 'admin_models.dart';
import 'admin_reports.dart';
import 'admin_repository.dart';

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Ricerca utenti per nome utente o nome pubblico.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.repository});

  final AdminRepository repository;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final TextEditingController _query = TextEditingController();
  List<AdminPerson>? _items;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    try {
      final List<AdminPerson> items = await widget.repository.searchUsers(_query.text);
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

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => unawaited(_search()));
  }

  Future<void> _open(AdminPerson p) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => UserDetailScreen(repository: widget.repository, userId: p.id)),
    );
    await _search();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AdminPerson>? items = _items;
    final DateTime now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Utenti')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: const ValueKey<String>('utenti_cerca'),
              controller: _query,
              onChanged: _changed,
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Nome utente o nome',
              ),
            ),
          ),
          Expanded(
            child: items == null
                ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
                : items.isEmpty
                ? const Center(child: Text('Nessun utente trovato.'))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final AdminPerson p in items)
                        SoftCard(
                          key: ValueKey<String>('utente_${p.username}'),
                          onTap: () => _open(p),
                          child: Row(
                            children: [
                              IconTile(p.business ? Icons.storefront_outlined : Icons.person_outline_rounded),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: theme.textTheme.titleSmall),
                                    Text('@${p.username}${p.business ? ' · Azienda' : ''}',
                                        style: theme.textTheme.bodySmall),
                                    if (p.bannedAt(now))
                                      Text(
                                        'Bannato ${banLabel(p.bannedUntil!)}',
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
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
          ),
        ],
      ),
    );
  }
}

/// Scheda dell'utente: dati pubblici, conteggi, storico, avviso, ban e sblocco.
class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({super.key, required this.repository, required this.userId});

  final AdminRepository repository;
  final String userId;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  AdminUserDetail? _detail;
  String? _error;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final AdminUserDetail? d = await widget.repository.user(widget.userId);
      if (mounted) {
        setState(() {
          _detail = d;
          _loaded = true;
          _error = null;
        });
      }
    } on AdminFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _run(Future<void> Function() body, String done) async {
    setState(() => _busy = true);
    try {
      await body();
      if (mounted) _toast(context, done);
      await _load();
    } on AdminFailure catch (f) {
      if (mounted) _toast(context, f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _warnOrBan({required bool ban}) async {
    final ModerationChoice? c = await showDialog<ModerationChoice>(
      context: context,
      builder: (_) => ModerationDialog(ban: ban),
    );
    if (c == null) return;
    await _run(
      () => ban
          ? widget.repository.ban(widget.userId, c.length ?? BanLength.week, c.message)
          : widget.repository.warn(widget.userId, c.message),
      ban ? 'Utente bannato.' : 'Avviso inviato.',
    );
  }

  Future<void> _unban() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Sbloccare l\'utente?'),
        content: const Text('Potrà di nuovo pubblicare. Riceve un avviso che l\'account è attivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(
            key: const ValueKey<String>('utente_sblocca_conferma'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sblocca'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    await _run(() => widget.repository.unban(widget.userId), 'Utente sbloccato.');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdminUserDetail? d = _detail;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Utente')),
        body: Center(
          child: _error != null
              ? Text(_error!)
              : _loaded
              ? const Text('Utente non trovato.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final AdminPerson p = d.person;
    final bool banned = p.bannedAt(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text('@${p.username}')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: theme.textTheme.titleMedium),
                Text(
                  '@${p.username} · ${p.business ? 'Azienda' : 'Privato'}'
                  '${d.isAdmin ? ' · Amministratore' : ''}',
                ),
                if (d.createdAt != null)
                  Text('Iscritto dal ${adminDate(d.createdAt!)}', style: theme.textTheme.bodySmall),
                if ((d.bio ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(d.bio!),
                ],
                if (banned) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Bannato ${banLabel(p.bannedUntil!)}',
                    key: const ValueKey<String>('utente_stato_ban'),
                    style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
                  ),
                  if (d.banReason != null) Text('Motivo: ${d.banReason}'),
                ],
              ],
            ),
          ),
          SoftCard(
            child: Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _Stat('Annunci attivi', d.listings),
                _Stat('Commenti', d.comments),
                _Stat('Segnalazioni aperte', d.reportsOpen),
                _Stat('Segnalazioni totali', d.reportsTotal),
              ],
            ),
          ),
          if (!d.isAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    key: const ValueKey<String>('utente_avvisa'),
                    onPressed: _busy ? null : () => _warnOrBan(ban: false),
                    child: const Text('Avvisa'),
                  ),
                  if (banned)
                    FilledButton(
                      key: const ValueKey<String>('utente_sblocca'),
                      onPressed: _busy ? null : _unban,
                      child: const Text('Sblocca'),
                    )
                  else
                    FilledButton(
                      key: const ValueKey<String>('utente_banna'),
                      style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                      onPressed: _busy ? null : () => _warnOrBan(ban: true),
                      child: const Text('Banna'),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Text('Storico', style: theme.textTheme.titleSmall),
          ),
          if (d.history.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nessuna azione finora.')),
          for (final HistoryEntry h in d.history)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history_rounded),
              title: Text(h.label),
              subtitle: Text(
                <String>[
                  if (h.at != null) adminDateTime(h.at!),
                  if (h.by != null) 'da @${h.by}',
                  if ((h.reason ?? '').isNotEmpty) h.reason!,
                ].join(' · '),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value', style: theme.textTheme.titleLarge),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

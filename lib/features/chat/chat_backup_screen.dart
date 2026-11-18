import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'chat_backup.dart';
import 'chat_backup_service.dart';
import 'chat_media.dart' show formatBytes;
import 'chat_models.dart' show ChatFailure;

/// Data del backup come «18/11 alle 19:30» (con l'anno se non è quest'anno).
String backupDateLabel(DateTime at, DateTime now) {
  final DateTime l = at.toLocal();
  final String hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  final bool today = l.year == now.year && l.month == now.month && l.day == now.day;
  if (today) return 'oggi alle $hm';
  final String day = l.year == now.year ? '${l.day}/${l.month}' : '${l.day}/${l.month}/${l.year}';
  return '$day alle $hm';
}

/// Card nella lista delle chat: «Recupera le tue chat» sul telefono nuovo, oppure l'invito ad
/// attivare il backup.
class ChatBackupCard extends StatelessWidget {
  const ChatBackupCard({super.key, required this.backup, required this.hasChats, this.now = DateTime.now});

  final ChatBackup backup;
  final bool hasChats;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: backup,
    builder: (BuildContext context, _) {
      final ThemeData theme = Theme.of(context);
      final BackupInfo? info = backup.info;
      if (backup.offersRestore && info != null) {
        return Card(
          key: const ValueKey<String>('backup_offerta_ripristino'),
          margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.restore_rounded, color: AppColors.brandOrange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Recupera le tue chat',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'C\'è un backup del ${backupDateLabel(info.at, now())}. Inserisci la password '
                  'del backup per rimettere i messaggi su questo telefono.',
                  style: theme.textTheme.bodySmall,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const ValueKey<String>('backup_non_ora'),
                      onPressed: backup.skipRestore,
                      child: const Text('Non ora'),
                    ),
                    FilledButton(
                      key: const ValueKey<String>('backup_apri_ripristino'),
                      onPressed: () => ChatBackupScreen.open(context, backup),
                      child: const Text('Ripristina'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      if (backup.loaded && !backup.enabled && info == null && hasChats) {
        return ListTile(
          key: const ValueKey<String>('backup_invito'),
          leading: const Icon(Icons.cloud_upload_outlined, color: AppColors.brandBlue),
          title: const Text('Attiva il backup delle chat'),
          subtitle: const Text('Se cambi telefono ritrovi i messaggi'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => ChatBackupScreen.open(context, backup),
        );
      }
      return const SizedBox.shrink();
    },
  );
}

/// Backup delle chat: attiva, aggiorna, ripristina, disattiva.
class ChatBackupScreen extends StatefulWidget {
  const ChatBackupScreen({super.key, required this.backup, this.now = DateTime.now});

  final ChatBackup backup;
  final DateTime Function() now;

  static Future<void> open(BuildContext context, ChatBackup backup) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => ChatBackupScreen(backup: backup)),
  );

  @override
  State<ChatBackupScreen> createState() => _ChatBackupScreenState();
}

class _ChatBackupScreenState extends State<ChatBackupScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  bool _hide = true;

  /// Con un backup sul server e senza chiave: si sceglie tra ripristinare e ricominciare.
  bool _newInstead = false;
  String? _problem;

  ChatBackup get _b => widget.backup;

  @override
  void initState() {
    super.initState();
    if (!_b.loaded) _b.load(auto: false);
  }

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _enable() async {
    final String p = _password.text;
    final String? weak = backupPasswordProblem(p);
    if (weak != null || p != _repeat.text) {
      setState(() => _problem = weak ?? 'Le due password non sono uguali.');
      return;
    }
    if (_b.info != null) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Sostituire il backup?'),
          content: const Text('Il backup che c\'è ora verrà sostituito da quello di questo telefono.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
            FilledButton(
              key: const ValueKey<String>('backup_sostituisci'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sostituisci'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _problem = null);
    try {
      await _b.enable(p);
      _password.clear();
      _repeat.clear();
      if (mounted) _toast('Backup fatto');
    } on ChatFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _restore() async {
    setState(() => _problem = null);
    try {
      final int n = await _b.restore(_password.text);
      _password.clear();
      if (!mounted) return;
      _toast(n == 1 ? '1 messaggio recuperato' : '$n messaggi recuperati');
      Navigator.of(context).pop();
    } on ChatFailure catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _now() async {
    try {
      await _b.backupNow();
      if (mounted) _toast('Backup fatto');
    } on ChatFailure catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _disable() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Disattivare il backup?'),
        content: const Text(
          'Il backup viene cancellato dal server. Se cambi telefono non potrai recuperare i messaggi.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(
            key: const ValueKey<String>('backup_conferma_disattiva'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disattiva'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _b.disable();
      if (mounted) _toast('Backup disattivato e cancellato');
    } on ChatFailure catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Widget _field(TextEditingController c, String label, String key) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
    child: TextField(
      key: ValueKey<String>(key),
      controller: c,
      obscureText: _hide,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _hide ? 'Mostra' : 'Nascondi',
          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hide = !_hide),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _b,
    builder: (BuildContext context, _) {
      final ThemeData theme = Theme.of(context);
      final BackupInfo? info = _b.info;
      final bool busy = _b.busy;
      final bool restoring = !_b.enabled && info != null && !_newInstead;
      final List<Widget> children = <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Le chat vengono cifrate su questo telefono con una password che scegli tu. Piazly non '
            'la conosce: se la dimentichi, il backup non si può aprire. Foto, video, vocali e '
            'documenti non sono inclusi.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        ListTile(
          key: const ValueKey<String>('backup_stato'),
          leading: Icon(
            info == null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
            color: info == null ? theme.colorScheme.onSurfaceVariant : AppColors.brandBlue,
          ),
          title: Text(info == null
              ? 'Nessun backup'
              : 'Ultimo backup: ${backupDateLabel(info.at, widget.now())}'),
          subtitle: Text(info == null
              ? 'Le chat sono solo su questo telefono'
              : '${formatBytes(info.size)} · ${_b.enabled ? 'si aggiorna da solo ogni giorno' : 'fatto da un altro telefono'}'),
        ),
        const Divider(height: 20),
      ];
      if (!_b.loaded) {
        children.add(const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
      } else if (_b.enabled) {
        children.addAll(<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              key: const ValueKey<String>('backup_ora'),
              onPressed: busy ? null : _now,
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(busy ? 'Backup in corso…' : 'Esegui il backup ora'),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              key: const ValueKey<String>('backup_disattiva'),
              onPressed: busy ? null : _disable,
              child: const Text('Disattiva e cancella il backup'),
            ),
          ),
        ]);
      } else if (restoring) {
        children.addAll(<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Recupera le chat', style: theme.textTheme.titleMedium),
          ),
          _field(_password, 'Password del backup', 'backup_password'),
          if (_problem != null) _Problem(_problem!),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey<String>('backup_ripristina'),
              onPressed: busy ? null : _restore,
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.restore_rounded),
              label: Text(busy ? 'Recupero in corso…' : 'Ripristina'),
            ),
          ),
          TextButton(
            key: const ValueKey<String>('backup_nuovo_invece'),
            onPressed: busy ? null : () => setState(() {
              _newInstead = true;
              _problem = null;
            }),
            child: const Text('Ho dimenticato la password: crea un backup nuovo'),
          ),
        ]);
      } else {
        children.addAll(<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Scegli la password del backup', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Almeno 8 caratteri, con lettere e almeno un numero o un simbolo. Scrivila in un posto sicuro.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          _field(_password, 'Password', 'backup_password'),
          _field(_repeat, 'Ripeti la password', 'backup_password_ripeti'),
          if (_problem != null) _Problem(_problem!),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey<String>('backup_attiva'),
              onPressed: busy ? null : _enable,
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_outline_rounded),
              label: Text(busy ? 'Backup in corso…' : 'Attiva il backup'),
            ),
          ),
        ]);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Backup delle chat')),
        body: ListView(padding: const EdgeInsets.only(bottom: 32), children: children),
      );
    },
  );
}

class _Problem extends StatelessWidget {
  const _Problem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
    child: Text(
      text,
      key: const ValueKey<String>('backup_problema'),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

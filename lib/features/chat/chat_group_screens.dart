import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_repository.dart';
import 'chat_media_picker.dart';
import 'chat_models.dart';
import 'chat_service.dart';

/// Foto del gruppo (o icona con le persone se non c'è).
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({super.key, required this.chat, required this.conversation, this.size = 48});

  final ChatService chat;
  final ChatConversation conversation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: <Color>[AppColors.brandBlue, Color(0xFF7C4DFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.groups_rounded, color: Colors.white, size: size * 0.55),
    );
    if (conversation.photoVersion == 0) return fallback;
    return FutureBuilder<Uint8List?>(
      key: ValueKey<String>('foto_${conversation.id}_${conversation.photoVersion}'),
      future: chat.groupPhoto(conversation),
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
        final Uint8List? bytes = snap.data;
        if (bytes == null) return fallback;
        return ClipOval(
          child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
        );
      },
    );
  }
}

/// Elenco di contatti da spuntare (nuovo gruppo, aggiungi membri).
class _ContactPicker extends StatelessWidget {
  const _ContactPicker({
    required this.contacts,
    required this.chosen,
    required this.onToggle,
    required this.profiles,
    this.exclude = const <String>{},
  });

  final List<ChatContact> contacts;
  final Set<String> chosen;
  final ValueChanged<String> onToggle;
  final ProfileRepository? profiles;
  final Set<String> exclude;

  @override
  Widget build(BuildContext context) {
    final List<ChatContact> list = contacts.where((c) => !exclude.contains(c.id)).toList();
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Nessun contatto da aggiungere. Attiva la rubrica in Profilo → Privacy, oppure '
          'condividi il codice d\'invito del gruppo.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      children: [
        for (final ChatContact c in list)
          CheckboxListTile(
            key: ValueKey<String>('scegli_${c.id}'),
            value: chosen.contains(c.id),
            onChanged: (_) => onToggle(c.id),
            secondary: AvatarView(name: c.name, repository: profiles, path: c.avatarPath, size: 42),
            title: Text(c.name.isEmpty ? '@${c.username}' : c.name),
            subtitle: Text('@${c.username}'),
          ),
      ],
    );
  }
}

/// «Nuovo gruppo»: nome e persone dalla rubrica.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key, required this.chat, this.profiles, this.onCreated});

  final ChatService chat;
  final ProfileRepository? profiles;

  /// Apre il gruppo appena creato (la conversazione).
  final void Function(BuildContext context, String conversationId)? onCreated;

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final TextEditingController _title = TextEditingController();
  final Set<String> _chosen = <String>{};
  List<ChatContact>? _contacts;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    widget.chat.contacts().then((List<ChatContact> c) {
      if (mounted) setState(() => _contacts = c);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final String id = await widget.chat.createGroup(_title.text, _chosen.toList());
      if (!mounted) return;
      final void Function(BuildContext, String)? open = widget.onCreated;
      if (open != null) {
        open(context, id);
      } else {
        Navigator.of(context).pop(id);
      }
    } on ChatFailure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool ready = _title.text.trim().isNotEmpty && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Nuovo gruppo')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const ValueKey<String>('gruppo_nome'),
              controller: _title,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome del gruppo',
                prefixIcon: Icon(Icons.groups_rounded),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Chi non ti ha in rubrica riceve un invito e entra solo se accetta. '
              'Il numero di telefono non si vede mai.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _chosen.isEmpty ? 'Scegli le persone' : 'Scelte: ${_chosen.length}',
              style: theme.textTheme.labelLarge,
            ),
          ),
          if (_contacts == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else
            _ContactPicker(
              contacts: _contacts!,
              chosen: _chosen,
              profiles: widget.profiles,
              onToggle: (String id) => setState(() => _chosen.contains(id) ? _chosen.remove(id) : _chosen.add(id)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          key: const ValueKey<String>('gruppo_crea'),
          onPressed: ready ? _create : null,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: const Text('Crea il gruppo'),
        ),
      ),
    );
  }
}

/// «Entra con un codice»: anteprima del gruppo e conferma.
Future<String?> joinGroupWithCode(BuildContext context, ChatService chat) async {
  final TextEditingController code = TextEditingController();
  final String? id = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => _JoinDialog(chat: chat, code: code),
  );
  code.dispose();
  return id;
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog({required this.chat, required this.code});

  final ChatService chat;
  final TextEditingController code;

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  GroupInviteInfo? _info;
  String? _error;
  bool _busy = false;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GroupInviteInfo info = await widget.chat.inviteInfo(widget.code.text);
      if (mounted) setState(() => _info = info);
    } on ChatFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final String id = await widget.chat.joinWithCode(widget.code.text);
      if (mounted) Navigator.of(context).pop(id);
    } on ChatFailure catch (f) {
      if (mounted) {
        setState(() {
          _error = f.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final GroupInviteInfo? info = _info;
    return AlertDialog(
      title: Text(info == null ? 'Entra con un codice' : info.title),
      content: info == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey<String>('codice_invito'),
                  controller: widget.code,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 10,
                  decoration: InputDecoration(labelText: 'Codice del gruppo', errorText: _error),
                ),
              ],
            )
          : Text(
              info.alreadyMember
                  ? 'Fai già parte di questo gruppo.'
                  : '${info.members} ${info.members == 1 ? 'persona' : 'persone'}. Entrando, gli altri '
                        'membri vedranno il tuo nome e la tua foto, mai il numero.'
                        '${_error == null ? '' : '\n\n$_error'}',
            ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),
        if (info == null)
          FilledButton(
            key: const ValueKey<String>('codice_verifica'),
            onPressed: _busy ? null : _check,
            child: const Text('Avanti'),
          )
        else
          FilledButton(
            key: const ValueKey<String>('codice_entra'),
            onPressed: _busy
                ? null
                : (info.alreadyMember ? () => Navigator.of(context).pop(info.conversationId) : _join),
            child: Text(info.alreadyMember ? 'Apri' : 'Entra'),
          ),
      ],
    );
  }
}

/// Info del gruppo: foto, nome, descrizione, membri, amministratori, codice, esci.
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.chat,
    required this.conversationId,
    this.profiles,
    this.device,
  });

  final ChatService chat;
  final String conversationId;
  final ProfileRepository? profiles;
  final ChatDevice? device;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  List<GroupMember>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<GroupMember> list = await widget.chat.groupMembers(widget.conversationId);
      if (mounted) setState(() => _members = list);
    } on ChatFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _guard(Future<void> Function() job, {String? done}) async {
    try {
      await job();
      await _load();
      if (done != null) _toast(done);
    } on ChatFailure catch (f) {
      _toast(f.message);
    }
  }

  Future<void> _edit(ChatConversation c) async {
    final TextEditingController title = TextEditingController(text: c.title);
    final TextEditingController desc = TextEditingController(text: c.description);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Modifica il gruppo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey<String>('modifica_nome'),
              controller: title,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              key: const ValueKey<String>('modifica_descrizione'),
              controller: desc,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Descrizione'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(
            key: const ValueKey<String>('modifica_salva'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await _guard(() => widget.chat.updateGroup(widget.conversationId, title: title.text, description: desc.text));
    }
    title.dispose();
    desc.dispose();
  }

  Future<void> _photo() async {
    final ChatDevice device = widget.device ?? RealChatDevice();
    try {
      final PickedMedia? p = await device.pickImage(camera: false);
      if (p == null) return;
      await _guard(() => widget.chat.setGroupPhoto(widget.conversationId, p.bytes), done: 'Foto aggiornata');
    } on ChatFailure catch (f) {
      _toast(f.message);
    }
  }

  Future<void> _add(List<GroupMember> members) async {
    final List<ChatContact> contacts = await widget.chat.contacts();
    if (!mounted) return;
    final Set<String> already = <String>{for (final GroupMember m in members) m.userId};
    final List<String>? chosen = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => _AddMembersScreen(contacts: contacts, exclude: already, profiles: widget.profiles),
      ),
    );
    if (chosen == null || chosen.isEmpty) return;
    await _guard(() async {
      final int n = await widget.chat.addToGroup(widget.conversationId, chosen);
      if (n == 0) throw const ChatFailure('Nessuna persona aggiunta: forse non ha ancora attivato la chat.');
    }, done: 'Aggiunte o invitate: ${chosen.length}');
  }

  Future<void> _invite() async {
    try {
      final String code = await widget.chat.inviteCode(widget.conversationId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext ctx) => _InviteSheet(
          code: code,
          title: widget.chat.conversation(widget.conversationId)?.title ?? '',
          onRenew: () async {
            Navigator.of(ctx).pop();
            await _guard(() async {
              await widget.chat.inviteCode(widget.conversationId, renew: true);
            }, done: 'Nuovo codice creato: il vecchio non vale più');
          },
          onRevoke: () async {
            Navigator.of(ctx).pop();
            await _guard(() => widget.chat.revokeInvite(widget.conversationId), done: 'Codice disattivato');
          },
        ),
      );
    } on ChatFailure catch (f) {
      _toast(f.message);
    }
  }

  Future<void> _memberActions(GroupMember m) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(m.displayName), subtitle: Text('@${m.username}')),
            if (m.isActive)
              ListTile(
                key: const ValueKey<String>('membro_admin'),
                leading: Icon(m.isAdmin ? Icons.remove_moderator_outlined : Icons.add_moderator_outlined),
                title: Text(m.isAdmin ? 'Togli amministratore' : 'Nomina amministratore'),
                onTap: () => Navigator.of(ctx).pop('admin'),
              ),
            ListTile(
              key: const ValueKey<String>('membro_rimuovi'),
              leading: Icon(Icons.person_remove_outlined, color: Theme.of(ctx).colorScheme.error),
              title: Text(m.isInvited ? 'Annulla l\'invito' : 'Rimuovi dal gruppo',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.of(ctx).pop('rimuovi'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'admin') {
      await _guard(() => widget.chat.setGroupAdmin(widget.conversationId, m.userId, !m.isAdmin));
    } else if (choice == 'rimuovi') {
      await _guard(() => widget.chat.removeFromGroup(widget.conversationId, m.userId));
    }
  }

  Future<void> _leave() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Uscire dal gruppo?'),
        content: const Text('Non riceverai più i messaggi e il gruppo sparirà da questo telefono.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(
            key: const ValueKey<String>('esci_conferma'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    try {
      await widget.chat.leaveGroup(widget.conversationId);
      if (mounted) Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    } on ChatFailure catch (f) {
      _toast(f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.chat,
      builder: (BuildContext context, _) {
        final ChatConversation? c = widget.chat.conversation(widget.conversationId);
        if (c == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Gruppo non disponibile')));
        }
        final List<GroupMember>? members = _members;
        final bool admin = c.isAdmin;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Info gruppo'),
            actions: [
              if (admin)
                IconButton(
                  key: const ValueKey<String>('gruppo_modifica'),
                  onPressed: () => _edit(c),
                  icon: const Icon(Icons.edit_rounded),
                  tooltip: 'Modifica',
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SizedBox(height: 16),
              Center(
                child: Stack(
                  children: [
                    GroupAvatar(chat: widget.chat, conversation: c, size: 108),
                    if (admin)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton.filled(
                          key: const ValueKey<String>('gruppo_foto'),
                          onPressed: _photo,
                          style: IconButton.styleFrom(backgroundColor: AppColors.brandOrange),
                          icon: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 20),
                          tooltip: 'Cambia foto',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text(c.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
              Center(child: Text('Gruppo · ${c.members} ${c.members == 1 ? 'membro' : 'membri'}',
                  style: theme.textTheme.bodyMedium)),
              if (c.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Text(c.description, textAlign: TextAlign.center),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Messaggi e allegati cifrati end-to-end, anche nei gruppi.',
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
              const Divider(height: 28),
              if (admin) ...[
                ListTile(
                  key: const ValueKey<String>('gruppo_aggiungi'),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.brandOrange,
                    child: Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
                  ),
                  title: const Text('Aggiungi persone'),
                  enabled: members != null,
                  onTap: members == null ? null : () => _add(members),
                ),
                ListTile(
                  key: const ValueKey<String>('gruppo_codice'),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.brandBlue,
                    child: Icon(Icons.qr_code_rounded, color: Colors.white),
                  ),
                  title: const Text('Codice d\'invito'),
                  subtitle: const Text('Chi ha il codice può entrare'),
                  onTap: _invite,
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(members == null ? 'Membri' : 'Membri (${members.where((m) => m.isActive).length})',
                    style: theme.textTheme.labelLarge),
              ),
              if (_error != null)
                Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
              else if (members == null)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else
                for (final GroupMember m in members.where((m) => m.isActive || m.isInvited))
                  ListTile(
                    key: ValueKey<String>('membro_${m.userId}'),
                    leading: AvatarView(name: m.displayName, repository: widget.profiles, path: m.avatarPath, size: 42),
                    title: Text(m.userId == widget.chat.myId ? 'Tu' : m.displayName),
                    subtitle: Text(m.isInvited
                        ? 'Invitato · non ha ancora accettato'
                        : (m.mlsState == 'in' ? '@${m.username}' : '@${m.username} · in attesa di entrare')),
                    trailing: m.isAdmin
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.brandBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Amministratore',
                                style: TextStyle(color: AppColors.brandBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                          )
                        : null,
                    onTap: admin && m.userId != widget.chat.myId ? () => _memberActions(m) : null,
                  ),
              const Divider(height: 28),
              ListTile(
                key: const ValueKey<String>('gruppo_esci'),
                leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
                title: Text('Esci dal gruppo', style: TextStyle(color: theme.colorScheme.error)),
                onTap: _leave,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddMembersScreen extends StatefulWidget {
  const _AddMembersScreen({required this.contacts, required this.exclude, this.profiles});

  final List<ChatContact> contacts;
  final Set<String> exclude;
  final ProfileRepository? profiles;

  @override
  State<_AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<_AddMembersScreen> {
  final Set<String> _chosen = <String>{};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aggiungi persone')),
    body: ListView(
      children: [
        _ContactPicker(
          contacts: widget.contacts,
          chosen: _chosen,
          exclude: widget.exclude,
          profiles: widget.profiles,
          onToggle: (String id) => setState(() => _chosen.contains(id) ? _chosen.remove(id) : _chosen.add(id)),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: FilledButton(
        key: const ValueKey<String>('aggiungi_conferma'),
        onPressed: _chosen.isEmpty ? null : () => Navigator.of(context).pop(_chosen.toList()),
        child: Text(_chosen.isEmpty ? 'Scegli le persone' : 'Aggiungi (${_chosen.length})'),
      ),
    ),
  );
}

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.code, required this.title, required this.onRenew, required this.onRevoke});

  final String code;
  final String title;
  final VoidCallback onRenew;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String pretty = code.length == 10 ? '${code.substring(0, 5)}-${code.substring(5)}' : code;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Codice d\'invito', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              key: const ValueKey<String>('codice_mostrato'),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(pretty,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
            ),
            const SizedBox(height: 8),
            Text('In Chat → Nuova chat → «Entra con un codice».', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('codice_condividi'),
              onPressed: () => SharePlus.instance.share(ShareParams(
                text: 'Entra nel gruppo «$title» su Piazly: in Chat tocca Nuova chat → '
                    'Entra con un codice e scrivi $code',
              )),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Condividi'),
            ),
            TextButton(key: const ValueKey<String>('codice_nuovo'), onPressed: onRenew, child: const Text('Crea un codice nuovo')),
            TextButton(
              key: const ValueKey<String>('codice_disattiva'),
              onPressed: onRevoke,
              child: Text('Disattiva il codice', style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
        ),
      ),
    );
  }
}

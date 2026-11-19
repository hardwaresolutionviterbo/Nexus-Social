import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../calls/calls_list.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_repository.dart';
import 'chat_backup_screen.dart';
import 'chat_group_screens.dart';
import 'chat_media.dart';
import 'chat_models.dart';
import 'chat_service.dart';
import 'chat_thread_screen.dart';

/// Scheda Chat (Fase 4, Blocco 1): le chat a due cifrate, le richieste dagli sconosciuti e
/// «Nuova chat» dalla rubrica. Senza server collegato resta l'anteprima della Fase 1.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, this.service, this.profiles, this.now = DateTime.now});

  final ChatService? service;

  final ProfileRepository? profiles;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final ChatService? chat = service;
    if (chat == null) {
      return const PhasePreview(
        icon: Icons.forum_outlined,
        accent: AppColors.brandBlue,
        phase: 4,
        title: 'Chat e chiamate',
        description:
            'Messaggi uno a uno e di gruppo, vocali, foto, video e chiamate, '
            'con crittografia end-to-end.',
        features: [
          'Crittografia end-to-end con un protocollo collaudato',
          'Stato inviato, consegnato e letto, risposte, inoltri e reazioni',
          'Richieste di messaggio dagli sconosciuti: il numero non si vede mai',
          'Chiamate vocali e videochiamate, anche di gruppo',
          'Notifiche con anteprima decifrata solo sul telefono',
          'Condividi l\'incontro con una persona fidata prima di vederti con uno sconosciuto',
        ],
      );
    }
    return ListenableBuilder(
      listenable: chat,
      builder: (BuildContext context, _) =>
          _ChatList(chat: chat, profiles: profiles, now: now()),
    );
  }
}

enum _Section { chats, calls }

class _ChatList extends StatefulWidget {
  const _ChatList({required this.chat, required this.profiles, required this.now});

  final ChatService chat;
  final ProfileRepository? profiles;
  final DateTime now;

  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  /// Sezione aperta: chat o chiamate (Blocco 11).
  _Section _section = _Section.chats;

  ChatService get chat => widget.chat;
  ProfileRepository? get profiles => widget.profiles;
  DateTime get now => widget.now;

  /// «Chat | Chiamate» in alto. Gli Stati hanno la loro scheda nella barra in basso.
  Widget _sections(BuildContext context) {
    final int missed = chat.calls?.log.unseenMissed ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: SegmentedButton<_Section>(
        key: const ValueKey<String>('chat_sezioni'),
        showSelectedIcon: false,
        segments: <ButtonSegment<_Section>>[
          const ButtonSegment<_Section>(value: _Section.chats, label: Text('Chat')),
          if (chat.calls != null)
            ButtonSegment<_Section>(
              value: _Section.calls,
              label: Text(missed > 0 ? 'Chiamate · $missed' : 'Chiamate', key: const ValueKey<String>('sezione_chiamate')),
            ),
        ],
        selected: <_Section>{_section},
        onSelectionChanged: (Set<_Section> v) => setState(() => _section = v.first),
      ),
    );
  }

  void _openChat(String conversationId) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ChatThreadScreen(chat: chat, conversationId: conversationId, profiles: profiles),
    ),
  );

  Future<void> _newChat(BuildContext context) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => NewChatScreen(chat: chat, profiles: profiles),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (!chat.ready) {
      final String? error = chat.startError;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.md),
                    Text('Prepariamo la chat cifrata…', style: theme.textTheme.bodyMedium),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 40, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: AppSpacing.sm),
                    Text(error, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      key: const ValueKey<String>('chat_riprova'),
                      onPressed: chat.start,
                      child: const Text('Riprova'),
                    ),
                  ],
                ),
        ),
      );
    }
    final List<ChatThread> threads = chat.threads;
    final List<ChatThread> requests = chat.requests;
    if (chat.calls != null) {
      final Listenable sections = Listenable.merge(<Listenable?>[chat.calls?.log]);
      return Column(
        children: [
          ListenableBuilder(listenable: sections, builder: (BuildContext c, _) => _sections(c)),
          Expanded(
            child: switch (_section) {
              _Section.calls when chat.calls != null =>
                CallsList(chat: chat, calls: chat.calls!, profiles: profiles, openChat: _openChat, now: () => now),
              _ => _chats(context, theme, threads, requests),
            },
          ),
        ],
      );
    }
    return _chats(context, theme, threads, requests);
  }

  Widget _chats(BuildContext context, ThemeData theme, List<ChatThread> threads, List<ChatThread> requests) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: chat.refresh,
          child: ListView(
            padding: AppSpacing.pagePadding.copyWith(left: 0, right: 0),
            children: [
              const _E2eBanner(),
              if (chat.backup != null)
                ChatBackupCard(backup: chat.backup!, hasChats: threads.isNotEmpty, now: () => now),
              if (requests.isNotEmpty)
                ListTile(
                  key: const ValueKey<String>('chat_richieste'),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.brandOrange.withValues(alpha: 0.15),
                    child: const Icon(Icons.mark_email_unread_outlined, color: AppColors.brandOrange),
                  ),
                  title: const Text('Richieste di messaggio'),
                  subtitle: Text(
                    requests.length == 1
                        ? '1 persona che non hai in rubrica ti ha scritto'
                        : '${requests.length} persone che non hai in rubrica ti hanno scritto',
                  ),
                  trailing: _Count(requests.length),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatRequestsScreen(chat: chat, profiles: profiles, now: now),
                    ),
                  ),
                ),
              if (threads.isEmpty)
                const _EmptyChats()
              else
                for (final ChatThread t in threads)
                  ChatThreadTile(thread: t, chat: chat, profiles: profiles, now: now),
            ],
          ),
        ),
        Positioned(
          right: 18,
          bottom: 112,
          child: FloatingActionButton.extended(
            key: const ValueKey<String>('chat_nuova'),
            heroTag: 'chat_nuova',
            backgroundColor: AppColors.brandOrange,
            foregroundColor: Colors.white,
            onPressed: () => _newChat(context),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Nuova chat'),
          ),
        ),
      ],
    );
  }
}

class _E2eBanner extends StatelessWidget {
  const _E2eBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Le chat sono cifrate end-to-end: le leggono solo le persone della chat.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandBlue.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.forum_outlined, size: 36, color: AppColors.brandBlue),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Nessuna chat per ora', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Scrivi a un contatto con «Nuova chat», oppure tocca «Contatta» su un annuncio.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.brandOrange,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '$n',
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

/// «18:30», «Ieri», «lun 9/11» o «9/11/25».
String chatTimeLabel(DateTime at, DateTime now) {
  final DateTime day = DateTime(at.year, at.month, at.day);
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int days = today.difference(day).inDays;
  String two(int v) => v.toString().padLeft(2, '0');
  if (days <= 0) return '${two(at.hour)}:${two(at.minute)}';
  if (days == 1) return 'Ieri';
  if (at.year == now.year) return '${at.day}/${at.month}';
  return '${at.day}/${at.month}/${at.year % 100}';
}

/// Spunte come su WhatsApp: orologio, una, due grigie, due blu; rossa se non partito.
class TicksIcon extends StatelessWidget {
  const TicksIcon(this.ticks, {super.key, this.size = 16});

  final MessageTicks ticks;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color grey = Theme.of(context).colorScheme.onSurfaceVariant;
    switch (ticks) {
      case MessageTicks.sending:
        return Icon(Icons.schedule_rounded, size: size - 2, color: grey, semanticLabel: 'In invio');
      case MessageTicks.failed:
        return Icon(Icons.error_outline_rounded, size: size, color: Theme.of(context).colorScheme.error,
            semanticLabel: 'Non inviato');
      case MessageTicks.sent:
        return Icon(Icons.done_rounded, size: size, color: grey, semanticLabel: 'Inviato');
      case MessageTicks.delivered:
        return Icon(Icons.done_all_rounded, size: size, color: grey, semanticLabel: 'Consegnato');
      case MessageTicks.read:
        return Icon(Icons.done_all_rounded, size: size, color: AppColors.brandBlue, semanticLabel: 'Letto');
    }
  }
}

String chatPreview(ChatMessage? m) {
  if (m == null) return '';
  switch (m.kind) {
    case MessageKind.text:
      if (m.deleted) return m.mine ? 'Hai eliminato questo messaggio' : 'Questo messaggio è stato eliminato';
      final ChatMedia? md = m.media;
      if (md != null) {
        final String label = switch (md.kind) {
          MediaKind.image => '📷 Foto',
          MediaKind.video => '🎬 Video',
          MediaKind.audio => '🎤 Messaggio vocale (${formatDuration(md.durationMs)})',
          MediaKind.file => '📄 ${md.name.isEmpty ? 'Documento' : md.name}',
        };
        return m.body.isEmpty ? label : '$label · ${m.body.replaceAll('\n', ' ')}';
      }
      return m.body.replaceAll('\n', ' ');
    case MessageKind.unreadable:
      return 'Messaggio non disponibile';
    case MessageKind.notice:
      return m.body;
  }
}

class ChatThreadTile extends StatelessWidget {
  const ChatThreadTile({
    super.key,
    required this.thread,
    required this.chat,
    required this.profiles,
    required this.now,
  });

  final ChatThread thread;
  final ChatService chat;
  final ProfileRepository? profiles;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChatConversation c = thread.conversation;
    final ChatMessage? last = thread.last;
    final bool unread = thread.unread > 0;
    return ListTile(
      key: ValueKey<String>('chat_${c.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: c.isGroup
          ? GroupAvatar(chat: chat, conversation: c)
          : AvatarView(name: c.peerName, repository: profiles, path: c.peerAvatarPath, size: 48),
      title: Text(
        c.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Row(
        children: [
          if (last != null && last.mine && last.isText) ...[
            TicksIcon(last.ticksFor(c), size: 15),
            const SizedBox(width: 3),
          ],
          Expanded(
            child: Text(
              c.isGroup && c.isRequest
                  ? 'Invito al gruppo · ${c.members} membri'
                  : (c.isGroup && last != null && last.kind == MessageKind.text && !last.mine
                        ? '${chat.memberName(c.id, last.senderId)}: ${chatPreview(last)}'
                        : chatPreview(last)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: unread
                  ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
                  : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            chatTimeLabel(thread.sortAt, now),
            style: theme.textTheme.bodySmall?.copyWith(
              color: unread ? AppColors.brandOrange : theme.colorScheme.onSurfaceVariant,
              fontWeight: unread ? FontWeight.w700 : null,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (c.isMuted)
                Padding(
                  padding: EdgeInsets.only(right: unread ? 4 : 0),
                  child: Icon(
                    Icons.notifications_off_outlined,
                    key: ValueKey<String>('silenziata_${c.id}'),
                    size: 17,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (unread) _Count(thread.unread) else if (!c.isMuted) const SizedBox(height: 20),
            ],
          ),
        ],
      ),
      onTap: () => ChatThreadScreen.open(context, chat: chat, conversationId: c.id, profiles: profiles),
    );
  }
}

/// Le richieste di messaggio: chi ti ha scritto senza essere nella tua rubrica.
class ChatRequestsScreen extends StatelessWidget {
  const ChatRequestsScreen({super.key, required this.chat, this.profiles, required this.now});

  final ChatService chat;
  final ProfileRepository? profiles;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Richieste di messaggio')),
      body: ListenableBuilder(
        listenable: chat,
        builder: (BuildContext context, _) {
          final List<ChatThread> requests = chat.requests;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                child: Text(
                  'Queste persone non sono nella tua rubrica. Non vedono il tuo numero e non '
                  'sanno se hai letto finché non accetti.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (requests.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Nessuna richiesta in attesa')),
                ),
              for (final ChatThread t in requests)
                ChatThreadTile(thread: t, chat: chat, profiles: profiles, now: now),
            ],
          );
        },
      ),
    );
  }
}

/// «Nuova chat»: i contatti della rubrica iscritti a Piazly (mai il numero).
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key, required this.chat, this.profiles});

  final ChatService chat;
  final ProfileRepository? profiles;

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  List<ChatContact>? _contacts;
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<ChatContact> list = await widget.chat.contacts();
      if (mounted) setState(() => _contacts = list);
    } catch (_) {
      if (mounted) setState(() => _error = 'Contatti non caricati. Riprova.');
    }
  }

  Future<void> _joinCode() async {
    final String? id = await joinGroupWithCode(context, widget.chat);
    if (id == null || !mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatThreadScreen(chat: widget.chat, conversationId: id, profiles: widget.profiles),
      ),
    );
  }

  Future<void> _open(ChatContact c) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final String id = await widget.chat.openDirect(c.id);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatThreadScreen(
            chat: widget.chat,
            conversationId: id,
            profiles: widget.profiles,
            fallbackName: c.name,
          ),
        ),
      );
    } on ChatFailure catch (f) {
      if (!mounted) return;
      setState(() => _opening = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ChatContact>? contacts = _contacts;
    final List<Widget> top = <Widget>[
      ListTile(
        key: const ValueKey<String>('nuovo_gruppo'),
        leading: const CircleAvatar(
          backgroundColor: AppColors.brandBlue,
          child: Icon(Icons.group_add_rounded, color: Colors.white),
        ),
        title: const Text('Nuovo gruppo'),
        onTap: _opening
            ? null
            : () => Navigator.of(context).pushReplacement<void, void>(
                MaterialPageRoute<void>(
                  builder: (_) => NewGroupScreen(
                    chat: widget.chat,
                    profiles: widget.profiles,
                    onCreated: (BuildContext ctx, String id) => Navigator.of(ctx).pushReplacement<void, void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatThreadScreen(chat: widget.chat, conversationId: id, profiles: widget.profiles),
                      ),
                    ),
                  ),
                ),
              ),
      ),
      ListTile(
        key: const ValueKey<String>('entra_codice'),
        leading: const CircleAvatar(
          backgroundColor: AppColors.brandOrange,
          child: Icon(Icons.vpn_key_rounded, color: Colors.white),
        ),
        title: const Text('Entra con un codice'),
        subtitle: const Text('Il codice d\'invito di un gruppo'),
        onTap: _opening ? null : _joinCode,
      ),
      const Divider(height: 8),
    ];
    Widget body;
    if (_error != null) {
      body = ListView(children: [...top, Padding(padding: const EdgeInsets.all(24), child: Text(_error!))]);
    } else if (contacts == null) {
      body = ListView(children: [...top, const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))]);
    } else if (contacts.isEmpty) {
      body = ListView(
        children: [
          ...top,
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              'Nessun contatto su Piazly. Attiva la rubrica in Profilo → Privacy, oppure scrivi '
              'con «Contatta» su un annuncio.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );
    } else {
      body = ListView(
        children: [
          ...top,
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Text('Contatti su Piazly', style: theme.textTheme.labelLarge),
          ),
          for (final ChatContact c in contacts)
            ListTile(
              key: ValueKey<String>('contatto_${c.id}'),
              enabled: !_opening,
              leading: AvatarView(name: c.name, repository: widget.profiles, path: c.avatarPath, size: 44),
              title: Text(c.name.isEmpty ? '@${c.username}' : c.name),
              subtitle: Text('@${c.username}'),
              onTap: () => _open(c),
            ),
        ],
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Nuova chat')), body: body);
  }
}

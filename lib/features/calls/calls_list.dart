import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/piazly_ui.dart';
import '../chat/chat_models.dart';
import '../chat/chat_service.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_repository.dart';
import 'call_log.dart';
import 'call_service.dart';

/// «Oggi, 18:05», «Ieri, 09:12», «12/11, 21:40».
String callTimeLabel(DateTime at, DateTime now) {
  final DateTime l = at.toLocal();
  final int days = DateTime(now.year, now.month, now.day).difference(DateTime(l.year, l.month, l.day)).inDays;
  final String hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  if (days <= 0) return 'Oggi, $hm';
  if (days == 1) return 'Ieri, $hm';
  return l.year == now.year ? '${l.day}/${l.month}, $hm' : '${l.day}/${l.month}/${l.year % 100}, $hm';
}

/// Sezione «Chiamate» della chat: perse, fatte e ricevute, come su WhatsApp.
class CallsList extends StatefulWidget {
  const CallsList({
    super.key,
    required this.chat,
    required this.calls,
    required this.openChat,
    this.profiles,
    this.now = DateTime.now,
    this.all = false,
  });

  /// Tutta la cronologia (pagina «Tutte le chiamate»), senza i pulsanti rapidi.
  final bool all;

  final ChatService chat;
  final CallService calls;
  final ProfileRepository? profiles;
  final void Function(String conversationId) openChat;
  final DateTime Function() now;

  @override
  State<CallsList> createState() => _CallsListState();
}

class _CallsListState extends State<CallsList> {
  @override
  void initState() {
    super.initState();
    // Aperta la sezione: le chiamate perse non sono più «nuove».
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.calls.log.markSeen(widget.now()));
  }

  Future<void> _callBack(CallRecord r, {bool? video}) async {
    final ChatConversation? c = widget.chat.conversation(r.conversationId);
    try {
      if (c == null) throw const ChatFailure('Questa chat non c\'è più.');
      if (c.isGroup) {
        await widget.calls.startGroup(c.id, video: video ?? r.video);
      } else {
        await widget.calls.start(c.id, video: video ?? r.video);
      }
    } on ChatFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// «Nuova chiamata»: scegli una chat e parte la chiamata.
  Future<void> _newCall({required bool video}) async {
    final List<ChatConversation> chats = <ChatConversation>[
      for (final ChatThread t in widget.chat.threads)
        if (!t.conversation.isRequest &&
            (!t.conversation.isGroup ||
                (widget.calls.groupMedia != null && t.conversation.myMlsState == 'in' && t.conversation.members <= 8)))
          t.conversation,
    ];
    final ChatConversation? pick = await showModalBottomSheet<ChatConversation>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(video ? 'Nuova videochiamata' : 'Nuova chiamata vocale',
                    style: Theme.of(c).textTheme.titleMedium),
              ),
              if (chats.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nessuna chat ancora: scrivi a qualcuno con «Nuova chat» e poi chiamalo.'),
                ),
              for (final ChatConversation conv in chats)
                ListTile(
                  key: ValueKey<String>('nuova_chiamata_${conv.id}'),
                  leading: conv.isGroup
                      ? CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.brandBlue.withValues(alpha: 0.12),
                          child: const Icon(Icons.groups_rounded, color: AppColors.brandBlue),
                        )
                      : AvatarView(name: conv.displayName, repository: widget.profiles, path: conv.peerAvatarPath, size: 44),
                  title: Text(conv.displayName),
                  trailing: Icon(video ? Icons.videocam_outlined : Icons.call_outlined, color: PiazlyColors.violet),
                  onTap: () => Navigator.of(c).pop(conv),
                ),
            ],
          ),
        ),
      ),
    );
    if (pick == null) return;
    try {
      if (pick.isGroup) {
        await widget.calls.startGroup(pick.id, video: video);
      } else {
        await widget.calls.start(pick.id, video: video);
      }
    } on ChatFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _quick({required bool video}) {
    final ThemeData theme = Theme.of(context);
    final Color color = video ? AppColors.brandOrange : PiazlyColors.violet;
    return Expanded(
      child: SoftCard(
        key: ValueKey<String>(video ? 'nuova_videochiamata' : 'nuova_chiamata_vocale'),
        tint: video ? PiazlyColors.orangeSoft : PiazlyColors.violetSoft,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        onTap: () => _newCall(video: video),
        child: Column(
          children: [
            Icon(video ? Icons.videocam_rounded : Icons.call_rounded, color: color, size: 30),
            const SizedBox(height: 6),
            Text(
              video ? 'Nuova\nvideochiamata' : 'Nuova\nchiamata vocale',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(color: video ? AppColors.brandOrangeDeep : PiazlyColors.violetDeep),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(CallRecord r, DateTime now) {
    final ThemeData theme = Theme.of(context);
    final ChatConversation? c = widget.chat.conversation(r.conversationId);
    final String name = c?.displayName ?? r.name;
    final Color red = theme.colorScheme.error;
    final IconData icon = r.video
        ? Icons.videocam_outlined
        : r.missed
        ? Icons.call_missed_rounded
        : r.outgoing
        ? Icons.call_made_rounded
        : Icons.call_received_rounded;
    final String kind = r.video ? 'Videochiamata' : 'Chiamata vocale';
    final String what = r.missed
        ? (r.video ? 'Videochiamata persa' : 'Chiamata persa')
        : r.outgoing && !r.answered
        ? '$kind senza risposta'
        : '$kind ${r.outgoing ? 'in uscita' : 'in arrivo'}';
    final String extra = r.duration == null ? '' : ' · ${callDuration(r.duration!)}';
    final Color tone = r.missed ? red : (r.answered ? const Color(0xFF2E7D32) : theme.colorScheme.onSurfaceVariant);
    return ListTile(
      key: ValueKey<String>('chiamata_${r.id}'),
      contentPadding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
      leading: c != null && !c.isGroup
          ? AvatarView(name: name, repository: widget.profiles, path: c.peerAvatarPath, size: 50)
          : CircleAvatar(
              radius: 25,
              backgroundColor: PiazlyColors.violetSoft,
              child: Icon(r.group ? Icons.groups_rounded : Icons.person_rounded, color: PiazlyColors.violet),
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(callTimeLabel(r.at, now), style: theme.textTheme.bodySmall),
        ],
      ),
      subtitle: Row(
        children: [
          Icon(icon, size: 17, color: tone),
          const SizedBox(width: 5),
          Expanded(
            child: Text('$what$extra', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: r.missed ? red : null)),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey<String>('chiamata_menu_${r.id}'),
        tooltip: 'Opzioni',
        onSelected: (String v) {
          if (v == 'chat') {
            widget.openChat(r.conversationId);
          } else {
            unawaited(_callBack(r, video: v == 'video'));
          }
        },
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            key: ValueKey<String>('richiama_${r.id}'),
            value: r.video ? 'video' : 'voce',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.video ? Icons.videocam_outlined : Icons.call_outlined),
              title: Text(r.video ? 'Videochiama' : 'Richiama'),
            ),
          ),
          PopupMenuItem<String>(
            value: r.video ? 'voce' : 'video',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.video ? Icons.call_outlined : Icons.videocam_outlined),
              title: Text(r.video ? 'Chiamata vocale' : 'Videochiamata'),
            ),
          ),
          const PopupMenuItem<String>(
            value: 'chat',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.chat_bubble_outline_rounded),
              title: Text('Apri la chat'),
            ),
          ),
        ],
      ),
      onTap: () => widget.openChat(r.conversationId),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(<Listenable>[widget.calls.log, widget.chat]),
    builder: (BuildContext context, _) {
      final ThemeData theme = Theme.of(context);
      final List<CallRecord> list = widget.calls.log.records;
      final DateTime now = widget.now();
      final List<CallRecord> recent = widget.all ? list : list.take(15).toList();
      return ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          if (!widget.all)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Row(children: [_quick(video: false), const SizedBox(width: 12), _quick(video: true)]),
            ),
          if (list.isEmpty) ...[
            const SizedBox(height: 48),
            Icon(Icons.call_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Nessuna chiamata', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Usa i pulsanti qui sopra, oppure apri una chat e tocca la cornetta o la videocamera.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ] else ...[
            if (!widget.all)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 2),
                child: Row(
                  children: [
                    Expanded(child: Text('Recenti', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                    TextButton(
                        key: const ValueKey<String>('tutte_le_chiamate'),
                        style: TextButton.styleFrom(foregroundColor: PiazlyColors.violet),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('Tutte le chiamate')),
                              body: CallsList(
                                chat: widget.chat,
                                calls: widget.calls,
                                openChat: widget.openChat,
                                profiles: widget.profiles,
                                now: widget.now,
                                all: true,
                              ),
                            ),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [Text('Tutte le chiamate'), SizedBox(width: 4), Icon(Icons.arrow_forward_rounded, size: 18)],
                        ),
                      ),
                  ],
                ),
              ),
            for (int i = 0; i < recent.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 84),
              _tile(recent[i], now),
            ],
          ],
        ],
      );
    },
  );
}

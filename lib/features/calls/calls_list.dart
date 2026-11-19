import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
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
  });

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

  Future<void> _callBack(CallRecord r) async {
    final ChatConversation? c = widget.chat.conversation(r.conversationId);
    try {
      if (c == null) throw const ChatFailure('Questa chat non c\'è più.');
      if (c.isGroup) {
        await widget.calls.startGroup(c.id, video: r.video);
      } else {
        await widget.calls.start(c.id, video: r.video);
      }
    } on ChatFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(<Listenable>[widget.calls.log, widget.chat]),
    builder: (BuildContext context, _) {
      final ThemeData theme = Theme.of(context);
      final List<CallRecord> list = widget.calls.log.records;
      final DateTime now = widget.now();
      if (list.isEmpty) {
        return ListView(
          children: [
            const SizedBox(height: 80),
            Icon(Icons.call_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Nessuna chiamata', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Per chiamare apri una chat e tocca la cornetta o la videocamera in alto.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: list.length,
        itemBuilder: (BuildContext context, int i) {
          final CallRecord r = list[i];
          final ChatConversation? c = widget.chat.conversation(r.conversationId);
          final String name = c?.displayName ?? r.name;
          final Color tone = r.missed ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;
          final IconData arrow = r.outgoing
              ? Icons.call_made_rounded
              : (r.missed ? Icons.call_missed_rounded : Icons.call_received_rounded);
          final String what = r.outgoing
              ? (r.answered ? 'In uscita' : 'Senza risposta')
              : (r.answered ? 'In arrivo' : 'Persa');
          final String extra = r.duration == null ? '' : ' · ${callDuration(r.duration!)}';
          return ListTile(
            key: ValueKey<String>('chiamata_${r.id}'),
            leading: c != null && !c.isGroup
                ? AvatarView(name: name, repository: widget.profiles, path: c.peerAvatarPath, size: 48)
                : CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.brandBlue.withValues(alpha: 0.12),
                    child: Icon(r.group ? Icons.groups_rounded : Icons.person_rounded, color: AppColors.brandBlue),
                  ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: r.missed ? theme.colorScheme.error : null,
              ),
            ),
            subtitle: Row(
              children: [
                Icon(arrow, size: 16, color: r.missed ? tone : (r.answered ? const Color(0xFF2E7D32) : tone)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$what · ${callTimeLabel(r.at, now)}$extra',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tone),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              key: ValueKey<String>('richiama_${r.id}'),
              tooltip: r.video ? 'Videochiama' : 'Chiama',
              icon: Icon(r.video ? Icons.videocam_outlined : Icons.call_outlined, color: AppColors.brandBlue),
              onPressed: () => _callBack(r),
            ),
            onTap: () => widget.openChat(r.conversationId),
          );
        },
      );
    },
  );
}

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_repository.dart';
import 'chat_models.dart';
import 'chat_screen.dart' show TicksIcon, chatTimeLabel;
import 'chat_service.dart';

/// La chat attiva dell'app (una per accesso): la usano i pulsanti «Contatta» degli annunci,
/// che si aprono sopra la barra principale.
abstract final class ChatRegistry {
  static ChatService? current;
  static ProfileRepository? profiles;
}

/// «Contatta»: apre la chat con [userId]. Senza chat (server non collegato) un avviso.
Future<void> openChatWith(BuildContext context, {required String userId, required String name}) async {
  final ChatService? chat = ChatRegistry.current;
  if (chat == null) {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Chat in arrivo'),
        content: Text('Potrai scrivere a $name quando la chat di Piazly sarà collegata.'),
        actions: [
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Ok')),
        ],
      ),
    );
    return;
  }
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final NavigatorState navigator = Navigator.of(context);
  try {
    final String id = await chat.openDirect(userId);
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatThreadScreen(
          chat: chat,
          conversationId: id,
          profiles: ChatRegistry.profiles,
          fallbackName: name,
        ),
      ),
    );
  } on ChatFailure catch (f) {
    messenger.showSnackBar(SnackBar(content: Text(f.message)));
  }
}

/// Una conversazione: messaggi, spunte, richiesta da accettare e campo per scrivere.
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.chat,
    required this.conversationId,
    this.profiles,
    this.fallbackName = '',
    this.now = DateTime.now,
  });

  final ChatService chat;
  final String conversationId;
  final ProfileRepository? profiles;
  final String fallbackName;
  final DateTime Function() now;

  static Future<void> open(
    BuildContext context, {
    required ChatService chat,
    required String conversationId,
    ProfileRepository? profiles,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ChatThreadScreen(chat: chat, conversationId: conversationId, profiles: profiles),
    ),
  );

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final TextEditingController _text = TextEditingController();
  bool _answering = false;

  @override
  void initState() {
    super.initState();
    widget.chat.setOpenConversation(widget.conversationId);
    widget.chat.addListener(_onChange);
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.chat.removeListener(_onChange);
    widget.chat.setOpenConversation(null);
    _text.dispose();
    super.dispose();
  }

  int _lastSeen = 0;

  void _onChange() {
    // Nuovi messaggi mentre la chat è aperta: letti.
    final int n = widget.chat.messages(widget.conversationId).length;
    if (n != _lastSeen) {
      _lastSeen = n;
      widget.chat.markRead(widget.conversationId);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _send() async {
    final String text = _text.text;
    if (text.trim().isEmpty) return;
    _text.clear();
    try {
      await widget.chat.send(widget.conversationId, text);
    } on ChatFailure catch (f) {
      if (mounted) _toast(f.message);
    }
  }

  Future<void> _answer(bool accept) async {
    setState(() => _answering = true);
    try {
      await widget.chat.respondRequest(widget.conversationId, accept);
      if (!accept && mounted) Navigator.of(context).pop();
    } on ChatFailure catch (f) {
      if (mounted) _toast(f.message);
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.chat,
      builder: (BuildContext context, _) {
        final ChatConversation? c = widget.chat.conversation(widget.conversationId);
        final String name = c == null
            ? widget.fallbackName
            : (c.peerName.isEmpty ? '@${c.peerUsername}' : c.peerName);
        final List<ChatMessage> messages = widget.chat.messages(widget.conversationId);
        final DateTime now = widget.now();
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                AvatarView(name: name, repository: widget.profiles, path: c?.peerAvatarPath, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (c != null)
                        Text('@${c.peerUsername}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              if (c != null && c.isRequest)
                _RequestBanner(name: name, busy: _answering, onAnswer: _answer),
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: messages.length + 1,
                  itemBuilder: (BuildContext context, int i) {
                    if (i == messages.length) return const _E2eNote();
                    final ChatMessage m = messages[messages.length - 1 - i];
                    return _Bubble(
                      message: m,
                      ticks: m.ticksFor(c),
                      now: now,
                      onRetry: m.ticks == MessageTicks.failed ? () => widget.chat.retry(m) : null,
                    );
                  },
                ),
              ),
              _Composer(controller: _text, onSend: _send),
            ],
          ),
        );
      },
    );
  }
}

class _E2eNote extends StatelessWidget {
  const _E2eNote();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 4, 24, 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.brandAmber.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Messaggi cifrati end-to-end. Nessuno, nemmeno Piazly, può leggerli.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestBanner extends StatelessWidget {
  const _RequestBanner({required this.name, required this.busy, required this.onAnswer});

  final String name;
  final bool busy;
  final Future<void> Function(bool accept) onAnswer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('richiesta_banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandOrange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$name vuole scriverti', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Non è nella tua rubrica. Non vede il tuo numero e non sa se hai letto finché non '
            'accetti. Se rifiuti, la chat sparisce e non ricevi altro.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('richiesta_rifiuta'),
                  onPressed: busy ? null : () => onAnswer(false),
                  style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  child: const Text('Rifiuta'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey<String>('richiesta_accetta'),
                  onPressed: busy ? null : () => onAnswer(true),
                  child: const Text('Accetta'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.ticks, required this.now, this.onRetry});

  final ChatMessage message;
  final MessageTicks ticks;
  final DateTime now;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    if (message.kind == MessageKind.notice) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(message.body, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ),
      );
    }
    final bool mine = message.mine;
    final Color bg = mine
        ? (dark ? const Color(0xFF3A2614) : const Color(0xFFFFE6D2))
        : theme.colorScheme.surface;
    final String time = chatTimeLabel(message.at, now).contains(':')
        ? chatTimeLabel(message.at, now)
        : '${chatTimeLabel(message.at, now)} '
              '${message.at.hour.toString().padLeft(2, '0')}:${message.at.minute.toString().padLeft(2, '0')}';
    final Widget content = message.kind == MessageKind.unreadable
        ? Text(
            'Messaggio non disponibile su questo telefono',
            style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant),
          )
        : Text(message.body, style: theme.textTheme.bodyLarge);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onRetry,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06), blurRadius: 4,
                  offset: const Offset(0, 1)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(alignment: Alignment.centerLeft, widthFactor: 1, child: content),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ticks == MessageTicks.failed ? 'Non inviato · tocca per riprovare' : time,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ticks == MessageTicks.failed
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    TicksIcon(ticks, size: 15),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canSend = controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey<String>('chat_testo'),
                controller: controller,
                minLines: 1,
                maxLines: 5,
                maxLength: ChatContent.maxTextLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Scrivi un messaggio',
                  counterText: '',
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey<String>('chat_invia'),
              onPressed: canSend ? onSend : null,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.brandOrange,
                foregroundColor: Colors.white,
                fixedSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Invia',
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_repository.dart';
import 'chat_group_screens.dart';
import 'chat_media.dart';
import 'chat_media_picker.dart';
import 'chat_media_widgets.dart';
import 'chat_models.dart';
import 'chat_safety_screens.dart';
import 'chat_screen.dart' show TicksIcon, chatPreview, chatTimeLabel;
import 'chat_service.dart';

/// La chat attiva dell'app (una per accesso): la usano i pulsanti «Contatta» degli annunci,
/// che si aprono sopra la barra principale.
/// Testo del menu «Silenzia» quando la chat è già silenziata.
String mutedLabel(DateTime until, DateTime now) {
  if (until.year >= 9999) return 'Silenziata per sempre';
  final DateTime l = until.toLocal();
  final String hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  final bool today = l.year == now.year && l.month == now.month && l.day == now.day;
  return today ? 'Silenziata fino alle $hm' : 'Silenziata fino al ${l.day}/${l.month} alle $hm';
}

/// Notifica toccata (Blocco 5): si chiude quello che c'era sopra e si apre la chat.
void openChatFromNotification(
  BuildContext context, {
  required ChatService chat,
  required String conversationId,
  ProfileRepository? profiles,
}) {
  final NavigatorState nav = Navigator.of(context);
  nav.popUntil((Route<dynamic> r) => r.isFirst);
  nav.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ChatThreadScreen(chat: chat, conversationId: conversationId, profiles: profiles),
    ),
  );
}

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
    this.device,
  });

  final ChatService chat;
  final String conversationId;
  final ProfileRepository? profiles;
  final String fallbackName;
  final DateTime Function() now;

  /// Fotocamera, galleria, documenti, microfono (finto nei test).
  final ChatDevice? device;

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
  final FocusNode _focus = FocusNode();
  bool _answering = false;

  /// Messaggio a cui si sta rispondendo (barra sopra il campo di testo).
  ChatMessage? _replyTo;

  late final ChatDevice _device = widget.device ?? RealChatDevice();

  /// Registrazione del vocale in corso: da quando.
  DateTime? _recording;
  Timer? _recordTick;

  @override
  void initState() {
    super.initState();
    widget.chat.setOpenConversation(widget.conversationId);
    widget.chat.addListener(_onChange);
    // Nei gruppi servono i nomi dei membri (fumetti, citazioni, invito).
    if (widget.chat.conversation(widget.conversationId)?.isGroup ?? false) {
      widget.chat.groupMembers(widget.conversationId).then((_) {
        if (mounted) setState(() {});
      }, onError: (Object _) {});
    }
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.chat.removeListener(_onChange);
    widget.chat.setOpenConversation(null);
    _text.dispose();
    _focus.dispose();
    _recordTick?.cancel();
    if (_recording != null) unawaited(_device.cancelVoice());
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
    final ChatMessage? replyTo = _replyTo;
    _text.clear();
    setState(() => _replyTo = null);
    try {
      await widget.chat.send(widget.conversationId, text, replyTo: replyTo);
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

  String get _peerName {
    final ChatConversation? c = widget.chat.conversation(widget.conversationId);
    if (c == null) return widget.fallbackName;
    return c.peerName.isEmpty ? '@${c.peerUsername}' : c.peerName;
  }

  /// Graffetta: Galleria, Fotocamera, Video, Documento.
  Future<void> _attach() async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => const _AttachSheet(),
    );
    if (!mounted || choice == null) return;
    PickedMedia? picked;
    try {
      picked = switch (choice) {
        'galleria' => await _device.pickImage(camera: false),
        'fotocamera' => await _device.pickImage(camera: true),
        'video' => await _device.pickVideo(),
        _ => await _device.pickFile(),
      };
    } on ChatFailure catch (f) {
      _toast(f.message);
      return;
    } catch (_) {
      _toast('Non è stato possibile aprire il file.');
      return;
    }
    if (picked == null || !mounted) return;
    final String? caption = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => MediaPreviewScreen(media: picked!, peerName: _peerName)),
    );
    if (caption == null || !mounted) return;
    await _sendPicked(picked, caption: caption);
  }

  Future<void> _sendPicked(PickedMedia p, {String caption = ''}) async {
    final ChatMessage? replyTo = _replyTo;
    setState(() => _replyTo = null);
    try {
      await widget.chat.sendMedia(
        widget.conversationId,
        kind: p.kind,
        bytes: p.bytes,
        mime: p.mime,
        name: p.name,
        width: p.width,
        height: p.height,
        durationMs: p.durationMs,
        thumb: p.thumb,
        caption: caption,
        replyTo: replyTo,
      );
    } on ChatFailure catch (f) {
      if (mounted) _toast(f.message);
    }
  }

  Future<void> _startVoice() async {
    try {
      if (!await _device.startVoice()) {
        _toast('Per i vocali serve il permesso del microfono (Impostazioni del telefono).');
        return;
      }
    } catch (_) {
      _toast('Il microfono non è disponibile.');
      return;
    }
    if (!mounted) return;
    setState(() => _recording = DateTime.now());
    _recordTick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
      final DateTime? start = _recording;
      if (start != null && DateTime.now().difference(start) >= MediaLimits.maxVoice) _stopVoice(send: true);
    });
  }

  Future<void> _stopVoice({required bool send}) async {
    _recordTick?.cancel();
    _recordTick = null;
    setState(() => _recording = null);
    if (!send) {
      await _device.cancelVoice();
      return;
    }
    final PickedMedia? voice = await _device.stopVoice();
    if (voice == null) {
      _toast('Vocale troppo corto.');
      return;
    }
    await _sendPicked(voice);
  }

  String _authorName(ChatConversation? c, String authorId) {
    if (authorId == widget.chat.myId) return 'Tu';
    if (c != null && c.isGroup) return widget.chat.memberName(c.id, authorId);
    return c?.peerName.isNotEmpty ?? false ? c!.peerName : widget.fallbackName;
  }

  void _openInfo() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => GroupInfoScreen(
        chat: widget.chat,
        conversationId: widget.conversationId,
        profiles: widget.profiles,
        device: widget.device,
      ),
    ),
  );

  /// Tieni premuto un messaggio: reazioni, Rispondi, Copia, Inoltra, Elimina.
  Future<void> _actions(ChatMessage m) async {
    final DateTime now = widget.now();
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => _MessageActions(message: m, now: now),
    );
    if (!mounted || choice == null) return;
    try {
      switch (choice) {
        case 'rispondi':
          setState(() => _replyTo = m);
          _focus.requestFocus();
        case 'copia':
          await Clipboard.setData(ClipboardData(text: m.body));
          _toast('Messaggio copiato');
        case 'inoltra':
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ForwardScreen(chat: widget.chat, message: m, profiles: widget.profiles),
            ),
          );
        case 'elimina':
          await _delete(m);
        default:
          if (choice.startsWith('reazione:')) {
            await widget.chat.react(m, choice.substring('reazione:'.length));
          }
      }
    } on ChatFailure catch (f) {
      if (mounted) _toast(f.message);
    }
  }

  Future<void> _more(String choice, ChatConversation c) async {
    if (choice == 'incontro') {
      await ShareMeetingScreen.open(
        context,
        widget.chat,
        withName: '${c.displayName} (@${c.peerUsername})',
        excludeId: c.peerId,
      );
    } else if (choice == 'segnala') {
      final bool? done = await ReportChatScreen.open(context, widget.chat, c.id);
      // Persona bloccata: la chat non c'è più.
      if (done == true && mounted && widget.chat.conversation(c.id) == null) Navigator.of(context).pop();
    }
  }

  Future<void> _mute(String choice) async {
    try {
      switch (choice) {
        case '8h':
          await widget.chat.setMute(widget.conversationId, duration: const Duration(hours: 8));
        case '1w':
          await widget.chat.setMute(widget.conversationId, duration: const Duration(days: 7));
        case 'sempre':
          await widget.chat.setMute(widget.conversationId);
        default:
          await widget.chat.setMute(widget.conversationId, unmute: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
        SnackBar(content: Text(choice == 'riattiva' ? 'Notifiche riattivate' : 'Chat silenziata')),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Non riuscito. Controlla la connessione.')),
      );
    }
  }

  Future<void> _delete(ChatMessage m) async {
    final bool forEveryone = m.canDeleteForEveryone(widget.now());
    final String? how = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Eliminare il messaggio?'),
        content: Text(
          forEveryone
              ? '«Elimina per tutti» lo toglie anche dal telefono dell\'altra persona.'
              : 'Il messaggio sparisce solo da questo telefono.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annulla')),
          TextButton(
            key: const ValueKey<String>('elimina_per_me'),
            onPressed: () => Navigator.of(ctx).pop('me'),
            child: const Text('Elimina per me'),
          ),
          if (forEveryone)
            FilledButton(
              key: const ValueKey<String>('elimina_per_tutti'),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.of(ctx).pop('tutti'),
              child: const Text('Elimina per tutti'),
            ),
        ],
      ),
    );
    if (how == 'me') await widget.chat.deleteForMe(m);
    if (how == 'tutti') await widget.chat.deleteForEveryone(m);
    if (_replyTo?.localId == m.localId && mounted) setState(() => _replyTo = null);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.chat,
      builder: (BuildContext context, _) {
        final ChatConversation? c = widget.chat.conversation(widget.conversationId);
        final String name = c == null ? widget.fallbackName : c.displayName;
        final bool group = c?.isGroup ?? false;
        final List<ChatMessage> messages = widget.chat.messages(widget.conversationId);
        final DateTime now = widget.now();
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: InkWell(
              key: const ValueKey<String>('chat_intestazione'),
              onTap: group && c != null && !c.isRequest ? _openInfo : null,
              child: Row(
                children: [
                  if (group && c != null)
                    GroupAvatar(chat: widget.chat, conversation: c, size: 38)
                  else
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
                          Text(
                            group ? '${c.members} ${c.members == 1 ? 'membro' : 'membri'} · tocca per le info'
                                : '@${c.peerUsername}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (c != null && !c.isRequest)
                PopupMenuButton<String>(
                  key: const ValueKey<String>('silenzia_chat'),
                  tooltip: c.isMuted ? 'Notifiche silenziate' : 'Silenzia',
                  icon: Icon(c.isMuted ? Icons.notifications_off_outlined : Icons.notifications_none_rounded),
                  onSelected: _mute,
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    if (c.isMuted)
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(mutedLabel(c.mutedUntil!, now)),
                      ),
                    const PopupMenuItem<String>(value: '8h', child: Text('Silenzia per 8 ore')),
                    const PopupMenuItem<String>(value: '1w', child: Text('Silenzia per 1 settimana')),
                    const PopupMenuItem<String>(value: 'sempre', child: Text('Silenzia sempre')),
                    if (c.isMuted)
                      const PopupMenuItem<String>(
                        key: ValueKey<String>('riattiva_notifiche'),
                        value: 'riattiva',
                        child: Text('Riattiva le notifiche'),
                      ),
                  ],
                ),
              if (c != null)
                PopupMenuButton<String>(
                  key: const ValueKey<String>('chat_altro'),
                  tooltip: 'Altro',
                  onSelected: (String v) => _more(v, c),
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    if (!c.isGroup)
                      const PopupMenuItem<String>(
                        key: ValueKey<String>('menu_incontro'),
                        value: 'incontro',
                        child: ListTile(
                          leading: Icon(Icons.shield_outlined),
                          title: Text('Condividi l\'incontro'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    const PopupMenuItem<String>(
                      key: ValueKey<String>('menu_segnala'),
                      value: 'segnala',
                      child: ListTile(
                        leading: Icon(Icons.flag_outlined),
                        title: Text('Segnala'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: Column(
            children: [
              if (c != null && c.isRequest)
                _RequestBanner(
                  name: name,
                  busy: _answering,
                  onAnswer: _answer,
                  group: group,
                  invitedBy: group && c.invitedBy != null ? widget.chat.memberName(c.id, c.invitedBy!) : null,
                )
              else if (c != null && group && c.myMlsState != 'in')
                const _WaitingBanner(),
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: messages.length + 1,
                  itemBuilder: (BuildContext context, int i) {
                    if (i == messages.length) return const _E2eNote();
                    final ChatMessage m = messages[messages.length - 1 - i];
                    return _Bubble(
                      chat: widget.chat,
                      message: m,
                      ticks: m.ticksFor(c),
                      now: now,
                      quoteAuthor: m.quote == null ? null : _authorName(c, m.quote!.authorId),
                      senderName: group && !m.mine && m.kind != MessageKind.notice
                          ? widget.chat.memberName(widget.conversationId, m.senderId)
                          : null,
                      onRetry: m.ticks == MessageTicks.failed ? () => widget.chat.retry(m) : null,
                      onLongPress: m.kind == MessageKind.notice || m.ticks == MessageTicks.sending
                          ? null
                          : () => _actions(m),
                    );
                  },
                ),
              ),
              if (_replyTo != null)
                _ReplyBar(
                  author: _authorName(c, _replyTo!.mine ? widget.chat.myId : (c?.peerId ?? '')),
                  text: chatPreview(_replyTo),
                  onClose: () => setState(() => _replyTo = null),
                ),
              if (c != null && group && (c.isRequest || c.myMlsState != 'in'))
                const SizedBox(height: 12)
              else if (_recording != null)
                _RecordingBar(
                  since: _recording!,
                  onCancel: () => _stopVoice(send: false),
                  onSend: () => _stopVoice(send: true),
                )
              else
                _Composer(
                  controller: _text,
                  focus: _focus,
                  onSend: _send,
                  onAttach: _attach,
                  onVoice: _startVoice,
                ),
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
  const _RequestBanner({
    required this.name,
    required this.busy,
    required this.onAnswer,
    this.group = false,
    this.invitedBy,
  });

  final String name;
  final bool busy;
  final Future<void> Function(bool accept) onAnswer;
  final bool group;
  final String? invitedBy;

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
          Text(
            group ? 'Invito al gruppo «$name»' : '$name vuole scriverti',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            group
                ? '${invitedBy == null || invitedBy == 'Un membro' ? 'Qualcuno che non hai in rubrica' : invitedBy} '
                      'ti ha aggiunto. Entrando, i membri vedranno il tuo nome e la tua foto, mai il '
                      'numero. Se rifiuti, l\'invito sparisce.'
                : 'Non è nella tua rubrica. Non vede il tuo numero e non sa se hai letto finché non '
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
                  child: Text(group ? 'Entra' : 'Accetta'),
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
  const _Bubble({
    required this.chat,
    required this.message,
    required this.ticks,
    required this.now,
    this.quoteAuthor,
    this.senderName,
    this.onRetry,
    this.onLongPress,
  });

  /// Nome di chi scrive (solo nei gruppi, per i messaggi degli altri).
  final String? senderName;

  final ChatService chat;
  final ChatMessage message;
  final MessageTicks ticks;
  final DateTime now;
  final String? quoteAuthor;
  final VoidCallback? onRetry;
  final VoidCallback? onLongPress;

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
    final TextStyle? faint = theme.textTheme.bodyMedium?.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final Widget content;
    if (message.kind == MessageKind.unreadable) {
      content = Text('Messaggio non disponibile su questo telefono', style: faint);
    } else if (message.deleted) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              mine ? 'Hai eliminato questo messaggio' : 'Questo messaggio è stato eliminato',
              style: faint,
            ),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (senderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                senderName!,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: senderColor(message.senderId),
                ),
              ),
            ),
          if (message.forwarded)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shortcut_rounded, size: 15, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Inoltrato', style: theme.textTheme.labelSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
                ],
              ),
            ),
          if (message.quote != null)
            _QuoteBox(author: quoteAuthor ?? '', text: message.quote!.text, mine: mine),
          if (message.hasMedia)
            Padding(
              padding: EdgeInsets.only(bottom: message.body.isEmpty ? 0 : 6),
              child: MediaContent(chat: chat, message: message, mine: mine),
            ),
          if (message.body.isNotEmpty) Text(message.body, style: theme.textTheme.bodyLarge),
        ],
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onRetry,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
            if (message.allReactions.isNotEmpty) _Reactions(list: message.allReactions),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.onSend,
    required this.onAttach,
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onVoice;

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
            IconButton(
              key: const ValueKey<String>('chat_allega'),
              onPressed: onAttach,
              icon: const Icon(Icons.attach_file_rounded),
              tooltip: 'Allega',
            ),
            Expanded(
              child: TextField(
                key: const ValueKey<String>('chat_testo'),
                controller: controller,
                focusNode: focus,
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
              key: ValueKey<String>(canSend ? 'chat_invia' : 'chat_vocale'),
              onPressed: canSend ? onSend : onVoice,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.brandOrange,
                foregroundColor: Colors.white,
                fixedSize: const Size(48, 48),
              ),
              icon: Icon(canSend ? Icons.send_rounded : Icons.mic_rounded),
              tooltip: canSend ? 'Invia' : 'Registra un vocale',
            ),
          ],
        ),
      ),
    );
  }
}

/// Citazione dentro il fumetto di una risposta.
class _QuoteBox extends StatelessWidget {
  const _QuoteBox({required this.author, required this.text, required this.mine});

  final String author;
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = author == 'Tu' ? AppColors.brandOrange : AppColors.brandBlue;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: mine ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(author, style: theme.textTheme.labelMedium?.copyWith(color: accent, fontWeight: FontWeight.w700)),
          Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Reazioni sotto il fumetto: ogni emoji con quante persone l'hanno messa.
class _Reactions extends StatelessWidget {
  const _Reactions({required this.list});

  final List<String> list;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, int> count = <String, int>{};
    for (final String e in list) {
      count[e] = (count[e] ?? 0) + 1;
    }
    final String shown = count.entries.map((e) => e.value > 1 ? '${e.key} ${e.value}' : e.key).join(' ');
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Container(
        key: const ValueKey<String>('reazioni'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(shown, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

/// Barra «Rispondi a…» sopra il campo di testo.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.author, required this.text, required this.onClose});

  final String author;
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = author == 'Tu' ? AppColors.brandOrange : AppColors.brandBlue;
    return Container(
      key: const ValueKey<String>('risposta_barra'),
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rispondi a $author',
                    style: theme.textTheme.labelMedium?.copyWith(color: accent, fontWeight: FontWeight.w700)),
                Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey<String>('risposta_chiudi'),
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Annulla risposta',
          ),
        ],
      ),
    );
  }
}

/// Foglio delle azioni su un messaggio. Restituisce la scelta.
class _MessageActions extends StatelessWidget {
  const _MessageActions({required this.message, required this.now});

  final ChatMessage message;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool text = message.isText;
    final bool sent = message.serverId != null;
    Widget action(String key, IconData icon, String label, {Color? color}) => ListTile(
      key: ValueKey<String>('azione_$key'),
      leading: Icon(icon, color: color),
      title: Text(label, style: color == null ? null : TextStyle(color: color)),
      onTap: () => Navigator.of(context).pop(key),
    );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text && sent)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final String e in chatReactions)
                    InkWell(
                      key: ValueKey<String>('reazione_$e'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.of(context).pop('reazione:$e'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: message.myReaction == e
                              ? AppColors.brandOrange.withValues(alpha: 0.18)
                              : Colors.transparent,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
          if (text && sent) action('rispondi', Icons.reply_rounded, 'Rispondi'),
          if (text && message.body.isNotEmpty) action('copia', Icons.copy_rounded, 'Copia'),
          if (text && sent) action('inoltra', Icons.shortcut_rounded, 'Inoltra'),
          action('elimina', Icons.delete_outline_rounded, 'Elimina', color: theme.colorScheme.error),
        ],
      ),
    );
  }
}

/// «Inoltra»: scegli fino a 5 chat.
class ForwardScreen extends StatefulWidget {
  const ForwardScreen({super.key, required this.chat, required this.message, this.profiles});

  final ChatService chat;
  final ChatMessage message;
  final ProfileRepository? profiles;

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  final Set<String> _chosen = <String>{};
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await widget.chat.forward(widget.message, _chosen.toList());
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(_chosen.length == 1 ? 'Messaggio inoltrato' : 'Messaggio inoltrato a ${_chosen.length} chat'),
      ));
    } on ChatFailure catch (f) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ChatThread> threads = widget.chat.threads;
    return Scaffold(
      appBar: AppBar(title: const Text('Inoltra a…')),
      body: ListView(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(widget.message.body, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
          for (final ChatThread t in threads)
            CheckboxListTile(
              key: ValueKey<String>('inoltra_${t.conversation.id}'),
              value: _chosen.contains(t.conversation.id),
              onChanged: _sending || (!_chosen.contains(t.conversation.id) && _chosen.length >= 5)
                  ? null
                  : (bool? v) => setState(() {
                      if (v ?? false) {
                        _chosen.add(t.conversation.id);
                      } else {
                        _chosen.remove(t.conversation.id);
                      }
                    }),
              secondary: t.conversation.isGroup
                  ? GroupAvatar(chat: widget.chat, conversation: t.conversation, size: 40)
                  : AvatarView(
                      name: t.conversation.peerName,
                      repository: widget.profiles,
                      path: t.conversation.peerAvatarPath,
                      size: 40,
                    ),
              title: Text(t.conversation.displayName),
              subtitle: Text(t.conversation.isGroup
                  ? 'Gruppo · ${t.conversation.members} membri'
                  : '@${t.conversation.peerUsername}'),
            ),
          if (threads.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nessuna chat a cui inoltrare')),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          key: const ValueKey<String>('inoltra_invia'),
          onPressed: _chosen.isEmpty || _sending ? null : _send,
          icon: const Icon(Icons.send_rounded),
          label: Text(_chosen.isEmpty ? 'Scegli fino a 5 chat' : 'Inoltra (${_chosen.length})'),
        ),
      ),
    );
  }
}

/// Scelta dell'allegato.
class _AttachSheet extends StatelessWidget {
  const _AttachSheet();

  @override
  Widget build(BuildContext context) {
    Widget item(String key, IconData icon, String label, Color color) => Expanded(
      child: InkWell(
        key: ValueKey<String>('allega_$key'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pop(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color,
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                item('galleria', Icons.photo_library_rounded, 'Galleria', const Color(0xFF7C4DFF)),
                item('fotocamera', Icons.photo_camera_rounded, 'Fotocamera', AppColors.brandOrange),
                item('video', Icons.videocam_rounded, 'Video', const Color(0xFFE53935)),
                item('documento', Icons.description_rounded, 'Documento', AppColors.brandBlue),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Gli allegati sono cifrati sul telefono prima di partire. Massimo 50 MB.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra della registrazione del vocale: puntino rosso, tempo, annulla e invia.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({required this.since, required this.onCancel, required this.onSend});

  final DateTime since;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int ms = DateTime.now().difference(since).inMilliseconds;
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey<String>('registrazione'),
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey<String>('registrazione_annulla'),
              onPressed: onCancel,
              icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
              tooltip: 'Annulla',
            ),
            const Icon(Icons.fiber_manual_record_rounded, color: Color(0xFFE53935), size: 14),
            const SizedBox(width: 6),
            Text(formatDuration(ms), style: theme.textTheme.titleMedium),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Registrazione… (max 5 min)',
                  style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ),
            IconButton.filled(
              key: const ValueKey<String>('registrazione_invia'),
              onPressed: onSend,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.brandOrange,
                foregroundColor: Colors.white,
                fixedSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Invia il vocale',
            ),
          ],
        ),
      ),
    );
  }
}

/// Colore del nome di chi scrive nel gruppo (sempre lo stesso per la stessa persona).
Color senderColor(String userId) {
  const List<Color> palette = <Color>[
    Color(0xFF1E88E5), Color(0xFF8E24AA), Color(0xFF43A047), Color(0xFFE53935),
    Color(0xFFFB8C00), Color(0xFF00897B), Color(0xFF6D4C41), Color(0xFF3949AB),
  ];
  int h = 0;
  for (final int c in userId.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Nel gruppo ma non ancora nel gruppo cifrato: un amministratore lo farà da solo.
class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('gruppo_attesa'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 20, color: AppColors.brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Stai entrando nel gruppo cifrato: succede da solo appena un amministratore apre l\'app.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

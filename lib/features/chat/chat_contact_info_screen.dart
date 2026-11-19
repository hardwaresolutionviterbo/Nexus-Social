import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/piazly_ui.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_models.dart';
import '../profile/profile_repository.dart';
import '../profile/public_profile_screen.dart' show OpenLink, openExternally;
import 'chat_models.dart';
import 'chat_safety_screens.dart';
import 'chat_service.dart';

/// «Info contatto», come su WhatsApp: si apre toccando nome o foto in alto nella chat a due.
/// Foto grande, nome come in rubrica, @nome utente, online, numero (se la persona lo rende
/// visibile), bio e social (se li mostra), chiamate, notifiche, incontro, blocca e segnala.
class ChatContactInfoScreen extends StatefulWidget {
  const ChatContactInfoScreen({
    super.key,
    required this.chat,
    required this.conversationId,
    this.profiles,
    this.onCall,
    this.onMute,
    this.openLink = openExternally,
  });

  final ChatService chat;
  final String conversationId;
  final ProfileRepository? profiles;

  /// Chiamata vocale o video (la fa la chat: torna indietro e chiama).
  final void Function({required bool video})? onCall;

  /// Silenzia o riattiva (stesse scelte del menu della chat).
  final Future<void> Function()? onMute;
  final OpenLink openLink;

  @override
  State<ChatContactInfoScreen> createState() => _ChatContactInfoScreenState();
}

class _ChatContactInfoScreenState extends State<ChatContactInfoScreen> {
  PublicProfile? _profile;
  ChatContact? _contact;
  Presence? _presence;

  ChatConversation? get _c => widget.chat.conversation(widget.conversationId);

  @override
  void initState() {
    super.initState();
    final ChatConversation? c = _c;
    if (c == null) return;
    widget.profiles?.fetchPublic(c.peerId).then((PublicProfile? p) {
      if (mounted) setState(() => _profile = p);
    }, onError: (Object _) {});
    widget.chat.contacts().then((List<ChatContact> l) {
      final ChatContact? me = l.where((ChatContact x) => x.id == c.peerId).firstOrNull;
      if (mounted) setState(() => _contact = me);
    }, onError: (Object _) {});
    widget.chat.presence(c.peerId).then((Presence? p) {
      if (mounted) setState(() => _presence = p);
    }, onError: (Object _) {});
  }

  Future<void> _block(ChatConversation c) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Bloccare ${c.displayName}?'),
        content: const Text(
          'Non potrà più scriverti, chiamarti, vedere i tuoi stati, il tuo ultimo accesso né la '
          'tua posizione. Non riceverà nessun avviso. Puoi sbloccarlo da Privacy.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(
            key: const ValueKey<String>('info_conferma_blocco'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Blocca'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.chat.blockPeer(c.id);
      messenger?.showSnackBar(SnackBar(content: Text('${c.displayName} è bloccato.')));
      // Chiude la scheda e la chat.
      nav
        ..pop()
        ..pop();
    } on ChatFailure catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(content: Text('Non è stato possibile: riprova tra poco.')));
    }
  }

  Widget _action(String key, IconData icon, String label, VoidCallback? onTap) => Expanded(
    child: SoftCard(
      key: ValueKey<String>(key),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      radius: 18,
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: onTap == null ? Colors.grey : AppColors.brandOrange),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.chat,
    builder: (BuildContext context, _) {
      final ThemeData theme = Theme.of(context);
      final ChatConversation? c = _c;
      if (c == null) {
        return Scaffold(appBar: AppBar(), body: const Center(child: Text('Chat non più disponibile')));
      }
      final PublicProfile? p = _profile;
      final String? pres = presenceLabel(_presence, DateTime.now());
      final String? phone = _contact?.phone;
      final String piazlyName = p?.publicName ?? '';
      return Scaffold(
        appBar: AppBar(title: const Text('Info contatto')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.orangeGradient),
                child: AvatarView(
                  name: c.displayName,
                  repository: widget.profiles,
                  path: p?.avatarPath ?? c.peerAvatarPath,
                  size: 132,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              c.displayName,
              key: const ValueKey<String>('info_nome'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              '@${c.peerUsername}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (piazlyName.isNotEmpty && piazlyName != c.displayName)
              Text(
                'Su Piazly: $piazlyName',
                key: const ValueKey<String>('info_nome_piazly'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            if (pres != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  pres,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _presence?.online == true ? PiazlyColors.green : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                _action('info_chiama', Icons.call_outlined, 'Chiama',
                    widget.onCall == null || c.isRequest ? null : () => widget.onCall!(video: false)),
                _action('info_video', Icons.videocam_outlined, 'Video',
                    widget.onCall == null || c.isRequest ? null : () => widget.onCall!(video: true)),
                _action(
                  'info_notifiche',
                  c.isMuted ? Icons.notifications_off_outlined : Icons.notifications_none_rounded,
                  c.isMuted ? 'Silenziata' : 'Silenzia',
                  widget.onMute == null || c.isRequest ? null : () => widget.onMute!(),
                ),
              ],
            ),
            if (phone != null && phone.isNotEmpty)
              MenuCard(
                key: const ValueKey<String>('info_numero'),
                icon: Icons.phone_rounded,
                color: PiazlyColors.green,
                title: phone,
                subtitle: 'Numero di telefono',
                trailing: const SizedBox.shrink(),
              ),
            if (p?.bio != null && p!.bio!.trim().isNotEmpty)
              SoftCard(
                key: const ValueKey<String>('info_bio'),
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Info', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(p.bio!, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
            if (p != null && p.social.isNotEmpty)
              SoftCard(
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final MapEntry<SocialNetwork, String> e in p.social.entries)
                      ActionChip(
                        key: ValueKey<String>('info_social_${e.key.name}'),
                        avatar: const Icon(Icons.link_rounded, size: 18),
                        label: Text('${e.key.label} · ${e.value}'),
                        onPressed: () => widget.openLink(Uri.parse(e.key.profileUrl(e.value))),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            if (!c.isRequest)
              MenuCard(
                key: const ValueKey<String>('info_incontro'),
                icon: Icons.shield_outlined,
                title: 'Condividi l\'incontro',
                subtitle: 'Avvisa una persona di fiducia quando vi vedete',
                onTap: () => ShareMeetingScreen.open(
                  context,
                  widget.chat,
                  withName: '${c.displayName} (@${c.peerUsername})',
                  excludeId: c.peerId,
                ),
              ),
            MenuCard(
              key: const ValueKey<String>('info_blocca'),
              icon: Icons.block_rounded,
              color: theme.colorScheme.error,
              title: 'Blocca ${c.displayName}',
              onTap: () => _block(c),
            ),
            MenuCard(
              key: const ValueKey<String>('info_segnala'),
              icon: Icons.flag_outlined,
              color: theme.colorScheme.error,
              title: 'Segnala ${c.displayName}',
              onTap: () async {
                final bool? done = await ReportChatScreen.open(context, widget.chat, c.id);
                if (done == true && context.mounted && widget.chat.conversation(c.id) == null) {
                  Navigator.of(context)
                    ..pop()
                    ..pop();
                }
              },
            ),
          ],
        ),
      );
    },
  );
}

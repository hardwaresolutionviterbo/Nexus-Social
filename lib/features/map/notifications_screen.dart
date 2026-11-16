import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'comments_screen.dart';
import 'listing_models.dart' show publishedLabel;
import 'listing_repository.dart';
import 'social_models.dart';
import 'social_repository.dart';

/// Campanella dell'app (Fase 3): Mi piace (raggruppati), commenti, risposte e commenti sui
/// post seguiti. All'apertura le notifiche risultano lette; toccandone una si apre il post
/// sul commento. Le push con l'app chiusa arrivano con il server attivo (Fase 4).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.repository,
    this.now = DateTime.now,
    this.openSwaps,
    this.openDeals,
  });

  final SocialRepository repository;
  final DateTime Function() now;

  /// Apre le proposte di scambio (Fase 5, Blocco 3); null se Scambia & Vendi non c'è.
  final Future<void> Function(BuildContext context)? openSwaps;

  /// Apre conclusioni e feedback (Fase 5, Blocco 4).
  final Future<void> Function(BuildContext context)? openDeals;

  static Future<void> open(
    BuildContext context,
    SocialRepository repository, {
    Future<void> Function(BuildContext context)? openSwaps,
    Future<void> Function(BuildContext context)? openDeals,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) =>
          NotificationsScreen(repository: repository, openSwaps: openSwaps, openDeals: openDeals),
    ),
  );

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<AppNotification> items = await widget.repository.notifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
      if (items.any((AppNotification n) => !n.read)) await widget.repository.markAllRead();
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (n.kind.isSwap || n.kind.isDeal) {
      final Future<void> Function(BuildContext)? open = n.kind.isSwap ? widget.openSwaps : widget.openDeals;
      if (open != null) await open(context);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CommentsScreen(
          listingId: n.listingId,
          listingTitle: n.listingTitle,
          repository: widget.repository,
          highlightCommentId: n.commentId,
          now: widget.now,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _items = <AppNotification>[
          for (final AppNotification x in _items ?? const <AppNotification>[]) x.markedRead(),
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AppNotification>? items = _items;
    final DateTime now = widget.now();
    Widget body;
    if (_error != null) {
      body = Center(child: Text(_error!));
    } else if (items == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nessuna notifica per ora', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Qui arrivano i Mi piace, i commenti e le risposte ai tuoi annunci e ai post '
                'che segui.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (BuildContext context, int i) {
            final AppNotification n = items[i];
            return ListTile(
              key: ValueKey<String>('notifica_${n.id}'),
              tileColor: n.read ? null : AppColors.brandOrange.withValues(alpha: 0.07),
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.brandOrange,
                    foregroundColor: Colors.white,
                    child: Text(n.actor.initial),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: theme.colorScheme.surface,
                      child: Icon(_icon(n.kind), size: 14, color: AppColors.brandOrangeDeep),
                    ),
                  ),
                ],
              ),
              title: Text(n.text, style: theme.textTheme.bodyMedium),
              subtitle: Text(
                publishedLabel(n.createdAt, now).replaceFirst('pubblicato ', ''),
                style: theme.textTheme.labelSmall,
              ),
              onTap: () => _open(n),
            );
          },
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Notifiche')), body: body);
  }

  static IconData _icon(NotificationKind k) => switch (k) {
    NotificationKind.listingLike || NotificationKind.commentLike => Icons.thumb_up_alt_rounded,
    NotificationKind.commentReply => Icons.reply_rounded,
    NotificationKind.listingComment || NotificationKind.followedComment => Icons.mode_comment_rounded,
    NotificationKind.swapProposal || NotificationKind.swapCounter => Icons.swap_horiz_rounded,
    NotificationKind.swapAccepted || NotificationKind.dealConfirm || NotificationKind.dealCompleted =>
      Icons.handshake_rounded,
    NotificationKind.feedbackReceived => Icons.star_rounded,
  };
}

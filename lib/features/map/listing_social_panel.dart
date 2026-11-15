import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'comments_screen.dart';
import 'listing_models.dart';
import 'listing_repository.dart';
import 'listing_share.dart';
import 'social_models.dart';
import 'social_repository.dart';

/// Sotto ogni annuncio, come Facebook (decisione del titolare): evento di gruppo con
/// «Partecipo», Mi piace / Non mi piace con i conteggi e gli elenchi, Commenta, Condividi,
/// «Disattiva notifiche per questo post».
class ListingSocialPanel extends StatefulWidget {
  const ListingSocialPanel({
    super.key,
    required this.listing,
    required this.listings,
    this.social,
    this.share = shareWithSystem,
  });

  final NearbyListing listing;
  final MapListingRepository listings;

  /// null finché il server delle interazioni non c'è: resta solo «Condividi».
  final SocialRepository? social;
  final ShareListing share;

  @override
  State<ListingSocialPanel> createState() => _ListingSocialPanelState();
}

class _ListingSocialPanelState extends State<ListingSocialPanel> {
  ListingSocial? _s;
  bool _busy = false;

  NearbyListing get _l => widget.listing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SocialRepository? repo = widget.social;
    if (repo == null) return;
    try {
      final ListingSocial s = await repo.social(_l.id);
      if (mounted) setState(() => _s = s);
    } on ListingFailure catch (f) {
      _toast(f.message);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ListingFailure catch (f) {
      _toast(f.message);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _react(Reaction r) => _guarded(() async {
    final ListingSocial s = _s ?? const ListingSocial();
    final Reaction? next = s.myReaction == r ? null : r;
    setState(() => _s = s.withReaction(next));
    await widget.social!.react(_l.id, next);
  });

  Future<void> _toggleParticipation() => _guarded(() async {
    final ListingSocial s = _s!;
    if (s.iParticipate) {
      await widget.social!.leave(_l.id);
    } else {
      await widget.social!.join(_l.id);
    }
    await _load();
  });

  Future<void> _toggleMuted() => _guarded(() async {
    final bool muted = !(_s?.muted ?? false);
    await widget.social!.setMuted(_l.id, muted);
    setState(() => _s = _s?.copyWith(muted: muted));
    _toast(muted ? 'Notifiche disattivate per questo post.' : 'Notifiche riattivate per questo post.');
  });

  Future<void> _showPeople(PeopleList list) async {
    final SocialRepository repo = widget.social!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => PeopleSheet(load: () => repo.people(_l.id, list), title: list.title),
    );
  }

  Future<void> _openComments() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CommentsScreen(
          listingId: _l.id,
          listingTitle: _l.title,
          repository: widget.social!,
        ),
      ),
    );
    await _load();
  }

  Future<void> _share() async {
    Uint8List? photo;
    if (_l.photos.isNotEmpty) photo = await widget.listings.downloadPhoto(_l.photos.first);
    await widget.share(ListingShare.text(_l, social: _s), photo: photo);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ListingSocial? s = _s;
    final bool server = widget.social != null;
    final Widget shareButton = _ActionButton(
      key: const ValueKey<String>('condividi'),
      icon: Icons.share_outlined,
      label: 'Condividi',
      onTap: _share,
    );
    if (!server) return Row(children: [Expanded(child: shareButton)]);
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.isEvent) ...[
          _EventCard(
            social: s,
            mine: _l.isMine,
            busy: _busy,
            onToggle: _toggleParticipation,
            onShowParticipants: () => _showPeople(PeopleList.participants),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        // Conteggi, come sotto un post di Facebook: toccandoli si vede chi.
        Wrap(
          spacing: 14,
          children: [
            _CountLink(
              key: const ValueKey<String>('conteggio_mi_piace'),
              icon: Icons.thumb_up_alt_rounded,
              text: '${s.likes}',
              onTap: s.likes > 0 ? () => _showPeople(PeopleList.likes) : null,
            ),
            _CountLink(
              key: const ValueKey<String>('conteggio_non_mi_piace'),
              icon: Icons.thumb_down_alt_rounded,
              text: '${s.dislikes}',
              onTap: s.dislikes > 0 ? () => _showPeople(PeopleList.dislikes) : null,
            ),
            _CountLink(
              key: const ValueKey<String>('conteggio_commenti'),
              icon: Icons.mode_comment_outlined,
              text: s.comments == 1 ? '1 commento' : '${s.comments} commenti',
              onTap: _openComments,
            ),
          ],
        ),
        Divider(height: 18, color: scheme.outlineVariant),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                key: const ValueKey<String>('mi_piace'),
                icon: s.myReaction == Reaction.like
                    ? Icons.thumb_up_alt_rounded
                    : Icons.thumb_up_alt_outlined,
                label: 'Mi piace',
                active: s.myReaction == Reaction.like,
                onTap: () => _react(Reaction.like),
              ),
            ),
            Expanded(
              child: _ActionButton(
                key: const ValueKey<String>('non_mi_piace'),
                icon: s.myReaction == Reaction.dislike
                    ? Icons.thumb_down_alt_rounded
                    : Icons.thumb_down_alt_outlined,
                label: 'Non mi piace',
                active: s.myReaction == Reaction.dislike,
                onTap: () => _react(Reaction.dislike),
              ),
            ),
            Expanded(
              child: _ActionButton(
                key: const ValueKey<String>('commenta'),
                icon: Icons.mode_comment_outlined,
                label: 'Commenta',
                onTap: _openComments,
              ),
            ),
            Expanded(child: shareButton),
          ],
        ),
        if (_l.isMine || s.following)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey<String>('silenzia_post'),
              onPressed: _toggleMuted,
              icon: Icon(
                s.muted ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
                size: 18,
              ),
              label: Text(
                s.muted ? 'Riattiva notifiche per questo post' : 'Disattiva notifiche per questo post',
              ),
            ),
          ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.social,
    required this.mine,
    required this.busy,
    required this.onToggle,
    required this.onShowParticipants,
  });

  final ListingSocial social;
  final bool mine;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onShowParticipants;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ListingSocial s = social;
    return Container(
      key: const ValueKey<String>('evento_gruppo'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandMint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  missingLabel(s.groupSpots!, s.participants),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: s.participants > 0 ? onShowParticipants : null,
            child: Text(
              '${s.participants} su ${s.groupSpots} '
              '${s.participants == 1 ? 'partecipa' : 'partecipano'}',
              style: theme.textTheme.bodySmall?.copyWith(
                decoration: s.participants > 0 ? TextDecoration.underline : null,
              ),
            ),
          ),
          if (!mine) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: s.iParticipate
                  ? OutlinedButton.icon(
                      key: const ValueKey<String>('non_partecipo'),
                      onPressed: busy ? null : onToggle,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Partecipi · Non partecipo più'),
                    )
                  : FilledButton.icon(
                      key: const ValueKey<String>('partecipo'),
                      onPressed: busy || s.full ? null : onToggle,
                      icon: const Icon(Icons.how_to_reg_rounded),
                      label: Text(s.full ? 'Al completo' : 'Partecipo'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountLink extends StatelessWidget {
  const _CountLink({super.key, required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(text, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: active ? FontWeight.w800 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Elenco di persone (chi ha reagito, chi partecipa): nome abbreviato e @username.
class PeopleSheet extends StatelessWidget {
  const PeopleSheet({super.key, required this.load, required this.title});

  final Future<List<PersonRef>> Function() load;
  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FutureBuilder<List<PersonRef>>(
      future: load(),
      builder: (BuildContext context, AsyncSnapshot<List<PersonRef>> snap) {
        final List<PersonRef>? people = snap.data;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              if (snap.hasError)
                const Text('Elenco non disponibile.')
              else if (people == null)
                const Center(child: CircularProgressIndicator())
              else if (people.isEmpty)
                const Text('Ancora nessuno.')
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final PersonRef p in people)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.brandOrange,
                            foregroundColor: Colors.white,
                            child: Text(p.initial),
                          ),
                          title: Text(p.publicName),
                          subtitle: Text('@${p.username}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

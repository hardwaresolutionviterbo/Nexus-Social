import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'listing_models.dart' show publishedLabel;
import 'listing_repository.dart';
import 'social_models.dart';
import 'social_repository.dart';

/// Commenti di un annuncio, come Facebook: commenti principali con le risposte sotto,
/// «Mi piace» e «Rispondi» su ogni commento, «Elimina» per i propri (e per l'autore
/// dell'annuncio su tutti). Chi commenta segue il post e riceve gli avvisi successivi.
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({
    super.key,
    required this.listingId,
    required this.listingTitle,
    required this.repository,
    this.highlightCommentId,
    this.now = DateTime.now,
  });

  final String listingId;
  final String listingTitle;
  final SocialRepository repository;

  /// Commento da evidenziare (aperto da una notifica).
  final String? highlightCommentId;
  final DateTime Function() now;

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<ListingComment>? _items;
  String? _error;
  ListingComment? _replyTo;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<ListingComment> items = await widget.repository.comments(widget.listingId);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _send() async {
    final String body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.repository.addComment(widget.listingId, body, parentId: _replyTo?.id);
      _text.clear();
      setState(() => _replyTo = null);
      await _load();
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(ListingComment c) async {
    try {
      await widget.repository.likeComment(c.id, !c.likedByMe);
      await _load();
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _delete(ListingComment c) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Eliminare il commento?'),
        content: const Text('Si eliminano anche le risposte.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Elimina')),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    try {
      await widget.repository.deleteComment(c.id);
      await _load();
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  void _reply(ListingComment c) {
    setState(() => _replyTo = c);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ListingComment>? items = _items;
    final DateTime now = widget.now();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Commenti'),
            Text(
              widget.listingTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Expanded(
            child: items == null
                ? (_error == null
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink())
                : items.isEmpty
                ? const Center(child: Text('Ancora nessun commento: scrivi il primo.'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      for (final (ListingComment root, List<ListingComment> replies)
                          in threadComments(items)) ...[
                        _CommentTile(
                          comment: root,
                          now: now,
                          highlighted: root.id == widget.highlightCommentId,
                          onLike: () => _toggleLike(root),
                          onReply: () => _reply(root),
                          onDelete: root.canDelete ? () => _delete(root) : null,
                        ),
                        for (final ListingComment r in replies)
                          Padding(
                            padding: const EdgeInsets.only(left: 44),
                            child: _CommentTile(
                              comment: r,
                              now: now,
                              highlighted: r.id == widget.highlightCommentId,
                              onLike: () => _toggleLike(r),
                              // Si risponde sempre nel filo del commento principale.
                              onReply: () => _reply(r),
                              onDelete: r.canDelete ? () => _delete(r) : null,
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Material(
              elevation: 6,
              color: theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyTo != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Rispondi a ${_replyTo!.author.publicName}',
                              key: const ValueKey<String>('risposta_a'),
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Annulla risposta',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _replyTo = null),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey<String>('nuovo_commento'),
                            controller: _text,
                            focusNode: _focus,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: SocialRules.commentMax,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Scrivi un commento…',
                              counterText: '',
                            ),
                          ),
                        ),
                        IconButton.filled(
                          key: const ValueKey<String>('invia_commento'),
                          tooltip: 'Invia',
                          onPressed: _sending ? null : _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.now,
    required this.highlighted,
    required this.onLike,
    required this.onReply,
    this.onDelete,
  });

  final ListingComment comment;
  final DateTime now;
  final bool highlighted;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ListingComment c = comment;
    final String when = publishedLabel(c.createdAt, now).replaceFirst('pubblicato ', '');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.brandOrange,
            foregroundColor: Colors.white,
            child: Text(c.author.initial, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  key: ValueKey<String>('commento_${c.id}'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  decoration: BoxDecoration(
                    color: highlighted
                        ? AppColors.brandAmber.withValues(alpha: 0.25)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.author.publicName, style: theme.textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(c.body, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 2,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8, right: 4),
                      child: Text(when, style: theme.textTheme.labelSmall),
                    ),
                    TextButton(
                      onPressed: onLike,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: c.likedByMe ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      child: Text(c.likes > 0 ? 'Mi piace · ${c.likes}' : 'Mi piace'),
                    ),
                    TextButton(
                      onPressed: onReply,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                      child: const Text('Rispondi'),
                    ),
                    if (onDelete != null)
                      TextButton(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: scheme.error,
                        ),
                        child: const Text('Elimina'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

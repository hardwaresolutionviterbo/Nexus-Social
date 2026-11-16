import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../map/listing_repository.dart' show ListingFailure;
import 'market_models.dart';
import 'market_repository.dart';

/// Stelle piene e vuote (da 1 a 5).
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 18});

  final num stars;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (int i = 1; i <= 5; i++)
        Icon(
          stars >= i
              ? Icons.star_rounded
              : (stars >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
          size: size,
          color: const Color(0xFFF2A516),
        ),
    ],
  );
}

/// Media dei feedback di una persona; toccando si apre l'elenco (Blocco 4).
class FeedbackSummaryTile extends StatefulWidget {
  const FeedbackSummaryTile({
    super.key,
    required this.repository,
    required this.userId,
    required this.name,
    this.dense = false,
  });

  final MarketRepository repository;
  final String userId;
  final String name;
  final bool dense;

  @override
  State<FeedbackSummaryTile> createState() => _FeedbackSummaryTileState();
}

class _FeedbackSummaryTileState extends State<FeedbackSummaryTile> {
  late final Future<FeedbackSummary> _summary = widget.repository
      .feedbackSummary(widget.userId)
      .catchError((Object _) => const FeedbackSummary());

  @override
  Widget build(BuildContext context) => FutureBuilder<FeedbackSummary>(
    future: _summary,
    builder: (BuildContext context, AsyncSnapshot<FeedbackSummary> snap) {
      final FeedbackSummary s = snap.data ?? const FeedbackSummary();
      final ThemeData theme = Theme.of(context);
      return InkWell(
        key: ValueKey<String>('feedback_di_${widget.userId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => FeedbackListScreen(
              repository: widget.repository,
              userId: widget.userId,
              name: widget.name,
              summary: s,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.dense ? 2 : 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarRow(stars: s.average ?? 0, size: widget.dense ? 16 : 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  s.label,
                  style: (widget.dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Elenco dei feedback ricevuti da una persona, 20 alla volta.
class FeedbackListScreen extends StatefulWidget {
  const FeedbackListScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.name,
    this.summary,
  });

  final MarketRepository repository;
  final String userId;
  final String name;
  final FeedbackSummary? summary;

  @override
  State<FeedbackListScreen> createState() => _FeedbackListScreenState();
}

class _FeedbackListScreenState extends State<FeedbackListScreen> {
  final List<FeedbackEntry> _items = <FeedbackEntry>[];
  bool _loading = true;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    setState(() => _loading = true);
    try {
      final List<FeedbackEntry> page =
          await widget.repository.feedbackList(widget.userId, offset: _items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= MarketQuery.pageSize;
      });
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FeedbackSummary? s = widget.summary;
    return Scaffold(
      appBar: AppBar(title: Text('Feedback di ${widget.name}')),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          if (s != null) ...[
            Row(
              children: [
                StarRow(stars: s.average ?? 0, size: 26),
                const SizedBox(width: 8),
                Expanded(child: Text(s.label, style: theme.textTheme.titleMedium)),
              ],
            ),
            if (s.completedDeals > 0)
              Text(
                '${s.completedDeals} ${s.completedDeals == 1 ? 'scambio o vendita conclusa' : 'scambi e vendite conclusi'}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          if (!_loading && _items.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Ancora nessun feedback.', textAlign: TextAlign.center),
            ),
          for (final FeedbackEntry f in _items)
            Card(
              key: ValueKey<String>('voce_${f.id}'),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StarRow(stars: f.stars),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _date(f.createdAt),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (f.comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(f.comment, style: theme.textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${f.authorPublicName} (@${f.authorUsername}) · «${f.listingTitle}» · ${f.roleLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (_hasMore)
            Center(
              child: TextButton(
                key: const ValueKey<String>('feedback_altri'),
                onPressed: _more,
                child: const Text('Mostra altri'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lascia un feedback: 1-5 stelle e un commento facoltativo; poi non si modifica.
/// Restituisce true se inviato.
class LeaveFeedbackScreen extends StatefulWidget {
  const LeaveFeedbackScreen({super.key, required this.repository, required this.deal});

  final MarketRepository repository;
  final MarketDeal deal;

  @override
  State<LeaveFeedbackScreen> createState() => _LeaveFeedbackScreenState();
}

class _LeaveFeedbackScreenState extends State<LeaveFeedbackScreen> {
  int _stars = 0;
  final TextEditingController _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_stars < 1) {
      setState(() => _error = 'Scegli da 1 a 5 stelle.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.leaveFeedback(widget.deal.id, _stars, _comment.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MarketDeal d = widget.deal;
    return Scaffold(
      appBar: AppBar(title: const Text('Lascia un feedback')),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          Text('Com\'è andata con ${d.otherPublicName}?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Per «${d.listingTitle}»', style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 1; i <= 5; i++)
                IconButton(
                  key: ValueKey<String>('stella_$i'),
                  iconSize: 44,
                  tooltip: '$i ${i == 1 ? 'stella' : 'stelle'}',
                  onPressed: () => setState(() {
                    _stars = i;
                    _error = null;
                  }),
                  icon: Icon(
                    i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFF2A516),
                  ),
                ),
            ],
          ),
          Center(
            child: Text(
              switch (_stars) {
                1 => 'Pessima',
                2 => 'Non buona',
                3 => 'Nella media',
                4 => 'Buona',
                5 => 'Ottima',
                _ => 'Tocca le stelle',
              },
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey<String>('feedback_commento'),
            controller: _comment,
            maxLength: FeedbackRules.commentMax,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Commento (facoltativo)'),
          ),
          Text(
            'Il feedback sarà visibile sul profilo di ${d.otherPublicName} e non potrai modificarlo.',
            style: theme.textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              key: const ValueKey<String>('feedback_errore'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: FilledButton(
          key: const ValueKey<String>('feedback_invia'),
          onPressed: _busy ? null : _send,
          child: const Text('Invia feedback'),
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../map/listing_repository.dart' show ListingFailure;
import 'market_feedback.dart';
import 'market_models.dart';
import 'market_repository.dart';

/// Conclusioni e feedback (Blocco 4): da confermare, in attesa dell'altra persona, concluse
/// (con «Lascia un feedback»), non concluse.
class MarketDealsScreen extends StatefulWidget {
  const MarketDealsScreen({super.key, required this.repository});

  final MarketRepository repository;

  static Future<void> open(BuildContext context, MarketRepository repository) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => MarketDealsScreen(repository: repository)),
      );

  @override
  State<MarketDealsScreen> createState() => _MarketDealsScreenState();
}

class _MarketDealsScreenState extends State<MarketDealsScreen> {
  List<MarketDeal>? _items;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<MarketDeal> items = await widget.repository.myDeals();
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

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _act(Future<String> Function() action, String Function(String) done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String r = await action();
      _toast(done(r));
    } on ListingFailure catch (f) {
      _toast(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<bool> _ask(String title, String text, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ok)),
          ],
        ),
      ) ??
      false;

  Future<void> _confirm(MarketDeal d) async {
    if (!await _ask(
      'Confermi che è avvenuto?',
      d.isSwap
          ? 'Lo scambio di «${d.listingTitle}» con ${d.otherPublicName} è stato fatto. '
                'Quando confermate entrambi, gli annunci si chiudono.'
          : '«${d.listingTitle}» con ${d.otherPublicName}: l\'annuncio si chiuderà.',
      'Confermo',
    )) {
      return;
    }
    await _act(
      () => d.isSwap
          ? widget.repository.confirmSwapConcluded(d.proposalId!)
          : widget.repository.answerDeal(d.id, confirm: true),
      (String r) => r == 'completed'
          ? 'Concluso! Ora potete lasciarvi un feedback.'
          : 'Confermato: aspettiamo ${d.otherPublicName}.',
    );
  }

  Future<void> _decline(MarketDeal d) async {
    if (!await _ask(
      'Non è avvenuto?',
      '${d.otherPublicName} potrà indicare un\'altra persona o riprovare.',
      'Non è avvenuto',
    )) {
      return;
    }
    await _act(
      () => widget.repository.answerDeal(d.id, confirm: false),
      (_) => 'Fatto: la conclusione non è avvenuta.',
    );
  }

  Future<void> _cancel(MarketDeal d) async {
    await _act(() async {
      await widget.repository.cancelDeal(d.id);
      return 'cancelled';
    }, (_) => 'Richiesta annullata.');
  }

  Future<void> _feedback(MarketDeal d) async {
    final bool? sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LeaveFeedbackScreen(repository: widget.repository, deal: d),
      ),
    );
    if ((sent ?? false) && mounted) {
      _toast('Grazie per il feedback!');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MarketDeal>? items = _items;
    final List<MarketDeal> toConfirm = items?.where((MarketDeal d) => d.toConfirm).toList() ?? const <MarketDeal>[];
    final List<MarketDeal> waiting = items?.where((MarketDeal d) => d.waiting).toList() ?? const <MarketDeal>[];
    final List<MarketDeal> done = items?.where((MarketDeal d) => d.completed).toList() ?? const <MarketDeal>[];
    final List<MarketDeal> failed =
        items?.where((MarketDeal d) => d.declined || d.cancelled).toList() ?? const <MarketDeal>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Conclusioni e feedback')),
      body: items == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: AppSpacing.pagePadding,
                children: [
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'Qui troverai gli scambi e le vendite da confermare e i feedback da lasciare.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (toConfirm.isNotEmpty) ...[
                    _Header('Da confermare', theme),
                    for (final MarketDeal d in toConfirm)
                      _DealCard(
                        deal: d,
                        busy: _busy,
                        actions: [
                          FilledButton(
                            key: ValueKey<String>('conferma_${d.id}'),
                            onPressed: _busy ? null : () => _confirm(d),
                            child: const Text('Confermo, è avvenuto'),
                          ),
                          if (!d.isSwap && !d.iAmOwner)
                            TextButton(
                              key: ValueKey<String>('non_avvenuto_${d.id}'),
                              onPressed: _busy ? null : () => _decline(d),
                              child: const Text('Non è avvenuto'),
                            ),
                        ],
                      ),
                  ],
                  if (waiting.isNotEmpty) ...[
                    _Header('In attesa dell\'altra persona', theme),
                    for (final MarketDeal d in waiting)
                      _DealCard(
                        deal: d,
                        busy: _busy,
                        actions: [
                          if (d.canCancel)
                            TextButton(
                              key: ValueKey<String>('annulla_conclusione_${d.id}'),
                              onPressed: _busy ? null : () => _cancel(d),
                              child: const Text('Annulla richiesta'),
                            ),
                        ],
                      ),
                  ],
                  if (done.isNotEmpty) ...[
                    _Header('Concluse', theme),
                    for (final MarketDeal d in done)
                      _DealCard(
                        deal: d,
                        busy: _busy,
                        actions: [
                          if (d.canLeaveFeedback)
                            FilledButton.icon(
                              key: ValueKey<String>('lascia_feedback_${d.id}'),
                              onPressed: () => _feedback(d),
                              icon: const Icon(Icons.star_rounded),
                              label: const Text('Lascia un feedback'),
                            ),
                        ],
                      ),
                  ],
                  if (failed.isNotEmpty) ...[
                    _Header('Non concluse', theme),
                    for (final MarketDeal d in failed) _DealCard(deal: d, busy: _busy, actions: const <Widget>[]),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, this.theme);

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
    child: Text(text, style: theme.textTheme.titleMedium),
  );
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.deal, required this.busy, required this.actions});

  final MarketDeal deal;
  final bool busy;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MarketDeal d = deal;
    final String who = '${d.otherPublicName} (@${d.otherUsername})';
    final String status = switch (d) {
      MarketDeal(completed: true) => 'Concluso',
      MarketDeal(declined: true) => 'Non avvenuto',
      MarketDeal(cancelled: true) => 'Richiesta annullata',
      MarketDeal(iConfirmed: true) => 'Hai confermato · manca $who',
      MarketDeal(otherConfirmed: true) => '$who ha confermato · manchi tu',
      _ => 'Da confermare',
    };
    return Card(
      key: ValueKey<String>('conclusione_${d.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('«${d.listingTitle}»', style: theme.textTheme.titleMedium),
            Text(
              '${d.isSwap ? 'Scambio' : d.listingType.label} con $who',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(status, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (d.completed) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Il tuo voto: ', style: theme.textTheme.bodySmall),
                  if (d.myStars != null) StarRow(stars: d.myStars!, size: 16) else Text('—', style: theme.textTheme.bodySmall),
                ],
              ),
              Row(
                children: [
                  Text('Ricevuto: ', style: theme.textTheme.bodySmall),
                  if (d.theirStars != null)
                    StarRow(stars: d.theirStars!, size: 16)
                  else
                    Text('non ancora', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

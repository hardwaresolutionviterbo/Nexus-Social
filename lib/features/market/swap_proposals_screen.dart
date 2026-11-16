import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../map/listing_repository.dart' show ListingFailure;
import 'market_deals_screen.dart';
import 'market_models.dart';
import 'market_publish_screen.dart' show MarketPhoto;
import 'market_repository.dart';
import 'swap_offer_screen.dart';

/// Proposte di scambio (Blocco 3): ricevute, inviate e storico, con accetta, rifiuta,
/// controproposta e annulla.
class SwapProposalsScreen extends StatefulWidget {
  const SwapProposalsScreen({super.key, required this.repository, this.now = DateTime.now});

  final MarketRepository repository;
  final DateTime Function() now;

  static Future<void> open(BuildContext context, MarketRepository repository) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => SwapProposalsScreen(repository: repository)),
      );

  @override
  State<SwapProposalsScreen> createState() => _SwapProposalsScreenState();
}

class _SwapProposalsScreenState extends State<SwapProposalsScreen> {
  List<SwapProposal>? _items;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<SwapProposal> items = await widget.repository.mySwaps();
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

  Future<void> _guarded(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _toast(done);
    } on ListingFailure catch (f) {
      _toast(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<bool> _confirm(String title, String text, String ok) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ok)),
        ],
      ),
    );
    return yes ?? false;
  }

  Future<void> _accept(SwapProposal p) async {
    if (!await _confirm(
      'Accettare la proposta?',
      'Vi accorderete su luogo e consegna nei commenti dell\'annuncio (la chat arriverà presto).',
      'Accetta',
    )) {
      return;
    }
    await _guarded(
      () => widget.repository.respondSwap(p.id, accept: true),
      'Proposta accettata.',
    );
  }

  Future<void> _reject(SwapProposal p) async {
    if (!await _confirm('Rifiutare la proposta?', 'L\'altra persona lo vedrà nelle sue proposte.', 'Rifiuta')) {
      return;
    }
    await _guarded(
      () => widget.repository.respondSwap(p.id, accept: false),
      'Proposta rifiutata.',
    );
  }

  Future<void> _cancel(SwapProposal p) async {
    if (!await _confirm('Annullare la proposta?', 'Potrai farne un\'altra in seguito.', 'Annulla proposta')) {
      return;
    }
    await _guarded(() => widget.repository.cancelSwap(p.id), 'Proposta annullata.');
  }

  Future<void> _conclude(SwapProposal p) async {
    if (!await _confirm(
      'Lo scambio è avvenuto?',
      'Quando lo confermate entrambi, gli annunci si chiudono e potrete lasciarvi un feedback.',
      'Confermo',
    )) {
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String r = await widget.repository.confirmSwapConcluded(p.id);
      _toast(r == 'completed'
          ? 'Scambio concluso! Lascia un feedback da «Conclusioni e feedback».'
          : 'Confermato: aspettiamo ${p.otherPublicName}.');
    } on ListingFailure catch (f) {
      _toast(f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _counter(SwapProposal p) async {
    final bool? sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SwapOfferScreen(
          repository: widget.repository,
          targetTitle: p.targetTitle,
          cashAllowed: p.targetCashAdjustment,
          counterOf: p,
        ),
      ),
    );
    if ((sent ?? false) && mounted) {
      _toast('Controproposta inviata.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<SwapProposal>? items = _items;
    final List<SwapProposal> received =
        items?.where((SwapProposal p) => p.toAnswer).toList() ?? const <SwapProposal>[];
    final List<SwapProposal> sent =
        items?.where((SwapProposal p) => p.pending && p.fromMe).toList() ?? const <SwapProposal>[];
    final List<SwapProposal> history =
        items?.where((SwapProposal p) => !p.pending).toList() ?? const <SwapProposal>[];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Proposte di scambio'),
          bottom: TabBar(
            tabs: [
              Tab(key: const ValueKey<String>('tab_ricevute'), text: 'Ricevute (${received.length})'),
              Tab(key: const ValueKey<String>('tab_inviate'), text: 'Inviate (${sent.length})'),
              const Tab(key: ValueKey<String>('tab_storico'), text: 'Storico'),
            ],
          ),
        ),
        body: _error != null && items == null
            ? Center(child: Text(_error!))
            : items == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _list(received, 'Nessuna proposta da valutare.'),
                  _list(sent, 'Non hai proposte in attesa di risposta.'),
                  _list(history, 'Qui troverai le proposte accettate, rifiutate e annullate.'),
                ],
              ),
      ),
    );
  }

  Widget _list(List<SwapProposal> list, String empty) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(empty, textAlign: TextAlign.center),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          for (final SwapProposal p in list)
            _ProposalCard(
              key: ValueKey<String>('proposta_${p.id}'),
              proposal: p,
              repository: widget.repository,
              busy: _busy,
              onAccept: () => _accept(p),
              onReject: () => _reject(p),
              onCounter: () => _counter(p),
              onCancel: () => _cancel(p),
              onConclude: () => _conclude(p),
              onDeals: () => MarketDealsScreen.open(context, widget.repository),
            ),
        ],
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    super.key,
    required this.proposal,
    required this.repository,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onCounter,
    required this.onCancel,
    required this.onConclude,
    required this.onDeals,
  });

  final SwapProposal proposal;
  final MarketRepository repository;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCounter;
  final VoidCallback onCancel;
  final VoidCallback onConclude;
  final VoidCallback onDeals;

  static Color _statusColor(SwapStatus s, ColorScheme scheme) => switch (s) {
    SwapStatus.pending => AppColors.brandOrangeDeep,
    SwapStatus.accepted || SwapStatus.completed => const Color(0xFF1E8E5A),
    SwapStatus.countered => AppColors.brandBlue,
    SwapStatus.rejected || SwapStatus.cancelled => scheme.outline,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final SwapProposal p = proposal;
    final Color color = _statusColor(p.status, scheme);
    final String who = '${p.otherPublicName} (@${p.otherUsername})';
    final String headline = p.iAmOwner
        ? (p.fromMe ? 'Controproposta a $who' : '$who vuole il tuo annuncio')
        : (p.fromMe ? 'Proposta a $who' : 'Controproposta di $who');
    final String? cash = p.cashLabel;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '«${p.targetTitle}»',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    child: Text(
                      p.status.label,
                      key: ValueKey<String>('stato_${p.id}'),
                      style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(headline, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              p.iAmOwner ? 'In cambio ti offre:' : 'In cambio offri:',
              style: theme.textTheme.labelLarge,
            ),
            for (final SwapItem i in p.items)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: i.photo == null
                            ? const ColoredBox(color: Color(0x14000000))
                            : MarketPhoto(path: i.photo!, repository: repository),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        i.available ? i.title : '${i.title} · non più disponibile',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration: i.available ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    if (i.priceCents != null)
                      Text(MarketRules.formatPrice(i.priceCents!), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            if (cash != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(cash, key: ValueKey<String>('conguaglio_${p.id}'), style: theme.textTheme.bodyMedium),
            ],
            if (p.message.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('«${p.message}»', style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
            ],
            if (!p.targetAvailable && p.pending) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'L\'annuncio richiesto non è più disponibile.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            if (p.status == SwapStatus.accepted) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Accordatevi su luogo e consegna nei commenti dell\'annuncio: la chat arriverà presto. '
                'Dopo lo scambio confermatelo entrambi.',
                key: ValueKey<String>('accordo_${p.id}'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                key: ValueKey<String>('concluso_${p.id}'),
                onPressed: busy ? null : onConclude,
                icon: const Icon(Icons.handshake_rounded),
                label: const Text('Confermo: scambio avvenuto'),
              ),
            ],
            if (p.status == SwapStatus.completed) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                key: ValueKey<String>('vai_feedback_${p.id}'),
                onPressed: onDeals,
                icon: const Icon(Icons.star_rounded),
                label: const Text('Feedback'),
              ),
            ],
            if (p.toAnswer) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: ValueKey<String>('accetta_${p.id}'),
                    onPressed: busy ? null : onAccept,
                    child: const Text('Accetta'),
                  ),
                  OutlinedButton(
                    key: ValueKey<String>('controproposta_${p.id}'),
                    onPressed: busy ? null : onCounter,
                    child: const Text('Controproposta'),
                  ),
                  TextButton(
                    key: ValueKey<String>('rifiuta_${p.id}'),
                    onPressed: busy ? null : onReject,
                    child: const Text('Rifiuta'),
                  ),
                ],
              ),
            ] else if (p.pending && p.fromMe) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: ValueKey<String>('annulla_${p.id}'),
                  onPressed: busy ? null : onCancel,
                  child: const Text('Annulla proposta'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

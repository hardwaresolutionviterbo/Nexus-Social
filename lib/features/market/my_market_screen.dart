import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../map/listing_models.dart' show expiryLabel;
import '../map/listing_repository.dart' show ListingFailure;
import '../map/map_screen.dart' show MapServices;
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import 'market_models.dart';
import 'market_publish_screen.dart';
import 'market_repository.dart';

/// I miei annunci di Scambia & Vendi: stato, revisione, scadenza, Rinnova, Modifica, Chiudi.
class MyMarketScreen extends StatefulWidget {
  const MyMarketScreen({
    super.key,
    required this.repository,
    required this.catalog,
    required this.section,
    this.services,
    this.pickImage = pickFromGallery,
    this.now = DateTime.now,
  });

  final MarketRepository repository;
  final MarketCatalog catalog;
  final MarketSection section;
  final MapServices? services;
  final PickImage pickImage;
  final DateTime Function() now;

  @override
  State<MyMarketScreen> createState() => _MyMarketScreenState();
}

class _MyMarketScreenState extends State<MyMarketScreen> {
  List<MyMarketListing>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<MyMarketListing> all = await widget.repository.mine();
      if (!mounted) return;
      setState(() {
        _items = <MyMarketListing>[
          for (final MyMarketListing l in all)
            if (widget.section.types.contains(l.type)) l,
        ];
        _error = null;
      });
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(done)));
      }
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _close(MyMarketListing l) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Chiudere l\'annuncio?'),
        content: const Text('Non sarà più visibile e non si potrà riaprire.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Chiudi')),
        ],
      ),
    );
    if (ok ?? false) await _run(() => widget.repository.close(l.id), 'Annuncio chiuso.');
  }

  Future<void> _edit(MyMarketListing l) async {
    final MarketPublishResult? r = await Navigator.of(context).push<MarketPublishResult>(
      MaterialPageRoute<MarketPublishResult>(
        builder: (_) => MarketPublishScreen(
          repository: widget.repository,
          catalog: widget.catalog,
          section: widget.section,
          services: widget.services,
          existing: l,
          pickImage: widget.pickImage,
        ),
      ),
    );
    if (r != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MyMarketListing>? items = _items;
    final DateTime now = widget.now();
    Widget body;
    if (items == null && _error == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items == null || items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(_error ?? 'Non hai ancora annunci qui.', textAlign: TextAlign.center),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          for (final MyMarketListing l in items)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (l.photos.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: MarketPhoto(path: l.photos.first, repository: widget.repository),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.title, style: theme.textTheme.titleSmall),
                              if (l.priceCents != null)
                                Text(
                                  MarketRules.formatPrice(l.priceCents!),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: AppColors.brandOrangeDeep,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _Tag(l.type.label, AppColors.brandCyan),
                                  _Tag(
                                    l.state.label,
                                    l.state == MarketListingState.active
                                        ? AppColors.brandMint
                                        : theme.colorScheme.outline,
                                  ),
                                  if (l.review == ReviewStatus.pendingReview)
                                    const _Tag('In revisione', AppColors.brandAmber),
                                  if (l.review == ReviewStatus.rejected)
                                    _Tag('Rifiutato', theme.colorScheme.error),
                                ],
                              ),
                              if (l.editable)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    expiryLabel(l.expiresAt, now),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (l.editable)
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        children: [
                          if (l.canRenew(now))
                            TextButton.icon(
                              key: ValueKey<String>('rinnova_${l.id}'),
                              onPressed: () => _run(
                                () => widget.repository.renew(l.id),
                                'Rinnovato per altri 30 giorni.',
                              ),
                              icon: const Icon(Icons.autorenew_rounded, size: 18),
                              label: const Text('Rinnova'),
                            ),
                          TextButton.icon(
                            onPressed: () => _edit(l),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Modifica'),
                          ),
                          TextButton.icon(
                            onPressed: () => _close(l),
                            icon: const Icon(Icons.check_circle_outline, size: 18),
                            label: const Text('Chiudi'),
                          ),
                        ],
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('I miei annunci')), body: body);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

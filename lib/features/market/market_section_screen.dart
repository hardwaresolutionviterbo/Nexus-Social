import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../map/listing_repository.dart' show ListingFailure;
import '../map/map_screen.dart' show MapServices;
import '../map/social_repository.dart';
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import 'category_picker.dart';
import 'market_catalog_data.dart';
import 'market_deals_screen.dart';
import 'market_filters_screen.dart';
import 'market_listing_screen.dart';
import 'market_models.dart';
import 'market_publish_screen.dart';
import 'market_repository.dart';
import 'my_market_screen.dart';
import 'swap_proposals_screen.dart';

/// Sezioni «Scambia» e «Vendita» (D10): un solo sistema di annunci, due vetrine.
/// Pubblicare e gestire i propri annunci (Blocco 1); cercare con parola, 13 filtri e
/// 5 ordinamenti, a pagine da 20, e aprire la scheda (Blocco 2).
class MarketSectionScreen extends StatefulWidget {
  const MarketSectionScreen({
    super.key,
    required this.section,
    this.repository,
    this.services,
    this.social,
    this.pickImage = pickFromGallery,
  });

  final MarketSection section;

  /// null finché il server non è collegato.
  final MarketRepository? repository;
  final MapServices? services;

  /// Mi piace e commenti nella scheda.
  final SocialRepository? social;
  final PickImage pickImage;

  @override
  State<MarketSectionScreen> createState() => _MarketSectionScreenState();
}

class _MarketSectionScreenState extends State<MarketSectionScreen> {
  MarketCatalog? _catalog;
  MarketQuery _query = const MarketQuery();
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<MarketListing> _results = const <MarketListing>[];
  bool _loading = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    if (widget.repository != null) _search();
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 400) _loadMore();
  }

  /// Nuova ricerca dalla prima pagina.
  Future<void> _search([MarketQuery? q]) async {
    final MarketRepository? repo = widget.repository;
    if (repo == null) return;
    final MarketQuery query = q ?? _query;
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });
    try {
      final List<MarketListing> page = await repo.search(widget.section, query);
      if (!mounted) return;
      setState(() {
        _results = page;
        _hasMore = page.length >= MarketQuery.pageSize;
      });
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pagina successiva (D9: pagine da 20).
  Future<void> _loadMore() async {
    final MarketRepository? repo = widget.repository;
    if (repo == null || _loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final List<MarketListing> page =
          await repo.search(widget.section, _query, offset: _results.length);
      if (!mounted) return;
      final Set<String> seen = <String>{for (final MarketListing l in _results) l.id};
      setState(() {
        _results = <MarketListing>[..._results, ...page.where((MarketListing l) => !seen.contains(l.id))];
        _hasMore = page.length >= MarketQuery.pageSize;
      });
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _submitText(String value) {
    final String t = value.trim();
    MarketSort sort = _query.sort;
    // Con una parola cercata, l'ordinamento naturale è «Più pertinenti» (D4).
    if (t.isNotEmpty && sort == MarketSort.recent) sort = MarketSort.relevant;
    if (t.isEmpty && sort == MarketSort.relevant) sort = MarketSort.recent;
    _search(_query.copyWith(text: t, sort: sort));
  }

  Future<void> _openFilters() async {
    if (!_serverReady()) return;
    final MarketCatalog catalog = await _ensureCatalog();
    if (!mounted) return;
    final MarketQuery? q = await Navigator.of(context).push<MarketQuery>(
      MaterialPageRoute<MarketQuery>(
        builder: (_) => MarketFiltersScreen(
          section: widget.section,
          catalog: catalog,
          initial: _query,
          services: widget.services,
        ),
      ),
    );
    if (q != null && mounted) await _search(q);
  }

  Future<void> _open(MarketListing l) async {
    final MarketCatalog catalog = await _ensureCatalog();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MarketListingScreen(
          listing: l,
          repository: widget.repository!,
          catalog: catalog,
          social: widget.social,
          origin: _query.hasPoint ? _query.point : null,
        ),
      ),
    );
  }

  /// Catalogo dal server (stato attivo aggiornato); se non arriva, quello dell'app.
  Future<MarketCatalog> _ensureCatalog() async {
    final MarketCatalog? c = _catalog;
    if (c != null) return c;
    List<MarketCategory> list = builtInMarketCatalog;
    try {
      final List<MarketCategory> remote = await widget.repository!.categories();
      if (remote.isNotEmpty) list = remote;
    } on ListingFailure {
      // Si usa il catalogo incluso nell'app.
    }
    return _catalog = MarketCatalog(list);
  }

  bool _serverReady() {
    if (widget.repository != null) return true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Per pubblicare serve il collegamento al server: si attiverà con il piano Blaze.',
          ),
        ),
      );
    return false;
  }

  Future<void> _publish() async {
    if (!_serverReady()) return;
    final MarketCatalog catalog = await _ensureCatalog();
    if (!mounted) return;
    final MarketPublishResult? r = await Navigator.of(context).push<MarketPublishResult>(
      MaterialPageRoute<MarketPublishResult>(
        builder: (_) => MarketPublishScreen(
          repository: widget.repository!,
          catalog: catalog,
          section: widget.section,
          services: widget.services,
          pickImage: widget.pickImage,
        ),
      ),
    );
    if (r == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            r.pendingReview
                ? 'Annuncio inviato: lo vedranno gli altri dopo il controllo della moderazione.'
                : 'Annuncio pubblicato.',
          ),
        ),
      );
    await _search();
  }

  Future<void> _mine() async {
    if (!_serverReady()) return;
    final MarketCatalog catalog = await _ensureCatalog();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MyMarketScreen(
          repository: widget.repository!,
          catalog: catalog,
          section: widget.section,
          services: widget.services,
          pickImage: widget.pickImage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MarketCatalog preview = _catalog ?? MarketCatalog(builtInMarketCatalog);
    final bool server = widget.repository != null;
    final int filters = _query.activeFilters;
    return RefreshIndicator(
      onRefresh: () => _search(),
      child: ListView(
        controller: _scroll,
        padding: AppSpacing.pagePadding,
        children: [
          Text(widget.section.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            widget.section == MarketSection.swap
                ? 'Scambia, regala o cerca oggetti vicino a te. Sempre gratis.'
                : 'Vendi tra privati vicino a te. Gratis, senza commissioni.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: ValueKey<String>('pubblica_${widget.section.name}'),
                  onPressed: _publish,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Pubblica'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _mine,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('I miei annunci'),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                key: const ValueKey<String>('mercato_proposte'),
                onPressed: () {
                  if (_serverReady()) SwapProposalsScreen.open(context, widget.repository!);
                },
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Proposte'),
              ),
              TextButton.icon(
                key: const ValueKey<String>('mercato_conclusioni'),
                onPressed: () {
                  if (_serverReady()) MarketDealsScreen.open(context, widget.repository!);
                },
                icon: const Icon(Icons.star_outline_rounded),
                label: const Text('Conclusioni e feedback'),
              ),
            ],
          ),
          TextField(
            key: const ValueKey<String>('mercato_cerca'),
            controller: _text,
            textInputAction: TextInputAction.search,
            onSubmitted: _submitText,
            enabled: server,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: widget.section == MarketSection.swap ? 'Cerca in Scambia' : 'Cerca in Vendita',
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Cancella ricerca',
                      onPressed: () {
                        _text.clear();
                        _submitText('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              OutlinedButton.icon(
                key: const ValueKey<String>('mercato_filtri'),
                onPressed: _openFilters,
                icon: const Icon(Icons.tune_rounded),
                label: Text(filters == 0 ? 'Filtri' : 'Filtri ($filters)'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<MarketSort>(
                    key: const ValueKey<String>('mercato_ordina'),
                    enabled: server,
                    initialValue: _query.sort,
                    onSelected: (MarketSort s) => _search(_query.copyWith(sort: s)),
                    itemBuilder: (_) => [
                      for (final MarketSort s in MarketSort.values)
                        PopupMenuItem<MarketSort>(
                          key: ValueKey<String>('ordina_${s.serverValue}'),
                          value: s,
                          enabled: switch (s) {
                            MarketSort.nearest => _query.hasPoint,
                            MarketSort.relevant => _query.text.isNotEmpty,
                            _ => true,
                          },
                          child: Text(s.label),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sort_rounded, size: 20),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _query.sort.label,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            key: const ValueKey<String>('mercato_categorie'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Tutte'),
                    selected: _query.categoryId == null,
                    onSelected: server
                        ? (_) => _search(_query.copyWith(categoryId: () => null, subcategoryId: () => null))
                        : null,
                  ),
                ),
                for (final MarketCategory c in preview.mains)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey<String>('categoria_${c.slug}'),
                      avatar: Icon(marketCategoryIcon(c.slug), size: 18),
                      label: Text(c.name),
                      selected: _query.categoryId == c.id,
                      onSelected: server
                          ? (bool on) => _search(
                              _query.copyWith(categoryId: () => on ? c.id : null, subcategoryId: () => null),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const AntiScamNotice(),
          const SizedBox(height: AppSpacing.md),
          if (!server)
            Text(
              'Gli annunci vicino a te compariranno qui quando l\'app sarà collegata al server.',
              key: const ValueKey<String>('mercato_senza_server'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else if (_error != null && _results.isEmpty)
            Text(
              _error!,
              key: const ValueKey<String>('mercato_errore_ricerca'),
              style: TextStyle(color: theme.colorScheme.error),
            )
          else if (_results.isEmpty && !_loading)
            Padding(
              key: const ValueKey<String>('mercato_nessun_risultato'),
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nessun annuncio trovato. Prova a cambiare parola o filtri.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            )
          else ...[
            for (final MarketListing l in _results)
              _ResultCard(
                key: ValueKey<String>('risultato_${l.id}'),
                listing: l,
                repository: widget.repository!,
                onTap: () => _open(l),
              ),
            if (_hasMore)
              Center(
                child: TextButton(
                  key: const ValueKey<String>('mercato_altri'),
                  onPressed: _loading ? null : _loadMore,
                  child: const Text('Mostra altri annunci'),
                ),
              ),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Un risultato: foto, prezzo, titolo, condizioni e distanza.
class _ResultCard extends StatelessWidget {
  const _ResultCard({super.key, required this.listing, required this.repository, required this.onTap});

  final MarketListing listing;
  final MarketRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MarketListing l = listing;
    final List<String> meta = <String>[
      if (l.type != MarketType.sell) l.type.label,
      if (l.condition != null) l.condition!.label,
      if (l.distanceBandMeters != null) marketDistanceLabel(l.distanceBandMeters!),
      if (l.ownerIsBusiness) 'Azienda',
      if (l.swappable && l.type == MarketType.sell) 'Valuta scambi',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: l.photos.isEmpty
                      ? ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.search_rounded),
                        )
                      : MarketPhoto(path: l.photos.first, repository: repository),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (l.priceLabel.isNotEmpty)
                      Text(
                        l.priceLabel,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    Text(
                      l.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

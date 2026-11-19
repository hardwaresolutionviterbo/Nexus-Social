import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/piazly_ui.dart';
import '../map/listing_repository.dart' show ListingFailure;
import '../map/map_screen.dart' show MapServices;
import '../map/social_repository.dart';
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import 'category_picker.dart';
import 'comuni_italia.dart';
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
    this.unified = false,
    this.searchRequests,
  });

  /// Sezione di partenza. Con [unified] si parte da «Tutti» (Scambio e Vendita insieme).
  final MarketSection section;

  /// «Scambia & Vendi» in una sola schermata (mockup del titolare, 19/11/2026).
  final bool unified;

  /// La lente dell'intestazione: a ogni avviso il cursore va nella ricerca.
  final Listenable? searchRequests;

  /// null finché il server non è collegato.
  final MarketRepository? repository;
  final MapServices? services;

  /// Mi piace e commenti nella scheda.
  final SocialRepository? social;
  final PickImage pickImage;

  @override
  State<MarketSectionScreen> createState() => _MarketSectionScreenState();
}

/// Filtro in alto: Tutti, Scambio, Vendita, Regalo.
enum _Mode { all, swap, sale, free }

class _MarketSectionScreenState extends State<MarketSectionScreen> {
  MarketCatalog? _catalog;
  MarketQuery _query = const MarketQuery();
  final TextEditingController _text = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  List<MarketListing> _results = const <MarketListing>[];
  final Map<MarketSection, int> _offsets = <MarketSection, int>{};
  final Set<MarketSection> _more = <MarketSection>{};
  bool _loading = false;
  String? _error;
  late _Mode _mode = widget.unified
      ? _Mode.all
      : (widget.section == MarketSection.swap ? _Mode.swap : _Mode.sale);

  bool get _hasMore => _more.isNotEmpty;

  /// Sezione su cui si pubblica, si filtra e si gestisce; null con «Tutti».
  MarketSection? get _section => switch (_mode) {
    _Mode.all => null,
    _Mode.sale => MarketSection.sale,
    _ => MarketSection.swap,
  };

  List<MarketSection> get _sections =>
      _mode == _Mode.all ? const <MarketSection>[MarketSection.sale, MarketSection.swap] : <MarketSection>[_section!];

  /// Nella schermata unica, «Scambio» e «Regalo» filtrano per tipologia.
  MarketQuery _queryFor(MarketSection s, MarketQuery q) {
    if (!widget.unified) return q;
    return switch (_mode) {
      _Mode.swap => q.copyWith(types: const <MarketType>{MarketType.swap, MarketType.wanted}),
      _Mode.free => q.copyWith(types: const <MarketType>{MarketType.free}),
      _ => q,
    };
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    widget.searchRequests?.addListener(_focusSearch);
    if (widget.repository != null) _search();
    // Nomi dei comuni sulle schede degli annunci.
    if (ComuniItalia.loaded == null) {
      ComuniItalia.load().then((_) {
        if (mounted) setState(() {});
      }, onError: (Object _) {});
    }
  }

  @override
  void dispose() {
    widget.searchRequests?.removeListener(_focusSearch);
    _text.dispose();
    _textFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _focusSearch() {
    if (!mounted) return;
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
    }
    _textFocus.requestFocus();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 400) _loadMore();
  }

  List<MarketListing> _merge(List<MarketListing> a) {
    if (_mode != _Mode.all || _query.sort != MarketSort.recent) return a;
    return <MarketListing>[...a]..sort((MarketListing x, MarketListing y) => y.createdAt.compareTo(x.createdAt));
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
      final List<MarketListing> all = <MarketListing>[];
      _offsets.clear();
      _more.clear();
      for (final MarketSection s in _sections) {
        final List<MarketListing> page = await repo.search(s, _queryFor(s, query));
        all.addAll(page);
        _offsets[s] = page.length;
        if (page.length >= MarketQuery.pageSize) _more.add(s);
      }
      if (!mounted) return;
      setState(() => _results = _merge(all));
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
      final List<MarketListing> extra = <MarketListing>[];
      for (final MarketSection s in _more.toList()) {
        final List<MarketListing> page = await repo.search(s, _queryFor(s, _query), offset: _offsets[s] ?? 0);
        extra.addAll(page);
        _offsets[s] = (_offsets[s] ?? 0) + page.length;
        if (page.length < MarketQuery.pageSize) _more.remove(s);
      }
      if (!mounted) return;
      final Set<String> seen = <String>{for (final MarketListing l in _results) l.id};
      setState(() {
        _results = <MarketListing>[..._results, ...extra.where((MarketListing l) => !seen.contains(l.id))];
      });
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setMode(_Mode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    // Le tipologie scelte nei filtri valgono per una sola vetrina.
    _search(_query.copyWith(types: const <MarketType>{}));
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
          section: _section ?? MarketSection.sale,
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
    MarketSection? section = _section;
    // Con «Tutti» si sceglie prima che cosa pubblicare.
    section ??= await showModalBottomSheet<MarketSection>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey<String>('pubblica_scegli_vendita'),
              leading: const IconTile(Icons.sell_outlined, color: AppColors.brandOrange),
              title: const Text('Vendi'),
              subtitle: const Text('Metti in vendita un oggetto'),
              onTap: () => Navigator.of(c).pop(MarketSection.sale),
            ),
            ListTile(
              key: const ValueKey<String>('pubblica_scegli_scambio'),
              leading: const IconTile(Icons.swap_horiz_rounded),
              title: const Text('Scambia, regala o cerca'),
              subtitle: const Text('Proponi uno scambio, regala o cerca un oggetto'),
              onTap: () => Navigator.of(c).pop(MarketSection.swap),
            ),
          ],
        ),
      ),
    );
    if (section == null) return;
    final MarketSection chosen = section;
    final MarketCatalog catalog = await _ensureCatalog();
    if (!mounted) return;
    final MarketPublishResult? r = await Navigator.of(context).push<MarketPublishResult>(
      MaterialPageRoute<MarketPublishResult>(
        builder: (_) => MarketPublishScreen(
          repository: widget.repository!,
          catalog: catalog,
          section: chosen,
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
          section: _section,
          services: widget.services,
          pickImage: widget.pickImage,
        ),
      ),
    );
  }

  /// Le categorie principali da mostrare come riquadri: le prime quattro e «Altre».
  static const List<String> _quickSlugs = <String>['motori', 'immobili', 'elettronica', 'casa-arredamento'];

  Future<void> _allCategories(MarketCatalog catalog) async {
    final MarketCategory? pick = await showModalBottomSheet<MarketCategory>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: const Text('Tutte le categorie'),
                onTap: () => Navigator.of(c).pop(),
              ),
              for (final MarketCategory m in catalog.mains)
                ListTile(
                  key: ValueKey<String>('categoria_${m.slug}'),
                  leading: Icon(marketCategoryIcon(m.slug), color: AppColors.brandOrange),
                  title: Text(m.name),
                  selected: _query.categoryId == m.id,
                  onTap: () => Navigator.of(c).pop(m),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    _search(_query.copyWith(categoryId: () => pick?.id, subcategoryId: () => null));
  }

  Widget _banner({required bool swap}) {
    final ThemeData theme = Theme.of(context);
    final bool on = swap ? _mode == _Mode.swap : _mode == _Mode.sale;
    return Expanded(
      child: Material(
        key: ValueKey<String>(swap ? 'banner_scambia' : 'banner_vendi'),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: on ? 6 : 3,
        shadowColor: (swap ? PiazlyColors.violet : AppColors.brandOrange).withValues(alpha: 0.5),
        child: InkWell(
          onTap: () => _setMode(swap ? _Mode.swap : _Mode.sale),
          child: Ink(
            height: 118,
            decoration: BoxDecoration(
              gradient: swap ? PiazlyColors.violetGradient : AppColors.orangeGradient,
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -10,
                  bottom: -12,
                  child: Icon(
                    swap ? Icons.inventory_2_rounded : Icons.shopping_bag_rounded,
                    size: 78,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(swap ? Icons.swap_horiz_rounded : Icons.sell_outlined, color: Colors.white, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            swap ? 'Scambia' : 'Vendi',
                            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        swap ? 'Trova oggetti\nda scambiare' : 'Metti in vendita\ni tuoi oggetti',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.95)),
                      ),
                      const Spacer(),
                      const Align(
                        alignment: Alignment.bottomRight,
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryTile({required String key, required IconData icon, required String label, required bool on, VoidCallback? onTap}) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 78,
        child: SoftCard(
          key: ValueKey<String>(key),
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          radius: 16,
          tint: on ? PiazlyColors.orangeSoft : null,
          onTap: onTap,
          child: Column(
            children: [
              Icon(icon, color: AppColors.brandOrange, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
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
    final MarketSection? section = _section;
    final List<MarketCategory> quick = <MarketCategory>[
      for (final String slug in _quickSlugs)
        ...preview.mains.where((MarketCategory c) => c.slug == slug),
    ];
    final MarketCategory? chosenOther = _query.categoryId == null
        ? null
        : preview.mains.where((MarketCategory c) => c.id == _query.categoryId && !_quickSlugs.contains(c.slug)).firstOrNull;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _search(),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 132),
            children: [
              if (widget.unified)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Row(children: [_banner(swap: true), const SizedBox(width: 12), _banner(swap: false)]),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                  child: Text(widget.section.title, style: theme.textTheme.headlineSmall),
                ),
              if (widget.unified)
                PillTabs<_Mode>(
                  key: const ValueKey<String>('mercato_tipologia'),
                  scroll: true,
                  tabs: const <PillTab<_Mode>>[
                    PillTab<_Mode>(value: _Mode.all, label: 'Tutti', key: ValueKey<String>('filtro_tutti')),
                    PillTab<_Mode>(value: _Mode.swap, label: 'Scambio', icon: Icons.swap_horiz_rounded, key: ValueKey<String>('filtro_scambio')),
                    PillTab<_Mode>(value: _Mode.sale, label: 'Vendita', icon: Icons.sell_outlined, key: ValueKey<String>('filtro_vendita')),
                    PillTab<_Mode>(value: _Mode.free, label: 'Regalo', icon: Icons.card_giftcard_rounded, key: ValueKey<String>('filtro_regalo')),
                  ],
                  selected: _mode,
                  onChanged: _setMode,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>('mercato_cerca'),
                        controller: _text,
                        focusNode: _textFocus,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _submitText,
                        enabled: server,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: section == null
                              ? 'Cerca annunci…'
                              : section == MarketSection.swap
                              ? 'Cerca in Scambia'
                              : 'Cerca in Vendita',
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
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
                    ),
                    const SizedBox(width: 10),
                    Badge(
                      isLabelVisible: filters > 0,
                      label: Text('$filters'),
                      backgroundColor: AppColors.brandOrange,
                      child: IconButton(
                        key: const ValueKey<String>('mercato_filtri'),
                        tooltip: filters == 0 ? 'Filtri' : 'Filtri ($filters)',
                        onPressed: _openFilters,
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.surface,
                          side: BorderSide(color: theme.colorScheme.outlineVariant),
                          fixedSize: const Size(52, 52),
                        ),
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                key: const ValueKey<String>('mercato_categorie'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    _categoryTile(
                      key: 'categoria_tutte',
                      icon: Icons.apps_rounded,
                      label: 'Tutte',
                      on: _query.categoryId == null,
                      onTap: server ? () => _search(_query.copyWith(categoryId: () => null, subcategoryId: () => null)) : null,
                    ),
                    for (final MarketCategory c in quick)
                      _categoryTile(
                        key: 'categoria_${c.slug}',
                        icon: marketCategoryIcon(c.slug),
                        label: c.name.split(' ').first,
                        on: _query.categoryId == c.id,
                        onTap: server
                            ? () => _search(_query.copyWith(
                                  categoryId: () => _query.categoryId == c.id ? null : c.id,
                                  subcategoryId: () => null,
                                ))
                            : null,
                      ),
                    _categoryTile(
                      key: 'categoria_altre',
                      icon: chosenOther == null ? Icons.grid_view_rounded : marketCategoryIcon(chosenOther.slug),
                      label: chosenOther == null ? 'Altre' : chosenOther.name.split(' ').first,
                      on: chosenOther != null,
                      onTap: server ? () => _allCategories(preview) : null,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                child: Wrap(
                  spacing: 0,
                  children: [
                    TextButton.icon(
                      key: const ValueKey<String>('mercato_miei'),
                      onPressed: _mine,
                      icon: const Icon(Icons.inventory_2_outlined, size: 18),
                      label: const Text('I miei annunci'),
                    ),
                    TextButton.icon(
                      key: const ValueKey<String>('mercato_proposte'),
                      onPressed: () {
                        if (_serverReady()) SwapProposalsScreen.open(context, widget.repository!);
                      },
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Proposte'),
                    ),
                    TextButton.icon(
                      key: const ValueKey<String>('mercato_conclusioni'),
                      onPressed: () {
                        if (_serverReady()) MarketDealsScreen.open(context, widget.repository!);
                      },
                      icon: const Icon(Icons.star_outline_rounded, size: 18),
                      label: const Text('Conclusioni e feedback'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 4),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: PiazlyColors.violet),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Annunci vicino a te',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    PopupMenuButton<MarketSort>(
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
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _query.sort.label,
                              style: theme.textTheme.labelLarge?.copyWith(color: PiazlyColors.violet, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.sort_rounded, size: 18, color: PiazlyColors.violet),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!server)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: Text(
                    'Gli annunci vicino a te compariranno qui quando l\'app sarà collegata al server.',
                    key: const ValueKey<String>('mercato_senza_server'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else if (_error != null && _results.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: Text(
                    _error!,
                    key: const ValueKey<String>('mercato_errore_ricerca'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                )
              else if (_results.isEmpty && !_loading)
                Padding(
                  key: const ValueKey<String>('mercato_nessun_risultato'),
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
                  child: Text(
                    'Nessun annuncio trovato. Prova a cambiare parola o filtri.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LayoutBuilder(
                    builder: (BuildContext c, BoxConstraints box) {
                      final double w = (box.maxWidth - 12) / 2;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final MarketListing l in _results)
                            SizedBox(
                              width: w,
                              child: _ResultCard(
                                key: ValueKey<String>('risultato_${l.id}'),
                                listing: l,
                                repository: widget.repository!,
                                onTap: () => _open(l),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: AntiScamNotice(),
              ),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 112,
          child: FloatingActionButton.extended(
            key: ValueKey<String>('pubblica_${section?.name ?? 'tutti'}'),
            heroTag: 'mercato_pubblica_${widget.section.name}_${widget.unified}',
            backgroundColor: AppColors.brandOrange,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            onPressed: _publish,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Pubblica', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

/// Un annuncio a scheda: foto con l'etichetta (Scambio, Vendita, Regalo, Cerco), titolo, prezzo
/// e distanza.
class _ResultCard extends StatelessWidget {
  const _ResultCard({super.key, required this.listing, required this.repository, required this.onTap});

  final MarketListing listing;
  final MarketRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MarketListing l = listing;
    final (String tag, Color color) = switch (l.type) {
      MarketType.sell => ('Vendita', AppColors.brandOrange),
      MarketType.swap => ('Scambio', PiazlyColors.violet),
      MarketType.free => ('Regalo', PiazlyColors.green),
      MarketType.wanted => ('Cerco', AppColors.brandBlue),
    };
    final String? place = ComuniItalia.loaded?.nearest(l.point).label;
    final List<String> meta = <String>[
      if (l.condition != null) l.condition!.label,
      if (l.ownerIsBusiness) 'Azienda',
      if (l.swappable && l.type == MarketType.sell) 'Valuta scambi',
    ];
    return SoftCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      radius: 18,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: AspectRatio(
              aspectRatio: 1.25,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (l.photos.isEmpty)
                    ColoredBox(
                      color: color.withValues(alpha: 0.10),
                      child: Icon(Icons.image_outlined, color: color, size: 36),
                    )
                  else
                    MarketPhoto(path: l.photos.first, repository: repository),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                      child: Text(tag, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (l.type == MarketType.sell && l.priceLabel.isNotEmpty)
                  Text(
                    l.priceLabel,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.brandOrangeDeep),
                  )
                else if (l.priceLabel.isNotEmpty && l.type != MarketType.swap)
                  Text(l.priceLabel, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (meta.isNotEmpty)
                  Text(meta.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                if (place != null || l.distanceBandMeters != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 15, color: PiazlyColors.violet),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          <String>[
                            ?place,
                            if (l.distanceBandMeters != null) marketDistanceLabel(l.distanceBandMeters!),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

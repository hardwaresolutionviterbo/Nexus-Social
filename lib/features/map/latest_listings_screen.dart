import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../business/business_models.dart' show BusinessFailure;
import '../business/business_promotions.dart';
import '../business/business_repository.dart';
import '../business/promotion_models.dart';
import 'listing_form_screen.dart' show ListingPhotoView;
import 'listing_models.dart';
import 'listing_repository.dart';
import 'listing_sheets.dart';
import 'social_models.dart' show missingLabel;

/// «Ultimi annunci» (R3.10): due schede, Annunci (persone, categoria Libera) e Promozioni
/// (attività, dalla Fase 6), entro il raggio scelto e con gli stessi filtri della Mappa.
class LatestListingsScreen extends StatefulWidget {
  const LatestListingsScreen({
    super.key,
    required this.services,
    required this.origin,
    required this.filters,
    this.now = DateTime.now,
    this.businesses,
  });

  /// Promozioni delle attività (Fase 6) nella scheda «Promozioni»; se manca si usa
  /// [BusinessRegistry.current].
  final BusinessRepository? businesses;
  final ListingSheetServices services;

  /// Posizione attuale del telefono; null se non consentita.
  final GeoPoint? origin;
  final MapFilters filters;
  final DateTime Function() now;

  @override
  State<LatestListingsScreen> createState() => _LatestListingsScreenState();
}

class _LatestListingsScreenState extends State<LatestListingsScreen> {
  late MapFilters _filters = widget.filters;
  final Map<ListingTab, List<NearbyListing>?> _items = <ListingTab, List<NearbyListing>?>{};
  final Map<ListingTab, String?> _errors = <ListingTab, String?>{};
  List<Promotion> _business = const <Promotion>[];

  BusinessRepository? get _biz => widget.businesses ?? BusinessRegistry.current;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    for (final ListingTab tab in ListingTab.values) {
      _load(tab);
    }
    _loadBusiness();
  }

  /// Promozioni ed eventi delle attività (Fase 6, Blocco 3) entro il raggio scelto.
  Future<void> _loadBusiness() async {
    final BusinessRepository? repo = _biz;
    final GeoPoint? origin = widget.origin;
    if (repo == null || origin == null) return;
    try {
      final List<Promotion> p = await repo.promotionsNearby(
        origin.latitude,
        origin.longitude,
        radiusKm: _filters.radiusKm.clamp(1, 50),
      );
      if (mounted) setState(() => _business = p);
    } on BusinessFailure {
      // Restano gli annunci della Mappa.
    }
  }

  Future<void> _load(ListingTab tab) async {
    final GeoPoint? origin = widget.origin;
    if (origin == null) return;
    setState(() {
      _items[tab] = null;
      _errors[tab] = null;
    });
    try {
      final List<NearbyListing> items =
          await widget.services.listings.nearby(origin, _filters, tab: tab);
      if (mounted) setState(() => _items[tab] = items);
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _errors[tab] = f.message);
    }
  }

  Future<void> _editFilters() async {
    final MapFilters? f = await showMapFilters(context, _filters);
    if (f == null || f == _filters || !mounted) return;
    setState(() => _filters = f);
    _loadAll();
  }

  Future<void> _open(NearbyListing listing) async {
    final bool? blocked = await showListingSheet(
      context,
      listing: listing,
      services: widget.services,
      now: widget.now,
    );
    if (blocked ?? false) _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: ListingTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ultimi annunci'),
          actions: [
            IconButton(
              tooltip: 'Filtri',
              onPressed: _editFilters,
              icon: Badge(
                isLabelVisible: _filters.narrowed,
                child: const Icon(Icons.tune_rounded),
              ),
            ),
          ],
          bottom: TabBar(
            tabs: [for (final ListingTab t in ListingTab.values) Tab(text: t.label)],
          ),
        ),
        body: Column(
          children: [
            _FilterSummary(filters: _filters, onTap: _editFilters),
            Expanded(
              child: TabBarView(
                children: [
                  for (final ListingTab t in ListingTab.values) _tabBody(context, t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBody(BuildContext context, ListingTab tab) {
    final ThemeData theme = Theme.of(context);
    if (widget.origin == null) {
      return const _Empty(
        icon: Icons.location_off_outlined,
        text: 'Consenti la posizione dalla Mappa per vedere gli annunci intorno a te.',
      );
    }
    final String? error = _errors[tab];
    if (error != null) return _Empty(icon: Icons.cloud_off_rounded, text: error);
    final List<NearbyListing>? items = _items[tab];
    if (items == null) return const Center(child: CircularProgressIndicator());
    final List<Promotion> business = tab == ListingTab.promotions ? _business : const <Promotion>[];
    if (items.isEmpty && business.isEmpty) {
      return _Empty(
        icon: tab == ListingTab.promotions ? Icons.storefront_outlined : Icons.map_outlined,
        text: tab == ListingTab.promotions
            ? 'Qui compariranno le promozioni delle attività della zona.'
            : 'Nessun annuncio entro ${_filters.radiusKm} km con questi filtri.',
      );
    }
    final DateTime now = widget.now();
    return RefreshIndicator(
      onRefresh: () => _load(tab),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: business.length + items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          if (i < business.length) {
            final Promotion p = business[i];
            return PromotionTile(
              key: ValueKey<String>('ultimi_promo_${p.id}'),
              promotion: p,
              now: now,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PromotionDetailScreen(repository: _biz!, promotion: p, now: widget.now),
                ),
              ),
            );
          }
          final NearbyListing l = items[i - business.length];
          return Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _open(l),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: l.photos.isEmpty
                            ? ColoredBox(
                                color: AppColors.brandOrange.withValues(alpha: 0.15),
                                child: Center(
                                  child: Text(
                                    l.initial,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: AppColors.brandOrangeDeep,
                                    ),
                                  ),
                                ),
                              )
                            : ListingPhotoView(
                                path: l.photos.first,
                                repository: widget.services.listings,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.title, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            '${l.ownerPublicName} · ${distanceLabel(l.distanceBandMeters)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            publishedLabel(l.createdAt, now),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (l.groupSpots != null)
                            Text(
                              missingLabel(l.groupSpots!, l.participants),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.brandOrangeDeep,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (l.availableNow || l.isMine) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                if (l.availableNow)
                                  const _Pill(text: 'Disponibile ora', color: AppColors.brandMint),
                                if (l.isMine)
                                  const _Pill(text: 'Tuo', color: AppColors.brandCyan),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterSummary extends StatelessWidget {
  const _FilterSummary({required this.filters, required this.onTap});

  final MapFilters filters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final List<String> parts = <String>[
      'Entro ${filters.radiusKm} km',
      if (filters.published != PublishedWithin.any) filters.published.label,
      if (filters.availableNowOnly) 'Disponibile ora',
    ];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  parts.join(' · '),
                  key: const ValueKey<String>('riepilogo_filtri'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

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

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm),
          Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  );
}

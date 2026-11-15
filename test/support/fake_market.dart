import 'dart:typed_data';

import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/listing_repository.dart';
import 'package:nexus_social/features/market/market_catalog_data.dart';
import 'package:nexus_social/features/market/market_models.dart';
import 'package:nexus_social/features/market/market_repository.dart';

/// Scambia & Vendi finto in memoria: nessun server.
class FakeMarketRepository implements MarketRepository {
  FakeMarketRepository({
    List<MyMarketListing>? items,
    List<MarketListing>? listings,
    this.photoBytes = const <String, Uint8List>{},
  }) : items = items ?? <MyMarketListing>[],
       listings = listings ?? <MarketListing>[];

  /// Foto finte per le anteprime (percorso → immagine).
  final Map<String, Uint8List> photoBytes;

  final List<MyMarketListing> items;

  /// Annunci degli altri, per la ricerca e la scheda.
  final List<MarketListing> listings;
  final List<(MarketSection, MarketQuery, int)> searches = <(MarketSection, MarketQuery, int)>[];
  final List<(String, ReportReason)> reports = <(String, ReportReason)>[];
  final Set<String> gone = <String>{};
  final List<MarketDraft> published = <MarketDraft>[];
  final List<(String, MarketDraft)> updates = <(String, MarketDraft)>[];
  final List<String> renewed = <String>[];
  final List<String> closed = <String>[];
  bool flagNext = false;
  String? failWith;

  @override
  Future<List<MarketCategory>> categories() async => builtInMarketCatalog;

  @override
  Future<MarketPublishResult> publish(MarketDraft draft) async {
    final String? f = failWith;
    if (f != null) {
      failWith = null;
      throw ListingFailure(f);
    }
    published.add(draft);
    return MarketPublishResult(id: 'm${published.length}', pendingReview: flagNext);
  }

  @override
  Future<MarketPublishResult> update(String id, MarketDraft draft) async {
    updates.add((id, draft));
    return MarketPublishResult(id: id, pendingReview: false);
  }

  @override
  Future<DateTime> renew(String id) async {
    renewed.add(id);
    final DateTime until = DateTime(2026, 12, 15);
    final int i = items.indexWhere((MyMarketListing l) => l.id == id);
    if (i >= 0) items[i] = items[i].copyWith(expiresAt: until, state: MarketListingState.active);
    return until;
  }

  @override
  Future<void> close(String id) async {
    closed.add(id);
    final int i = items.indexWhere((MyMarketListing l) => l.id == id);
    if (i >= 0) items[i] = items[i].copyWith(state: MarketListingState.completed);
  }

  @override
  Future<List<MyMarketListing>> mine() async => List<MyMarketListing>.of(items);

  @override
  Future<Uint8List?> downloadPhoto(String path) async => photoBytes[path];

  /// Filtri principali applicati in memoria, come farebbe il server (migrazione 0013).
  @override
  Future<List<MarketListing>> search(MarketSection section, MarketQuery query, {int offset = 0}) async {
    searches.add((section, query, offset));
    final MarketCatalog catalog = MarketCatalog(builtInMarketCatalog);
    final String q = query.text.trim().toLowerCase();
    final List<MarketListing> hits = listings.where((MarketListing l) {
      final MarketCategory? sub = catalog.byId(l.categoryId);
      return section.types.contains(l.type) &&
          (query.types.isEmpty || query.types.contains(l.type)) &&
          (q.isEmpty || '${l.title} ${l.description}'.toLowerCase().contains(q)) &&
          (query.categoryId == null || sub?.parentId == query.categoryId) &&
          (query.subcategoryId == null || l.categoryId == query.subcategoryId) &&
          (query.priceMinCents == null || (l.priceCents ?? -1) >= query.priceMinCents!) &&
          (query.priceMaxCents == null || (l.priceCents ?? 1 << 40) <= query.priceMaxCents!) &&
          (query.conditions.isEmpty || query.conditions.contains(l.condition)) &&
          (query.seller == SellerKind.any || l.ownerIsBusiness == (query.seller == SellerKind.business)) &&
          (!query.ships || l.ships) &&
          (!query.pickup || l.pickup) &&
          (!query.openToSwap || l.swappable) &&
          (!query.cashAdjustment || l.cashAdjustment);
    }).toList();
    switch (query.sort) {
      case MarketSort.priceAsc:
        hits.sort((MarketListing a, MarketListing b) => (a.priceCents ?? 0).compareTo(b.priceCents ?? 0));
      case MarketSort.priceDesc:
        hits.sort((MarketListing a, MarketListing b) => (b.priceCents ?? 0).compareTo(a.priceCents ?? 0));
      case MarketSort.nearest:
        hits.sort((MarketListing a, MarketListing b) =>
            (a.distanceBandMeters ?? 0).compareTo(b.distanceBandMeters ?? 0));
      case MarketSort.recent || MarketSort.relevant:
        hits.sort((MarketListing a, MarketListing b) => b.createdAt.compareTo(a.createdAt));
    }
    return hits.skip(offset).take(MarketQuery.pageSize).toList();
  }

  @override
  Future<MarketListing?> listing(String id, {GeoPoint? origin}) async {
    if (gone.contains(id)) return null;
    return listings.where((MarketListing l) => l.id == id).firstOrNull;
  }

  @override
  Future<void> report(String id, ReportReason reason, {String? details}) async {
    reports.add((id, reason));
  }
}

MarketListing sampleListing({
  String id = 'x1',
  MarketType type = MarketType.sell,
  String slug = 'elettronica-smartphone',
  String title = 'iPhone 13 128 GB',
  String description = 'Perfetto, con scatola',
  int? priceCents = 35000,
  ItemCondition? condition = ItemCondition.excellent,
  bool ships = true,
  bool pickup = true,
  bool openToSwap = false,
  bool cashAdjustment = false,
  bool business = false,
  bool mine = false,
  int? distance = 1250,
  String? wantedInExchange,
  ReviewStatus review = ReviewStatus.published,
  List<String> photos = const <String>['u/f1.jpg', 'u/f2.jpg'],
  DateTime? createdAt,
}) => MarketListing(
  id: id,
  type: type,
  categoryId: categoryBySlug(slug).id,
  title: title,
  description: description,
  priceCents: priceCents,
  condition: condition,
  ships: ships,
  pickup: pickup,
  openToSwap: openToSwap,
  cashAdjustment: cashAdjustment,
  attributes: slug.startsWith('elettronica') ? const <String, Object>{'memoria': '128 GB'} : const <String, Object>{},
  wantedInExchange: wantedInExchange,
  photos: photos,
  place: ListingPlace.approximateZone,
  point: const GeoPoint(41.905, 12.495),
  distanceBandMeters: distance,
  review: review,
  expiresAt: DateTime(2026, 12, 10),
  createdAt: createdAt ?? DateTime(2026, 11, 12),
  isMine: mine,
  ownerId: business ? 'azienda1' : 'utente1',
  ownerUsername: business ? 'bottega_verdi' : 'luca_r',
  ownerPublicName: business ? 'Bottega Verdi' : 'Luca R.',
  ownerIsBusiness: business,
);

MarketCategory categoryBySlug(String slug) =>
    builtInMarketCatalog.firstWhere((MarketCategory c) => c.slug == slug);

MyMarketListing sampleMarket({
  String id = 'm1',
  MarketType type = MarketType.sell,
  String slug = 'elettronica-smartphone',
  String title = 'iPhone 13 128 GB',
  int? priceCents = 35000,
  MarketListingState state = MarketListingState.active,
  ReviewStatus review = ReviewStatus.published,
  DateTime? expiresAt,
}) => MyMarketListing(
  id: id,
  type: type,
  categoryId: categoryBySlug(slug).id,
  title: title,
  description: 'Perfetto, con scatola',
  priceCents: priceCents,
  condition: ItemCondition.excellent,
  pickup: true,
  attributes: const <String, Object>{'memoria': '128 GB'},
  photos: const <String>['u/f.jpg'],
  place: ListingPlace.approximateZone,
  savedPoint: const GeoPoint(41.9028, 12.4964),
  state: state,
  review: review,
  expiresAt: expiresAt ?? DateTime(2026, 12, 10),
  createdAt: DateTime(2026, 11, 10),
);

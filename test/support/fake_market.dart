import 'dart:typed_data';

import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/listing_repository.dart';
import 'package:nexus_social/features/market/market_catalog_data.dart';
import 'package:nexus_social/features/market/market_models.dart';
import 'package:nexus_social/features/market/market_repository.dart';

/// Scambia & Vendi finto in memoria: nessun server.
class FakeMarketRepository implements MarketRepository {
  FakeMarketRepository({List<MyMarketListing>? items}) : items = items ?? <MyMarketListing>[];

  final List<MyMarketListing> items;
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
  Future<Uint8List?> downloadPhoto(String path) async => null;
}

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

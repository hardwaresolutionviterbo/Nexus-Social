import 'dart:typed_data';

import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/listing_repository.dart';

/// Annunci finti in memoria: nessun server.
class FakeListingRepository implements MapListingRepository {
  FakeListingRepository({List<MyListing>? items}) : items = items ?? <MyListing>[];

  final List<MyListing> items;
  final List<ListingDraft> published = <ListingDraft>[];
  final List<(String, ListingDraft)> updates = <(String, ListingDraft)>[];
  final List<(String, GeoPoint, ListingPlace)> moves = <(String, GeoPoint, ListingPlace)>[];
  final List<String> closed = <String>[];

  /// Se impostato, la prossima pubblicazione fallisce con questo messaggio.
  String? failWith;

  @override
  Future<String> publish(ListingDraft draft) async {
    final String? f = failWith;
    if (f != null) {
      failWith = null;
      throw ListingFailure(f);
    }
    published.add(draft);
    return 'annuncio-${published.length}';
  }

  @override
  Future<void> update(String id, ListingDraft draft) async => updates.add((id, draft));

  @override
  Future<void> move(String id, GeoPoint point, ListingPlace place) async =>
      moves.add((id, point, place));

  @override
  Future<void> close(String id) async {
    closed.add(id);
    final int i = items.indexWhere((MyListing x) => x.id == id);
    if (i >= 0) {
      final MyListing x = items[i];
      items[i] = MyListing(
        id: x.id,
        title: x.title,
        details: x.details,
        photos: x.photos,
        place: x.place,
        publicPoint: x.publicPoint,
        savedPoint: x.savedPoint,
        state: ListingState.completed,
        expiresAt: x.expiresAt,
        createdAt: x.createdAt,
      );
    }
  }

  @override
  Future<List<MyListing>> mine() async => List<MyListing>.of(items);

  @override
  Future<Uint8List?> downloadPhoto(String path) async => null;

  /// Annunci vicini restituiti dal «server» e richieste ricevute.
  List<NearbyListing> nearbyItems = <NearbyListing>[];
  final List<(GeoPoint, MapFilters, ListingTab)> nearbyCalls = <(GeoPoint, MapFilters, ListingTab)>[];
  final List<(String, bool)> availability = <(String, bool)>[];
  final List<(String, ReportReason, String?)> reports = <(String, ReportReason, String?)>[];

  @override
  Future<List<NearbyListing>> nearby(
    GeoPoint origin,
    MapFilters filters, {
    ListingTab tab = ListingTab.free,
  }) async {
    nearbyCalls.add((origin, filters, tab));
    return <NearbyListing>[
      for (final NearbyListing l in nearbyItems)
        if (l.category == tab.category && (!filters.availableNowOnly || l.availableNow)) l,
    ];
  }

  @override
  Future<void> setAvailableNow(String id, bool available) async =>
      availability.add((id, available));

  @override
  Future<void> report(String id, ReportReason reason, {String? details}) async =>
      reports.add((id, reason, details));
}

NearbyListing sampleNearby({
  String id = 'n1',
  String title = 'Ci manca uno per il calcetto, chi viene?',
  bool availableNow = false,
  bool isMine = false,
  String category = 'libera',
  int distance = 1250,
  DateTime? createdAt,
  DateTime? expiresAt,
}) => NearbyListing(
  id: id,
  title: title,
  details: 'Campo del quartiere, ore 21',
  category: category,
  place: ListingPlace.chosenPoint,
  point: const GeoPoint(43.7731, 11.256),
  distanceBandMeters: distance,
  availableNow: availableNow,
  expiresAt: expiresAt ?? DateTime(2026, 11, 15, 14),
  createdAt: createdAt ?? DateTime(2026, 11, 15, 10, 5),
  isMine: isMine,
  ownerId: 'utente-b',
  ownerUsername: 'marco_r',
  ownerPublicName: 'Marco R.',
);

MyListing sampleListing({
  String id = 'a1',
  String title = 'Chi viene a prendere un caffè?',
  ListingPlace place = ListingPlace.approximateZone,
  ListingState state = ListingState.active,
  DateTime? expiresAt,
}) => MyListing(
  id: id,
  title: title,
  details: 'Verso le 17',
  place: place,
  publicPoint: const GeoPoint(43.77, 11.255),
  savedPoint: const GeoPoint(43.7696, 11.2558),
  state: state,
  expiresAt: expiresAt ?? DateTime(2026, 11, 15, 14),
  createdAt: DateTime(2026, 11, 15, 11),
);

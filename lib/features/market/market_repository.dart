import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException, StorageException, SupabaseClient;

import '../map/listing_models.dart' show GeoPoint, ReportReason;
import '../map/listing_repository.dart' show ListingFailure, ListingPhotos, SupabaseMapListingRepository;
import 'market_models.dart';

/// Annunci di Scambia & Vendi sul server (migrazioni 0010-0013). Nei test: versione finta.
abstract class MarketRepository {
  Future<List<MarketCategory>> categories();

  Future<MarketPublishResult> publish(MarketDraft draft);

  Future<MarketPublishResult> update(String id, MarketDraft draft);

  Future<DateTime> renew(String id);

  Future<void> close(String id);

  Future<List<MyMarketListing>> mine();

  Future<Uint8List?> downloadPhoto(String path);

  /// Una pagina di risultati (20, D9) dalla posizione [offset].
  Future<List<MarketListing>> search(MarketSection section, MarketQuery query, {int offset = 0});

  /// La scheda; null se non esiste più o non è visibile. [origin] solo per la distanza.
  Future<MarketListing?> listing(String id, {GeoPoint? origin});

  Future<void> report(String id, ReportReason reason, {String? details});
}

class SupabaseMarketRepository implements MarketRepository {
  SupabaseMarketRepository(this._client, {required this.uid});

  static const String bucket = 'listing-photos';

  final SupabaseClient _client;
  final String Function() uid;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ListingFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw SupabaseMapListingRepository.failureFor(e.code, e.message);
    } on StorageException {
      throw const ListingFailure('La foto non è stata caricata. Riprova.');
    } catch (_) {
      throw const ListingFailure('Qualcosa non ha funzionato. Riprova.');
    }
  }

  @override
  Future<List<MarketCategory>> categories() => _guard(() async {
    final Object? data = await _client.rpc('marketplace_categories_list');
    return <MarketCategory>[
      if (data is List)
        for (final Object? r in data)
          if (r is Map<String, dynamic>) MarketCategory.fromJson(r),
    ];
  });

  Map<String, Object?> _fields(MarketDraft d, List<String> photos) => <String, Object?>{
    'p_category': d.categoryId,
    'p_title': d.title.trim(),
    'p_description': d.description.trim(),
    'p_price_cents': d.priceCents,
    'p_condition': d.condition?.serverValue,
    'p_ships': d.ships,
    'p_pickup': d.pickup,
    'p_attributes': d.attributes,
    'p_photos': photos,
    'p_wanted_in_exchange': (d.wantedInExchange?.trim().isEmpty ?? true)
        ? null
        : d.wantedInExchange!.trim(),
    'p_open_to_swap': d.type == MarketType.sell && d.openToSwap,
    'p_cash_adjustment': d.cashAdjustment,
  };

  static MarketPublishResult _result(Object? data) {
    final Map<String, dynamic> m = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    return MarketPublishResult(
      id: '${m['id']}',
      pendingReview: m['review_status'] == 'pending_review',
    );
  }

  @override
  Future<MarketPublishResult> publish(MarketDraft d) => _guard(() async {
    final List<String> photos = await _upload(d);
    final Object? data = await _client.rpc(
      'publish_market_listing',
      params: <String, Object?>{
        'p_type': d.type.serverValue,
        ..._fields(d, photos),
        'p_lat': d.point.latitude,
        'p_lon': d.point.longitude,
        'p_location_mode': d.place.serverValue,
        'p_no_prohibited_items': d.noProhibitedItems,
      },
    );
    return _result(data);
  });

  @override
  Future<MarketPublishResult> update(String id, MarketDraft d) => _guard(() async {
    final List<String> photos = await _upload(d);
    final Object? data = await _client.rpc(
      'update_market_listing',
      params: <String, Object?>{'p_id': id, ..._fields(d, photos)},
    );
    return _result(data);
  });

  @override
  Future<DateTime> renew(String id) => _guard(() async {
    final Object? until = await _client.rpc(
      'renew_market_listing',
      params: <String, Object?>{'p_id': id},
    );
    return DateTime.parse('$until').toLocal();
  });

  @override
  Future<void> close(String id) => _guard(() async {
    await _client.rpc('close_market_listing', params: <String, Object?>{'p_id': id});
  });

  @override
  Future<List<MyMarketListing>> mine() => _guard(() async {
    final Object? data = await _client.rpc('my_market_listings');
    return <MyMarketListing>[
      if (data is List)
        for (final Object? r in data)
          if (r is Map<String, dynamic>) MyMarketListing.fromJson(r),
    ];
  });

  static List<MarketListing> _listings(Object? data) => <MarketListing>[
    if (data is List)
      for (final Object? r in data)
        if (r is Map<String, dynamic>) MarketListing.fromJson(r),
  ];

  @override
  Future<List<MarketListing>> search(MarketSection section, MarketQuery query, {int offset = 0}) =>
      _guard(() async {
        final Object? data = await _client.rpc(
          'market_search',
          params: query.toParams(section, offset: offset),
        );
        return _listings(data);
      });

  @override
  Future<MarketListing?> listing(String id, {GeoPoint? origin}) => _guard(() async {
    final Object? data = await _client.rpc(
      'market_listing',
      params: <String, Object?>{
        'p_id': id,
        'p_lat': origin?.latitude,
        'p_lon': origin?.longitude,
      },
    );
    final List<MarketListing> l = _listings(data);
    return l.isEmpty ? null : l.first;
  });

  @override
  Future<void> report(String id, ReportReason reason, {String? details}) => _guard(() async {
    await _client.rpc(
      'report_listing',
      params: <String, Object?>{
        'p_listing': id,
        'p_reason': reason.serverValue,
        'p_details': details?.trim().isEmpty ?? true ? null : details!.trim(),
      },
    );
  });

  @override
  Future<Uint8List?> downloadPhoto(String path) async {
    try {
      return await _client.storage.from(bucket).download(path);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _upload(MarketDraft d) async {
    final List<String> paths = <String>[...d.keptPhotos];
    const FileOptions options = FileOptions(contentType: 'image/jpeg', upsert: false);
    for (final Uint8List raw in d.newPhotos) {
      final Uint8List jpg = await ListingPhotos.prepareInBackground(raw);
      final String path = '${uid()}/${_token()}.jpg';
      await _client.storage.from(bucket).uploadBinary(path, jpg, fileOptions: options);
      paths.add(path);
    }
    return paths;
  }

  static String _token() {
    const String chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final Random r = Random.secure();
    return List<String>.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

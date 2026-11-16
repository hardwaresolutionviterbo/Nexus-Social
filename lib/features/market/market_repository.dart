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

  // Proposte di scambio (Blocco 3, migrazione 0014).

  /// Annunci che si possono offrire: i propri, o in una controproposta quelli di chi chiede.
  Future<List<SwapItem>> swapCandidates({String? proposalId});

  Future<String> proposeSwap(String listingId, SwapOffer offer);

  Future<String> counterSwap(String proposalId, SwapOffer offer);

  /// true = accetta, false = rifiuta.
  Future<SwapStatus> respondSwap(String proposalId, {required bool accept});

  Future<void> cancelSwap(String proposalId);

  Future<List<SwapProposal>> mySwaps();

  // Conclusione e feedback (Blocco 4, migrazione 0015).

  Future<List<DealCandidate>> dealCandidates(String listingId);

  Future<String> markConcluded(String listingId, String otherId);

  /// «waiting» finché manca l'altra parte, «completed» a conclusione avvenuta.
  Future<String> confirmSwapConcluded(String proposalId);

  /// true = confermo, false = non è avvenuto.
  Future<String> answerDeal(String dealId, {required bool confirm});

  Future<void> cancelDeal(String dealId);

  Future<void> leaveFeedback(String dealId, int stars, String comment);

  Future<FeedbackSummary> feedbackSummary(String userId);

  Future<List<FeedbackEntry>> feedbackList(String userId, {int offset = 0});

  Future<List<MarketDeal>> myDeals();
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
  Future<List<SwapItem>> swapCandidates({String? proposalId}) => _guard(() async {
    final Object? data = await _client.rpc(
      'swap_offer_candidates',
      params: <String, Object?>{'p_proposal': proposalId},
    );
    return <SwapItem>[
      if (data is List)
        for (final Object? r in data)
          if (r is Map<String, dynamic>) SwapItem.fromJson(r),
    ];
  });

  @override
  Future<String> proposeSwap(String listingId, SwapOffer offer) => _guard(() async {
    final Object? id = await _client.rpc(
      'propose_swap',
      params: <String, Object?>{'p_listing': listingId, ...offer.toParams()},
    );
    return '$id';
  });

  @override
  Future<String> counterSwap(String proposalId, SwapOffer offer) => _guard(() async {
    final Object? id = await _client.rpc(
      'counter_swap',
      params: <String, Object?>{'p_proposal': proposalId, ...offer.toParams()},
    );
    return '$id';
  });

  @override
  Future<SwapStatus> respondSwap(String proposalId, {required bool accept}) => _guard(() async {
    final Object? s = await _client.rpc(
      'respond_swap',
      params: <String, Object?>{'p_proposal': proposalId, 'p_accept': accept},
    );
    return SwapStatus.fromServer('$s');
  });

  @override
  Future<void> cancelSwap(String proposalId) => _guard(() async {
    await _client.rpc('cancel_swap', params: <String, Object?>{'p_proposal': proposalId});
  });

  @override
  Future<List<SwapProposal>> mySwaps() => _guard(() async {
    final Object? data = await _client.rpc('my_swap_proposals');
    return <SwapProposal>[
      if (data is List)
        for (final Object? r in data)
          if (r is Map<String, dynamic>) SwapProposal.fromJson(r),
    ];
  });

  static List<Map<String, dynamic>> _rows(Object? data) => <Map<String, dynamic>>[
    if (data is List)
      for (final Object? r in data)
        if (r is Map<String, dynamic>) r,
  ];

  @override
  Future<List<DealCandidate>> dealCandidates(String listingId) => _guard(() async {
    final Object? data = await _client.rpc(
      'deal_candidates',
      params: <String, Object?>{'p_listing': listingId},
    );
    return _rows(data).map(DealCandidate.fromJson).toList();
  });

  @override
  Future<String> markConcluded(String listingId, String otherId) => _guard(() async {
    final Object? id = await _client.rpc(
      'mark_listing_concluded',
      params: <String, Object?>{'p_listing': listingId, 'p_other': otherId},
    );
    return '$id';
  });

  @override
  Future<String> confirmSwapConcluded(String proposalId) => _guard(() async {
    final Object? s = await _client.rpc(
      'confirm_swap_concluded',
      params: <String, Object?>{'p_proposal': proposalId},
    );
    return '$s';
  });

  @override
  Future<String> answerDeal(String dealId, {required bool confirm}) => _guard(() async {
    final Object? s = await _client.rpc(
      'answer_deal',
      params: <String, Object?>{'p_deal': dealId, 'p_confirm': confirm},
    );
    return '$s';
  });

  @override
  Future<void> cancelDeal(String dealId) => _guard(() async {
    await _client.rpc('cancel_deal', params: <String, Object?>{'p_deal': dealId});
  });

  @override
  Future<void> leaveFeedback(String dealId, int stars, String comment) => _guard(() async {
    await _client.rpc(
      'leave_feedback',
      params: <String, Object?>{'p_deal': dealId, 'p_stars': stars, 'p_comment': comment.trim()},
    );
  });

  @override
  Future<FeedbackSummary> feedbackSummary(String userId) => _guard(() async {
    final Object? data = await _client.rpc(
      'feedback_summary',
      params: <String, Object?>{'p_user': userId},
    );
    final List<Map<String, dynamic>> r = _rows(data);
    return r.isEmpty ? const FeedbackSummary() : FeedbackSummary.fromJson(r.first);
  });

  @override
  Future<List<FeedbackEntry>> feedbackList(String userId, {int offset = 0}) => _guard(() async {
    final Object? data = await _client.rpc(
      'feedback_list',
      params: <String, Object?>{'p_user': userId, 'p_offset': offset},
    );
    return _rows(data).map(FeedbackEntry.fromJson).toList();
  });

  @override
  Future<List<MarketDeal>> myDeals() => _guard(() async {
    final Object? data = await _client.rpc('my_deals');
    return _rows(data).map(MarketDeal.fromJson).toList();
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

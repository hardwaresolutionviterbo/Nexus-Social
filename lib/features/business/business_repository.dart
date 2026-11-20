import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'business_models.dart';
import 'promotion_models.dart';

/// Dati delle attività sul server (Fase 6). Nei test: una versione in memoria.
abstract class BusinessRepository {
  /// I miei dati Azienda e la mia pagina (null se non sono registrato come Azienda).
  Future<MyBusiness?> mine();

  /// Registra (o corregge) ragione sociale e partita IVA; un Privato diventa Azienda.
  Future<void> register({required String businessName, required String vatNumber});

  /// Salva la pagina; [newPhotos] sono immagini da aggiungere (vengono ridotte e caricate).
  Future<void> savePage(BusinessPageDraft draft, {List<Uint8List> newPhotos = const <Uint8List>[]});

  /// Documento facoltativo (foto JPEG o PDF): lo vedono solo l'azienda e gli amministratori.
  Future<void> setDocument(Uint8List bytes, {required bool pdf});

  Future<BusinessPage?> page(String id);

  Future<List<BusinessPin>> nearby(double lat, double lng, {int radiusKm = 20});

  Future<Uint8List?> photo(String path);

  // ---- Promozioni e coupon (Blocco 3)

  /// Crea una promozione (solo con Premium; 5 al giorno). Restituisce l'identificativo.
  Future<String> createPromotion(PromotionDraft draft);

  Future<void> cancelPromotion(String id);

  /// Le mie promozioni (anche finite) con i conteggi.
  Future<List<Promotion>> myPromotions();

  Future<List<Promotion>> promotionsNearby(double lat, double lng, {int radiusKm = 20});

  Future<List<Promotion>> promotionsOf(String businessId);

  /// Prendo il coupon: restituisce il mio codice (sempre lo stesso).
  Future<String> claimCoupon(String promotionId);

  Future<List<Promotion>> myCoupons();

  /// Il titolare convalida un coupon (dal QR o scritto a mano).
  Future<CouponCheck> redeemCoupon(String code);

  /// Prova gratuita di 7 giorni (una sola volta per azienda e per partita IVA).
  Future<BusinessSubscription> startTrial();

  /// Solo amministratori: attiva o prolunga di [months] mesi, oppure ferma subito.
  Future<void> adminExtendSubscription(String id, {int months = 1});

  Future<void> adminStopSubscription(String id);

  /// Solo amministratori.
  Future<List<BusinessReviewItem>> reviewQueue();

  Future<void> review(String id, {required bool approve, String note = ''});

  Future<Uint8List?> document(String path);
}

/// Quella dell'app (la imposta main.dart).
abstract final class BusinessRegistry {
  static BusinessRepository? current;
}

/// Foto ridotta a 1600 px, JPEG.
Future<Uint8List?> prepareBusinessPhoto(Uint8List original) => compute(_prepare, original);

Uint8List? _prepare(Uint8List original) {
  final img.Image? decoded = img.decodeImage(original);
  if (decoded == null) return null;
  final img.Image upright = img.bakeOrientation(decoded);
  final img.Image big = upright.width > 1600 || upright.height > 1600
      ? img.copyResize(
          upright,
          width: upright.width >= upright.height ? 1600 : null,
          height: upright.height > upright.width ? 1600 : null,
        )
      : upright;
  return img.encodeJpg(big, quality: 82);
}

class SupabaseBusinessRepository implements BusinessRepository {
  SupabaseBusinessRepository(this._client, {required this.uid});

  final SupabaseClient _client;
  final String Function() uid;

  static const String photosBucket = 'aziende';
  static const String documentsBucket = 'aziende_documenti';

  final Map<String, Uint8List> _photoCache = <String, Uint8List>{};
  final math.Random _random = math.Random.secure();

  String _token() {
    const String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List<String>.generate(20, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  Future<Object?> _rpc(String name, [Map<String, Object?>? params]) async {
    try {
      return await _client.rpc(name, params: params);
    } on PostgrestException catch (e) {
      if (e.code == '22023' || e.code == '23505') {
        throw BusinessFailure(e.message.endsWith('.') ? e.message : '${e.message}.');
      }
      if (e.code == '42501') throw const BusinessFailure('Operazione non permessa.');
      throw const BusinessFailure('Non è stato possibile: riprova tra poco.');
    } on BusinessFailure {
      rethrow;
    } catch (_) {
      throw const BusinessFailure('Connessione assente. Riprova tra poco.');
    }
  }

  static List<Map<String, dynamic>> _rows(Object? r) => <Map<String, dynamic>>[
    for (final Object? x in (r as List<dynamic>? ?? const <dynamic>[])) x as Map<String, dynamic>,
  ];

  @override
  Future<MyBusiness?> mine() async {
    final Object? r = await _rpc('business_mine');
    return r is Map<String, dynamic> ? MyBusiness.fromJson(r) : null;
  }

  @override
  Future<void> register({required String businessName, required String vatNumber}) async {
    await _rpc('business_register', <String, Object?>{
      'p_business_name': businessName.trim(),
      'p_vat_number': vatNumber.replaceAll(' ', ''),
    });
  }

  @override
  Future<void> savePage(BusinessPageDraft d, {List<Uint8List> newPhotos = const <Uint8List>[]}) async {
    final String me = uid();
    final List<String> photos = <String>[...d.keptPhotos];
    final List<String> uploaded = <String>[];
    try {
      for (final Uint8List raw in newPhotos) {
        if (photos.length >= 6) break;
        final Uint8List? jpeg = await prepareBusinessPhoto(raw);
        if (jpeg == null) throw const BusinessFailure('Una delle foto non si apre: scegline un\'altra.');
        final String path = '$me/foto-${_token()}.jpg';
        await _client.storage.from(photosBucket).uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
        );
        uploaded.add(path);
        photos.add(path);
      }
    } on BusinessFailure {
      rethrow;
    } catch (_) {
      if (uploaded.isNotEmpty) await _remove(photosBucket, uploaded);
      throw const BusinessFailure('Caricamento delle foto non riuscito. Riprova.');
    }
    final MyBusiness? before = await mine();
    try {
      await _rpc('business_page_save', <String, Object?>{
        'p_display_name': d.displayName.trim(),
        'p_category': d.category.key,
        'p_description': d.description.trim(),
        'p_street': d.address.street.trim(),
        'p_civic': d.address.civic.trim(),
        'p_city': d.address.city.trim(),
        'p_cap': d.address.cap.trim(),
        'p_province': d.address.province.trim().toUpperCase(),
        'p_lat': d.lat,
        'p_lng': d.lng,
        'p_phone': d.phone.trim(),
        'p_booking_url': d.bookingUrl.trim(),
        'p_hours': d.hours.toJson(),
        'p_photos': photos,
        'p_published': d.published,
      });
    } catch (_) {
      if (uploaded.isNotEmpty) await _remove(photosBucket, uploaded);
      rethrow;
    }
    // Foto tolte dalla pagina: si cancellano anche dal server.
    final List<String> removed = <String>[
      for (final String p in before?.page?.photos ?? const <String>[]) if (!photos.contains(p)) p,
    ];
    if (removed.isNotEmpty) await _remove(photosBucket, removed);
  }

  Future<void> _remove(String bucket, List<String> paths) async {
    try {
      await _client.storage.from(bucket).remove(paths);
    } catch (_) {
      // Resta un file in più: nessun dato personale, si potrà ripulire.
    }
  }

  @override
  Future<void> setDocument(Uint8List bytes, {required bool pdf}) async {
    if (bytes.length > 10 * 1024 * 1024) throw const BusinessFailure('Documento troppo grande (massimo 10 MB).');
    final String path = '${uid()}/documento-${_token()}.${pdf ? 'pdf' : 'jpg'}';
    try {
      await _client.storage.from(documentsBucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: pdf ? 'application/pdf' : 'image/jpeg', upsert: false),
      );
    } catch (_) {
      throw const BusinessFailure('Caricamento del documento non riuscito. Riprova.');
    }
    await _rpc('business_set_document', <String, Object?>{'p_path': path});
  }

  @override
  Future<BusinessPage?> page(String id) async {
    final Object? r = await _rpc('business_page_get', <String, Object?>{'p_id': id});
    return r is Map<String, dynamic> ? BusinessPage.fromJson(r) : null;
  }

  @override
  Future<List<BusinessPin>> nearby(double lat, double lng, {int radiusKm = 20}) async => <BusinessPin>[
    for (final Map<String, dynamic> r in _rows(await _rpc('businesses_nearby', <String, Object?>{
      'p_lat': lat,
      'p_lng': lng,
      'p_radius_km': radiusKm.clamp(1, 50),
    })))
      BusinessPin(
        id: '${r['id']}',
        displayName: '${r['display_name'] ?? ''}',
        category: BusinessCategory.fromKey(r['category']),
        lat: (r['lat'] as num).toDouble(),
        lng: (r['lng'] as num).toDouble(),
        verified: r['verified'] == true,
      ),
  ];

  @override
  Future<Uint8List?> photo(String path) async {
    final Uint8List? cached = _photoCache[path];
    if (cached != null) return cached;
    try {
      final Uint8List bytes = await _client.storage.from(photosBucket).download(path);
      if (_photoCache.length > 60) _photoCache.remove(_photoCache.keys.first);
      return _photoCache[path] = bytes;
    } catch (_) {
      return null;
    }
  }

  static List<Promotion> _promos(Object? r) => <Promotion>[
    for (final Object? x in (r as List<dynamic>? ?? const <dynamic>[]))
      if (x is Map<String, dynamic>) Promotion.fromJson(x),
  ];

  @override
  Future<String> createPromotion(PromotionDraft d) async {
    final Object? id = await _rpc('promotion_create', <String, Object?>{
      'p_kind': d.kind.key,
      'p_title': d.title.trim(),
      'p_description': d.description.trim(),
      'p_starts_at': d.startsAt.toUtc().toIso8601String(),
      'p_ends_at': d.endsAt.toUtc().toIso8601String(),
      'p_lat': d.lat,
      'p_lng': d.lng,
      'p_place_label': d.placeLabel.trim(),
      'p_coupon_text': d.couponText.trim(),
      'p_coupon_limit': d.couponText.trim().isEmpty ? null : d.couponLimit,
    });
    return '$id';
  }

  @override
  Future<void> cancelPromotion(String id) async {
    await _rpc('promotion_cancel', <String, Object?>{'p_id': id});
  }

  @override
  Future<List<Promotion>> myPromotions() async => _promos(await _rpc('promotions_mine'));

  @override
  Future<List<Promotion>> promotionsNearby(double lat, double lng, {int radiusKm = 20}) async => _promos(
    await _rpc('promotions_nearby', <String, Object?>{'p_lat': lat, 'p_lng': lng, 'p_radius_km': radiusKm.clamp(1, 50)}),
  );

  @override
  Future<List<Promotion>> promotionsOf(String businessId) async =>
      _promos(await _rpc('promotions_of', <String, Object?>{'p_business_id': businessId}));

  @override
  Future<String> claimCoupon(String promotionId) async =>
      '${await _rpc('coupon_claim', <String, Object?>{'p_promotion_id': promotionId})}';

  @override
  Future<List<Promotion>> myCoupons() async => _promos(await _rpc('coupons_mine'));

  @override
  Future<CouponCheck> redeemCoupon(String code) async {
    final Object? r = await _rpc('coupon_redeem', <String, Object?>{'p_code': PromotionRules.normalizeCode(code)});
    final Map<String, dynamic> j = r is Map<String, dynamic> ? r : const <String, dynamic>{};
    return CouponCheck(
      title: '${j['title'] ?? ''}',
      couponText: '${j['coupon_text'] ?? ''}',
      redeemed: (j['redeemed'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<BusinessSubscription> startTrial() async =>
      BusinessSubscription.fromJson(await _rpc('subscription_start_trial'));

  @override
  Future<void> adminExtendSubscription(String id, {int months = 1}) async {
    await _rpc('subscription_admin_extend', <String, Object?>{'p_id': id, 'p_months': months.clamp(1, 12)});
  }

  @override
  Future<void> adminStopSubscription(String id) async {
    await _rpc('subscription_admin_stop', <String, Object?>{'p_id': id});
  }

  @override
  Future<List<BusinessReviewItem>> reviewQueue() async => <BusinessReviewItem>[
    for (final Map<String, dynamic> r in _rows(await _rpc('business_review_queue'))) BusinessReviewItem.fromJson(r),
  ];

  @override
  Future<void> review(String id, {required bool approve, String note = ''}) async {
    await _rpc('business_review', <String, Object?>{'p_id': id, 'p_approve': approve, 'p_note': note.trim()});
  }

  @override
  Future<Uint8List?> document(String path) async {
    try {
      return await _client.storage.from(documentsBucket).download(path);
    } catch (_) {
      return null;
    }
  }
}

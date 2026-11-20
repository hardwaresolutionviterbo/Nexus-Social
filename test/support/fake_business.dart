import 'dart:typed_data';

import 'package:nexus_social/features/business/business_models.dart';
import 'package:nexus_social/features/business/business_repository.dart';
import 'package:nexus_social/features/business/promotion_models.dart';
import 'package:nexus_social/features/profile/profile_models.dart';

/// Aziende in memoria, con gli stessi controlli principali del server.
class FakeBusinessRepository implements BusinessRepository {
  FakeBusinessRepository({this.me = 'utenteAnna000000000000000001'});

  String me;
  final Map<String, MyBusiness> registered = <String, MyBusiness>{};
  final Map<String, BusinessPage> pages = <String, BusinessPage>{};
  final Map<String, String> usernames = <String, String>{};
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final Map<String, BusinessSubscription> subscriptions = <String, BusinessSubscription>{};
  final Set<String> trialVats = <String>{};
  DateTime Function() clock = DateTime.now;
  int _n = 0;
  double? askedLat;

  bool _active(String id) => subscriptions[id]?.isActive(clock()) ?? false;

  /// Badge: approvata e con Premium attivo.
  bool badge(String id) => registered[id]?.status == VerificationStatus.verified && _active(id);

  BusinessSubscription _sub(String id) {
    final BusinessSubscription s = subscriptions[id] ?? const BusinessSubscription();
    final bool used = trialVats.contains(registered[id]?.vatNumber);
    return BusinessSubscription(periodEnd: s.periodEnd, source: s.source, trialUsed: used || s.trialUsed);
  }

  @override
  Future<MyBusiness?> mine() async {
    final MyBusiness? b = registered[me];
    if (b == null) return null;
    return MyBusiness(
      businessName: b.businessName,
      vatNumber: b.vatNumber,
      status: b.status,
      reviewNote: b.reviewNote,
      hasDocument: b.hasDocument,
      page: pages[me],
      verifiedBadge: badge(me),
      subscription: _sub(me),
    );
  }

  // ---- Promozioni e coupon
  final Map<String, PromotionDraft> drafts = <String, PromotionDraft>{};
  final Map<String, String> promoOwner = <String, String>{};
  final Map<String, DateTime> promoCreated = <String, DateTime>{};
  final Set<String> canceledPromos = <String>{};

  /// codice → (promozione, cliente, convalidato)
  final Map<String, (String, String, bool)> coupons = <String, (String, String, bool)>{};
  int _codes = 0;

  Promotion _promo(String id, {bool stats = false}) {
    final PromotionDraft d = drafts[id]!;
    final String owner = promoOwner[id]!;
    final BusinessPage page = pages[owner]!;
    final MapEntry<String, (String, String, bool)>? mine = coupons.entries
        .where((MapEntry<String, (String, String, bool)> e) => e.value.$1 == id && e.value.$2 == me)
        .firstOrNull;
    final int claimed = coupons.values.where(((String, String, bool) c) => c.$1 == id).length;
    final DateTime now = clock();
    final DateTime made = promoCreated[id]!;
    return Promotion(
      id: id,
      businessId: owner,
      kind: d.kind,
      title: d.title.trim(),
      description: d.description.trim(),
      startsAt: d.startsAt,
      endsAt: d.endsAt,
      lat: d.lat ?? page.lat,
      lng: d.lng ?? page.lng,
      placeLabel: d.placeLabel,
      atSite: d.lat == null,
      couponText: d.couponText.trim(),
      couponLimit: d.couponLimit,
      couponsLeft: d.couponLimit == null ? null : (d.couponLimit! - claimed).clamp(0, 1 << 30),
      businessName: page.displayName,
      category: page.category,
      businessAddress: page.address.label,
      verified: badge(owner),
      mine: owner == me,
      myCoupon: mine?.key,
      myCouponUsed: mine?.value.$3 ?? false,
      canceled: stats && canceledPromos.contains(id),
      claimed: stats ? claimed : 0,
      redeemed: stats ? coupons.values.where(((String, String, bool) c) => c.$1 == id && c.$3).length : 0,
      createdToday: stats && made.year == now.year && made.month == now.month && made.day == now.day,
    );
  }

  bool _visible(String id) {
    final DateTime now = clock();
    final PromotionDraft d = drafts[id]!;
    final String owner = promoOwner[id]!;
    return !canceledPromos.contains(id) &&
        d.endsAt.isAfter(now) &&
        !d.startsAt.isAfter(now.add(const Duration(days: 7))) &&
        _active(owner) &&
        (pages[owner]?.published ?? false);
  }

  @override
  Future<String> createPromotion(PromotionDraft d) async {
    if (pages[me] == null) throw const BusinessFailure('Crea prima il profilo attività.');
    if (!_active(me)) {
      throw const BusinessFailure('Le promozioni sono una funzione Premium: attiva la prova o l\'abbonamento.');
    }
    final String? err = d.check(clock());
    if (err != null) throw BusinessFailure(err);
    final DateTime now = clock();
    final int today = promoCreated.entries
        .where((MapEntry<String, DateTime> e) =>
            promoOwner[e.key] == me && e.value.year == now.year && e.value.month == now.month && e.value.day == now.day)
        .length;
    if (today >= PromotionRules.maxPerDay) throw const BusinessFailure('Hai già creato 5 promozioni oggi: riprova domani.');
    final String id = 'promo${drafts.length + 1}';
    drafts[id] = d;
    promoOwner[id] = me;
    promoCreated[id] = now;
    return id;
  }

  @override
  Future<void> cancelPromotion(String id) async => canceledPromos.add(id);

  @override
  Future<List<Promotion>> myPromotions() async => <Promotion>[
    for (final String id in drafts.keys.toList().reversed)
      if (promoOwner[id] == me) _promo(id, stats: true),
  ];

  @override
  Future<List<Promotion>> promotionsNearby(double lat, double lng, {int radiusKm = 20}) async => <Promotion>[
    for (final String id in drafts.keys)
      if (_visible(id)) _promo(id),
  ];

  @override
  Future<List<Promotion>> promotionsOf(String businessId) async => <Promotion>[
    for (final String id in drafts.keys)
      if (promoOwner[id] == businessId && _visible(id)) _promo(id),
  ];

  @override
  Future<String> claimCoupon(String promotionId) async {
    if (!_visible(promotionId)) throw const BusinessFailure('Promozione non disponibile.');
    final PromotionDraft d = drafts[promotionId]!;
    if (d.couponText.trim().isEmpty) throw const BusinessFailure('Questa promozione non ha coupon.');
    if (promoOwner[promotionId] == me) throw const BusinessFailure('Non puoi prendere i coupon della tua attività.');
    final String? have = _promo(promotionId).myCoupon;
    if (have != null) return have;
    final int taken = coupons.values.where(((String, String, bool) c) => c.$1 == promotionId).length;
    if (d.couponLimit != null && taken >= d.couponLimit!) throw const BusinessFailure('Coupon esauriti.');
    const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final int n = ++_codes;
    final String code = List<String>.generate(8, (int i) => alphabet[(n * 7 + i * 13) % 32]).join();
    coupons[code] = (promotionId, me, false);
    return code;
  }

  @override
  Future<List<Promotion>> myCoupons() async => <Promotion>[
    for (final (String, String, bool) c in coupons.values)
      if (c.$2 == me) _promo(c.$1),
  ];

  @override
  Future<CouponCheck> redeemCoupon(String code) async {
    final String c = PromotionRules.normalizeCode(code);
    final (String, String, bool)? found = coupons[c];
    if (found == null || promoOwner[found.$1] != me) {
      throw const BusinessFailure('Codice non valido per la tua attività.');
    }
    if (found.$3) throw const BusinessFailure('Coupon già usato.');
    if (canceledPromos.contains(found.$1) || !drafts[found.$1]!.endsAt.isAfter(clock())) {
      throw const BusinessFailure('Promozione finita.');
    }
    coupons[c] = (found.$1, found.$2, true);
    final PromotionDraft d = drafts[found.$1]!;
    return CouponCheck(
      title: d.title,
      couponText: d.couponText,
      redeemed: coupons.values.where(((String, String, bool) x) => x.$1 == found.$1 && x.$3).length,
    );
  }

  // ---- Recensioni: (attività, autore) → (stelle, testo, risposta, nome pubblico)
  final Map<(String, String), (int, String, String, String)> reviewsByKey =
      <(String, String), (int, String, String, String)>{};
  final Map<String, String> publicNames = <String, String>{};

  bool _verifiedCustomer(String business, String user) => coupons.values.any(
    ((String, String, bool) c) => c.$2 == user && c.$3 && promoOwner[c.$1] == business,
  );

  String _reviewId((String, String) k) => 'rev-${k.$1}-${k.$2}';

  @override
  Future<BusinessReviews> reviews(String businessId) async {
    final List<MapEntry<(String, String), (int, String, String, String)>> mine = reviewsByKey.entries
        .where((MapEntry<(String, String), (int, String, String, String)> e) => e.key.$1 == businessId)
        .toList();
    final List<BusinessReview> items = <BusinessReview>[
      for (final MapEntry<(String, String), (int, String, String, String)> e in mine)
        BusinessReview(
          id: _reviewId(e.key),
          author: e.value.$4,
          rating: e.value.$1,
          body: e.value.$2,
          reply: e.value.$3,
          createdAt: clock(),
          mine: e.key.$2 == me,
        ),
    ];
    return BusinessReviews(
      average: items.isEmpty ? null : items.map((BusinessReview r) => r.rating).reduce((int a, int b) => a + b) / items.length,
      count: items.length,
      canReview: businessId != me && _verifiedCustomer(businessId, me),
      ownerView: businessId == me,
      items: items,
    );
  }

  @override
  Future<void> saveReview(String businessId, {required int rating, String body = ''}) async {
    if (businessId == me) throw const BusinessFailure('Non puoi recensire la tua attività.');
    if (!_verifiedCustomer(businessId, me)) {
      throw const BusinessFailure('Puoi recensire solo dopo aver usato un suo coupon in cassa.');
    }
    final (int, String, String, String)? old = reviewsByKey[(businessId, me)];
    reviewsByKey[(businessId, me)] = (rating, body.trim(), old?.$3 ?? '', publicNames[me] ?? 'Cliente');
  }

  @override
  Future<void> deleteMyReview(String businessId) async => reviewsByKey.remove((businessId, me));

  @override
  Future<void> replyReview(String reviewId, String reply) async {
    for (final (String, String) k in reviewsByKey.keys.toList()) {
      if (_reviewId(k) == reviewId && k.$1 == me) {
        final (int, String, String, String) v = reviewsByKey[k]!;
        reviewsByKey[k] = (v.$1, v.$2, reply.trim(), v.$4);
        return;
      }
    }
    throw const BusinessFailure('Recensione non trovata.');
  }

  @override
  Future<void> adminDeleteReview(String reviewId) async =>
      reviewsByKey.removeWhere(((String, String) k, _) => _reviewId(k) == reviewId);

  @override
  Future<BusinessSubscription> startTrial() async {
    final MyBusiness? b = registered[me];
    if (b == null) throw const BusinessFailure('Registra prima l\'azienda.');
    if (_sub(me).trialUsed) throw const BusinessFailure('La prova gratuita è già stata usata.');
    if (_active(me)) throw const BusinessFailure('L\'abbonamento è già attivo.');
    trialVats.add(b.vatNumber);
    subscriptions[me] = BusinessSubscription(
      periodEnd: clock().add(const Duration(days: 7)),
      source: 'trial',
      trialUsed: true,
    );
    return _sub(me);
  }

  @override
  Future<void> adminExtendSubscription(String id, {int months = 1}) async {
    final DateTime now = clock();
    final DateTime? end = subscriptions[id]?.periodEnd;
    final DateTime from = end != null && end.isAfter(now) ? end : now;
    subscriptions[id] = BusinessSubscription(
      periodEnd: DateTime(from.year, from.month + months, from.day, from.hour, from.minute),
      source: 'admin',
    );
  }

  @override
  Future<void> adminStopSubscription(String id) async {
    final BusinessSubscription? s = subscriptions[id];
    if (s != null) subscriptions[id] = BusinessSubscription(periodEnd: clock(), source: s.source);
  }

  @override
  Future<void> register({required String businessName, required String vatNumber}) async {
    final String vat = vatNumber.replaceAll(' ', '');
    if (!ProfileRules.isValidPartitaIva(vat)) throw const BusinessFailure('Partita IVA non valida.');
    if (registered.entries.any((MapEntry<String, MyBusiness> e) => e.key != me && e.value.vatNumber == vat)) {
      throw const BusinessFailure('Questa partita IVA è già registrata su Piazly.');
    }
    final MyBusiness? old = registered[me];
    final bool changed = old == null || old.businessName != businessName.trim() || old.vatNumber != vat;
    registered[me] = MyBusiness(
      businessName: businessName.trim(),
      vatNumber: vat,
      status: changed ? VerificationStatus.pending : old.status,
      hasDocument: old?.hasDocument ?? false,
      reviewNote: changed ? '' : old.reviewNote,
    );
  }

  @override
  Future<void> savePage(BusinessPageDraft d, {List<Uint8List> newPhotos = const <Uint8List>[]}) async {
    if (registered[me] == null) throw const BusinessFailure('Registra prima l\'azienda.');
    if (!d.inItaly) throw const BusinessFailure('La sede deve essere in Italia.');
    final List<String> photos = <String>[...d.keptPhotos];
    for (final Uint8List b in newPhotos) {
      final String path = '$me/foto-${(++_n).toString().padLeft(8, '0')}.jpg';
      files[path] = b;
      photos.add(path);
    }
    pages[me] = BusinessPage(
      id: me,
      displayName: d.displayName.trim(),
      category: d.category,
      address: d.address,
      lat: d.lat,
      lng: d.lng,
      description: d.description.trim(),
      phone: d.phone.trim(),
      bookingUrl: d.bookingUrl.trim(),
      hours: d.hours,
      photos: photos,
      published: d.published,
    );
  }

  @override
  Future<void> setDocument(Uint8List bytes, {required bool pdf}) async {
    final MyBusiness b = registered[me]!;
    final String path = '$me/documento-${(++_n).toString().padLeft(8, '0')}.${pdf ? 'pdf' : 'jpg'}';
    files[path] = bytes;
    registered[me] = MyBusiness(
      businessName: b.businessName,
      vatNumber: b.vatNumber,
      status: b.status,
      reviewNote: b.reviewNote,
      hasDocument: true,
    );
  }

  @override
  Future<BusinessPage?> page(String id) async {
    final BusinessPage? p = pages[id];
    if (p == null || (!p.published && id != me)) return null;
    return BusinessPage(
      id: p.id,
      displayName: p.displayName,
      category: p.category,
      address: p.address,
      lat: p.lat,
      lng: p.lng,
      description: p.description,
      phone: p.phone,
      bookingUrl: p.bookingUrl,
      hours: p.hours,
      photos: p.photos,
      published: p.published,
      verified: badge(id),
      username: usernames[id] ?? '',
      mine: id == me,
    );
  }

  @override
  Future<List<BusinessPin>> nearby(double lat, double lng, {int radiusKm = 20}) async {
    askedLat = lat;
    return <BusinessPin>[
      for (final BusinessPage p in pages.values)
        if (p.published && (p.lat - lat).abs() < radiusKm / 111 && (p.lng - lng).abs() < radiusKm / 80)
          BusinessPin(
            id: p.id,
            displayName: p.displayName,
            category: p.category,
            lat: p.lat,
            lng: p.lng,
            verified: badge(p.id),
          ),
    ];
  }

  @override
  Future<Uint8List?> photo(String path) async => files[path];

  @override
  Future<List<BusinessReviewItem>> reviewQueue() async => <BusinessReviewItem>[
    for (final MapEntry<String, MyBusiness> e in registered.entries)
      BusinessReviewItem(
        id: e.key,
        username: usernames[e.key] ?? 'utente',
        businessName: e.value.businessName,
        vatNumber: e.value.vatNumber,
        status: e.value.status,
        displayName: pages[e.key]?.displayName ?? '',
        city: pages[e.key]?.address.city ?? '',
        province: pages[e.key]?.address.province ?? '',
        subscriptionEnd: subscriptions[e.key]?.periodEnd,
        subscriptionSource: subscriptions[e.key]?.source ?? '',
      ),
  ];

  @override
  Future<void> review(String id, {required bool approve, String note = ''}) async {
    final MyBusiness b = registered[id]!;
    registered[id] = MyBusiness(
      businessName: b.businessName,
      vatNumber: b.vatNumber,
      status: approve ? VerificationStatus.verified : VerificationStatus.rejected,
      reviewNote: note.trim(),
      hasDocument: b.hasDocument,
    );
  }

  @override
  Future<Uint8List?> document(String path) async => files[path];

  /// Un'attività già pronta (per le prove della Mappa e delle anteprime).
  void seed({
    required String id,
    required String username,
    required String name,
    required BusinessCategory category,
    required BusinessAddress address,
    required double lat,
    required double lng,
    VerificationStatus status = VerificationStatus.pending,
    DateTime? premiumUntil,
    BusinessHours hours = const BusinessHours(),
    String description = '',
    String phone = '',
    String bookingUrl = '',
  }) {
    usernames[id] = username;
    registered[id] = MyBusiness(businessName: '$name S.r.l.', vatNumber: '12345678903', status: status);
    if (premiumUntil != null) subscriptions[id] = BusinessSubscription(periodEnd: premiumUntil, source: 'admin');
    pages[id] = BusinessPage(
      id: id,
      displayName: name,
      category: category,
      address: address,
      lat: lat,
      lng: lng,
      hours: hours,
      description: description,
      phone: phone,
      bookingUrl: bookingUrl,
    );
  }
}

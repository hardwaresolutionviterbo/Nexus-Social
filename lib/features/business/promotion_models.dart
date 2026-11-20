import 'business_models.dart';

/// Fase 6 · Blocco 3: promozioni ed eventi delle attività, con coupon facoltativo.
enum PromotionKind {
  offerta('offerta', 'Offerta'),
  evento('evento', 'Evento');

  const PromotionKind(this.key, this.label);

  final String key;
  final String label;

  static PromotionKind fromKey(Object? k) => k == 'evento' ? PromotionKind.evento : PromotionKind.offerta;
}

/// Limiti del piano (li controlla anche il server).
abstract final class PromotionRules {
  static const int maxPerDay = 5;
  static const Duration maxDuration = Duration(days: 7);

  /// Testo dentro il QR del coupon.
  static String qrData(String code) => 'PIAZLY-$code';

  /// Codice letto da un QR o scritto a mano: «PIAZLY-ABCD2345», «abcd 2345» → «ABCD2345».
  static String normalizeCode(String raw) {
    String c = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (c.startsWith('PIAZLY')) c = c.substring(6);
    return c;
  }
}

class Promotion {
  const Promotion({
    required this.id,
    required this.businessId,
    required this.kind,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.lat,
    required this.lng,
    required this.businessName,
    this.description = '',
    this.placeLabel = '',
    this.atSite = true,
    this.couponText = '',
    this.couponLimit,
    this.couponsLeft,
    this.category = BusinessCategory.altro,
    this.businessAddress = '',
    this.verified = false,
    this.mine = false,
    this.myCoupon,
    this.myCouponUsed = false,
    this.canceled = false,
    this.claimed = 0,
    this.redeemed = 0,
    this.createdToday = false,
  });

  final String id;
  final String businessId;
  final PromotionKind kind;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;
  final double lat;
  final double lng;

  /// Per gli eventi fuori sede: dove.
  final String placeLabel;
  final bool atSite;
  final String couponText;
  final int? couponLimit;
  final int? couponsLeft;
  final String businessName;
  final BusinessCategory category;
  final String businessAddress;
  final bool verified;
  final bool mine;

  /// Il mio codice, se ho preso il coupon.
  final String? myCoupon;
  final bool myCouponUsed;

  // Solo per il titolare.
  final bool canceled;
  final int claimed;
  final int redeemed;
  final bool createdToday;

  bool get hasCoupon => couponText.isNotEmpty;

  bool isLive(DateTime now) => !canceled && !startsAt.isAfter(now) && endsAt.isAfter(now);

  bool isOver(DateTime now) => canceled || !endsAt.isAfter(now);

  /// Dove si svolge, in parole.
  String get whereLabel => atSite ? businessAddress : (placeLabel.isEmpty ? 'Fuori sede' : placeLabel);

  static Promotion fromJson(Map<String, dynamic> j) => Promotion(
    id: '${j['id']}',
    businessId: '${j['business_id']}',
    kind: PromotionKind.fromKey(j['kind']),
    title: '${j['title'] ?? ''}',
    description: j['description'] is String ? j['description'] as String : '',
    startsAt: DateTime.parse('${j['starts_at']}').toLocal(),
    endsAt: DateTime.parse('${j['ends_at']}').toLocal(),
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    placeLabel: j['place_label'] is String ? j['place_label'] as String : '',
    atSite: j['at_site'] != false,
    couponText: j['coupon_text'] is String ? j['coupon_text'] as String : '',
    couponLimit: (j['coupon_limit'] as num?)?.toInt(),
    couponsLeft: (j['coupons_left'] as num?)?.toInt(),
    businessName: '${j['business_name'] ?? ''}',
    category: BusinessCategory.fromKey(j['category']),
    businessAddress: '${j['business_address'] ?? ''}',
    verified: j['verified'] == true,
    mine: j['mine'] == true,
    myCoupon: j['my_coupon'] is String ? j['my_coupon'] as String : null,
    myCouponUsed: j['my_coupon_used'] == true,
    canceled: j['canceled'] == true,
    claimed: (j['claimed'] as num?)?.toInt() ?? 0,
    redeemed: (j['redeemed'] as num?)?.toInt() ?? 0,
    createdToday: j['created_today'] == true,
  );
}

/// Nuova promozione.
class PromotionDraft {
  const PromotionDraft({
    required this.kind,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.description = '',
    this.lat,
    this.lng,
    this.placeLabel = '',
    this.couponText = '',
    this.couponLimit,
  });

  final PromotionKind kind;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;

  /// Solo per gli eventi in un altro luogo (null: alla sede).
  final double? lat;
  final double? lng;
  final String placeLabel;
  final String couponText;
  final int? couponLimit;

  /// Errore da mostrare, o null se va bene (stesse regole del server).
  String? check(DateTime now) {
    if (title.trim().length < 3 || title.trim().length > 80) return 'Scrivi un titolo (da 3 a 80 caratteri).';
    if (!endsAt.isAfter(startsAt)) return 'La fine deve venire dopo l\'inizio.';
    if (endsAt.difference(startsAt) > PromotionRules.maxDuration) return 'Una promozione dura al massimo 7 giorni.';
    if (startsAt.isBefore(now.subtract(const Duration(hours: 1)))) return 'L\'inizio è già passato.';
    if (startsAt.isAfter(now.add(const Duration(days: 30)))) return 'L\'inizio deve essere entro 30 giorni.';
    if (lat != null && kind != PromotionKind.evento) return 'Solo gli eventi possono essere fuori sede.';
    if (couponText.trim().isNotEmpty && couponText.trim().length < 2) return 'Testo del coupon troppo corto.';
    return null;
  }
}

/// Coupon convalidato in cassa.
class CouponCheck {
  const CouponCheck({required this.title, required this.couponText, required this.redeemed});

  final String title;
  final String couponText;

  /// Clienti arrivati con questa promozione (conteggio aggiornato).
  final int redeemed;
}

import 'package:material_ui/material_ui.dart';

/// Fase 6 · Blocco 1: Aziende. Profilo attività con sede fissa, orari e verifica dell'admin.

class BusinessFailure implements Exception {
  const BusinessFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Categorie dell'attività (le stesse del server).
enum BusinessCategory {
  ristorante('ristorante', 'Ristorante e pizzeria', Icons.restaurant_rounded),
  bar('bar', 'Bar e caffetteria', Icons.local_cafe_rounded),
  alimentari('alimentari', 'Alimentari', Icons.local_grocery_store_rounded),
  negozio('negozio', 'Negozio', Icons.storefront_rounded),
  bellezza('bellezza', 'Bellezza e benessere', Icons.spa_rounded),
  salute('salute', 'Salute', Icons.local_pharmacy_rounded),
  sport('sport', 'Sport', Icons.fitness_center_rounded),
  casa('casa', 'Casa e lavori', Icons.handyman_rounded),
  auto('auto', 'Auto e moto', Icons.directions_car_rounded),
  servizi('servizi', 'Servizi', Icons.business_center_rounded),
  hotel('hotel', 'Hotel e alloggi', Icons.hotel_rounded),
  svago('svago', 'Svago e cultura', Icons.theater_comedy_rounded),
  altro('altro', 'Altro', Icons.category_rounded);

  const BusinessCategory(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;

  static BusinessCategory fromKey(Object? k) =>
      BusinessCategory.values.where((BusinessCategory c) => c.key == k).firstOrNull ?? BusinessCategory.altro;
}

/// Stato della verifica decisa dall'amministratore.
enum VerificationStatus {
  pending('In verifica'),
  verified('Verificata'),
  rejected('Non approvata');

  const VerificationStatus(this.label);

  final String label;

  static VerificationStatus fromKey(Object? k) => switch (k) {
    'verified' => VerificationStatus.verified,
    'rejected' => VerificationStatus.rejected,
    _ => VerificationStatus.pending,
  };
}

/// Fascia oraria in minuti dalla mezzanotte; la chiusura può superare la mezzanotte (fino alle 6).
class HourSlot {
  const HourSlot(this.open, this.close);

  final int open;
  final int close;

  static String hm(int minutes) {
    final int m = minutes % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  String get label => '${hm(open)}–${hm(close)}';

  bool get valid => open >= 0 && open < 1440 && close > open && close <= 1800;

  @override
  bool operator ==(Object other) => other is HourSlot && other.open == open && other.close == close;

  @override
  int get hashCode => Object.hash(open, close);
}

/// Orari della settimana: chiave 1 = lunedì … 7 = domenica.
class BusinessHours {
  const BusinessHours([this.days = const <int, List<HourSlot>>{}]);

  final Map<int, List<HourSlot>> days;

  static const List<String> dayNames = <String>[
    'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica',
  ];

  bool get isEmpty => days.values.every((List<HourSlot> s) => s.isEmpty);

  List<HourSlot> of(int weekday) => days[weekday] ?? const <HourSlot>[];

  static BusinessHours fromJson(Object? j) {
    final Map<int, List<HourSlot>> out = <int, List<HourSlot>>{};
    if (j is Map) {
      j.forEach((Object? k, Object? v) {
        final int? d = int.tryParse('$k');
        if (d == null || d < 1 || d > 7 || v is! List) return;
        out[d] = <HourSlot>[
          for (final Object? s in v)
            if (s is List && s.length == 2 && s[0] is num && s[1] is num)
              HourSlot((s[0] as num).toInt(), (s[1] as num).toInt()),
        ];
      });
    }
    return BusinessHours(out);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    for (final MapEntry<int, List<HourSlot>> e in days.entries)
      if (e.value.isNotEmpty) '${e.key}': <List<int>>[for (final HourSlot s in e.value) <int>[s.open, s.close]],
  };

  /// Aperta in questo momento? Conta anche la chiusura dopo mezzanotte del giorno prima.
  bool isOpenAt(DateTime t) {
    final int now = t.hour * 60 + t.minute;
    for (final HourSlot s in of(t.weekday)) {
      if (now >= s.open && now < s.close) return true;
    }
    final int yesterday = t.weekday == 1 ? 7 : t.weekday - 1;
    for (final HourSlot s in of(yesterday)) {
      if (s.close > 1440 && now < s.close - 1440) return true;
    }
    return false;
  }

  /// «Aperto ora · chiude alle 19:30» oppure «Chiuso · apre alle 16:00» (o «apre lunedì alle 9:00»).
  String statusLabel(DateTime t) {
    final int now = t.hour * 60 + t.minute;
    for (final HourSlot s in of(t.weekday)) {
      if (now >= s.open && now < s.close) return 'Aperto ora · chiude alle ${HourSlot.hm(s.close)}';
    }
    final int yesterday = t.weekday == 1 ? 7 : t.weekday - 1;
    for (final HourSlot s in of(yesterday)) {
      if (s.close > 1440 && now < s.close - 1440) return 'Aperto ora · chiude alle ${HourSlot.hm(s.close)}';
    }
    for (final HourSlot s in of(t.weekday)) {
      if (s.open > now) return 'Chiuso · apre alle ${HourSlot.hm(s.open)}';
    }
    for (int i = 1; i <= 7; i++) {
      final int d = (t.weekday - 1 + i) % 7 + 1;
      final List<HourSlot> slots = of(d);
      if (slots.isNotEmpty) {
        final String when = i == 1 ? 'domani' : dayNames[d - 1].toLowerCase();
        return 'Chiuso · apre $when alle ${HourSlot.hm(slots.first.open)}';
      }
    }
    return 'Orari non indicati';
  }
}

/// Indirizzo ufficiale della sede.
class BusinessAddress {
  const BusinessAddress({
    required this.street,
    required this.civic,
    required this.city,
    required this.cap,
    required this.province,
  });

  final String street;
  final String civic;
  final String city;
  final String cap;
  final String province;

  /// «Via Roma 12, 05010 Porano (TR)».
  String get label => '$street $civic, $cap $city ($province)';

  static String? streetError(String v) =>
      v.trim().length < 2 || v.trim().length > 100 ? 'Scrivi la via (es. «Via Roma»).' : null;

  static String? civicError(String v) {
    final String s = v.trim();
    if (RegExp(r'^[0-9]{1,5}( ?[A-Za-z]{1,3})?(/[0-9A-Za-z]{1,4})?$').hasMatch(s)) return null;
    if (RegExp(r'^(snc|SNC|s\.n\.c\.)$').hasMatch(s)) return null;
    return 'Numero civico non valido (es. 12, 12A, 12/3 o snc).';
  }

  static String? capError(String v) => RegExp(r'^[0-9]{5}$').hasMatch(v.trim()) ? null : 'Il CAP ha 5 cifre.';

  static String? provinceError(String v) =>
      RegExp(r'^[A-Za-z]{2}$').hasMatch(v.trim()) ? null : 'Sigla di 2 lettere (es. TR).';
}

/// Pagina pubblica dell'attività.
class BusinessPage {
  const BusinessPage({
    required this.id,
    required this.displayName,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    this.description = '',
    this.phone = '',
    this.bookingUrl = '',
    this.hours = const BusinessHours(),
    this.photos = const <String>[],
    this.published = true,
    this.verified = false,
    this.username = '',
    this.mine = false,
  });

  final String id;
  final String displayName;
  final BusinessCategory category;
  final BusinessAddress address;
  final double lat;
  final double lng;
  final String description;
  final String phone;
  final String bookingUrl;
  final BusinessHours hours;
  final List<String> photos;
  final bool published;
  final bool verified;
  final String username;
  final bool mine;

  static BusinessPage fromJson(Map<String, dynamic> j) => BusinessPage(
    id: '${j['id']}',
    displayName: '${j['display_name'] ?? ''}',
    category: BusinessCategory.fromKey(j['category']),
    address: BusinessAddress(
      street: '${j['street'] ?? ''}',
      civic: '${j['civic'] ?? ''}',
      city: '${j['city'] ?? ''}',
      cap: '${j['cap'] ?? ''}',
      province: '${j['province'] ?? ''}',
    ),
    lat: (j['lat'] as num?)?.toDouble() ?? 0,
    lng: (j['lng'] as num?)?.toDouble() ?? 0,
    description: '${j['description'] ?? ''}',
    phone: '${j['phone'] ?? ''}',
    bookingUrl: '${j['booking_url'] ?? ''}',
    hours: BusinessHours.fromJson(j['hours']),
    photos: <String>[for (final Object? p in (j['photos'] as List<dynamic>? ?? const <dynamic>[])) '$p'],
    published: j['published'] != false,
    verified: j['verified'] == true,
    username: '${j['username'] ?? ''}',
    mine: j['mine'] == true,
  );
}

/// Segnaposto di un'attività sulla Mappa (sede fissa).
class BusinessPin {
  const BusinessPin({
    required this.id,
    required this.displayName,
    required this.category,
    required this.lat,
    required this.lng,
    this.verified = false,
  });

  final String id;
  final String displayName;
  final BusinessCategory category;
  final double lat;
  final double lng;
  final bool verified;

  String get initial => displayName.trim().isEmpty ? '?' : displayName.trim().characters.first.toUpperCase();
}

/// Abbonamento Premium (privato): prova di 7 giorni, attivato dall'admin o, più avanti, Google Play.
class BusinessSubscription {
  const BusinessSubscription({
    this.periodEnd,
    this.source = '',
    this.autoRenew = false,
    this.trialUsed = false,
  });

  /// Prezzo mostrato nell'app (piano, Fase 6).
  static const String price = '9,99 €';
  static const int trialDays = 7;

  final DateTime? periodEnd;

  /// 'trial', 'admin', 'google_play', 'app_store' (vuoto: mai attivato).
  final String source;
  final bool autoRenew;
  final bool trialUsed;

  bool isActive(DateTime now) => periodEnd != null && periodEnd!.isAfter(now);

  bool get isTrial => source == 'trial';

  /// Giorni rimasti (arrotondati per eccesso), 0 se scaduto.
  int daysLeft(DateTime now) {
    final DateTime? end = periodEnd;
    if (end == null || !end.isAfter(now)) return 0;
    return (end.difference(now).inMinutes / 1440).ceil();
  }

  static BusinessSubscription fromJson(Object? j) {
    if (j is! Map) return const BusinessSubscription();
    return BusinessSubscription(
      periodEnd: DateTime.tryParse('${j['period_end'] ?? ''}')?.toLocal(),
      source: j['source'] is String ? j['source'] as String : '',
      autoRenew: j['auto_renew'] == true,
      trialUsed: j['trial_used'] == true,
    );
  }
}

/// «20 nov 2026».
String shortDate(DateTime d) {
  const List<String> m = <String>['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// I miei dati Azienda (privati: ragione sociale e partita IVA) e la mia pagina.
class MyBusiness {
  const MyBusiness({
    required this.businessName,
    required this.vatNumber,
    required this.status,
    this.reviewNote = '',
    this.hasDocument = false,
    this.page,
    this.verifiedBadge = false,
    this.subscription = const BusinessSubscription(),
  });

  /// Badge «Verificato»: approvata dall'admin e con l'abbonamento attivo.
  final bool verifiedBadge;
  final BusinessSubscription subscription;
  final String businessName;
  final String vatNumber;
  final VerificationStatus status;
  final String reviewNote;
  final bool hasDocument;
  final BusinessPage? page;

  static MyBusiness fromJson(Map<String, dynamic> j) => MyBusiness(
    businessName: '${j['business_name'] ?? ''}',
    vatNumber: '${j['vat_number'] ?? ''}',
    status: VerificationStatus.fromKey(j['status']),
    reviewNote: '${j['review_note'] ?? ''}',
    hasDocument: j['has_document'] == true,
    page: j['page'] is Map<String, dynamic> ? BusinessPage.fromJson(j['page'] as Map<String, dynamic>) : null,
    verifiedBadge: j['verified_badge'] == true,
    subscription: BusinessSubscription.fromJson(j['subscription']),
  );
}

/// Da salvare: la pagina e le foto nuove (byte JPEG) da caricare.
class BusinessPageDraft {
  const BusinessPageDraft({
    required this.displayName,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    this.description = '',
    this.phone = '',
    this.bookingUrl = '',
    this.hours = const BusinessHours(),
    this.keptPhotos = const <String>[],
    this.published = true,
  });

  final String displayName;
  final BusinessCategory category;
  final BusinessAddress address;
  final double lat;
  final double lng;
  final String description;
  final String phone;
  final String bookingUrl;
  final BusinessHours hours;
  final List<String> keptPhotos;
  final bool published;

  /// Sede in Italia (come controlla il server).
  bool get inItaly => lat >= 35.4 && lat <= 47.2 && lng >= 6.6 && lng <= 18.6;
}

/// Una richiesta da verificare (solo amministratori).
class BusinessReviewItem {
  const BusinessReviewItem({
    required this.id,
    required this.username,
    required this.businessName,
    required this.vatNumber,
    required this.status,
    this.displayName = '',
    this.city = '',
    this.province = '',
    this.documentPath,
    this.subscriptionEnd,
    this.subscriptionSource = '',
  });

  final DateTime? subscriptionEnd;
  final String subscriptionSource;

  final String id;
  final String username;
  final String businessName;
  final String vatNumber;
  final VerificationStatus status;
  final String displayName;
  final String city;
  final String province;
  final String? documentPath;

  static BusinessReviewItem fromJson(Map<String, dynamic> j) => BusinessReviewItem(
    id: '${j['id']}',
    username: '${j['username'] ?? ''}',
    businessName: '${j['business_name'] ?? ''}',
    vatNumber: '${j['vat_number'] ?? ''}',
    status: VerificationStatus.fromKey(j['status']),
    displayName: '${j['display_name'] ?? ''}',
    city: '${j['city'] ?? ''}',
    province: '${j['province'] ?? ''}',
    documentPath: j['document_path'] as String?,
    subscriptionEnd: DateTime.tryParse('${j['subscription_end'] ?? ''}')?.toLocal(),
    subscriptionSource: j['subscription_source'] is String ? j['subscription_source'] as String : '',
  );
}

/// Recensione verificata (Fase 6, Blocco 4): la scrive solo chi ha usato un coupon in cassa.
class BusinessReview {
  const BusinessReview({
    required this.id,
    required this.author,
    required this.rating,
    required this.createdAt,
    this.body = '',
    this.reply = '',
    this.mine = false,
  });

  final String id;

  /// Nome pubblico dell'autore.
  final String author;
  final int rating;
  final String body;
  final String reply;
  final DateTime createdAt;
  final bool mine;

  static BusinessReview fromJson(Map<String, dynamic> j) => BusinessReview(
    id: '${j['id']}',
    author: '${j['author'] ?? ''}',
    rating: (j['rating'] as num?)?.toInt() ?? 0,
    body: j['body'] is String ? j['body'] as String : '',
    reply: j['reply'] is String ? j['reply'] as String : '',
    createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime(2000),
    mine: j['mine'] == true,
  );
}

class BusinessReviews {
  const BusinessReviews({
    this.average,
    this.count = 0,
    this.canReview = false,
    this.ownerView = false,
    this.items = const <BusinessReview>[],
  });

  final double? average;
  final int count;

  /// Posso scriverne una (cliente verificato, non titolare).
  final bool canReview;

  /// Sto guardando le recensioni della mia attività (posso rispondere).
  final bool ownerView;
  final List<BusinessReview> items;

  BusinessReview? get mine => items.where((BusinessReview r) => r.mine).firstOrNull;

  static BusinessReviews fromJson(Object? j) {
    if (j is! Map) return const BusinessReviews();
    return BusinessReviews(
      average: (j['average'] as num?)?.toDouble(),
      count: (j['count'] as num?)?.toInt() ?? 0,
      canReview: j['can_review'] == true,
      ownerView: j['mine_owner'] == true,
      items: <BusinessReview>[
        for (final Object? x in (j['items'] as List<dynamic>? ?? const <dynamic>[]))
          if (x is Map<String, dynamic>) BusinessReview.fromJson(x),
      ],
    );
  }
}

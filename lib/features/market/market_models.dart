import 'package:flutter/foundation.dart';

import '../map/listing_models.dart' show GeoPoint, ListingPlace;

/// Una categoria o sottocategoria di Scambia & Vendi (specifica del titolare, sezione 3).
@immutable
class MarketCategory {
  const MarketCategory({
    required this.id,
    required this.parentId,
    required this.name,
    required this.slug,
    required this.sortOrder,
  });

  factory MarketCategory.fromJson(Map<String, dynamic> json) => MarketCategory(
    id: json['id'] as String,
    parentId: json['parent_id'] as String?,
    name: json['name'] as String,
    slug: json['slug'] as String,
    sortOrder: (json['sort_order'] as num).toInt(),
  );

  final String id;
  final String? parentId;
  final String name;

  /// Non cambia mai, anche se cambia il nome visualizzato.
  final String slug;
  final int sortOrder;

  bool get isMain => parentId == null;
}

/// Catalogo a due livelli con ricerca rapida per ID.
class MarketCatalog {
  MarketCatalog(List<MarketCategory> all)
    : mains = (all.where((MarketCategory c) => c.isMain).toList()
        ..sort((MarketCategory a, MarketCategory b) => a.sortOrder.compareTo(b.sortOrder))),
      _byId = <String, MarketCategory>{for (final MarketCategory c in all) c.id: c},
      _subs = <String, List<MarketCategory>>{} {
    for (final MarketCategory c in all) {
      if (c.parentId != null) (_subs[c.parentId!] ??= <MarketCategory>[]).add(c);
    }
    for (final List<MarketCategory> l in _subs.values) {
      l.sort((MarketCategory a, MarketCategory b) => a.sortOrder.compareTo(b.sortOrder));
    }
  }

  final List<MarketCategory> mains;
  final Map<String, MarketCategory> _byId;
  final Map<String, List<MarketCategory>> _subs;

  List<MarketCategory> subsOf(String mainId) => _subs[mainId] ?? const <MarketCategory>[];
  MarketCategory? byId(String id) => _byId[id];
  MarketCategory? parentOf(MarketCategory sub) =>
      sub.parentId == null ? null : _byId[sub.parentId!];
}

/// Tipologia dell'annuncio (specifica, sezione 4): un solo sistema, quattro tipi.
enum MarketType {
  sell('sell', 'Vendo'),
  swap('swap', 'Scambio'),
  free('free', 'Regalo'),
  wanted('wanted', 'Cerco');

  const MarketType(this.serverValue, this.label);

  final String serverValue;
  final String label;

  static MarketType fromServer(String? v) =>
      MarketType.values.firstWhere((MarketType t) => t.serverValue == v, orElse: () => MarketType.sell);

  /// Prezzo: obbligatorio per la Vendita, facoltativo per Scambio e Cerco, assente per il Regalo.
  bool get priceRequired => this == MarketType.sell;
  bool get priceAllowed => this != MarketType.free;

  /// Foto obbligatorie (decisione D11) tranne per chi cerca.
  bool get photosRequired => this != MarketType.wanted;
}

/// Sezioni della barra in basso (D10): Scambia mostra Scambio, Regalo e Cerco; Vendita la Vendita.
enum MarketSection {
  swap('Scambia vicino a te', <MarketType>[MarketType.swap, MarketType.free, MarketType.wanted]),
  sale('Vendita tra privati', <MarketType>[MarketType.sell]);

  const MarketSection(this.title, this.types);

  final String title;
  final List<MarketType> types;
}

/// Condizioni dell'oggetto (specifica, sezione 5).
enum ItemCondition {
  brandNew('new', 'Nuovo'),
  likeNew('like_new', 'Come nuovo'),
  excellent('excellent', 'Ottimo stato'),
  good('good', 'Buono stato'),
  fair('fair', 'Discreto'),
  toRepair('to_repair', 'Da riparare');

  const ItemCondition(this.serverValue, this.label);

  final String serverValue;
  final String label;

  static ItemCondition? fromServer(String? v) =>
      ItemCondition.values.where((ItemCondition c) => c.serverValue == v).firstOrNull;
}

/// Campo specifico di una categoria (decisione D3).
@immutable
class MarketAttribute {
  const MarketAttribute(this.key, this.label, {this.numeric = false, this.min, this.max, this.hint});

  final String key;
  final String label;
  final bool numeric;
  final int? min;
  final int? max;
  final String? hint;
}

abstract final class MarketRules {
  static const int maxPhotos = 10;
  static const int titleMin = 3;
  static const int titleMax = 120;
  static const int descriptionMax = 2000;
  static const int wantedInExchangeMax = 300;

  /// 999.999.999 € in centesimi (immobili compresi).
  static const int maxPriceCents = 99999999900;

  /// Senza condizioni né consegna: servizi e immobili.
  static bool noObjectFields(String mainSlug) => mainSlug == 'servizi' || mainSlug == 'immobili';

  static List<MarketAttribute> attributesFor(String mainSlug) => switch (mainSlug) {
    'motori' => <MarketAttribute>[
      MarketAttribute('anno', 'Anno', numeric: true, min: 1900, max: DateTime.now().year + 1),
      const MarketAttribute('km', 'Chilometri', numeric: true, min: 0, max: 2000000),
    ],
    'immobili' => const <MarketAttribute>[
      MarketAttribute('mq', 'Metri quadri', numeric: true, min: 1, max: 100000),
      MarketAttribute('locali', 'Locali', numeric: true, min: 1, max: 50),
    ],
    'abbigliamento-accessori' || 'bambini-neonati' => const <MarketAttribute>[
      MarketAttribute('taglia', 'Taglia o numero', hint: 'Es. M, 42, 38'),
    ],
    'elettronica' => const <MarketAttribute>[
      MarketAttribute('memoria', 'Memoria', hint: 'Es. 128 GB'),
    ],
    _ => const <MarketAttribute>[],
  };

  /// Campi obbligatori: l'anno per le auto, i metri quadri per gli immobili (D3).
  static Set<String> requiredAttributes(MarketCategory sub, String mainSlug, MarketType type) {
    if (type == MarketType.wanted) return const <String>{};
    if (sub.slug == 'motori-auto') return const <String>{'anno'};
    if (mainSlug == 'immobili') return const <String>{'mq'};
    return const <String>{};
  }

  /// «1.250,50» o «35» → centesimi; null se vuoto; eccezione se non valido.
  static int? parsePriceCents(String text) {
    final String t = text.trim().replaceAll('€', '').replaceAll(' ', '');
    if (t.isEmpty) return null;
    final String normalized = t.replaceAll('.', '').replaceAll(',', '.');
    final double? v = double.tryParse(normalized);
    if (v == null || v < 0) throw const FormatException('Prezzo non valido');
    final int cents = (v * 100).round();
    if (cents > maxPriceCents) throw const FormatException('Prezzo troppo alto');
    return cents;
  }

  /// 3500000 → «35.000 €», 12550 → «125,50 €».
  static String formatPrice(int cents) {
    final int euros = cents ~/ 100;
    final int rest = cents % 100;
    final String digits = euros.toString();
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
      b.write(digits[i]);
    }
    if (rest != 0) b.write(',${rest.toString().padLeft(2, '0')}');
    return '$b €';
  }
}

/// Quello che l'autore compila.
class MarketDraft {
  MarketDraft({
    required this.type,
    required this.categoryId,
    required this.title,
    this.description = '',
    this.priceCents,
    this.condition,
    this.ships = false,
    this.pickup = false,
    this.attributes = const <String, Object>{},
    required this.place,
    required this.point,
    this.keptPhotos = const <String>[],
    this.newPhotos = const <Uint8List>[],
    this.wantedInExchange,
    this.noProhibitedItems = false,
    this.openToSwap = false,
    this.cashAdjustment = false,
  });

  final MarketType type;
  final String categoryId;
  final String title;
  final String description;
  final int? priceCents;
  final ItemCondition? condition;
  final bool ships;
  final bool pickup;
  final Map<String, Object> attributes;
  final ListingPlace place;
  final GeoPoint point;
  final List<String> keptPhotos;
  final List<Uint8List> newPhotos;
  final String? wantedInExchange;

  /// Conferma «non pubblico prodotti vietati» (specifica, sezione 9).
  final bool noProhibitedItems;

  /// «Valuto anche scambi» (solo Vendita) e «Accetto conguaglio» (specifica, sezione 7).
  final bool openToSwap;
  final bool cashAdjustment;
}

/// Esito della pubblicazione: in revisione se il testo contiene parole a rischio.
@immutable
class MarketPublishResult {
  const MarketPublishResult({required this.id, required this.pendingReview});

  final String id;
  final bool pendingReview;
}

enum MarketListingState {
  active('Attivo'),
  expired('Scaduto'),
  completed('Concluso'),
  hidden('Nascosto'),
  removed('Rimosso');

  const MarketListingState(this.label);

  final String label;

  static MarketListingState fromServer(String? v) => switch (v) {
    'active' => MarketListingState.active,
    'expired' => MarketListingState.expired,
    'completed' => MarketListingState.completed,
    'hidden' => MarketListingState.hidden,
    _ => MarketListingState.removed,
  };
}

enum ReviewStatus {
  published,
  pendingReview,
  rejected;

  static ReviewStatus fromServer(String? v) => switch (v) {
    'pending_review' => ReviewStatus.pendingReview,
    'rejected' => ReviewStatus.rejected,
    _ => ReviewStatus.published,
  };
}

@immutable
class MyMarketListing {
  const MyMarketListing({
    required this.id,
    required this.type,
    required this.categoryId,
    required this.title,
    this.description = '',
    this.priceCents,
    this.condition,
    this.ships = false,
    this.pickup = false,
    this.attributes = const <String, Object>{},
    this.photos = const <String>[],
    this.wantedInExchange,
    required this.place,
    required this.savedPoint,
    required this.state,
    this.review = ReviewStatus.published,
    required this.expiresAt,
    required this.createdAt,
    this.openToSwap = false,
    this.cashAdjustment = false,
  });

  factory MyMarketListing.fromJson(Map<String, dynamic> json) => MyMarketListing(
    id: json['id'] as String,
    type: MarketType.fromServer(json['market_type'] as String?),
    categoryId: json['category_id'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    priceCents: (json['price_cents'] as num?)?.toInt(),
    condition: ItemCondition.fromServer(json['item_condition'] as String?),
    ships: json['ships'] as bool? ?? false,
    pickup: json['pickup'] as bool? ?? false,
    attributes: <String, Object>{
      for (final MapEntry<String, dynamic> e
          in ((json['attributes'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{})
              .entries)
        if (e.value != null) e.key: e.value as Object,
    },
    photos: <String>[for (final Object? p in json['photos'] as List? ?? const <Object?>[]) '$p'],
    wantedInExchange: json['wanted_in_exchange'] as String?,
    place: ListingPlace.fromServer(json['location_mode'] as String?),
    savedPoint: GeoPoint(
      (json['exact_lat'] as num).toDouble(),
      (json['exact_lon'] as num).toDouble(),
    ),
    state: MarketListingState.fromServer(json['status'] as String?),
    review: ReviewStatus.fromServer(json['review_status'] as String?),
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    openToSwap: json['open_to_swap'] as bool? ?? false,
    cashAdjustment: json['cash_adjustment'] as bool? ?? false,
  );

  final String id;
  final MarketType type;
  final String categoryId;
  final String title;
  final String description;
  final int? priceCents;
  final ItemCondition? condition;
  final bool ships;
  final bool pickup;
  final Map<String, Object> attributes;
  final List<String> photos;
  final String? wantedInExchange;
  final bool openToSwap;
  final bool cashAdjustment;
  final ListingPlace place;
  final GeoPoint savedPoint;
  final MarketListingState state;
  final ReviewStatus review;
  final DateTime expiresAt;
  final DateTime createdAt;

  bool get editable => state == MarketListingState.active || state == MarketListingState.expired;

  /// Si rinnova quando è scaduto o mancano meno di 7 giorni.
  bool canRenew(DateTime now) =>
      editable && expiresAt.difference(now) < const Duration(days: 7);

  MyMarketListing copyWith({MarketListingState? state, DateTime? expiresAt}) => MyMarketListing(
    id: id,
    type: type,
    categoryId: categoryId,
    title: title,
    description: description,
    priceCents: priceCents,
    condition: condition,
    ships: ships,
    pickup: pickup,
    attributes: attributes,
    photos: photos,
    wantedInExchange: wantedInExchange,
    place: place,
    savedPoint: savedPoint,
    state: state ?? this.state,
    review: review,
    expiresAt: expiresAt ?? this.expiresAt,
    createdAt: createdAt,
    openToSwap: openToSwap,
    cashAdjustment: cashAdjustment,
  );
}

/// Attributi in forma leggibile per la scheda (decisione D3).
Map<String, Object> marketAttributesFromJson(Object? raw) => <String, Object>{
  for (final MapEntry<String, dynamic> e
      in ((raw as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{}).entries)
    if (e.value != null) e.key: e.value as Object,
};

/// Un annuncio di Scambia & Vendi come lo vedono gli altri (ricerca e scheda, Blocco 2):
/// solo il punto pubblico e una distanza arrotondata, mai il punto salvato.
@immutable
class MarketListing {
  const MarketListing({
    required this.id,
    required this.type,
    required this.categoryId,
    required this.title,
    this.description = '',
    this.priceCents,
    this.condition,
    this.ships = false,
    this.pickup = false,
    this.openToSwap = false,
    this.cashAdjustment = false,
    this.attributes = const <String, Object>{},
    this.wantedInExchange,
    this.photos = const <String>[],
    required this.place,
    required this.point,
    this.distanceBandMeters,
    this.review = ReviewStatus.published,
    required this.expiresAt,
    required this.createdAt,
    this.isMine = false,
    required this.ownerId,
    required this.ownerUsername,
    required this.ownerPublicName,
    this.ownerAvatarThumbPath,
    this.ownerIsBusiness = false,
  });

  factory MarketListing.fromJson(Map<String, dynamic> json) => MarketListing(
    id: json['id'] as String,
    type: MarketType.fromServer(json['market_type'] as String?),
    categoryId: json['category_id'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    priceCents: (json['price_cents'] as num?)?.toInt(),
    condition: ItemCondition.fromServer(json['item_condition'] as String?),
    ships: json['ships'] as bool? ?? false,
    pickup: json['pickup'] as bool? ?? false,
    openToSwap: json['open_to_swap'] as bool? ?? false,
    cashAdjustment: json['cash_adjustment'] as bool? ?? false,
    attributes: marketAttributesFromJson(json['attributes']),
    wantedInExchange: json['wanted_in_exchange'] as String?,
    photos: <String>[for (final Object? p in json['photos'] as List? ?? const <Object?>[]) '$p'],
    place: ListingPlace.fromServer(json['location_mode'] as String?),
    point: GeoPoint((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
    distanceBandMeters: (json['distance_band_m'] as num?)?.toInt(),
    review: ReviewStatus.fromServer(json['review_status'] as String?),
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    isMine: json['is_mine'] as bool? ?? false,
    ownerId: json['owner_id'] as String,
    ownerUsername: json['owner_username'] as String? ?? '',
    ownerPublicName: json['owner_public_name'] as String? ?? '',
    ownerAvatarThumbPath: json['owner_avatar_thumb_path'] as String?,
    ownerIsBusiness: json['owner_is_business'] as bool? ?? false,
  );

  final String id;
  final MarketType type;
  final String categoryId;
  final String title;
  final String description;
  final int? priceCents;
  final ItemCondition? condition;
  final bool ships;
  final bool pickup;
  final bool openToSwap;
  final bool cashAdjustment;
  final Map<String, Object> attributes;
  final String? wantedInExchange;
  final List<String> photos;
  final ListingPlace place;

  /// Punto pubblico: zona approssimata o punto scelto dall'autore.
  final GeoPoint point;

  /// Arrotondata a 250 m; null se la ricerca non ha un punto di partenza.
  final int? distanceBandMeters;
  final ReviewStatus review;
  final DateTime expiresAt;
  final DateTime createdAt;
  final bool isMine;
  final String ownerId;
  final String ownerUsername;
  final String ownerPublicName;
  final String? ownerAvatarThumbPath;
  final bool ownerIsBusiness;

  /// «350 €», «Gratis», «Scambio», «Cerco · fino a 50 €».
  String get priceLabel {
    final int? p = priceCents;
    return switch (type) {
      MarketType.free => 'Gratis',
      MarketType.sell => p == null ? '' : MarketRules.formatPrice(p),
      MarketType.swap => p == null ? 'Scambio' : 'Scambio · ${MarketRules.formatPrice(p)}',
      MarketType.wanted => p == null ? 'Cerco' : 'Cerco · fino a ${MarketRules.formatPrice(p)}',
    };
  }

  /// Si scambia: lo Scambio sempre, la Vendita se l'autore lo accetta.
  bool get swappable => type == MarketType.swap || openToSwap;
}

/// Ordinamenti (specifica, sezione 7).
enum MarketSort {
  recent('recent', 'Più recenti'),
  priceAsc('price_asc', 'Prezzo crescente'),
  priceDesc('price_desc', 'Prezzo decrescente'),
  nearest('nearest', 'Più vicini'),
  relevant('relevant', 'Più pertinenti');

  const MarketSort(this.serverValue, this.label);

  final String serverValue;
  final String label;
}

/// Privato o azienda (dal tipo di account, Fase 2).
enum SellerKind {
  any(null, 'Tutti'),
  private('private', 'Privati'),
  business('business', 'Aziende');

  const SellerKind(this.serverValue, this.label);

  final String? serverValue;
  final String label;
}

/// Data di pubblicazione.
enum MarketPublished {
  any(null, 'Qualsiasi'),
  day(1, 'Ultime 24 ore'),
  week(7, 'Ultimi 7 giorni'),
  month(30, 'Ultimi 30 giorni');

  const MarketPublished(this.days, this.label);

  final int? days;
  final String label;
}

/// Da dove si cerca: ovunque, dalla posizione del telefono o da un punto scelto.
enum SearchOrigin { anywhere, myPosition, chosenPoint }

/// I 13 filtri, la parola cercata e l'ordinamento (specifica, sezione 7; D4).
@immutable
class MarketQuery {
  const MarketQuery({
    this.text = '',
    this.categoryId,
    this.subcategoryId,
    this.types = const <MarketType>{},
    this.priceMinCents,
    this.priceMaxCents,
    this.conditions = const <ItemCondition>{},
    this.origin = SearchOrigin.anywhere,
    this.point,
    this.radiusKm = defaultRadiusKm,
    this.seller = SellerKind.any,
    this.ships = false,
    this.pickup = false,
    this.openToSwap = false,
    this.cashAdjustment = false,
    this.published = MarketPublished.any,
    this.sort = MarketSort.recent,
  });

  static const int defaultRadiusKm = 30;
  static const int minRadiusKm = 1;
  static const int maxRadiusKm = 200;

  /// Pagine da 20 (D9).
  static const int pageSize = 20;

  final String text;
  final String? categoryId;
  final String? subcategoryId;

  /// Vuoto = tutte le tipologie della sezione.
  final Set<MarketType> types;
  final int? priceMinCents;
  final int? priceMaxCents;
  final Set<ItemCondition> conditions;
  final SearchOrigin origin;

  /// Punto di ricerca: serve solo al calcolo, il server non lo salva.
  final GeoPoint? point;
  final int radiusKm;
  final SellerKind seller;
  final bool ships;
  final bool pickup;
  final bool openToSwap;
  final bool cashAdjustment;
  final MarketPublished published;
  final MarketSort sort;

  bool get hasPoint => origin != SearchOrigin.anywhere && point != null;

  /// Quanti filtri sono attivi (per il segnalino sul pulsante «Filtri»).
  int get activeFilters =>
      (categoryId != null ? 1 : 0) +
      (subcategoryId != null ? 1 : 0) +
      (types.isNotEmpty ? 1 : 0) +
      (priceMinCents != null || priceMaxCents != null ? 1 : 0) +
      (conditions.isNotEmpty ? 1 : 0) +
      (hasPoint ? 1 : 0) +
      (seller != SellerKind.any ? 1 : 0) +
      (ships ? 1 : 0) +
      (pickup ? 1 : 0) +
      (openToSwap ? 1 : 0) +
      (cashAdjustment ? 1 : 0) +
      (published != MarketPublished.any ? 1 : 0);

  /// Parametri della funzione `market_search` (migrazione 0013).
  Map<String, Object?> toParams(MarketSection section, {int offset = 0}) {
    final String q = text.trim();
    MarketSort effective = sort;
    if (effective == MarketSort.nearest && !hasPoint) effective = MarketSort.recent;
    if (effective == MarketSort.relevant && q.isEmpty) effective = MarketSort.recent;
    final Set<MarketType> allowed = types.intersection(section.types.toSet());
    return <String, Object?>{
      'p_section': section == MarketSection.swap ? 'swap' : 'sale',
      'p_query': q.isEmpty ? null : q,
      'p_category': categoryId,
      'p_subcategory': subcategoryId,
      'p_types': allowed.isEmpty
          ? null
          : <String>[for (final MarketType t in allowed) t.serverValue],
      'p_price_min_cents': priceMinCents,
      'p_price_max_cents': priceMaxCents,
      'p_conditions': conditions.isEmpty
          ? null
          : <String>[for (final ItemCondition c in conditions) c.serverValue],
      'p_lat': hasPoint ? point!.latitude : null,
      'p_lon': hasPoint ? point!.longitude : null,
      'p_radius_km': hasPoint ? radiusKm.clamp(minRadiusKm, maxRadiusKm) : null,
      'p_seller': seller.serverValue,
      'p_ships': ships,
      'p_pickup': pickup,
      'p_open_to_swap': section == MarketSection.sale && openToSwap,
      'p_cash_adjustment': cashAdjustment,
      'p_published_within_days': published.days,
      'p_sort': effective.serverValue,
      'p_offset': offset,
    };
  }

  MarketQuery copyWith({
    String? text,
    String? Function()? categoryId,
    String? Function()? subcategoryId,
    Set<MarketType>? types,
    int? Function()? priceMinCents,
    int? Function()? priceMaxCents,
    Set<ItemCondition>? conditions,
    SearchOrigin? origin,
    GeoPoint? Function()? point,
    int? radiusKm,
    SellerKind? seller,
    bool? ships,
    bool? pickup,
    bool? openToSwap,
    bool? cashAdjustment,
    MarketPublished? published,
    MarketSort? sort,
  }) => MarketQuery(
    text: text ?? this.text,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    subcategoryId: subcategoryId != null ? subcategoryId() : this.subcategoryId,
    types: types ?? this.types,
    priceMinCents: priceMinCents != null ? priceMinCents() : this.priceMinCents,
    priceMaxCents: priceMaxCents != null ? priceMaxCents() : this.priceMaxCents,
    conditions: conditions ?? this.conditions,
    origin: origin ?? this.origin,
    point: point != null ? point() : this.point,
    radiusKm: radiusKm ?? this.radiusKm,
    seller: seller ?? this.seller,
    ships: ships ?? this.ships,
    pickup: pickup ?? this.pickup,
    openToSwap: openToSwap ?? this.openToSwap,
    cashAdjustment: cashAdjustment ?? this.cashAdjustment,
    published: published ?? this.published,
    sort: sort ?? this.sort,
  );

  /// Azzera i filtri, tenendo la parola cercata e l'ordinamento.
  MarketQuery cleared() => MarketQuery(text: text, sort: sort == MarketSort.nearest ? MarketSort.recent : sort);
}

/// «a 750 m», «a 12 km».
String marketDistanceLabel(int meters) {
  if (meters < 1000) return 'a meno di 1 km';
  final int km = (meters / 1000).round();
  return 'a $km km';
}

// ---------------------------------------------------------------- proposte di scambio (Blocco 3)

/// Stati di una proposta (specifica, sezione 6).
enum SwapStatus {
  pending('pending', 'In attesa'),
  accepted('accepted', 'Accettata'),
  rejected('rejected', 'Rifiutata'),
  countered('countered', 'Controproposta'),
  cancelled('cancelled', 'Annullata'),
  completed('completed', 'Completata');

  const SwapStatus(this.serverValue, this.label);

  final String serverValue;
  final String label;

  static SwapStatus fromServer(String? v) =>
      SwapStatus.values.firstWhere((SwapStatus s) => s.serverValue == v, orElse: () => SwapStatus.pending);
}

/// Chi aggiunge il conguaglio: chi chiede l'annuncio o chi l'ha pubblicato.
enum CashDirection {
  requesterPays('requester_pays'),
  ownerPays('owner_pays');

  const CashDirection(this.serverValue);

  final String serverValue;

  static CashDirection? fromServer(String? v) =>
      CashDirection.values.where((CashDirection d) => d.serverValue == v).firstOrNull;
}

/// Limiti delle proposte (migrazione 0014).
abstract final class SwapRules {
  static const int maxItems = 5;
  static const int messageMax = 500;

  /// Conguaglio da 1 a 999.999 €.
  static const int minCashCents = 100;
  static const int maxCashCents = 99999900;
}

/// Un annuncio che si può offrire, o che è stato offerto in una proposta.
@immutable
class SwapItem {
  const SwapItem({
    required this.id,
    required this.title,
    this.type = MarketType.sell,
    this.priceCents,
    this.photo,
    this.available = true,
  });

  factory SwapItem.fromJson(Map<String, dynamic> json) => SwapItem(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    type: MarketType.fromServer(json['market_type'] as String?),
    priceCents: (json['price_cents'] as num?)?.toInt(),
    photo: json['photo'] as String? ??
        ((json['photos'] as List?)?.isNotEmpty ?? false ? '${(json['photos'] as List).first}' : null),
    available: json['available'] as bool? ?? true,
  );

  final String id;
  final String title;
  final MarketType type;
  final int? priceCents;
  final String? photo;

  /// Ancora pubblicato e attivo.
  final bool available;
}

/// Cosa si offre: da 1 a 5 annunci, un eventuale conguaglio, un messaggio.
@immutable
class SwapOffer {
  const SwapOffer({required this.itemIds, this.cashCents, this.direction, this.message = ''});

  final List<String> itemIds;
  final int? cashCents;
  final CashDirection? direction;
  final String message;

  Map<String, Object?> toParams() => <String, Object?>{
    'p_items': itemIds,
    'p_cash_cents': cashCents,
    'p_cash_direction': cashCents == null ? null : direction?.serverValue,
    'p_message': message.trim(),
  };
}

/// Una proposta come la vede una delle due parti.
@immutable
class SwapProposal {
  const SwapProposal({
    required this.id,
    required this.status,
    this.parentId,
    required this.fromMe,
    required this.iAmOwner,
    required this.targetId,
    required this.targetTitle,
    this.targetType = MarketType.swap,
    this.targetPhoto,
    this.targetAvailable = true,
    this.targetCashAdjustment = false,
    required this.otherId,
    required this.otherUsername,
    required this.otherPublicName,
    this.otherIsBusiness = false,
    this.items = const <SwapItem>[],
    this.cashCents,
    this.direction,
    this.message = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory SwapProposal.fromJson(Map<String, dynamic> json) => SwapProposal(
    id: json['id'] as String,
    status: SwapStatus.fromServer(json['status'] as String?),
    parentId: json['parent_id'] as String?,
    fromMe: json['from_me'] as bool? ?? false,
    iAmOwner: json['i_am_owner'] as bool? ?? false,
    targetId: json['target_id'] as String,
    targetTitle: json['target_title'] as String? ?? '',
    targetType: MarketType.fromServer(json['target_type'] as String?),
    targetPhoto: json['target_photo'] as String?,
    targetAvailable: json['target_available'] as bool? ?? true,
    targetCashAdjustment: json['target_cash_adjustment'] as bool? ?? false,
    otherId: json['other_id'] as String,
    otherUsername: json['other_username'] as String? ?? '',
    otherPublicName: json['other_public_name'] as String? ?? '',
    otherIsBusiness: json['other_is_business'] as bool? ?? false,
    items: <SwapItem>[
      for (final Object? i in json['items'] as List? ?? const <Object?>[])
        if (i is Map<String, dynamic>) SwapItem.fromJson(i),
    ],
    cashCents: (json['cash_cents'] as num?)?.toInt(),
    direction: CashDirection.fromServer(json['cash_direction'] as String?),
    message: json['message'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String id;
  final SwapStatus status;

  /// La proposta a cui questa risponde (controproposta).
  final String? parentId;

  /// L'ho fatta io (altrimenti tocca a me rispondere).
  final bool fromMe;

  /// L'annuncio richiesto è mio.
  final bool iAmOwner;
  final String targetId;
  final String targetTitle;
  final MarketType targetType;
  final String? targetPhoto;
  final bool targetAvailable;

  /// L'annuncio richiesto accetta un conguaglio.
  final bool targetCashAdjustment;
  final String otherId;
  final String otherUsername;
  final String otherPublicName;
  final bool otherIsBusiness;
  final List<SwapItem> items;
  final int? cashCents;
  final CashDirection? direction;
  final String message;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get pending => status == SwapStatus.pending;

  /// Tocca a me: accettare, rifiutare o fare una controproposta.
  bool get toAnswer => pending && !fromMe;

  /// Il conguaglio dal punto di vista di chi legge.
  String? get cashLabel {
    final int? c = cashCents;
    final CashDirection? d = direction;
    if (c == null || d == null) return null;
    final bool iPay = (d == CashDirection.requesterPays) != iAmOwner;
    return iPay
        ? 'Conguaglio: aggiungi tu ${MarketRules.formatPrice(c)}'
        : 'Conguaglio: ${otherPublicName.isEmpty ? 'l\'altra persona' : otherPublicName} aggiunge ${MarketRules.formatPrice(c)}';
  }
}

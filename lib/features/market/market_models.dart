import 'dart:typed_data';

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
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// Regole degli annunci della Mappa (Fase 3, Blocco 2). Il server (0007) le ripete tutte.
abstract final class ListingRules {
  static const int titleMin = 3;
  static const int titleMax = 120;
  static const int detailsMax = 2000;
  static const int maxPhotos = 4;

  /// Categoria degli annunci delle persone (decisione del titolare, T4). La categoria
  /// «Promozione» è delle aziende e arriva con la Fase 6.
  static const String freeCategory = 'libera';

  static String? titleError(String value) {
    final int n = value.trim().length;
    if (n < titleMin) return 'Scrivi almeno $titleMin caratteri.';
    if (n > titleMax) return 'Al massimo $titleMax caratteri.';
    return null;
  }

  static String? detailsError(String value) =>
      value.length > detailsMax ? 'Al massimo $detailsMax caratteri.' : null;
}

/// Scadenze proposte (T5): da 1 ora a 7 giorni.
enum ListingExpiry {
  oneHour('1 ora'),
  threeHours('3 ore'),
  today('Oggi'),
  threeDays('3 giorni'),
  sevenDays('7 giorni');

  const ListingExpiry(this.label);

  final String label;

  /// Momento di scadenza a partire da [now] (ora del telefono). «Oggi» vale fino a
  /// mezzanotte, ma sempre almeno un'ora.
  DateTime resolve(DateTime now) => switch (this) {
    ListingExpiry.oneHour => now.add(const Duration(hours: 1)),
    ListingExpiry.threeHours => now.add(const Duration(hours: 3)),
    ListingExpiry.today => _latest(
      DateTime(now.year, now.month, now.day, 23, 59),
      now.add(const Duration(hours: 1)),
    ),
    ListingExpiry.threeDays => now.add(const Duration(days: 3)),
    ListingExpiry.sevenDays => now.add(const Duration(days: 7)),
  };

  static DateTime _latest(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
}

/// Dove compare l'annuncio (P9). Il server lo chiama «approximate» e «precise».
enum ListingPlace {
  /// Zona approssimata intorno alla posizione attuale (preselezionata).
  approximateZone('approximate'),

  /// Punto scelto a mano sulla mappa: bar, punto d'incontro. Visibile esattamente.
  chosenPoint('precise');

  const ListingPlace(this.serverValue);

  final String serverValue;

  static ListingPlace fromServer(String? value) =>
      value == 'precise' ? ListingPlace.chosenPoint : ListingPlace.approximateZone;

  String get title => switch (this) {
    ListingPlace.approximateZone => 'Zona approssimata',
    ListingPlace.chosenPoint => 'Punto scelto sulla mappa',
  };

  String get explanation => switch (this) {
    ListingPlace.approximateZone =>
      'Gli altri vedono solo la zona (circa 500 m), mai dove ti trovi esattamente.',
    ListingPlace.chosenPoint =>
      'Per un bar o un punto d\'incontro: gli altri vedono esattamente il punto che scegli. '
          'Vale solo per questo annuncio.',
  };
}

@immutable
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Quello che l'autore compila nel modulo.
class ListingDraft {
  ListingDraft({
    required this.title,
    this.details = '',
    required this.expiresAt,
    required this.place,
    required this.point,
    this.keptPhotos = const <String>[],
    this.newPhotos = const <Uint8List>[],
    this.groupSpots,
  });

  final String title;
  final String details;
  final DateTime expiresAt;
  final ListingPlace place;

  /// Posizione attuale (zona approssimata) o punto scelto. Il punto esatto resta
  /// privato sul server; gli altri vedono solo quello previsto da [place].
  final GeoPoint point;

  /// Foto già pubblicate da tenere (percorsi sul server) e foto nuove da caricare.
  final List<String> keptPhotos;
  final List<Uint8List> newPhotos;

  /// Evento di gruppo (R3.12): persone cercate oltre all'autore; null = annuncio semplice.
  final int? groupSpots;
}

enum ListingState {
  active('Attivo'),
  expired('Scaduto'),
  completed('Chiuso'),
  hidden('Nascosto'),
  removed('Rimosso');

  const ListingState(this.label);

  final String label;

  static ListingState fromServer(String? value) => switch (value) {
    'active' => ListingState.active,
    'expired' => ListingState.expired,
    'completed' => ListingState.completed,
    'hidden' => ListingState.hidden,
    _ => ListingState.removed,
  };
}

/// Un annuncio dell'utente, come lo restituisce `my_map_listings`.
@immutable
class MyListing {
  const MyListing({
    required this.id,
    required this.title,
    this.details = '',
    this.photos = const <String>[],
    required this.place,
    required this.publicPoint,
    required this.savedPoint,
    required this.state,
    this.availableNow = false,
    required this.expiresAt,
    required this.createdAt,
    this.groupSpots,
    this.participants = 0,
  });

  factory MyListing.fromJson(Map<String, dynamic> json) => MyListing(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    details: json['details'] as String? ?? '',
    photos: <String>[for (final Object? p in json['photos'] as List? ?? const <Object?>[]) '$p'],
    place: ListingPlace.fromServer(json['location_mode'] as String?),
    publicPoint: GeoPoint(
      (json['public_lat'] as num).toDouble(),
      (json['public_lon'] as num).toDouble(),
    ),
    savedPoint: GeoPoint(
      (json['exact_lat'] as num).toDouble(),
      (json['exact_lon'] as num).toDouble(),
    ),
    state: ListingState.fromServer(json['status'] as String?),
    availableNow: json['available_now'] as bool? ?? false,
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    groupSpots: (json['group_spots'] as num?)?.toInt(),
    participants: (json['participants'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String title;
  final String details;
  final List<String> photos;
  final ListingPlace place;

  /// Evento di gruppo: persone cercate e quante partecipano già.
  final int? groupSpots;
  final int participants;

  /// Punto che vedono gli altri (zona o punto scelto).
  final GeoPoint publicPoint;

  /// Punto salvato, visibile solo all'autore.
  final GeoPoint savedPoint;
  final ListingState state;

  /// «Disponibile ora» (R3.11), deciso dall'autore.
  final bool availableNow;
  final DateTime expiresAt;
  final DateTime createdAt;

  MyListing copyWith({ListingState? state, bool? availableNow}) => MyListing(
    id: id,
    title: title,
    details: details,
    photos: photos,
    place: place,
    publicPoint: publicPoint,
    savedPoint: savedPoint,
    state: state ?? this.state,
    availableNow: availableNow ?? this.availableNow,
    expiresAt: expiresAt,
    createdAt: createdAt,
    groupSpots: groupSpots,
    participants: participants,
  );

  bool get editable => state == ListingState.active;
}

/// «scade tra 3 ore», «scaduto»… per l'elenco dei propri annunci.
String expiryLabel(DateTime expiresAt, DateTime now) {
  final Duration left = expiresAt.difference(now);
  if (left.isNegative) return 'scaduto';
  if (left.inMinutes < 60) return 'scade tra ${left.inMinutes.clamp(1, 59)} min';
  if (left.inHours < 24) return 'scade tra ${left.inHours} ${left.inHours == 1 ? 'ora' : 'ore'}';
  final int days = (left.inHours / 24).round();
  return 'scade tra $days ${days == 1 ? 'giorno' : 'giorni'}';
}

/// Schede di «Ultimi annunci» e filtro categoria (T4): annunci delle persone e promozioni
/// delle aziende (queste ultime dalla Fase 6).
enum ListingTab {
  free('libera', 'Annunci'),
  promotions('promozione', 'Promozioni');

  const ListingTab(this.category, this.label);

  final String category;
  final String label;
}

/// Filtro «orario» (R3.11): annunci pubblicati di recente.
enum PublishedWithin {
  any(null, 'Sempre'),
  lastHour(1, 'Ultima ora'),
  today(24, 'Ultime 24 ore'),
  week(168, 'Ultimi 7 giorni');

  const PublishedWithin(this.hours, this.label);

  final int? hours;
  final String label;
}

/// Filtri della Mappa e di «Ultimi annunci»: raggio, orario, «Disponibile ora».
@immutable
class MapFilters {
  const MapFilters({
    this.radiusKm = 10,
    this.published = PublishedWithin.any,
    this.availableNowOnly = false,
  });

  static const List<int> radiusOptions = <int>[1, 5, 10, 30];

  final int radiusKm;
  final PublishedWithin published;
  final bool availableNowOnly;

  bool get narrowed => published != PublishedWithin.any || availableNowOnly;

  MapFilters copyWith({int? radiusKm, PublishedWithin? published, bool? availableNowOnly}) =>
      MapFilters(
        radiusKm: radiusKm ?? this.radiusKm,
        published: published ?? this.published,
        availableNowOnly: availableNowOnly ?? this.availableNowOnly,
      );

  @override
  bool operator ==(Object other) =>
      other is MapFilters &&
      other.radiusKm == radiusKm &&
      other.published == published &&
      other.availableNowOnly == availableNowOnly;

  @override
  int get hashCode => Object.hash(radiusKm, published, availableNowOnly);
}

/// Un annuncio di qualcuno vicino, come lo restituisce `map_listings_nearby`: solo il punto
/// pubblico e una distanza arrotondata a 250 m.
@immutable
class NearbyListing {
  const NearbyListing({
    required this.id,
    required this.title,
    this.details = '',
    this.category = ListingRules.freeCategory,
    this.photos = const <String>[],
    required this.place,
    required this.point,
    required this.distanceBandMeters,
    this.availableNow = false,
    required this.expiresAt,
    required this.createdAt,
    this.isMine = false,
    required this.ownerId,
    required this.ownerUsername,
    required this.ownerPublicName,
    this.ownerAvatarThumbPath,
    this.ownerIsBusiness = false,
    this.groupSpots,
    this.participants = 0,
  });

  factory NearbyListing.fromJson(Map<String, dynamic> json) => NearbyListing(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    details: json['details'] as String? ?? '',
    category: json['category'] as String? ?? ListingRules.freeCategory,
    photos: <String>[for (final Object? p in json['photos'] as List? ?? const <Object?>[]) '$p'],
    place: ListingPlace.fromServer(json['location_mode'] as String?),
    point: GeoPoint((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
    distanceBandMeters: (json['distance_band_m'] as num?)?.toInt() ?? 0,
    availableNow: json['available_now'] as bool? ?? false,
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    isMine: json['is_mine'] as bool? ?? false,
    ownerId: json['owner_id'] as String,
    ownerUsername: json['owner_username'] as String? ?? '',
    ownerPublicName: json['owner_public_name'] as String? ?? '',
    ownerAvatarThumbPath: json['owner_avatar_thumb_path'] as String?,
    ownerIsBusiness: json['owner_is_business'] as bool? ?? false,
    groupSpots: (json['group_spots'] as num?)?.toInt(),
    participants: (json['participants'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String title;
  final String details;
  final String category;
  final List<String> photos;
  final ListingPlace place;

  /// Punto pubblico: zona approssimata o punto scelto dall'autore.
  final GeoPoint point;
  final int distanceBandMeters;
  final bool availableNow;
  final DateTime expiresAt;
  final DateTime createdAt;
  final bool isMine;
  final String ownerId;
  final String ownerUsername;
  final String ownerPublicName;
  final String? ownerAvatarThumbPath;
  final bool ownerIsBusiness;

  /// Evento di gruppo: persone cercate (null = annuncio semplice) e partecipanti.
  final int? groupSpots;
  final int participants;

  /// Iniziale mostrata sul segnaposto della mappa (T2: foto o iniziale).
  String get initial {
    final String source = ownerPublicName.trim().isNotEmpty ? ownerPublicName : ownerUsername;
    return source.isEmpty ? '?' : source.trim().characters.first.toUpperCase();
  }
}

/// «a meno di 250 m», «a circa 1,5 km»: mai la distanza esatta.
String distanceLabel(int bandMeters) {
  if (bandMeters < 250) return 'a meno di 250 m';
  if (bandMeters < 1000) return 'a circa $bandMeters m';
  final double km = bandMeters / 1000;
  final String text = km == km.roundToDouble()
      ? km.toStringAsFixed(0)
      : km.toStringAsFixed(1).replaceAll('.', ',');
  return 'a circa $text km';
}

/// «pubblicato 5 min fa», «pubblicato ieri»…
String publishedLabel(DateTime createdAt, DateTime now) {
  final Duration ago = now.difference(createdAt);
  if (ago.inMinutes < 1) return 'pubblicato ora';
  if (ago.inMinutes < 60) return 'pubblicato ${ago.inMinutes} min fa';
  if (ago.inHours < 24) {
    return 'pubblicato ${ago.inHours} ${ago.inHours == 1 ? 'ora' : 'ore'} fa';
  }
  final int days = ago.inDays;
  return days == 1 ? 'pubblicato ieri' : 'pubblicato $days giorni fa';
}

/// Motivi della segnalazione: lo stesso elenco chiuso del server (0008).
enum ReportReason {
  spam('spam', 'Spam o pubblicità non richiesta'),
  scam('truffa', 'Truffa o richiesta di denaro'),
  inappropriate('contenuto_inappropriato', 'Contenuto offensivo o inappropriato'),
  danger('pericolo', 'Situazione pericolosa'),
  fake('falso', 'Annuncio falso'),
  other('altro', 'Altro');

  const ReportReason(this.serverValue, this.label);

  final String serverValue;
  final String label;
}

import 'package:flutter/foundation.dart';

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
    required this.expiresAt,
    required this.createdAt,
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
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String id;
  final String title;
  final String details;
  final List<String> photos;
  final ListingPlace place;

  /// Punto che vedono gli altri (zona o punto scelto).
  final GeoPoint publicPoint;

  /// Punto salvato, visibile solo all'autore.
  final GeoPoint savedPoint;
  final ListingState state;
  final DateTime expiresAt;
  final DateTime createdAt;

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

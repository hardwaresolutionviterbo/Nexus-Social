import 'dart:async';

import '../map/listing_models.dart' show GeoPoint;
import '../map/listing_repository.dart' show ListingFailure;
import '../map/map_location.dart';
import '../map/map_screen.dart' show MapServices;

/// Posizione del telefono una volta sola (Scambia & Vendi): per la zona di un annuncio o
/// per il punto di ricerca. Non viene seguita né salvata.
Future<GeoPoint> marketOneShotPosition(MapServices services) async {
  LocationAccess access = await services.location.status();
  if (access == LocationAccess.denied) access = await services.location.request();
  if (access != LocationAccess.granted) {
    throw const ListingFailure('Consenti la posizione oppure scegli un punto sulla mappa.');
  }
  try {
    final GeoFix fix = await services.location.fixes().first.timeout(const Duration(seconds: 20));
    return GeoPoint(fix.latitude, fix.longitude);
  } on TimeoutException {
    throw const ListingFailure('Posizione non trovata: riprova o scegli un punto sulla mappa.');
  }
}

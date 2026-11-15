import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

/// Regole della mappa (Fase 3, Blocco 1). Valori decisi nel piano: F9, R3.1, M3.
abstract final class MapRules {
  /// La posizione si aggiorna solo dopo circa 300 metri di spostamento (R3.1: batteria).
  static const int updateDistanceMeters = 300;

  /// Stile OpenFreeMap «Liberty»: tile gratuite con dati OpenStreetMap ed edifici 3D (F9).
  static const String styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  /// Attribuzione sempre visibile, come richiesto dalla licenza dei dati.
  static const String attribution = '© OpenStreetMap contributors · OpenFreeMap';

  /// Vista iniziale: tutta l'Italia, prima che arrivi la posizione.
  static const double italyLat = 42.5;
  static const double italyLng = 12.5;
  static const double italyZoom = 4.9;

  /// Vista sulla persona: abbastanza vicina da vedere gli edifici in 3D.
  static const double userZoom = 16;

  /// Inclinazione della vista 3D e della vista piatta.
  static const double tilt3d = 55;
  static const double tilt2d = 0;
}

/// Stato del permesso di posizione, senza dettagli della piattaforma.
enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// Una posizione del telefono: resta sul telefono e non viene inviata a nessuno.
@immutable
class GeoFix {
  const GeoFix({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.heading,
    required this.time,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? heading;
  final DateTime time;
}

/// Accesso alla posizione del telefono. Nei test si usa una versione finta.
abstract class DeviceLocation {
  /// Stato attuale, senza chiedere nulla alla persona.
  Future<LocationAccess> status();

  /// Mostra la richiesta del sistema (solo dopo la spiegazione dell'app).
  Future<LocationAccess> request();

  /// Posizioni con l'app aperta, una ogni [MapRules.updateDistanceMeters] metri circa.
  Stream<GeoFix> fixes();

  Future<void> openAppSettings();
  Future<void> openLocationSettings();
}

class GeolocatorDeviceLocation implements DeviceLocation {
  const GeolocatorDeviceLocation();

  static LocationAccess _map(LocationPermission p) => switch (p) {
    LocationPermission.whileInUse || LocationPermission.always => LocationAccess.granted,
    LocationPermission.deniedForever => LocationAccess.deniedForever,
    _ => LocationAccess.denied,
  };

  @override
  Future<LocationAccess> status() async {
    final LocationAccess access = _map(await Geolocator.checkPermission());
    if (access == LocationAccess.granted && !await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    return access;
  }

  @override
  Future<LocationAccess> request() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    final LocationAccess access = _map(p);
    if (access == LocationAccess.granted && !await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    return access;
  }

  @override
  Stream<GeoFix> fixes() {
    final LocationSettings settings = switch (defaultTargetPlatform) {
      // Precisione «bilanciata»: consuma poco ed è sufficiente per 300 metri.
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: MapRules.updateDistanceMeters,
        intervalDuration: const Duration(seconds: 30),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: MapRules.updateDistanceMeters,
        pauseLocationUpdatesAutomatically: true,
        // Mai in background: la posizione serve solo con la mappa aperta.
        allowBackgroundLocationUpdates: false,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: MapRules.updateDistanceMeters,
      ),
    };
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (Position p) => GeoFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        heading: p.heading >= 0 ? p.heading : null,
        time: p.timestamp,
      ),
    );
  }

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}

/// Ricorda se l'avviso di sicurezza della Mappa (M3) è già stato letto su questo telefono.
abstract class MapNoticeStore {
  Future<bool> seen();
  Future<void> markSeen();
}

class SecureMapNoticeStore implements MapNoticeStore {
  SecureMapNoticeStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'piazly_map_safety_notice_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> seen() async {
    try {
      return await _storage.read(key: _key) == 'yes';
    } catch (_) {
      // Memoria non leggibile: meglio mostrare di nuovo l'avviso che saltarlo.
      return false;
    }
  }

  @override
  Future<void> markSeen() async {
    try {
      await _storage.write(key: _key, value: 'yes');
    } catch (_) {
      // Non salvato: l'avviso ricomparirà al prossimo avvio, nessun danno.
    }
  }
}

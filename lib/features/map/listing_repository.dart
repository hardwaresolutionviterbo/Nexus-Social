import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException, StorageException, SupabaseClient;

import 'listing_models.dart';

/// Errore degli annunci con un messaggio già pronto per l'utente.
class ListingFailure implements Exception {
  const ListingFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Foto di un annuncio: lato lungo al massimo 1600 px, JPEG, senza metadati (posizione GPS
/// della foto, modello del telefono). Ricodificata sul telefono prima del caricamento.
abstract final class ListingPhotos {
  static const int maxSide = 1600;
  static const int maxBytes = 2 * 1024 * 1024;

  static Future<Uint8List> prepareInBackground(Uint8List original) => compute(prepare, original);

  static Uint8List prepare(Uint8List original) {
    final img.Image? decoded = img.decodeImage(original);
    if (decoded == null) {
      throw const ListingFailure('Formato dell\'immagine non supportato.');
    }
    img.Image image = img.bakeOrientation(decoded);
    final int longest = max(image.width, image.height);
    if (longest > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
    }
    image.exif = img.ExifData();
    final Uint8List jpg = img.encodeJpg(image, quality: 80);
    if (jpg.length > maxBytes) {
      throw const ListingFailure('Foto troppo pesante: scegline un\'altra.');
    }
    return jpg;
  }
}

/// Annunci della Mappa sul server (migrazione 0007). Nei test si usa una versione finta.
abstract class MapListingRepository {
  Future<String> publish(ListingDraft draft);

  /// Testo, scadenza e foto. Se cambia il luogo si usa anche [move].
  Future<void> update(String id, ListingDraft draft);

  Future<void> move(String id, GeoPoint point, ListingPlace place);

  Future<void> close(String id);

  Future<List<MyListing>> mine();

  Future<Uint8List?> downloadPhoto(String path);

  /// Annunci intorno a [origin] (la posizione serve solo al calcolo, non viene salvata).
  Future<List<NearbyListing>> nearby(
    GeoPoint origin,
    MapFilters filters, {
    ListingTab tab = ListingTab.free,
  });

  Future<void> setAvailableNow(String id, bool available);

  Future<void> report(String id, ReportReason reason, {String? details});
}

class SupabaseMapListingRepository implements MapListingRepository {
  SupabaseMapListingRepository(this._client, {required this.uid});

  static const String bucket = 'listing-photos';

  final SupabaseClient _client;
  final String Function() uid;

  @override
  Future<String> publish(ListingDraft d) => _guard(() async {
    final List<String> photos = await _upload(d);
    final Object? id = await _client.rpc(
      'publish_map_listing',
      params: <String, Object?>{
        'p_title': d.title.trim(),
        'p_details': d.details.trim(),
        'p_lat': d.point.latitude,
        'p_lon': d.point.longitude,
        'p_location_mode': d.place.serverValue,
        'p_expires_at': d.expiresAt.toUtc().toIso8601String(),
        'p_photos': photos,
      },
    );
    return '$id';
  });

  @override
  Future<void> update(String id, ListingDraft d) => _guard(() async {
    final List<String> photos = await _upload(d);
    await _client.rpc(
      'update_my_listing',
      params: <String, Object?>{
        'p_id': id,
        'p_title': d.title.trim(),
        'p_details': d.details.trim(),
        'p_expires_at': d.expiresAt.toUtc().toIso8601String(),
        'p_photos': photos,
      },
    );
  });

  @override
  Future<void> move(String id, GeoPoint point, ListingPlace place) => _guard(() async {
    await _client.rpc(
      'move_my_listing',
      params: <String, Object?>{
        'p_id': id,
        'p_lat': point.latitude,
        'p_lon': point.longitude,
        'p_location_mode': place.serverValue,
      },
    );
  });

  @override
  Future<void> close(String id) => _guard(() async {
    await _client.rpc('close_my_listing', params: <String, Object?>{'p_id': id});
  });

  @override
  Future<List<MyListing>> mine() => _guard(() async {
    final Object? data = await _client.rpc('my_map_listings');
    return <MyListing>[
      if (data is List)
        for (final Object? row in data)
          if (row is Map<String, dynamic>) MyListing.fromJson(row),
    ];
  });

  @override
  Future<Uint8List?> downloadPhoto(String path) async {
    try {
      return await _client.storage.from(bucket).download(path);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<NearbyListing>> nearby(
    GeoPoint origin,
    MapFilters filters, {
    ListingTab tab = ListingTab.free,
  }) => _guard(() async {
    final Object? data = await _client.rpc(
      'map_listings_nearby',
      params: <String, Object?>{
        'p_lat': origin.latitude,
        'p_lon': origin.longitude,
        'p_radius_m': filters.radiusKm * 1000,
        'p_category': tab.category,
        'p_published_within_hours': filters.published.hours,
        'p_available_now': filters.availableNowOnly,
      },
    );
    return <NearbyListing>[
      if (data is List)
        for (final Object? row in data)
          if (row is Map<String, dynamic>) NearbyListing.fromJson(row),
    ];
  });

  @override
  Future<void> setAvailableNow(String id, bool available) => _guard(() async {
    await _client.rpc(
      'set_my_listing_available',
      params: <String, Object?>{'p_id': id, 'p_available': available},
    );
  });

  @override
  Future<void> report(String id, ReportReason reason, {String? details}) => _guard(() async {
    await _client.rpc(
      'report_listing',
      params: <String, Object?>{
        'p_listing': id,
        'p_reason': reason.serverValue,
        'p_details': details?.trim().isEmpty ?? true ? null : details!.trim(),
      },
    );
  });

  Future<List<String>> _upload(ListingDraft d) async {
    final List<String> paths = <String>[...d.keptPhotos];
    const FileOptions options = FileOptions(contentType: 'image/jpeg', upsert: false);
    for (final Uint8List raw in d.newPhotos) {
      final Uint8List jpg = await ListingPhotos.prepareInBackground(raw);
      final String path = '${uid()}/${_randomToken()}.jpg';
      await _client.storage.from(bucket).uploadBinary(path, jpg, fileOptions: options);
      paths.add(path);
    }
    return paths;
  }

  static String _randomToken() {
    const String chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final Random r = Random.secure();
    return List<String>.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ListingFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw failureFor(e.code, e.message);
    } on StorageException {
      throw const ListingFailure('La foto non è stata caricata. Riprova.');
    } catch (_) {
      throw const ListingFailure('Qualcosa non ha funzionato. Riprova.');
    }
  }

  /// Messaggio per un errore del server, senza dati tecnici.
  static ListingFailure failureFor(String? code, String message) {
    switch (code) {
      case '22023':
        // Messaggi scritti dal server per l'utente (migrazione 0007).
        return ListingFailure('$message.');
      case '42501':
        if (message.contains('sospeso')) {
          return const ListingFailure('Il tuo account è sospeso: non puoi pubblicare.');
        }
        if (message.contains('non trovato')) {
          return const ListingFailure('Annuncio non più disponibile.');
        }
        if (message.contains('chiuso')) {
          return const ListingFailure('L\'annuncio è chiuso o rimosso: non si può modificare.');
        }
        return const ListingFailure('Operazione non permessa.');
      default:
        return const ListingFailure('Qualcosa non ha funzionato. Riprova.');
    }
  }
}

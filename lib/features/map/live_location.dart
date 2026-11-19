import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'map_location.dart';

/// GPS in tempo reale (Blocco 15, migrazione 0032).
///
/// Spento di partenza. Chi lo accende sceglie le persone (tra chi ha in rubrica) e per quanto:
/// 15 minuti, 1 ora o 8 ore. Si può smettere quando si vuole, anche per una sola persona. La
/// posizione si aggiorna mentre Piazly è aperta; quando la condivisione finisce, l'ultima posizione
/// si cancella dal server. Non è cifrata end-to-end: la proteggono le regole del server.

class LiveFailure implements Exception {
  const LiveFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Durate possibili, come su WhatsApp.
enum LiveDuration {
  quarter(15, '15 minuti'),
  hour(60, '1 ora'),
  eight(480, '8 ore');

  const LiveDuration(this.minutes, this.label);

  final int minutes;
  final String label;
}

/// Una persona con cui sto condividendo.
class LiveShare {
  const LiveShare({
    required this.viewerId,
    required this.name,
    required this.username,
    required this.expiresAt,
    this.avatarPath,
  });

  final String viewerId;
  final String name;
  final String username;
  final String? avatarPath;
  final DateTime expiresAt;
}

/// Una persona che sta condividendo la posizione con me.
class LivePerson {
  const LivePerson({
    required this.userId,
    required this.name,
    required this.username,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    required this.expiresAt,
    this.avatarPath,
    this.accuracy,
  });

  final String userId;
  final String name;
  final String username;
  final String? avatarPath;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime updatedAt;
  final DateTime expiresAt;

  String get initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

abstract class LiveLocationServer {
  Future<DateTime> start(List<String> viewers, int minutes);

  /// Con una sola persona ([viewer]) o con tutti (null).
  Future<void> stop({String? viewer});

  /// Falso se non c'è più nessuna condivisione attiva.
  Future<bool> update(double lat, double lng, double? accuracy);

  Future<List<LiveShare>> myShares();

  Future<List<LivePerson>> visible();
}

/// Il servizio, uno per l'app (vedi [LiveRegistry]).
class LiveLocationService extends ChangeNotifier {
  LiveLocationService({
    required this.server,
    required this.location,
    Stream<GeoFix> Function()? liveFixes,
    DateTime Function()? clock,
    this.minSendInterval = const Duration(seconds: 15),
  }) : _liveFixes = liveFixes ?? geolocatorLiveFixes,
       _clock = clock ?? DateTime.now;

  final LiveLocationServer server;
  final DeviceLocation location;
  final Stream<GeoFix> Function() _liveFixes;
  final DateTime Function() _clock;
  final Duration minSendInterval;

  /// Nome come scritto nella rubrica del telefono (Blocco 11).
  String? Function(String userId)? localName;

  List<LiveShare> _shares = const <LiveShare>[];
  List<LivePerson> _people = const <LivePerson>[];
  StreamSubscription<GeoFix>? _sub;
  Timer? _end;
  DateTime? _lastSent;
  GeoFix? _lastFix;
  bool _disposed = false;
  String? _error;

  DateTime get now => _clock();

  List<LiveShare> get shares =>
      <LiveShare>[for (final LiveShare s in _shares) if (s.expiresAt.isAfter(now)) s];

  bool get sharing => shares.isNotEmpty;

  /// Fino a quando, la più lunga delle condivisioni attive.
  DateTime? get until {
    final List<LiveShare> active = shares;
    if (active.isEmpty) return null;
    return active.map((LiveShare s) => s.expiresAt).reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);
  }

  /// Chi condivide con me (solo condivisioni ancora attive).
  List<LivePerson> get people =>
      <LivePerson>[for (final LivePerson p in _people) if (p.expiresAt.isAfter(now)) p];

  String? get error => _error;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String nameOf(String id, String fallback) {
    final String? local = localName?.call(id);
    return local != null && local.trim().isNotEmpty ? local : fallback;
  }

  /// Rilegge con chi sto condividendo e accende o spegne l'invio della posizione.
  Future<void> refresh() async {
    try {
      _shares = await server.myShares();
      _error = null;
    } on LiveFailure catch (e) {
      _error = e.message;
    } catch (_) {
      // Senza connessione resta lo stato di prima.
    }
    _sync();
    _notify();
  }

  void _sync() {
    _end?.cancel();
    if (!sharing) {
      unawaited(_sub?.cancel());
      _sub = null;
      _lastSent = null;
      return;
    }
    final Duration left = until!.difference(now);
    _end = Timer(left + const Duration(seconds: 1), () => unawaited(refresh()));
    _sub ??= _liveFixes().listen(_onFix, onError: (Object _) {});
  }

  bool _movedEnough(GeoFix a, GeoFix b) => distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude) > 50;

  Future<void> _onFix(GeoFix fix) async {
    final DateTime t = now;
    final GeoFix? last = _lastFix;
    final DateTime? sent = _lastSent;
    if (sent != null && t.difference(sent) < minSendInterval && (last == null || !_movedEnough(last, fix))) {
      return;
    }
    _lastFix = fix;
    _lastSent = t;
    try {
      final bool still = await server.update(fix.latitude, fix.longitude, fix.accuracyMeters);
      if (!still) await refresh();
    } catch (_) {
      // Riprova alla prossima posizione.
      _lastSent = null;
    }
  }

  Future<void> _ensurePermission() async {
    LocationAccess a = await location.status();
    if (a == LocationAccess.denied) a = await location.request();
    switch (a) {
      case LocationAccess.granted:
        return;
      case LocationAccess.serviceOff:
        throw const LiveFailure('Accendi la posizione (GPS) del telefono e riprova.');
      case LocationAccess.deniedForever:
        throw const LiveFailure('Serve il permesso di posizione: attivalo dalle impostazioni del telefono.');
      case LocationAccess.denied:
        throw const LiveFailure('Senza il permesso di posizione non si può condividere.');
    }
  }

  /// Accende (o rinnova) la condivisione con queste persone.
  Future<void> start(List<String> viewers, LiveDuration duration) async {
    if (viewers.isEmpty) throw const LiveFailure('Scegli almeno una persona.');
    await _ensurePermission();
    await server.start(viewers.toSet().toList()..sort(), duration.minutes);
    await refresh();
  }

  /// Smette con una persona o con tutti. L'ultima posizione si cancella dal server.
  Future<void> stop({String? viewer}) async {
    await server.stop(viewer: viewer);
    await refresh();
  }

  /// Chi condivide con me: la mappa lo chiede ogni 20 secondi mentre è aperta.
  Future<void> loadPeople() async {
    try {
      _people = await server.visible();
    } catch (_) {
      return;
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _end?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }
}

/// Distanza in metri tra due punti (formula dell'emisenoverso).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const double r = 6371000;
  double rad(double d) => d * math.pi / 180;
  final double dLat = rad(lat2 - lat1);
  final double dLng = rad(lng2 - lng1);
  final double s1 = math.sin(dLat / 2);
  final double s2 = math.sin(dLng / 2);
  final double a = s1 * s1 + math.cos(rad(lat1)) * math.cos(rad(lat2)) * s2 * s2;
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// Posizioni più fitte per il GPS in tempo reale: ogni 20 metri circa, con l'app aperta.
Stream<GeoFix> geolocatorLiveFixes() {
  final LocationSettings settings = switch (defaultTargetPlatform) {
    TargetPlatform.android => AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
      intervalDuration: const Duration(seconds: 10),
    ),
    TargetPlatform.iOS => AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
      allowBackgroundLocationUpdates: false,
    ),
    _ => const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
  };
  return Geolocator.getPositionStream(locationSettings: settings).map(
    (Position p) => GeoFix(latitude: p.latitude, longitude: p.longitude, accuracyMeters: p.accuracy, time: p.timestamp),
  );
}

/// Il servizio dell'app, come [ChatRegistry]: null finché il server non è collegato.
abstract final class LiveRegistry {
  static LiveLocationService? current;
}

class SupabaseLiveLocationServer implements LiveLocationServer {
  SupabaseLiveLocationServer(this._client);

  final SupabaseClient _client;

  Future<Object?> _rpc(String name, [Map<String, Object?>? params]) async {
    try {
      return await _client.rpc(name, params: params);
    } on PostgrestException catch (e) {
      if (e.code == '22023') throw LiveFailure(e.message.endsWith('.') ? e.message : '${e.message}.');
      throw const LiveFailure('Non è stato possibile: riprova tra poco.');
    } catch (_) {
      throw const LiveFailure('Connessione assente. Riprova tra poco.');
    }
  }

  static List<Map<String, dynamic>> _rows(Object? r) => <Map<String, dynamic>>[
    for (final Object? x in (r as List<dynamic>? ?? const <dynamic>[])) x as Map<String, dynamic>,
  ];

  static DateTime _time(Object? v) => DateTime.tryParse('$v')?.toLocal() ?? DateTime.now();

  static String _name(Map<String, dynamic> r) =>
      '${r['public_name'] ?? ''}'.trim().isNotEmpty ? '${r['public_name']}' : '@${r['username']}';

  @override
  Future<DateTime> start(List<String> viewers, int minutes) async =>
      _time(await _rpc('live_share_start', <String, Object?>{'p_viewers': viewers, 'p_minutes': minutes}));

  @override
  Future<void> stop({String? viewer}) async {
    await _rpc('live_share_stop', <String, Object?>{'p_viewer': viewer});
  }

  @override
  Future<bool> update(double lat, double lng, double? accuracy) async =>
      await _rpc('live_update', <String, Object?>{'p_lat': lat, 'p_lng': lng, 'p_accuracy': accuracy}) == true;

  @override
  Future<List<LiveShare>> myShares() async => <LiveShare>[
    for (final Map<String, dynamic> r in _rows(await _rpc('live_my_shares')))
      LiveShare(
        viewerId: '${r['viewer_id']}',
        name: _name(r),
        username: '${r['username'] ?? ''}',
        avatarPath: r['avatar_thumb_path'] as String?,
        expiresAt: _time(r['expires_at']),
      ),
  ];

  @override
  Future<List<LivePerson>> visible() async => <LivePerson>[
    for (final Map<String, dynamic> r in _rows(await _rpc('live_visible')))
      LivePerson(
        userId: '${r['user_id']}',
        name: _name(r),
        username: '${r['username'] ?? ''}',
        avatarPath: r['avatar_thumb_path'] as String?,
        latitude: (r['lat'] as num).toDouble(),
        longitude: (r['lng'] as num).toDouble(),
        accuracy: (r['accuracy'] as num?)?.toDouble(),
        updatedAt: _time(r['updated_at']),
        expiresAt: _time(r['expires_at']),
      ),
  ];
}

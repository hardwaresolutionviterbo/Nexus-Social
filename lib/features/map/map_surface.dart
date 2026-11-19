import 'dart:math' show Point;

import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'listing_models.dart';
import 'live_location.dart';
import 'map_location.dart';

/// Comandi che lo schermo della Mappa dà alla mappa disegnata.
/// Nei test la mappa vera (MapLibre) è sostituita da una finta.
abstract class MapSurfaceHandle {
  /// Sposta il segnaposto rotondo animato sulla posizione del telefono.
  Future<void> showMe(GeoFix fix);

  /// Porta la vista sulla posizione, in 3D o in piano.
  Future<void> flyTo(GeoFix fix, {required bool threeD});

  /// Inclina o raddrizza la vista lasciandola dov'è.
  Future<void> setThreeD(bool threeD);

  /// Punto al centro della vista (per scegliere a mano il luogo di un annuncio).
  Future<GeoPoint?> center();

  /// Segnaposti rotondi degli annunci vicini con l'iniziale dell'autore (T2); toccandoli
  /// si riceve l'identificativo dell'annuncio.
  Future<void> showListings(List<NearbyListing> listings, ValueChanged<String> onTap);

  /// Persone che condividono con me il GPS in tempo reale (Blocco 15): segnaposti viola con
  /// l'iniziale; toccandoli si riceve l'identificativo della persona.
  Future<void> showPeople(List<LivePerson> people, ValueChanged<String> onTap);
}

typedef MapSurfaceBuilder =
    Widget Function(BuildContext context, ValueChanged<MapSurfaceHandle> onReady);

/// Mappa MapLibre con le tile OpenFreeMap (F9).
///
/// La posizione arriva dall'app (sorgente «manuale»): MapLibre non legge il GPS da sola,
/// così l'aggiornamento resta quello deciso da [MapRules.updateDistanceMeters].
class MapLibreSurface extends StatefulWidget {
  const MapLibreSurface({super.key, required this.onReady});

  final ValueChanged<MapSurfaceHandle> onReady;

  static Widget builder(BuildContext context, ValueChanged<MapSurfaceHandle> onReady) =>
      MapLibreSurface(onReady: onReady);

  @override
  State<MapLibreSurface> createState() => _MapLibreSurfaceState();
}

class _MapLibreSurfaceState extends State<MapLibreSurface> implements MapSurfaceHandle {
  MapLibreMapController? _controller;
  ValueChanged<String>? _onListingTap;
  ValueChanged<String>? _onPersonTap;
  List<NearbyListing> _listings = const <NearbyListing>[];
  List<LivePerson> _people = const <LivePerson>[];

  void _tappedCircle(Circle c) => _tapped(c.data);
  void _tappedSymbol(Symbol s) => _tapped(s.data);

  void _tapped(Map<dynamic, dynamic>? data) {
    final Object? id = data?['id'];
    if (id is String) _onListingTap?.call(id);
    final Object? person = data?['persona'];
    if (person is String) _onPersonTap?.call(person);
  }

  @override
  Future<void> showPeople(List<LivePerson> people, ValueChanged<String> onTap) async {
    _onPersonTap = onTap;
    _people = people;
    await _redraw();
  }

  @override
  Future<void> showListings(List<NearbyListing> listings, ValueChanged<String> onTap) async {
    _onListingTap = onTap;
    _listings = listings;
    await _redraw();
  }

  /// Annunci e persone insieme: si ridisegnano tutti a ogni cambiamento.
  Future<void> _redraw() async {
    final MapLibreMapController? c = _controller;
    if (c == null) return;
    final List<NearbyListing> listings = _listings;
    final List<LivePerson> people = _people;
    await c.clearSymbols();
    await c.clearCircles();
    if (people.isNotEmpty) {
      final List<Map<String, dynamic>> who = <Map<String, dynamic>>[
        for (final LivePerson p in people) <String, dynamic>{'persona': p.userId},
      ];
      await c.addCircles(<CircleOptions>[
        for (final LivePerson p in people)
          CircleOptions(
            geometry: LatLng(p.latitude, p.longitude),
            circleRadius: 17,
            circleColor: '#7C3AED',
            circleStrokeWidth: 4,
            circleStrokeColor: '#FFFFFF',
          ),
      ], who);
      await c.addSymbols(<SymbolOptions>[
        for (final LivePerson p in people)
          SymbolOptions(
            geometry: LatLng(p.latitude, p.longitude),
            textField: p.initial,
            textSize: 14,
            textColor: '#FFFFFF',
            fontNames: const <String>['Noto Sans Bold'],
          ),
      ], who);
    }
    if (listings.isEmpty) return;
    final List<Map<String, dynamic>> data = <Map<String, dynamic>>[
      for (final NearbyListing l in listings) <String, dynamic>{'id': l.id},
    ];
    await c.addCircles(<CircleOptions>[
      for (final NearbyListing l in listings)
        CircleOptions(
          geometry: LatLng(l.point.latitude, l.point.longitude),
          circleRadius: 14,
          circleColor: l.isMine
              ? '#22B8CF'
              : l.availableNow
              ? '#12B886'
              : '#FF7A1A',
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ),
    ], data);
    await c.addSymbols(<SymbolOptions>[
      for (final NearbyListing l in listings)
        SymbolOptions(
          geometry: LatLng(l.point.latitude, l.point.longitude),
          textField: l.initial,
          textSize: 13,
          textColor: '#FFFFFF',
          fontNames: const <String>['Noto Sans Bold'],
        ),
    ], data);
  }

  @override
  void dispose() {
    _controller?.onCircleTapped.remove(_tappedCircle);
    _controller?.onSymbolTapped.remove(_tappedSymbol);
    super.dispose();
  }

  @override
  Future<void> showMe(GeoFix fix) async {
    await _controller?.updateManualLocation(
      ManualLocationUpdate(
        target: LatLng(fix.latitude, fix.longitude),
        horizontalAccuracy: fix.accuracyMeters,
        bearing: fix.heading,
        timestamp: fix.time,
      ),
    );
  }

  @override
  Future<void> flyTo(GeoFix fix, {required bool threeD}) async {
    final double bearing = _controller?.cameraPosition?.bearing ?? 0;
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(fix.latitude, fix.longitude),
          zoom: MapRules.userZoom,
          tilt: threeD ? MapRules.tilt3d : MapRules.tilt2d,
          bearing: bearing,
        ),
      ),
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  Future<void> setThreeD(bool threeD) async {
    await _controller?.animateCamera(
      CameraUpdate.tiltTo(threeD ? MapRules.tilt3d : MapRules.tilt2d),
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  Future<GeoPoint?> center() async {
    final LatLng? target = _controller?.cameraPosition?.target;
    return target == null ? null : GeoPoint(target.latitude, target.longitude);
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: MapRules.styleUrl,
      initialCameraPosition: const CameraPosition(
        target: LatLng(MapRules.italyLat, MapRules.italyLng),
        zoom: MapRules.italyZoom,
      ),
      minMaxZoomPreference: const MinMaxZoomPreference(3, 19),
      trackCameraPosition: true,
      // Rotazione e inclinazione con due dita: la vista 3D (F9).
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      compassEnabled: true,
      compassViewPosition: CompassViewPosition.topRight,
      compassViewMargins: const Point<num>(16, 96),
      // Oltre al testo sempre visibile dell'app resta il pulsante «i» di MapLibre.
      attributionEnabled: true,
      attributionButtonPosition: AttributionButtonPosition.bottomLeft,
      attributionButtonMargins: const Point<num>(8, 128),
      locationSource: const ManualLocationSource(),
      myLocationEnabled: true,
      myLocationStyle: const MyLocationStyle(
        fillColor: AppColors.brandOrange,
        accuracyColor: AppColors.brandOrange,
        pulseEnabled: true,
        pulseColor: AppColors.brandOrangeLight,
      ),
      // I segnaposti degli annunci sopra i cerchi, le iniziali sopra tutto.
      annotationOrder: const <AnnotationType>[
        AnnotationType.line,
        AnnotationType.fill,
        AnnotationType.circle,
        AnnotationType.symbol,
      ],
      onMapCreated: (MapLibreMapController c) {
        _controller = c;
        c.onCircleTapped.add(_tappedCircle);
        c.onSymbolTapped.add(_tappedSymbol);
      },
      onStyleLoadedCallback: () => widget.onReady(this),
    );
  }
}

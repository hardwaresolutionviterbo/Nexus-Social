import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/features/map/listing_models.dart';
import 'package:nexus_social/features/map/live_location.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/map/map_screen.dart';
import 'package:nexus_social/features/map/map_surface.dart';

/// Posizione finta: nessun GPS, nessun permesso vero.
class FakeDeviceLocation implements DeviceLocation {
  FakeDeviceLocation({this.current = LocationAccess.denied, this.afterRequest = LocationAccess.granted});

  LocationAccess current;
  LocationAccess afterRequest;
  int statusCalls = 0;
  int requestCalls = 0;
  int appSettingsCalls = 0;
  int locationSettingsCalls = 0;
  int listens = 0;
  int cancels = 0;
  StreamController<GeoFix>? _controller;

  bool get listening => _controller != null && _controller!.hasListener;

  void emit(GeoFix fix) => _controller?.add(fix);
  void fail(Object error) => _controller?.addError(error);

  @override
  Future<LocationAccess> status() async {
    statusCalls++;
    return current;
  }

  @override
  Future<LocationAccess> request() async {
    requestCalls++;
    current = afterRequest;
    return current;
  }

  @override
  Stream<GeoFix> fixes() {
    final StreamController<GeoFix> c = StreamController<GeoFix>(
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
    _controller = c;
    return c.stream;
  }

  @override
  Future<void> openAppSettings() async {
    appSettingsCalls++;
  }

  @override
  Future<void> openLocationSettings() async {
    locationSettingsCalls++;
  }
}

class MemoryNoticeStore implements MapNoticeStore {
  MemoryNoticeStore({this.wasSeen = false});

  bool wasSeen;
  int marks = 0;

  @override
  Future<bool> seen() async => wasSeen;

  @override
  Future<void> markSeen() async {
    marks++;
    wasSeen = true;
  }
}

/// Registra i comandi che lo schermo dà alla mappa.
class FakeMapHandle implements MapSurfaceHandle {
  final List<GeoFix> shown = <GeoFix>[];
  final List<(GeoFix, bool)> flights = <(GeoFix, bool)>[];
  final List<bool> tilts = <bool>[];

  @override
  Future<void> showMe(GeoFix fix) async => shown.add(fix);

  @override
  Future<void> flyTo(GeoFix fix, {required bool threeD}) async => flights.add((fix, threeD));

  @override
  Future<void> setThreeD(bool threeD) async => tilts.add(threeD);

  /// Centro della vista finta: si cambia nei test per «spostare la mappa».
  GeoPoint centerPoint = const GeoPoint(43.7731, 11.2560);

  @override
  Future<GeoPoint?> center() async => centerPoint;

  /// Annunci mostrati l'ultima volta e funzione per «toccarne» uno nei test.
  List<NearbyListing> markers = <NearbyListing>[];
  ValueChanged<String>? _onTap;
  int markerUpdates = 0;

  @override
  Future<void> showListings(List<NearbyListing> listings, ValueChanged<String> onTap) async {
    markers = listings;
    _onTap = onTap;
    markerUpdates++;
  }

  void tapMarker(String id) => _onTap?.call(id);

  List<LivePerson> people = const <LivePerson>[];
  ValueChanged<String>? _onPerson;

  @override
  Future<void> showPeople(List<LivePerson> people, ValueChanged<String> onTap) async {
    this.people = people;
    _onPerson = onTap;
  }

  void tapPerson(String id) => _onPerson?.call(id);
}

class FakeMapSurface extends StatefulWidget {
  const FakeMapSurface({super.key, required this.handle, required this.onReady});

  final FakeMapHandle handle;
  final ValueChanged<MapSurfaceHandle> onReady;

  @override
  State<FakeMapSurface> createState() => _FakeMapSurfaceState();
}

class _FakeMapSurfaceState extends State<FakeMapSurface> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady(widget.handle));
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: const ValueKey<String>('mappa_finta'),
    painter: _StreetsPainter(),
    child: const SizedBox.expand(),
  );
}

/// Strade disegnate a mano per le anteprime: non è una mappa reale.
class _StreetsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEAE6DF));
    final Paint park = Paint()..color = const Color(0xFFCDE8C4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.05, size.height * 0.55, size.width * 0.35, size.height * 0.16),
        const Radius.circular(18),
      ),
      park,
    );
    final Paint block = Paint()..color = const Color(0xFFD6D0C6);
    for (int i = 0; i < 9; i++) {
      for (int j = 0; j < 12; j++) {
        if ((i * 7 + j * 3) % 5 == 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(i * size.width / 8 + 10, j * size.height / 11 + 10, size.width / 8 - 26, size.height / 11 - 24),
          block,
        );
      }
    }
    final Paint road = Paint()
      ..color = Colors.white
      ..strokeWidth = 9;
    canvas.drawLine(Offset(0, size.height * 0.42), Offset(size.width, size.height * 0.30), road);
    canvas.drawLine(Offset(size.width * 0.62, 0), Offset(size.width * 0.48, size.height), road);
    final Paint water = Paint()
      ..color = const Color(0xFFA9D3F0)
      ..strokeWidth = 26;
    canvas.drawLine(Offset(0, size.height * 0.86), Offset(size.width, size.height * 0.78), water);
    // Segnaposto della persona: cerchio arancione con alone, come sul telefono.
    final Offset me = Offset(size.width * 0.52, size.height * 0.47);
    canvas.drawCircle(me, 34, Paint()..color = const Color(0x40FF7A1A));
    canvas.drawCircle(me, 13, Paint()..color = Colors.white);
    canvas.drawCircle(me, 10, Paint()..color = const Color(0xFFFF7A1A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FakeMap {
  FakeMap({LocationAccess access = LocationAccess.denied, bool noticeSeen = false})
    : location = FakeDeviceLocation(current: access),
      notices = MemoryNoticeStore(wasSeen: noticeSeen);

  final FakeDeviceLocation location;
  final MemoryNoticeStore notices;
  final FakeMapHandle handle = FakeMapHandle();
  int surfacesBuilt = 0;

  MapServices get services => MapServices(
    location: location,
    notices: notices,
    surface: (BuildContext context, ValueChanged<MapSurfaceHandle> onReady) {
      surfacesBuilt++;
      return FakeMapSurface(handle: handle, onReady: onReady);
    },
  );
}

GeoFix fixAt(double lat, double lng) =>
    GeoFix(latitude: lat, longitude: lng, accuracyMeters: 30, time: DateTime(2026, 11, 15, 11));

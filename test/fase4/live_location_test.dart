// Blocco 15: GPS in tempo reale. Solo con chi scelgo (in rubrica), a tempo, revocabile;
// la posizione si invia mentre l'app è aperta e sparisce a fine condivisione.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/features/contacts/contacts_sync.dart';
import 'package:nexus_social/features/map/live_location.dart';
import 'package:nexus_social/features/map/live_location_screens.dart';
import 'package:nexus_social/features/map/map_location.dart';

import '../support/fake_map.dart';

const String io = 'utenteAnna000000000000000001';
const String bruno = 'utenteBruno00000000000000002';
const String carla = 'utenteCarla00000000000000003';

/// Server finto con le stesse regole della migrazione 0032.
class FakeLiveHub {
  DateTime now = DateTime(2026, 11, 19, 10);
  final Map<String, Set<String>> contacts = <String, Set<String>>{
    io: <String>{bruno, carla},
    bruno: <String>{io},
  };
  final Map<String, String> names = <String, String>{io: 'Anna R.', bruno: 'Bruno B.', carla: 'Carla C.'};

  /// (owner, viewer) → scadenza.
  final Map<(String, String), DateTime> shares = <(String, String), DateTime>{};
  final Map<String, (double, double, DateTime)> positions = <String, (double, double, DateTime)>{};
  int updates = 0;

  void cleanup() {
    shares.removeWhere(((String, String) k, DateTime v) => !v.isAfter(now));
    positions.removeWhere((String u, _) => !shares.keys.any(((String, String) k) => k.$1 == u));
  }

  FakeLiveServer server(String uid) => FakeLiveServer(this, uid);
}

class FakeLiveServer implements LiveLocationServer {
  FakeLiveServer(this.hub, this.uid);

  final FakeLiveHub hub;
  final String uid;

  @override
  Future<DateTime> start(List<String> viewers, int minutes) async {
    if (!<int>[15, 60, 480].contains(minutes)) throw const LiveFailure('Durata non valida.');
    if (viewers.any((String v) => !(hub.contacts[uid]?.contains(v) ?? false))) {
      throw const LiveFailure('Puoi condividere la posizione solo con chi hai in rubrica.');
    }
    hub.cleanup();
    final DateTime until = hub.now.add(Duration(minutes: minutes));
    for (final String v in viewers) {
      hub.shares[(uid, v)] = until;
    }
    return until;
  }

  @override
  Future<void> stop({String? viewer}) async {
    hub.shares.removeWhere(((String, String) k, _) => k.$1 == uid && (viewer == null || k.$2 == viewer));
    hub.cleanup();
  }

  @override
  Future<bool> update(double lat, double lng, double? accuracy) async {
    hub.updates++;
    if (!hub.shares.entries.any((MapEntry<(String, String), DateTime> e) => e.key.$1 == uid && e.value.isAfter(hub.now))) {
      hub.positions.remove(uid);
      return false;
    }
    hub.positions[uid] = (lat, lng, hub.now);
    return true;
  }

  @override
  Future<List<LiveShare>> myShares() async => <LiveShare>[
    for (final MapEntry<(String, String), DateTime> e in hub.shares.entries)
      if (e.key.$1 == uid && e.value.isAfter(hub.now))
        LiveShare(viewerId: e.key.$2, name: hub.names[e.key.$2]!, username: e.key.$2, expiresAt: e.value),
  ];

  @override
  Future<List<LivePerson>> visible() async {
    hub.cleanup();
    return <LivePerson>[
      for (final MapEntry<(String, String), DateTime> e in hub.shares.entries)
        if (e.key.$2 == uid && hub.positions.containsKey(e.key.$1))
          LivePerson(
            userId: e.key.$1,
            name: hub.names[e.key.$1]!,
            username: e.key.$1,
            latitude: hub.positions[e.key.$1]!.$1,
            longitude: hub.positions[e.key.$1]!.$2,
            updatedAt: hub.positions[e.key.$1]!.$3,
            expiresAt: e.value,
          ),
    ];
  }
}

GeoFix fix(double lat, double lng) => GeoFix(latitude: lat, longitude: lng, time: DateTime(2026));

void main() {
  late FakeLiveHub hub;
  late StreamController<GeoFix> gps;

  setUp(() {
    hub = FakeLiveHub();
    gps = StreamController<GeoFix>.broadcast();
  });

  LiveLocationService phone(String uid, {FakeDeviceLocation? location}) => LiveLocationService(
    server: hub.server(uid),
    location: location ?? FakeDeviceLocation(current: LocationAccess.granted),
    liveFixes: () => gps.stream,
    clock: () => hub.now,
  );

  test('si accende per le persone scelte; la posizione arriva solo a loro', () async {
    final LiveLocationService a = phone(io);
    final LiveLocationService b = phone(bruno);
    final LiveLocationService c = phone(carla);
    expect(a.sharing, isFalse, reason: 'spento di partenza');
    await a.start(<String>[bruno], LiveDuration.hour);
    expect(a.sharing, isTrue);
    expect(a.until, hub.now.add(const Duration(hours: 1)));
    expect(liveSummary(a), 'Attivo con 1 persona fino alle 11:00');

    gps.add(fix(42.42, 12.10));
    await pumpEventQueue();
    await b.loadPeople();
    await c.loadPeople();
    expect(b.people.single.latitude, 42.42);
    expect(c.people, isEmpty);

    await expectLater(a.start(<String>['sconosciuto'], LiveDuration.quarter), throwsA(isA<LiveFailure>()));
    await expectLater(a.start(const <String>[], LiveDuration.quarter), throwsA(isA<LiveFailure>()));
    for (final LiveLocationService s in <LiveLocationService>[a, b, c]) {
      s.dispose();
    }
  });

  test('non invia troppo spesso: ogni 15 secondi, o prima se ci si sposta di più di 50 metri', () async {
    final LiveLocationService a = phone(io);
    await a.start(<String>[bruno], LiveDuration.quarter);
    gps.add(fix(42.4200, 12.1000));
    await pumpEventQueue();
    gps.add(fix(42.4201, 12.1000)); // 11 m, subito dopo
    await pumpEventQueue();
    expect(hub.updates, 1);
    gps.add(fix(42.4210, 12.1000)); // 110 m
    await pumpEventQueue();
    expect(hub.updates, 2);
    hub.now = hub.now.add(const Duration(seconds: 16));
    gps.add(fix(42.4211, 12.1000));
    await pumpEventQueue();
    expect(hub.updates, 3);
    a.dispose();
  });

  test('smetti con una persona o con tutti: l\'ultima posizione si cancella', () async {
    hub.contacts[io] = <String>{bruno, carla};
    final LiveLocationService a = phone(io);
    final LiveLocationService b = phone(bruno);
    await a.start(<String>[bruno, carla], LiveDuration.eight);
    gps.add(fix(42.4, 12.1));
    await pumpEventQueue();
    expect(a.shares, hasLength(2));
    await a.stop(viewer: carla);
    expect(a.shares.single.viewerId, bruno);
    expect(hub.positions, contains(io));
    await a.stop();
    expect(a.sharing, isFalse);
    expect(hub.positions, isEmpty);
    await b.loadPeople();
    expect(b.people, isEmpty);
    a.dispose();
    b.dispose();
  });

  test('a tempo scaduto sparisce per chi guardava', () async {
    final LiveLocationService a = phone(io);
    final LiveLocationService b = phone(bruno);
    await a.start(<String>[bruno], LiveDuration.quarter);
    gps.add(fix(42.4, 12.1));
    await pumpEventQueue();
    await b.loadPeople();
    expect(b.people, hasLength(1));
    hub.now = hub.now.add(const Duration(minutes: 16));
    expect(b.people, isEmpty, reason: 'scaduto anche prima di ricaricare');
    expect(a.sharing, isFalse);
    await b.loadPeople();
    expect(hub.positions, isEmpty);
    a.dispose();
    b.dispose();
  });

  test('senza permesso di posizione non parte e lo dice', () async {
    final LiveLocationService a = phone(
      io,
      location: FakeDeviceLocation(afterRequest: LocationAccess.deniedForever),
    );
    await expectLater(a.start(<String>[bruno], LiveDuration.hour), throwsA(isA<LiveFailure>()));
    expect(hub.shares, isEmpty);
    a.dispose();
  });

  testWidgets('Privacy → GPS: scelgo persona e durata, poi smetto', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final LiveLocationService a = phone(io);
    const List<RecognizedContact> contacts = <RecognizedContact>[
      RecognizedContact(id: bruno, username: 'bruno_b', publicName: 'Bruno B.'),
      RecognizedContact(id: carla, username: 'carla', publicName: 'Carla C.'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: LiveShareCard(service: a, contacts: contacts))),
    ));
    expect(find.text('Nessuna condivisione attiva.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('gps_condividi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('gps_durata_15')));
    await tester.tap(find.byKey(const ValueKey<String>('gps_persona_$carla')));
    await tester.pump();
    expect(find.text('Condividi per 15 minuti'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('gps_avvia')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('gps_attivo')), findsOneWidget);
    expect(find.text('Carla C.'), findsOneWidget);
    expect(hub.shares.keys.single, (io, carla));

    await tester.tap(find.byKey(const ValueKey<String>('gps_stop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('gps_stop_conferma')));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna condivisione attiva.'), findsOneWidget);
    expect(hub.shares, isEmpty);
    await tester.pumpWidget(const SizedBox());
    a.dispose();
  });

  test('distanza in metri', () {
    expect(distanceMeters(42.42, 12.10, 42.43, 12.10), closeTo(1112, 5));
  });
}

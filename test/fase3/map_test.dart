import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/map/map_location.dart';
import 'package:nexus_social/features/map/map_screen.dart';
import 'package:nexus_social/features/map/safety_notice.dart';
import 'package:nexus_social/features/shell/app_shell.dart';

import '../support/app_helpers.dart';
import '../support/fake_map.dart';

/// Fase 3, Blocco 1 · Prototipo della mappa: avviso M3, permesso con spiegazione,
/// posizione ogni ~300 m solo con la scheda aperta, vista 3D, attribuzione OSM.
void main() {
  Future<void> pumpMap(WidgetTester tester, FakeMap map, {bool active = true}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: MapScreen(active: active, services: map.services)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> rebuild(WidgetTester tester, FakeMap map, {required bool active}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: MapScreen(active: active, services: map.services)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Regole', () {
    test('aggiornamento ogni 300 m, tile OpenFreeMap, attribuzione OpenStreetMap', () {
      expect(MapRules.updateDistanceMeters, 300);
      expect(MapRules.styleUrl, startsWith('https://tiles.openfreemap.org/styles/'));
      expect(MapRules.attribution, contains('© OpenStreetMap contributors'));
      expect(MapRules.tilt3d, greaterThan(0));
      expect(MapRules.tilt2d, 0);
    });
  });

  group('M3 · avviso di sicurezza', () {
    testWidgets('al primo accesso compare prima di tutto e non chiede ancora la posizione', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap();
      await pumpMap(tester, map);

      expect(find.text('Sicurezza sulla mappa'), findsOneWidget);
      expect(find.text('Ho capito'), findsOneWidget);
      expect(map.location.statusCalls, 0);
      expect(map.location.requestCalls, 0);
      expect(find.byKey(const ValueKey<String>('richiesta_posizione')), findsNothing);

      await tester.tap(find.text('Ho capito'));
      await tester.pumpAndSettle();

      expect(find.text('Sicurezza sulla mappa'), findsNothing);
      expect(map.notices.marks, 1);
      expect(map.location.statusCalls, 1);
    });

    testWidgets('già letto: non ricompare da solo, ma si riapre sempre dallo scudo', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await pumpMap(tester, map);
      expect(find.text('Sicurezza sulla mappa'), findsNothing);

      await tester.tap(find.byTooltip('Consigli di sicurezza'));
      await tester.pumpAndSettle();
      expect(find.text('Sicurezza sulla mappa'), findsOneWidget);
      for (final (IconData _, String tip) in SafetyNoticeCard.tips) {
        expect(find.text(tip), findsOneWidget);
      }

      await tester.tap(find.text('Ho capito'));
      await tester.pumpAndSettle();
      expect(find.text('Sicurezza sulla mappa'), findsNothing);
    });

    testWidgets('l\'avviso copre la mappa: sotto non si tocca nulla finché non si legge', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap(access: LocationAccess.granted);
      await pumpMap(tester, map);
      await tester.tap(find.byTooltip('Centra su di me'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(map.handle.flights, isEmpty);
      expect(find.text('Sicurezza sulla mappa'), findsOneWidget);
    });
  });

  group('Permesso di posizione', () {
    testWidgets('prima la spiegazione, poi la richiesta del telefono solo con «Consenti»', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap(noticeSeen: true);
      await pumpMap(tester, map);

      expect(find.text('Mostra la mappa intorno a te'), findsOneWidget);
      expect(find.textContaining('circa ogni 300 metri'), findsOneWidget);
      expect(find.textContaining('solo con l\'app aperta'), findsOneWidget);
      expect(find.textContaining('posizione esatta non sarà mai visibile'), findsOneWidget);
      expect(map.location.requestCalls, 0);
      expect(map.location.listening, isFalse);

      await tester.tap(find.text('Consenti posizione'));
      await tester.pumpAndSettle();

      expect(map.location.requestCalls, 1);
      expect(map.location.listening, isTrue);
      expect(find.byKey(const ValueKey<String>('richiesta_posizione')), findsNothing);
    });

    testWidgets('«Non ora» chiude la spiegazione; «Centra su di me» la ripropone', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap(noticeSeen: true);
      await pumpMap(tester, map);
      await tester.tap(find.text('Non ora'));
      await tester.pumpAndSettle();
      expect(find.text('Mostra la mappa intorno a te'), findsNothing);
      expect(map.location.requestCalls, 0);

      await tester.tap(find.byTooltip('Centra su di me'));
      await tester.pumpAndSettle();
      expect(find.text('Mostra la mappa intorno a te'), findsOneWidget);
    });

    testWidgets('negato per sempre: porta alle impostazioni del telefono', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.deniedForever);
      await pumpMap(tester, map);
      expect(find.text('Posizione non consentita'), findsOneWidget);
      await tester.tap(find.text('Apri impostazioni'));
      await tester.pumpAndSettle();
      expect(map.location.appSettingsCalls, 1);
      expect(map.location.requestCalls, 0);
    });

    testWidgets('localizzazione spenta: porta ad accenderla', (WidgetTester tester) async {
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.serviceOff);
      await pumpMap(tester, map);
      expect(find.text('Localizzazione spenta'), findsOneWidget);
      await tester.tap(find.text('Attiva localizzazione'));
      await tester.pumpAndSettle();
      expect(map.location.locationSettingsCalls, 1);
    });

    testWidgets('localizzazione spenta mentre la mappa è aperta: lo dice e smette di ascoltare', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await pumpMap(tester, map);
      expect(map.location.listening, isTrue);
      map.location.fail(StateError('servizio spento'));
      await tester.pumpAndSettle();
      expect(find.text('Localizzazione spenta'), findsOneWidget);
      expect(map.location.listening, isFalse);
    });
  });

  group('Posizione e vista 3D', () {
    testWidgets('la prima posizione centra la mappa in 3D; le successive spostano solo il segnaposto', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await pumpMap(tester, map);

      map.location.emit(fixAt(42.4, 12.1));
      await tester.pumpAndSettle();
      expect(map.handle.shown, hasLength(1));
      expect(map.handle.flights, hasLength(1));
      expect(map.handle.flights.single.$2, isTrue);

      // Dopo ~300 m arriva la posizione nuova: il segnaposto si sposta, la vista no.
      map.location.emit(fixAt(42.403, 12.1));
      await tester.pumpAndSettle();
      expect(map.handle.shown, hasLength(2));
      expect(map.handle.flights, hasLength(1));

      await tester.tap(find.byTooltip('Centra su di me'));
      await tester.pumpAndSettle();
      expect(map.handle.flights, hasLength(2));
      expect(map.handle.flights.last.$1.latitude, 42.403);
    });

    testWidgets('pulsante 2D/3D: inclina o raddrizza la vista', (WidgetTester tester) async {
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await pumpMap(tester, map);
      expect(find.byTooltip('Vista in piano'), findsOneWidget);

      await tester.tap(find.byTooltip('Vista in piano'));
      await tester.pumpAndSettle();
      expect(map.handle.tilts, <bool>[false]);
      expect(find.byTooltip('Vista 3D'), findsOneWidget);

      map.location.emit(fixAt(45.46, 9.19));
      await tester.pumpAndSettle();
      expect(map.handle.flights.single.$2, isFalse);

      await tester.tap(find.byTooltip('Vista 3D'));
      await tester.pumpAndSettle();
      expect(map.handle.tilts, <bool>[false, true]);
    });

    testWidgets('attribuzione OpenStreetMap sempre visibile', (WidgetTester tester) async {
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await pumpMap(tester, map);
      expect(find.text(MapRules.attribution), findsOneWidget);
    });
  });

  group('Batteria', () {
    testWidgets('con la scheda chiusa non si crea la mappa e non si ascolta la posizione', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await pumpMap(tester, map, active: false);
      expect(map.surfacesBuilt, 0);
      expect(map.location.statusCalls, 0);
      expect(map.location.listening, isFalse);

      await rebuild(tester, map, active: true);
      expect(map.surfacesBuilt, greaterThan(0));
      expect(map.location.listening, isTrue);

      // Cambio scheda: smette di ascoltare.
      await rebuild(tester, map, active: false);
      expect(map.location.listening, isFalse);
    });

    testWidgets('app in background: smette di ascoltare; al ritorno ricontrolla e riprende', (
      WidgetTester tester,
    ) async {
      final FakeMap map = FakeMap(noticeSeen: true, access: LocationAccess.granted);
      await pumpMap(tester, map);
      expect(map.location.listening, isTrue);
      final int checks = map.location.statusCalls;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(map.location.listening, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(map.location.statusCalls, greaterThan(checks));
      expect(map.location.listening, isTrue);
    });
  });

  group('Barra delle sezioni', () {
    testWidgets('la Mappa parte solo quando si apre la sua scheda', (WidgetTester tester) async {
      final FakeMap map = FakeMap();
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: AppShell(map: map.services)),
      );
      await tester.pumpAndSettle();
      expect(map.surfacesBuilt, 0);
      expect(find.text('Sicurezza sulla mappa'), findsNothing);

      await openSection(tester, 'Mappa');
      expect(find.text('Sicurezza sulla mappa'), findsOneWidget);
      expect(map.surfacesBuilt, greaterThan(0));
    });

    testWidgets('senza servizi del telefono (anteprime): riquadro neutro, nessun avviso', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const AppShell()));
      await tester.pumpAndSettle();
      await openSection(tester, 'Mappa');
      expect(find.text('La mappa compare qui sul telefono.'), findsOneWidget);
      expect(find.text('Mappa Sociale'), findsOneWidget);
      expect(find.text(MapRules.attribution), findsOneWidget);
    });
  });
}

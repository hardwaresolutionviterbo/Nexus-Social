// Blocco 14: Privacy → Autorizzazioni mostra lo stato vero dei permessi, con un pulsante.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/features/privacy/phone_permissions.dart';

class _Fake implements PhonePermissions {
  final Map<PhonePermission, PermissionState> states = <PhonePermission, PermissionState>{
    PhonePermission.notifications: PermissionState.granted,
    PhonePermission.camera: PermissionState.denied,
    PhonePermission.microphone: PermissionState.blocked,
    PhonePermission.location: PermissionState.granted,
    PhonePermission.contacts: PermissionState.denied,
  };
  final List<PhonePermission> requested = <PhonePermission>[];
  int settings = 0;

  @override
  Future<PermissionState> status(PhonePermission p) async => states[p]!;

  @override
  Future<PermissionState> request(PhonePermission p) async {
    requested.add(p);
    return states[p] = PermissionState.granted;
  }

  @override
  Future<void> openSettings() async => settings++;
}

void main() {
  testWidgets('stato vero, «Consenti» chiede il permesso, «Impostazioni» apre il telefono',
      (WidgetTester tester) async {
    final _Fake fake = _Fake();
    phonePermissions = fake;
    addTearDown(() => phonePermissions = const RealPhonePermissions());
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PhonePermissionsList()))));
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp(r'^Attivo\n')), findsNWidgets(2));
    expect(find.textContaining(RegExp(r'^Non attivo\n')), findsNWidgets(2));
    expect(find.textContaining('Bloccato'), findsOneWidget);
    expect(find.textContaining('Messaggi vocali e chiamate'), findsOneWidget);
    // Testi vecchi tolti.
    expect(find.textContaining('Fase'), findsNothing);
    expect(find.textContaining('Non usat'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('permesso_camera_azione')));
    await tester.pumpAndSettle();
    expect(fake.requested, <PhonePermission>[PhonePermission.camera]);
    expect(find.textContaining(RegExp(r'^Attivo\n')), findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey<String>('permesso_microphone_azione')));
    await tester.pumpAndSettle();
    expect(fake.settings, 1);
  });
}

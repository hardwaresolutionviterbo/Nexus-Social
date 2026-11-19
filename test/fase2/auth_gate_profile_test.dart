import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/app.dart';
import 'package:nexus_social/features/profile/profile_models.dart';
import 'package:nexus_social/features/profile/profile_repository.dart';

import '../support/app_helpers.dart';
import '../support/fake_auth_gateway.dart';
import '../support/fake_profile_repository.dart';

/// Dopo l'accesso (Fase 2, Blocco 2): profilo da completare, poi l'app.
void main() {
  late FakeAuthGateway gateway;
  late FakeProfileRepository repo;

  setUp(() {
    gateway = FakeAuthGateway(uid: 'utenteProva');
    repo = FakeProfileRepository();
  });
  tearDown(() => gateway.close());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NexusApp(authGateway: gateway, profiles: repo));
    await tester.pumpAndSettle();
  }

  testWidgets('profilo non ancora creato: si completa, poi l\'app si apre su Chat', (tester) async {
    await pumpApp(tester);
    expect(find.text('Completa il profilo'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    for (final (String key, String text) in <(String, String)>[
      ('nascita', '01/01/1990'),
      ('username', 'carlo_r'),
      ('nome', 'Carlo Rossi'),
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey<String>(key)));
      await tester.enterText(find.byKey(ValueKey<String>(key)), text);
    }
    await tester.ensureVisible(find.byKey(const ValueKey<String>('salva_profilo')));
    await tester.tap(find.byKey(const ValueKey<String>('salva_profilo')));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Chat e chiamate'), findsOneWidget);
    await openSection(tester, 'Profilo');
    expect(find.text('Carlo R.'), findsOneWidget);
    expect(find.text('@carlo_r'), findsOneWidget);
  });

  testWidgets('profilo esistente: si apre l\'app; anteprima pubblica dal Profilo', (tester) async {
    repo.mine = const MyProfile(
      id: 'utenteProva',
      isBusiness: false,
      username: 'laura_b',
      publicName: 'Laura B.',
      fullName: 'Laura Bianchi',
      bio: 'Bio nascosta',
      showBio: false,
    );
    await pumpApp(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    await openSection(tester, 'Profilo');
    expect(find.byKey(const ValueKey<String>('mio_nome_pubblico')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('anteprima_profilo')));
    await tester.pumpAndSettle();
    expect(find.text('Come ti vedono gli altri'), findsOneWidget);
    expect(find.text('Bio nascosta'), findsNothing);
    expect(find.textContaining('Bianchi'), findsNothing);
  });

  testWidgets('profilo non caricato: messaggio e «Riprova»', (tester) async {
    repo.failNext = const ProfileFailure('Controlla la connessione e riprova.');
    await pumpApp(tester);
    expect(find.text('Profilo non caricato'), findsOneWidget);
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Completa il profilo'), findsOneWidget);
  });
}

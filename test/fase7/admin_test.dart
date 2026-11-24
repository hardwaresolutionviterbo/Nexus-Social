import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/admin/admin_models.dart';
import 'package:nexus_social/features/admin/admin_screen.dart';
import 'package:nexus_social/features/admin/moderation_gate.dart';

import '../support/fake_admin.dart';
import '../support/fake_security.dart';

Widget app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

FakeAdminRepository withQueue() {
  final FakeAdminRepository repo = FakeAdminRepository();
  repo.open.addAll(<AdminReport>[sampleListingReport(), sampleCommentReport(), sampleChatReport()]);
  repo.addUser(samplePerson(), reportsOpen: 1);
  repo.addUser(samplePerson(id: 'u2', username: 'promo.facile'));
  repo.addUser(samplePerson(id: 'u3', username: 'marco.b'));
  return repo;
}

Future<void> openGestionale(WidgetTester tester, FakeAdminRepository repo, {FakeBiometricLock? lock}) async {
  await tester.pumpWidget(app(AdminScreen(repository: repo, biometric: lock ?? FakeBiometricLock())));
  await tester.pumpAndSettle();
}

void main() {
  group('Accesso riservato', () {
    testWidgets('chi non è amministratore non entra', (WidgetTester tester) async {
      final FakeAdminRepository repo = withQueue()..accessState = const AdminAccess();
      await openGestionale(tester, repo);
      expect(find.text('Area riservata'), findsOneWidget);
      expect(find.text('Segnalazioni'), findsNothing);
      expect(find.byKey(const ValueKey<String>('gestionale_riprova')), findsNothing);
    });

    testWidgets('senza PIN non si apre', (WidgetTester tester) async {
      final FakeAdminRepository repo = withQueue()..accessState = const AdminAccess(admin: true, pin: false);
      await openGestionale(tester, repo);
      expect(find.text('Serve la verifica in due passaggi'), findsOneWidget);
      expect(find.text('Segnalazioni'), findsNothing);
    });

    testWidgets('impronta sbagliata: resta chiuso; giusta: si apre', (WidgetTester tester) async {
      final FakeAdminRepository repo = withQueue();
      final FakeBiometricLock lock = FakeBiometricLock()..succeed = false;
      await openGestionale(tester, repo, lock: lock);
      expect(find.text('Sblocco non riuscito'), findsOneWidget);
      lock.succeed = true;
      await tester.tap(find.byKey(const ValueKey<String>('gestionale_riprova')));
      await tester.pumpAndSettle();
      expect(lock.prompts, 2);
      expect(find.text('Segnalazioni'), findsOneWidget);
      expect(find.text('3 da gestire'), findsOneWidget);
      expect(find.text('Utenti'), findsOneWidget);
    });
  });

  group('Segnalazioni', () {
    testWidgets('elimina un annuncio: esce dalla coda e va tra le gestite', (WidgetTester tester) async {
      tall(tester);
      final FakeAdminRepository repo = withQueue();
      await openGestionale(tester, repo);
      await tester.tap(find.byKey(const ValueKey<String>('gestionale_segnalazioni')));
      await tester.pumpAndSettle();
      expect(find.text('iPhone nuovo a 100 €'), findsOneWidget);
      expect(find.textContaining('Truffa, Spam · 3 segnalazioni'), findsOneWidget);

      await tester.tap(find.text('iPhone nuovo a 100 €'));
      await tester.pumpAndSettle();
      expect(find.text('«Chiede un anticipo con bonifico»'), findsOneWidget);
      expect(find.text('@luca.r'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('segnalazione_elimina')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('segnalazione_conferma')));
      await tester.pumpAndSettle();
      expect(repo.calls, <String>['remove:r-annuncio']);
      expect(find.text('iPhone nuovo a 100 €'), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('segnalazioni_chiuse')));
      await tester.pumpAndSettle();
      expect(find.text('iPhone nuovo a 100 €'), findsOneWidget);
    });

    testWidgets('banna l\'autore di un commento per 30 giorni e toglie il commento', (WidgetTester tester) async {
      tall(tester);
      final FakeAdminRepository repo = withQueue();
      await openGestionale(tester, repo);
      await tester.tap(find.byKey(const ValueKey<String>('gestionale_segnalazioni')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guadagna 500 € al giorno, link in bio!'));
      await tester.pumpAndSettle();
      expect(find.text('Sotto l\'annuncio «Calcetto stasera?»'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('segnalazione_banna')));
      await tester.pumpAndSettle();
      final Finder send = find.byKey(const ValueKey<String>('moderazione_invia'));
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey<String>('modello_Spam')));
      await tester.tap(find.byKey(const ValueKey<String>('durata_30')));
      await tester.tap(find.byKey(const ValueKey<String>('moderazione_togli')));
      await tester.pumpAndSettle();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(repo.calls, <String>['ban:r-commento:togli:30', 'ban:u2:30']);
      expect(repo.users['u2']!.person.bannedAt(DateTime(2026, 12, 1)), isTrue);
      expect(find.text('Nessuna segnalazione da gestire.'), findsNothing);
    });

    testWidgets('chat: solo i messaggi scelti, niente «Elimina»', (WidgetTester tester) async {
      tall(tester);
      final FakeAdminRepository repo = withQueue();
      await openGestionale(tester, repo);
      await tester.tap(find.byKey(const ValueKey<String>('gestionale_segnalazioni')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat a due'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lasciami stare, grazie.'), findsOneWidget);
      expect(find.textContaining('Solo i messaggi scelti'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('segnalazione_elimina')), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('segnalazione_avvisa')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('moderazione_togli')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey<String>('moderazione_testo')), 'Rispetta chi ti dice no.');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('moderazione_invia')));
      await tester.pumpAndSettle();
      expect(repo.warnings, <(String, String)>[('u3', 'Rispetta chi ti dice no.')]);
    });
  });

  group('Utenti', () {
    testWidgets('cerca, banna, sblocca e vede lo storico', (WidgetTester tester) async {
      tall(tester);
      final FakeAdminRepository repo = withQueue();
      await openGestionale(tester, repo);
      await tester.tap(find.byKey(const ValueKey<String>('gestionale_utenti')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey<String>('utenti_cerca')), 'luca');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('utente_luca.r')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('utente_marco.b')), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('utente_luca.r')));
      await tester.pumpAndSettle();
      expect(find.text('Nessuna azione finora.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('utente_banna')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey<String>('moderazione_testo')), 'Annunci ingannevoli');
      await tester.tap(find.byKey(const ValueKey<String>('durata_definitivo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('moderazione_invia')));
      await tester.pumpAndSettle();
      expect(repo.calls, <String>['ban:u1:null']);
      expect(find.byKey(const ValueKey<String>('utente_stato_ban')), findsOneWidget);
      expect(find.text('Bannato definitivo'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('utente_sblocca')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('utente_sblocca_conferma')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'unban:u1');
      expect(find.byKey(const ValueKey<String>('utente_stato_ban')), findsNothing);
      expect(find.text('Sblocco'), findsOneWidget);
      expect(find.text('Ban definitivo'), findsOneWidget);
    });
  });

  group('Per la persona', () {
    testWidgets('account sospeso: schermata con motivo e scadenza', (WidgetTester tester) async {
      final FakeModerationRepository repo = FakeModerationRepository(
        ModerationState(bannedUntil: DateTime(2026, 12, 1, 10), banReason: 'Annunci ingannevoli'),
      );
      await tester.pumpWidget(app(ModerationGate(
        repository: repo,
        now: () => DateTime(2026, 11, 24),
        onSignOut: () async {},
        child: const Text('APP'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('APP'), findsNothing);
      expect(find.byKey(const ValueKey<String>('account_sospeso')), findsOneWidget);
      expect(find.text('Il tuo account è sospeso fino al 01/12/2026 10:00.'), findsOneWidget);
      expect(find.text('Motivo: Annunci ingannevoli'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('account_sospeso_esci')), findsOneWidget);
    });

    testWidgets('ban scaduto: si usa l\'app; avvisi mostrati una volta', (WidgetTester tester) async {
      final FakeModerationRepository repo = FakeModerationRepository(
        ModerationState(
          bannedUntil: DateTime(2026, 11, 20),
          notices: const <ModerationNotice>[
            ModerationNotice(id: 'n1', kind: 'warning', message: 'Usa titoli chiari, grazie.'),
          ],
        ),
      );
      await tester.pumpWidget(app(ModerationGate(
        repository: repo,
        now: () => DateTime(2026, 11, 24),
        child: const Text('APP'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('APP'), findsOneWidget);
      expect(find.text('Avviso del Team Piazly'), findsOneWidget);
      expect(find.text('Usa titoli chiari, grazie.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('avvisi_ok')));
      await tester.pumpAndSettle();
      expect(repo.reads, 1);
      expect(find.text('Usa titoli chiari, grazie.'), findsNothing);
    });

    testWidgets('nessun ban e nessun avviso: niente cambia', (WidgetTester tester) async {
      final FakeModerationRepository repo = FakeModerationRepository(const ModerationState());
      await tester.pumpWidget(app(ModerationGate(repository: repo, child: const Text('APP'))));
      await tester.pumpAndSettle();
      expect(find.text('APP'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.reads, 0);
    });
  });
}

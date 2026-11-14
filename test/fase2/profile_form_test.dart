import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/onboarding/registration_rules.dart';
import 'package:nexus_social/features/profile/profile_form_screen.dart';
import 'package:nexus_social/features/profile/profile_models.dart';
import 'package:nexus_social/features/profile/public_profile_screen.dart';

import '../support/fake_profile_repository.dart';

/// Profilo (Fase 2, Blocco 2): R2.3, R2.4, R2.10, P3, S4, S5.
void main() {
  late FakeProfileRepository repo;
  late int saved;

  setUp(() {
    repo = FakeProfileRepository();
    saved = 0;
  });

  Finder field(String key) => find.byKey(ValueKey<String>(key));

  Future<void> pumpForm(
    WidgetTester tester, {
    MyProfile? initial,
    RegistrationDraft? draft,
    PickImage? pick,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileFormScreen(
          repository: repo,
          initial: initial,
          draft: draft,
          onSaved: () => saved++,
          pickImage: pick ?? () async => null,
          today: () => DateTime(2026, 11, 14),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(field(key));
    await tester.enterText(field(key), text);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(field('salva_profilo'));
    await tester.tap(field('salva_profilo'));
    await tester.pumpAndSettle();
  }

  final RegistrationDraft privateDraft = RegistrationDraft(
    kind: AccountKind.private,
    birthDate: DateTime(1990, 5, 1),
    termsAcceptedAt: DateTime(2026, 11, 14),
  );

  testWidgets('R2.3 · creazione: @username normalizzato, data dalla registrazione', (tester) async {
    await pumpForm(tester, draft: privateDraft);
    expect(find.text('Completa il profilo'), findsOneWidget);
    expect(field('nascita'), findsNothing);
    expect(field('partita_iva'), findsNothing);

    await type(tester, 'username', 'Carlo.Rossi');
    await type(tester, 'nome', 'Carlo Rossi');
    expect(find.text('In pubblico vedranno solo «Carlo R.»'), findsOneWidget);
    await save(tester);

    expect(repo.created?.username, 'carlo.rossi');
    expect(repo.created?.fullName, 'Carlo Rossi');
    expect(repo.created?.birthDate, DateTime(1990, 5, 1));
    expect(repo.created?.isBusiness, isFalse);
    expect(repo.calls, <String>['isUsernameAvailable:carlo.rossi', 'create', 'update']);
    expect(saved, 1);
    expect(RegistrationDraftStore.current, isNull);
  });

  testWidgets('R2.3 · nome utente non valido, riservato o già preso: niente salvataggio', (tester) async {
    await pumpForm(tester, draft: privateDraft);
    await type(tester, 'nome', 'Carlo Rossi');

    await type(tester, 'username', 'ab');
    await save(tester);
    expect(find.textContaining('Da 3 a 24 caratteri'), findsOneWidget);

    await type(tester, 'username', 'piazly_staff');
    await save(tester);
    expect(find.text('Questo nome utente non è disponibile.'), findsOneWidget);

    await type(tester, 'username', 'gia_preso');
    await save(tester);
    expect(find.text('Questo nome utente è già preso: scegline un altro.'), findsOneWidget);

    expect(repo.created, isNull);
    expect(saved, 0);
  });

  testWidgets('R2.4 · P3 · bio, social e interruttori arrivano al server', (tester) async {
    await pumpForm(tester, draft: privateDraft);
    await type(tester, 'username', 'laura_b');
    await type(tester, 'nome', 'Laura Bianchi');
    await type(tester, 'bio', 'Amo i mercatini');
    await type(tester, 'social_instagram', '@laura.b');
    await tester.ensureVisible(field('mostra_bio'));
    await tester.tap(field('mostra_bio'));
    await tester.pump();
    await save(tester);

    expect(repo.updated?.bio, 'Amo i mercatini');
    expect(repo.updated?.social, <SocialNetwork, String>{SocialNetwork.instagram: 'laura.b'});
    expect(repo.updated?.showBio, isFalse);
    expect(repo.updated?.showSocial, isTrue);
  });

  testWidgets('R2.4 · un link al posto del nome utente social viene rifiutato', (tester) async {
    await pumpForm(tester, draft: privateDraft);
    await type(tester, 'username', 'laura_b');
    await type(tester, 'nome', 'Laura Bianchi');
    await type(tester, 'social_tiktok', 'https://example.com/x');
    await save(tester);
    expect(find.text('Scrivi solo il nome utente, senza link.'), findsOneWidget);
    expect(repo.created, isNull);
  });

  testWidgets('S4 · Azienda: ragione sociale e partita IVA controllata', (tester) async {
    await pumpForm(
      tester,
      draft: RegistrationDraft(
        kind: AccountKind.business,
        birthDate: DateTime(1980, 3, 3),
        termsAcceptedAt: DateTime(2026, 11, 14),
      ),
    );
    await type(tester, 'username', 'bottega_verdi');
    await type(tester, 'nome', 'Paolo Verdi');
    await type(tester, 'ragione_sociale', 'Bottega Verdi Srl');
    await type(tester, 'partita_iva', '01234567890');
    await save(tester);
    expect(find.text('Partita IVA non valida (11 cifre).'), findsOneWidget);
    expect(repo.created, isNull);

    await type(tester, 'partita_iva', '01234567897');
    await save(tester);
    expect(repo.created?.isBusiness, isTrue);
    expect(repo.created?.businessName, 'Bottega Verdi Srl');
    expect(repo.created?.vatNumber, '01234567897');
  });

  testWidgets('M2 · senza dati in memoria (app riaperta): data di nascita richiesta di nuovo', (tester) async {
    await pumpForm(tester);
    expect(field('nascita'), findsOneWidget);
    await type(tester, 'nascita', '01/01/2015');
    await type(tester, 'username', 'troppo_giovane');
    await type(tester, 'nome', 'Mario Bianchi');
    await save(tester);
    expect(find.text('Per usare Piazly devi avere almeno 14 anni.'), findsOneWidget);
    expect(repo.created, isNull);

    await type(tester, 'nascita', '01/01/1999');
    await save(tester);
    expect(repo.created?.birthDate, DateTime(1999, 1, 1));
  });

  testWidgets('S5 · foto scelta dalla galleria: caricata dopo il salvataggio', (tester) async {
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
    await pumpForm(tester, draft: privateDraft, pick: () async => bytes);
    await tester.tap(field('scegli_foto'));
    await tester.pumpAndSettle();
    expect(find.text('Cambia foto'), findsOneWidget);
    await type(tester, 'username', 'con_foto');
    await type(tester, 'nome', 'Anna Neri');
    await save(tester);
    expect(repo.avatarBytes, bytes);
    expect(repo.calls.last, 'setAvatar');
  });

  testWidgets('modifica: data di nascita e partita IVA non modificabili', (tester) async {
    final MyProfile me = MyProfile(
      id: 'utenteProva',
      isBusiness: true,
      username: 'bottega_verdi',
      publicName: 'Paolo V.',
      fullName: 'Paolo Verdi',
      businessName: 'Bottega Verdi Srl',
      vatNumber: '01234567897',
      businessStatus: BusinessStatus.pending,
    );
    repo.mine = me;
    await pumpForm(tester, initial: me);
    expect(find.text('Modifica profilo'), findsOneWidget);
    expect(field('nascita'), findsNothing);
    expect(tester.widget<TextField>(field('partita_iva')).enabled, isFalse);
    expect(find.text('Azienda in verifica'), findsOneWidget);
    await type(tester, 'bio', 'Prodotti a km zero');
    await save(tester);
    expect(repo.calls, <String>['update']);
    expect(repo.updated?.bio, 'Prodotti a km zero');
  });

  testWidgets('R2.10 · profilo pubblico: niente nome completo, bio nascosta se spenta', (tester) async {
    const MyProfile me = MyProfile(
      id: 'u1',
      isBusiness: false,
      username: 'laura_b',
      publicName: 'Laura B.',
      fullName: 'Laura Bianchi',
      bio: 'Bio privata',
      social: <SocialNetwork, String>{SocialNetwork.instagram: 'laura.b'},
      showBio: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PublicProfileScreen(profile: me.asSeenByOthers()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Laura B.'), findsOneWidget);
    expect(find.text('@laura_b'), findsOneWidget);
    expect(find.text('Instagram · @laura.b'), findsOneWidget);
    expect(find.textContaining('Bianchi'), findsNothing);
    expect(find.text('Bio privata'), findsNothing);
  });

  testWidgets('R2.4 · toccando un social si apre il profilo su quel social', (tester) async {
    final List<Uri> opened = <Uri>[];
    const PublicProfile other = PublicProfile(
      id: 'u2',
      isBusiness: false,
      username: 'laura_b',
      publicName: 'Laura B.',
      social: <SocialNetwork, String>{
        SocialNetwork.instagram: 'laura.b',
        SocialNetwork.tiktok: 'laurab',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PublicProfileScreen(
          profile: other,
          openLink: (Uri uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('apri_instagram')));
    await tester.tap(find.byKey(const ValueKey<String>('apri_tiktok')));
    await tester.pumpAndSettle();
    expect(opened, <Uri>[
      Uri.parse('https://instagram.com/laura.b'),
      Uri.parse('https://www.tiktok.com/@laurab'),
    ]);
  });

  testWidgets('R2.4 · social non apribile: messaggio chiaro', (tester) async {
    const PublicProfile other = PublicProfile(
      id: 'u2',
      isBusiness: false,
      username: 'laura_b',
      publicName: 'Laura B.',
      social: <SocialNetwork, String>{SocialNetwork.x: 'laurab'},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PublicProfileScreen(profile: other, openLink: (Uri uri) async => false),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('apri_x')));
    await tester.pumpAndSettle();
    expect(find.text('Non è stato possibile aprire X.'), findsOneWidget);
  });
}

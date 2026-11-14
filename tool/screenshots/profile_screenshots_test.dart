// Anteprime per il titolare (Fase 2, Blocco 2): immagini delle nuove schermate,
// disegnate con dati inventati e senza nessun servizio reale.
//
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/onboarding/registration_rules.dart';
import 'package:nexus_social/features/profile/profile_form_screen.dart';
import 'package:nexus_social/features/profile/profile_models.dart';
import 'package:nexus_social/features/profile/public_profile_screen.dart';
import 'package:nexus_social/features/shell/app_shell.dart';

import '../../test/support/fake_profile_repository.dart';

Future<void> _loadFonts() async {
  final String root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final Directory dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final FontLoader roboto = FontLoader('Roboto');
  final FontLoader icons = FontLoader('MaterialIcons');
  for (final FileSystemEntity f in dir.listSync()) {
    final String name = f.uri.pathSegments.last;
    final Future<ByteData> data =
        File(f.path).readAsBytes().then((Uint8List b) => ByteData.view(b.buffer));
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) roboto.addFont(data);
    if (name.startsWith('MaterialIcons-Regular')) icons.addFont(data);
  }
  await roboto.load();
  await icons.load();
}

/// Foto di esempio: un ritratto stilizzato generato al momento (nessuna persona reale).
Uint8List _samplePhoto() {
  final img.Image p = img.Image(width: 512, height: 512);
  for (int y = 0; y < 512; y++) {
    for (int x = 0; x < 512; x++) {
      final double t = (x + y) / 1024;
      p.setPixelRgb(x, y, (47 + 208 * t).round(), 123, (255 - 229 * t).round());
    }
  }
  img.fillCircle(p, x: 256, y: 200, radius: 92, color: img.ColorRgb8(255, 236, 214));
  img.fillCircle(p, x: 256, y: 520, radius: 210, color: img.ColorRgb8(255, 236, 214));
  return img.encodePng(p);
}

class _PhotoRepo extends FakeProfileRepository {
  _PhotoRepo({super.mine});

  final Uint8List photo = _samplePhoto();

  @override
  Future<Uint8List?> downloadAvatar(String path) async => photo;
}

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester tester, String name, Widget home,
      {ThemeData? theme, Future<void> Function()? before}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.light,
      home: home,
    ));
    await tester.pumpAndSettle();
    if (before != null) await before();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
  }

  const MyProfile laura = MyProfile(
    id: 'demo',
    isBusiness: false,
    username: 'laura_b',
    publicName: 'Laura B.',
    fullName: 'Laura Bianchi',
    avatarPath: 'demo/avatar-esempio0001.jpg',
    avatarThumbPath: 'demo/thumb-esempio0001.jpg',
    bio: 'Amo i mercatini dell\'usato e il caffè al bar sotto casa ☕',
    social: <SocialNetwork, String>{
      SocialNetwork.instagram: 'laura.b',
      SocialNetwork.tiktok: 'laurab',
    },
  );

  testWidgets('1 · completa il profilo (Privato)', (tester) async {
    final _PhotoRepo repo = _PhotoRepo();
    await shoot(
      tester,
      '1_completa_profilo',
      ProfileFormScreen(
        repository: repo,
        draft: RegistrationDraft(
          kind: AccountKind.private,
          birthDate: DateTime(1990, 5, 1),
          termsAcceptedAt: DateTime(2026, 11, 14),
        ),
        onSaved: () {},
        pickImage: () async => repo.photo,
      ),
      before: () async {
        await tester.tap(find.byKey(const ValueKey<String>('scegli_foto')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey<String>('username')), 'laura_b');
        await tester.enterText(find.byKey(const ValueKey<String>('nome')), 'Laura Bianchi');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('2 · completa il profilo (Azienda), parte bassa', (tester) async {
    final _PhotoRepo repo = _PhotoRepo();
    await shoot(
      tester,
      '2_profilo_azienda',
      ProfileFormScreen(
        repository: repo,
        draft: RegistrationDraft(
          kind: AccountKind.business,
          birthDate: DateTime(1980, 3, 3),
          termsAcceptedAt: DateTime(2026, 11, 14),
        ),
        onSaved: () {},
      ),
      before: () async {
        await tester.enterText(find.byKey(const ValueKey<String>('username')), 'bottega_verdi');
        await tester.enterText(find.byKey(const ValueKey<String>('nome')), 'Paolo Verdi');
        await tester.enterText(
            find.byKey(const ValueKey<String>('ragione_sociale')), 'Bottega Verdi Srl');
        await tester.enterText(find.byKey(const ValueKey<String>('partita_iva')), '0123456789');
        await tester.enterText(find.byKey(const ValueKey<String>('social_instagram')), 'bottega');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.tap(find.byKey(const ValueKey<String>('salva_profilo')),
            warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey<String>('partita_iva')));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('3 · sezione Profilo con il profilo completo', (tester) async {
    final _PhotoRepo repo = _PhotoRepo(mine: laura);
    await shoot(
      tester,
      '3_sezione_profilo',
      AppShell(onSignOut: () async {}, profile: laura, profiles: repo),
      before: () async {
        await tester.tap(find.descendant(
            of: find.byType(NavigationBar), matching: find.text('Profilo')));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('4 · come ti vedono gli altri', (tester) async {
    final _PhotoRepo repo = _PhotoRepo(mine: laura);
    await shoot(tester, '4_profilo_pubblico',
        PublicProfileScreen(profile: laura.asSeenByOthers(), repository: repo));
  });

  testWidgets('5 · modifica profilo, tema scuro', (tester) async {
    final _PhotoRepo repo = _PhotoRepo(mine: laura);
    await shoot(
      tester,
      '5_modifica_scuro',
      ProfileFormScreen(repository: repo, initial: laura, onSaved: () {}),
      theme: AppTheme.dark,
    );
  });
}

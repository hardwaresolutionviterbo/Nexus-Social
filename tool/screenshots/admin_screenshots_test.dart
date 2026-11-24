// Anteprime per il titolare (Fase 7, Blocco 1): gestionale con dati inventati, nessun servizio reale.
//
// Non fa parte dei test di regressione: lo esegue solo il workflow «Anteprime schermate».
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/admin/admin_models.dart';
import 'package:nexus_social/features/admin/admin_reports.dart';
import 'package:nexus_social/features/admin/admin_screen.dart';
import 'package:nexus_social/features/admin/admin_users.dart';
import 'package:nexus_social/features/admin/moderation_gate.dart';

import '../../test/support/fake_admin.dart';

Future<void> _loadFonts() async {
  final String root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final Directory dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final FontLoader roboto = FontLoader('Roboto');
  final FontLoader fallback = FontLoader('FlutterTest');
  final FontLoader ahem = FontLoader('Ahem');
  final FontLoader icons = FontLoader('MaterialIcons');
  for (final FileSystemEntity f in dir.listSync()) {
    final String name = f.uri.pathSegments.last;
    final Future<ByteData> data =
        File(f.path).readAsBytes().then((Uint8List b) => ByteData.view(b.buffer));
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) {
      roboto.addFont(data);
      fallback.addFont(data);
      ahem.addFont(data);
    }
    if (name.startsWith('MaterialIcons-Regular')) icons.addFont(data);
  }
  // Emoji a colori (installate dal workflow delle anteprime, se disponibili).
  final File emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emoji.existsSync()) {
    final FontLoader e = FontLoader('NotoColorEmoji')
      ..addFont(emoji.readAsBytes().then((Uint8List b) => ByteData.view(b.buffer)));
    await e.load();
  }
  await roboto.load();
  await fallback.load();
  await ahem.load();
  await icons.load();
}

ThemeData _withRoboto(ThemeData base) => _withRobotoOnly(
  base.copyWith(textTheme: base.textTheme.apply(fontFamilyFallback: const <String>['NotoColorEmoji'])),
);

ThemeData _withRobotoOnly(ThemeData t) => t.copyWith(
  filledButtonTheme: FilledButtonThemeData(
    style: t.filledButtonTheme.style?.copyWith(
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w800),
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: (t.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700),
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      textStyle: const TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700),
    ),
  ),
  chipTheme: t.chipTheme.copyWith(
    labelStyle: (t.chipTheme.labelStyle ?? const TextStyle()).copyWith(fontFamily: 'Roboto'),
  ),
  listTileTheme: t.listTileTheme.copyWith(
    titleTextStyle: (t.listTileTheme.titleTextStyle ?? t.textTheme.bodyLarge)
        ?.copyWith(fontFamily: 'Roboto'),
    subtitleTextStyle: (t.listTileTheme.subtitleTextStyle ?? t.textTheme.bodyMedium)
        ?.copyWith(fontFamily: 'Roboto'),
  ),
);

FakeAdminRepository seeded() {
  final FakeAdminRepository repo = FakeAdminRepository();
  repo.open.addAll(<AdminReport>[sampleListingReport(), sampleCommentReport(), sampleChatReport()]);
  repo.addUser(samplePerson(), reportsOpen: 1);
  repo.addUser(samplePerson(id: 'u2', username: 'promo.facile', name: 'Promo F.'));
  repo.addUser(samplePerson(id: 'u3', username: 'marco.b', name: 'Marco B.'));
  return repo;
}

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester tester, String name, Widget home,
      {Future<void> Function()? before}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // Nei test le ombre diventano bordi neri: qui si disegnano come sul telefono.
    debugDisableShadows = false;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _withRoboto(AppTheme.light),
      home: home,
    ));
    await tester.pumpAndSettle();
    if (before != null) await before();
    await tester.pumpAndSettle();
    // Le foto si decodificano solo fuori dal tempo finto dei test.
    await tester.runAsync(() async {
      for (final Element e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();
    try {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('gestionale 1 · pagina principale', (tester) async {
    await shoot(tester, 'gestionale_1_home', AdminHomeScreen(repository: seeded()));
  });

  testWidgets('gestionale 2 · coda delle segnalazioni', (tester) async {
    await shoot(tester, 'gestionale_2_segnalazioni', ReportsScreen(repository: seeded()));
  });

  testWidgets('gestionale 3 · annuncio segnalato', (tester) async {
    await shoot(tester, 'gestionale_3_annuncio',
        ReportDetailScreen(repository: seeded(), report: sampleListingReport()));
  });

  testWidgets('gestionale 4 · chat segnalata', (tester) async {
    await shoot(tester, 'gestionale_4_chat', ReportDetailScreen(repository: seeded(), report: sampleChatReport()));
  });

  testWidgets('gestionale 5 · ban con motivo e durata', (tester) async {
    await shoot(tester, 'gestionale_5_ban', ReportDetailScreen(repository: seeded(), report: sampleCommentReport()),
        before: () async {
      await tester.tap(find.byKey(const ValueKey<String>('segnalazione_banna')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('modello_Spam')));
      await tester.tap(find.byKey(const ValueKey<String>('moderazione_togli')));
    });
  });

  testWidgets('gestionale 6 · scheda utente con storico', (tester) async {
    final FakeAdminRepository repo = seeded();
    await repo.warn('u1', 'Usa titoli chiari, grazie.');
    await repo.ban('u1', BanLength.week, 'Annunci ingannevoli');
    await shoot(tester, 'gestionale_6_utente', UserDetailScreen(repository: repo, userId: 'u1'));
  });

  testWidgets('gestionale 7 · accesso senza PIN', (tester) async {
    await shoot(tester, 'gestionale_7_senza_pin',
        AdminScreen(repository: FakeAdminRepository(accessState: const AdminAccess(admin: true))));
  });

  testWidgets('gestionale 8 · account sospeso (per la persona)', (tester) async {
    await shoot(tester, 'gestionale_8_sospeso', BannedScreen(
      until: DateTime(2026, 12, 1, 10),
      reason: 'Annunci ingannevoli ripetuti dopo un avviso.',
      onSignOut: () async {},
      onRetry: () async {},
    ));
  });
}

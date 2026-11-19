// Fase 4 · Blocco 5: preferenze delle notifiche (Profilo → Notifiche).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_social/core/theme/app_theme.dart';
import 'package:nexus_social/features/notifications/notification_settings.dart';

class FakePushSettings implements PushSettingsRepository {
  FakePushSettings({this.failSave = false});

  PushSettings stored = const PushSettings();
  bool failSave;
  int saves = 0;

  @override
  Future<PushSettings> load() async => stored;

  @override
  Future<void> save(PushSettings settings) async {
    saves++;
    if (failSave) throw Exception('rete');
    stored = settings;
  }
}

Widget app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void main() {
  test('preferenze lette dal server, con valori di partenza', () {
    final PushSettings s = PushSettings.fromRow(<String, dynamic>{
      'messages': true,
      'comments': false,
      'market': true,
      'preview': false,
      'dnd_enabled': true,
      'dnd_from': '23:30:00',
      'dnd_to': '06:45:00',
      'time_zone': 'Europe/Rome',
    });
    expect(s.comments, isFalse);
    expect(s.preview, isFalse);
    expect(s.dndEnabled, isTrue);
    expect(PushSettings.hhmm(s.dndFrom), '23:30');
    expect(PushSettings.hhmm(s.dndTo), '06:45');
    final PushSettings d = PushSettings.fromRow(<String, dynamic>{});
    expect(d.messages && d.comments && d.market && d.preview, isTrue);
    expect(d.dndEnabled, isFalse);
    expect(PushSettings.hhmm(d.dndFrom), '22:00');
  });

  testWidgets('interruttori salvati subito; Non disturbare mostra gli orari', (WidgetTester tester) async {
    final FakePushSettings repo = FakePushSettings();
    await tester.pumpWidget(app(NotificationSettingsScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.textContaining('non contengono mai il testo'), findsOneWidget);
    expect(find.text('«Anna R. · Nuovo messaggio»'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('notifiche_commenti')));
    await tester.pumpAndSettle();
    expect(repo.stored.comments, isFalse);

    await tester.tap(find.byKey(const ValueKey<String>('notifiche_anteprima')));
    await tester.pumpAndSettle();
    expect(repo.stored.preview, isFalse);
    expect(find.text('«Piazly · Hai un nuovo messaggio»'), findsOneWidget);

    expect(find.byKey(const ValueKey<String>('non_disturbare_dalle')), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('notifiche_non_disturbare')));
    await tester.pumpAndSettle();
    expect(repo.stored.dndEnabled, isTrue);
    expect(find.text('Dalle 22:00'), findsOneWidget);
    expect(find.text('Alle 07:00'), findsOneWidget);
    expect(repo.saves, 3);
  });

  testWidgets('messaggi spenti: l\'anteprima non si può cambiare', (WidgetTester tester) async {
    final FakePushSettings repo = FakePushSettings();
    await tester.pumpWidget(app(NotificationSettingsScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('notifiche_messaggi')));
    await tester.pumpAndSettle();
    expect(repo.stored.messages, isFalse);
    final SwitchListTile preview = tester.widget(find.byKey(const ValueKey<String>('notifiche_anteprima')));
    expect(preview.onChanged, isNull);
  });

  testWidgets('salvataggio non riuscito: torna com\'era e lo dice', (WidgetTester tester) async {
    final FakePushSettings repo = FakePushSettings(failSave: true);
    await tester.pumpWidget(app(NotificationSettingsScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('notifiche_scambi')));
    await tester.pumpAndSettle();
    expect(find.text('Non salvato. Riprova.'), findsOneWidget);
    final SwitchListTile market = tester.widget(find.byKey(const ValueKey<String>('notifiche_scambi')));
    expect(market.value, isTrue);
    await tester.pump(const Duration(seconds: 5));
  });
}

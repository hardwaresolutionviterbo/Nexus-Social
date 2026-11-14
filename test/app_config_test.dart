import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/core/config/app_config.dart';

void main() {
  test('Supabase risulta pronto solo con URL e chiave', () {
    expect(
      AppConfig.hasSupabase,
      AppConfig.supabaseUrl.isNotEmpty && AppConfig.supabaseKey.isNotEmpty,
    );
  });

  test('senza dart-define i servizi restano spenti', () {
    if (AppConfig.supabaseUrl.isEmpty) {
      expect(AppConfig.hasSupabase, isFalse);
    }
    expect(AppConfig.hasFirebase, AppConfig.firebaseEnabled);
  });

  test('le costanti descrivono la Fase 1', () {
    expect(AppInfo.name, 'VoxLine');
    expect(AppInfo.phase, 1);
    expect(AppInfo.version, isNotEmpty);
  });
}

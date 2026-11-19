import 'package:nexus_social/features/contacts/contacts_sync.dart';
import 'package:nexus_social/features/privacy/privacy_repository.dart';

import 'fake_privacy_repository.dart';

/// Rubrica simulata (regola F8): nessun contatto reale, nessun server.
class FakeContactsRepository implements ContactsRepository {
  FakeContactsRepository(this.privacy);

  final FakePrivacyRepository privacy;
  final List<String> calls = <String>[];
  List<RecognizedContact> found = <RecognizedContact>[
    const RecognizedContact(id: 'u2', username: 'laura_b', publicName: 'Laura B.',
        phone: '+393000000002'),
    const RecognizedContact(id: 'u3', username: 'marco_t', publicName: 'Marco T.'),
  ];
  List<RecognizedContact> current = <RecognizedContact>[];
  int autoChecks = 0;
  final List<void Function()> listeners = <void Function()>[];

  /// Simula il salvataggio di un nuovo contatto nella rubrica del telefono.
  void simulateContactsChange() {
    for (final void Function() l in List<void Function()>.of(listeners)) {
      l();
    }
  }

  @override
  Future<bool> autoSyncIfNeeded() async {
    autoChecks++;
    return false;
  }

  @override
  void watchContacts(void Function() onChange) => listeners.add(onChange);

  @override
  void unwatchContacts(void Function() onChange) => listeners.remove(onChange);

  void _update({required bool enabled, DateTime? synced}) {
    final PrivacySettings s = privacy.settings;
    privacy.settings = PrivacySettings(
      phoneVisibility: s.phoneVisibility,
      discoverable: enabled || s.discoverable,
      showBio: s.showBio,
      showSocial: s.showSocial,
      contactsEnabled: enabled,
      contactsConsentAt: enabled ? DateTime(2026, 11, 14) : null,
      contactsSyncedAt: synced,
      contactsExpireAt: synced?.add(ContactsLimits.expiry),
      contactsCount: current.length,
    );
  }

  @override
  Future<void> enable() async {
    calls.add('enable');
    _update(enabled: true);
  }

  @override
  Future<List<RecognizedContact>> sync({void Function(double)? onProgress}) async {
    calls.add('sync');
    onProgress?.call(0.5);
    current = List<RecognizedContact>.of(found);
    _update(enabled: true, synced: DateTime(2026, 11, 14));
    onProgress?.call(1);
    return current;
  }

  @override
  Future<List<RecognizedContact>> contacts() async => current;

  /// Nomi della rubrica del telefono simulata.
  Map<String, String> names = <String, String>{};

  @override
  Future<Map<String, String>> localNames() async => names;

  @override
  Future<void> setDiscoverable(bool value) async {
    calls.add('setDiscoverable:$value');
    final PrivacySettings s = privacy.settings;
    privacy.settings = PrivacySettings(
      phoneVisibility: s.phoneVisibility,
      discoverable: value,
      showBio: s.showBio,
      showSocial: s.showSocial,
      contactsEnabled: s.contactsEnabled,
      contactsConsentAt: s.contactsConsentAt,
      contactsSyncedAt: s.contactsSyncedAt,
      contactsExpireAt: s.contactsExpireAt,
      contactsCount: s.contactsCount,
    );
  }

  @override
  Future<void> revoke() async {
    calls.add('revoke');
    current = <RecognizedContact>[];
    _update(enabled: false);
  }
}

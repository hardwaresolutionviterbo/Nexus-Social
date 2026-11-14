import 'package:material_ui/material_ui.dart';

import '../contacts/contacts_sync.dart';
import '../profile/profile_repository.dart' show ProfileFailure;
import 'privacy_repository.dart';

/// Stato condiviso da pagina Privacy e Controllo privacy.
///
/// Ogni scelta si salva subito sul server (P15); se il salvataggio non riesce, la scelta
/// torna com'era e compare un messaggio.
class PrivacyController extends ChangeNotifier {
  PrivacyController(this.repository, {this.contactsRepository});

  final PrivacyRepository repository;

  /// Rubrica (Blocco 5): presente quando il server è collegato.
  final ContactsRepository? contactsRepository;
  List<RecognizedContact> contacts = const <RecognizedContact>[];

  /// Avanzamento della sincronizzazione (0-1), null se ferma.
  double? syncProgress;

  PrivacySettings settings = const PrivacySettings();
  List<BlockedUser> blocked = const <BlockedUser>[];
  bool loading = true;
  bool saving = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      settings = await repository.fetch();
      blocked = await repository.blockedUsers();
      final ContactsRepository? c = contactsRepository;
      if (c != null && settings.contactsEnabled) contacts = await c.contacts();
    } on ProfileFailure catch (f) {
      error = f.message;
    } catch (_) {
      error = 'Impostazioni non caricate. Riprova.';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _save(PrivacySettings next, Future<void> Function() call) async {
    final PrivacySettings before = settings;
    settings = next;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await call();
    } on ProfileFailure catch (f) {
      settings = before;
      error = f.message;
    } catch (_) {
      settings = before;
      error = 'Scelta non salvata. Riprova.';
    }
    saving = false;
    notifyListeners();
  }

  Future<void> setPhoneVisibility(PhoneVisibility value) => _save(
    settings.copyWith(phoneVisibility: value),
    () => repository.setPhoneVisibility(value),
  );

  Future<void> setShowBio(bool value) => _save(
    settings.copyWith(showBio: value),
    () => repository.setProfileVisibility(showBio: value, showSocial: settings.showSocial),
  );

  Future<void> setShowSocial(bool value) => _save(
    settings.copyWith(showSocial: value),
    () => repository.setProfileVisibility(showBio: settings.showBio, showSocial: value),
  );

  Future<void> _contactsAction(Future<void> Function(ContactsRepository repo) action) async {
    final ContactsRepository? repo = contactsRepository;
    if (repo == null) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await action(repo);
      settings = await repository.fetch();
      contacts = settings.contactsEnabled ? await repo.contacts() : const <RecognizedContact>[];
    } on ProfileFailure catch (f) {
      error = f.message;
    } catch (_) {
      error = 'Operazione non riuscita. Riprova.';
    }
    saving = false;
    syncProgress = null;
    notifyListeners();
  }

  Future<void> _sync(ContactsRepository repo) async {
    syncProgress = 0;
    notifyListeners();
    await repo.sync(
      onProgress: (double p) {
        syncProgress = p;
        notifyListeners();
      },
    );
  }

  /// Consenso dato: registra il consenso e fa la prima sincronizzazione.
  Future<void> enableContacts() => _contactsAction((ContactsRepository repo) async {
    await repo.enable();
    await _sync(repo);
  });

  Future<void> syncContacts() => _contactsAction(_sync);

  Future<void> setDiscoverable(bool value) =>
      _contactsAction((ContactsRepository repo) => repo.setDiscoverable(value));

  Future<void> revokeContacts() => _contactsAction((ContactsRepository repo) => repo.revoke());

  Future<void> unblock(BlockedUser user) async {
    final List<BlockedUser> before = blocked;
    blocked = <BlockedUser>[for (final BlockedUser b in blocked) if (b.id != user.id) b];
    await _save(
      settings.copyWith(blockedCount: blocked.length),
      () => repository.unblock(user.id),
    );
    if (error != null) {
      blocked = before;
      notifyListeners();
    }
  }
}

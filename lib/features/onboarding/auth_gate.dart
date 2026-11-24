import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/services/auth_gateway.dart';
import '../../core/services/backend_bootstrap.dart';
import '../../core/widgets/nexus_ui.dart';
import '../admin/admin_repository.dart';
import '../admin/moderation_gate.dart';
import '../chat/chat_service.dart';
import '../contacts/contacts_auto_sync.dart';
import '../contacts/contacts_sync.dart';
import '../map/listing_repository.dart';
import '../map/map_screen.dart';
import '../map/social_repository.dart';
import '../market/market_repository.dart';
import '../notifications/notification_settings.dart';
import '../privacy/privacy_checkup_screen.dart';
import '../privacy/privacy_controller.dart';
import '../privacy/privacy_repository.dart';
import '../profile/profile_form_screen.dart';
import '../security/app_lock.dart';
import '../security/security_repository.dart';
import '../security/security_screens.dart';
import '../profile/profile_models.dart';
import '../profile/profile_repository.dart';
import '../shell/app_shell.dart';
import 'onboarding_flow.dart';
import 'registration_rules.dart';

/// Controllo d'accesso (Fase 2, Blocco 1).
///
/// - Nessun utente: registrazione e accesso ([OnboardingFlow]).
/// - Utente appena entrato o all'apertura dell'app: ruolo `authenticated` e verifica che
///   Supabase lo riconosca ([AuthGateway.ensureLinked]).
/// - Con il server collegato ([profiles] presente, Blocco 2): se il profilo non esiste
///   ancora si completa ([ProfileFormScreen]); poi l'app.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.gateway,
    this.backend = const BackendStatus.unconfigured(),
    this.today,
    this.profiles,
    this.pickImage = pickFromGallery,
    this.privacy,
    this.pushSettings,
    this.security,
    this.biometricLock,
    this.contacts,
    this.map,
    this.listings,
    this.social,
    this.market,
    this.chat,
    this.isAdmin,
  });

  /// Vero solo per gli amministratori di Piazly: vedono lo stato dei servizi e la diagnostica.
  final Future<bool> Function()? isAdmin;


  final AuthGateway gateway;

  /// Profilo su Supabase: null finché il collegamento al server è in pausa (S1).
  final ProfileRepository? profiles;
  final PickImage pickImage;

  /// Impostazioni privacy (Blocco 3): con il server collegato.
  final PrivacyRepository? privacy;

  /// Preferenze delle notifiche (Fase 4, Blocco 5).
  final PushSettingsRepository? pushSettings;

  /// Verifica in due passaggi (Blocco 4): con il server collegato.
  final SecurityRepository? security;

  /// Sblocco con impronta o volto (Blocco 4), solo sul telefono.
  final BiometricLock? biometricLock;

  /// Rubrica (Blocco 5): con il server collegato.
  final ContactsRepository? contacts;
  final MapServices? map;
  final MapListingRepository? listings;
  final SocialRepository? social;
  final MarketRepository? market;

  /// Chat cifrata (Fase 4): una per account, creata quando il profilo è pronto.
  final ChatService Function(String uid)? chat;
  final BackendStatus backend;
  final DateTime Function()? today;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _Link { checking, linked, failed }

enum _Profile { loading, needsPin, missing, ready, failed }

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<String?>? _subscription;
  String? _uid;
  _Link _link = _Link.checking;
  String? _failure;
  _Profile _profileState = _Profile.loading;
  MyProfile? _profile;

  /// Controllo privacy proposto alla fine della registrazione (P14).
  PrivacyController? _checkup;
  SecurityStatus? _securityStatus;

  /// Chat dell'account collegato; si chiude all'uscita o al cambio di account.
  ChatService? _chat;
  String? _chatUid;

  ChatService? _chatFor(String uid) {
    final ChatService Function(String uid)? make = widget.chat;
    if (make == null) return null;
    if (_chatUid != uid) {
      _chat?.dispose();
      _chat = make(uid);
      _chatUid = uid;
    }
    return _chat;
  }

  void _closeChat() {
    _chat?.dispose();
    _chat = null;
    _chatUid = null;
  }

  @override
  void initState() {
    super.initState();
    _uid = widget.gateway.currentUid;
    if (_uid != null) unawaited(_ensureLinked());
    _subscription = widget.gateway.uidChanges().listen((String? uid) {
      if (!mounted || uid == _uid) return;
      setState(() {
        _uid = uid;
        _link = _Link.checking;
        _failure = null;
        _profile = null;
        _profileState = _Profile.loading;
      });
      if (uid != null) {
        unawaited(_ensureLinked());
      } else {
        RegistrationDraftStore.current = null;
      }
    });
  }

  void _profileCreated() {
    final PrivacyRepository? privacy = widget.privacy;
    if (privacy != null) {
      _checkup = PrivacyController(privacy, contactsRepository: widget.contacts)..load();
    }
    _loadProfile();
  }

  void _closeCheckup() {
    final PrivacyController? c = _checkup;
    setState(() => _checkup = null);
    c?.dispose();
  }

  @override
  void dispose() {
    _checkup?.dispose();
    _closeChat();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _ensureLinked() async {
    // In initState lo stato è già «checking»: niente setState prima del primo disegno.
    if (_link != _Link.checking || _failure != null) {
      setState(() {
        _link = _Link.checking;
        _failure = null;
      });
    }
    try {
      await widget.gateway.ensureLinked();
      if (mounted) setState(() => _link = _Link.linked);
      await _loadProfile();
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _link = _Link.failed;
          _failure = failure.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _link = _Link.failed;
          _failure = 'Qualcosa non ha funzionato. Riprova.';
        });
      }
    }
  }

  Future<void> _loadProfile() async {
    final ProfileRepository? repo = widget.profiles;
    if (repo == null) return;
    if (_profileState != _Profile.loading) {
      setState(() {
        _profileState = _Profile.loading;
        _failure = null;
      });
    }
    try {
      // Telefono nuovo con il PIN attivo: prima il PIN, altrimenti il server non riconosce
      // l'utente e il profilo sembrerebbe mancante.
      final SecurityRepository? security = widget.security;
      if (security != null) {
        final SecurityStatus status = await security.status();
        if (!mounted) return;
        if (status.needsPin) {
          setState(() {
            _securityStatus = status;
            _profileState = _Profile.needsPin;
          });
          return;
        }
      }
      final MyProfile? mine = await repo.fetchMine();
      if (!mounted) return;
      setState(() {
        _profile = mine;
        _profileState = mine == null ? _Profile.missing : _Profile.ready;
      });
    } on ProfileFailure catch (f) {
      if (mounted) {
        setState(() {
          _profileState = _Profile.failed;
          _failure = f.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _profileState = _Profile.failed;
          _failure = 'Qualcosa non ha funzionato. Riprova.';
        });
      }
    }
  }

  Future<void> _signOut() async {
    _closeChat();
    // Uscita sicura: questo telefono non resta attendibile e lo sblocco con impronta si spegne.
    await widget.security?.forgetThisDevice();
    await widget.biometricLock?.setEnabled(false);
    _profile = null;
    _profileState = _Profile.loading;
    RegistrationDraftStore.current = null;
    await widget.gateway.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return OnboardingFlow(
        gateway: widget.gateway,
        today: widget.today,
        onDraftReady: (RegistrationDraft draft) => RegistrationDraftStore.current = draft,
      );
    }
    switch (_link) {
      case _Link.linked:
        final ProfileRepository? repo = widget.profiles;
        if (repo == null) {
          return AppShell(backend: widget.backend, onSignOut: _signOut, map: widget.map);
        }
        switch (_profileState) {
          case _Profile.loading:
            return const _LinkScreen(title: 'Carichiamo il tuo profilo…', busy: true);
          case _Profile.needsPin:
            return PinEntryScreen(
              repository: widget.security!,
              initialStatus: _securityStatus ?? const SecurityStatus(),
              onVerified: _loadProfile,
              onSignOut: _signOut,
            );
          case _Profile.failed:
            return _LinkScreen(
              title: 'Profilo non caricato',
              message: _failure,
              onRetry: _loadProfile,
              onSignOut: _signOut,
            );
          case _Profile.missing:
            return ProfileFormScreen(
              repository: repo,
              draft: RegistrationDraftStore.current,
              onSaved: _profileCreated,
              onSignOut: _signOut,
              pickImage: widget.pickImage,
              today: widget.today,
            );
          case _Profile.ready:
            final PrivacyController? checkup = _checkup;
            if (checkup != null) {
              return PrivacyCheckupScreen(
                controller: checkup,
                profiles: repo,
                offeredAfterSignUp: true,
                onDone: _closeCheckup,
              );
            }
            final Widget shell = AppShell(
              backend: widget.backend,
              onSignOut: _signOut,
              profile: _profile,
              profiles: repo,
              onProfileChanged: _loadProfile,
              privacy: widget.privacy,
              pushSettings: widget.pushSettings,
              security: widget.security,
              biometricLock: widget.biometricLock,
              contacts: widget.contacts,
              map: widget.map,
              listings: widget.listings,
              social: widget.social,
              market: widget.market,
              chat: _uid == null ? null : _chatFor(_uid!),
              isAdmin: widget.isAdmin,
              phone: widget.gateway.currentPhone,
            );
            // Fase 7: account sospeso e avvisi del Team Piazly.
            final ModerationRepository? moderation = ModerationRegistry.current;
            final Widget moderated = moderation == null
                ? shell
                : ModerationGate(repository: moderation, onSignOut: _signOut, child: shell);
            final ContactsRepository? contacts = widget.contacts;
            final Widget synced = contacts == null
                ? moderated
                : ContactsAutoSync(repository: contacts, child: moderated);
            final BiometricLock? lock = widget.biometricLock;
            return lock == null ? synced : AppLockGate(lock: lock, child: synced);
        }
      case _Link.checking:
        return const _LinkScreen(
          title: 'Colleghiamo il tuo account…',
          busy: true,
        );
      case _Link.failed:
        return _LinkScreen(
          title: 'Accesso non completato',
          message: _failure,
          onRetry: _ensureLinked,
          onSignOut: _signOut,
        );
    }
  }
}

class _LinkScreen extends StatelessWidget {
  const _LinkScreen({
    required this.title,
    this.message,
    this.busy = false,
    this.onRetry,
    this.onSignOut,
  });

  final String title;
  final String? message;
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NexusMark(size: 56),
                const SizedBox(height: 22),
                Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                if (message != null) ...[
                  const SizedBox(height: 10),
                  Text(message!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 22),
                if (busy) const CircularProgressIndicator(),
                if (onRetry != null)
                  FilledButton(onPressed: onRetry, child: const Text('Riprova')),
                if (onSignOut != null) ...[
                  const SizedBox(height: 8),
                  TextButton(onPressed: onSignOut, child: const Text('Esci')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

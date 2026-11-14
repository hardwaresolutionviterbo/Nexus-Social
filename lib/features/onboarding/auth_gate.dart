import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/services/auth_gateway.dart';
import '../../core/services/backend_bootstrap.dart';
import '../../core/widgets/nexus_ui.dart';
import '../shell/app_shell.dart';
import 'onboarding_flow.dart';
import 'registration_rules.dart';

/// Controllo d'accesso (Fase 2, Blocco 1).
///
/// - Nessun utente: registrazione e accesso ([OnboardingFlow]).
/// - Utente appena entrato o all'apertura dell'app: ruolo `authenticated` e verifica che
///   Supabase lo riconosca ([AuthGateway.ensureLinked]); poi l'app.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.gateway,
    this.backend = const BackendStatus.unconfigured(),
    this.today,
  });

  final AuthGateway gateway;
  final BackendStatus backend;
  final DateTime Function()? today;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _Link { checking, linked, failed }

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<String?>? _subscription;
  String? _uid;
  _Link _link = _Link.checking;
  String? _failure;

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
      });
      if (uid != null) {
        unawaited(_ensureLinked());
      } else {
        RegistrationDraftStore.current = null;
      }
    });
  }

  @override
  void dispose() {
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

  Future<void> _signOut() async {
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
        return AppShell(backend: widget.backend, onSignOut: _signOut);
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

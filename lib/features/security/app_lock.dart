import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/nexus_ui.dart';

/// Sblocco con impronta o volto (S3), solo sul telefono: facoltativo, lo attiva l'utente.
abstract class BiometricLock {
  Future<bool> isAvailable();

  Future<bool> isEnabled();

  Future<void> setEnabled(bool value);

  /// Chiede impronta o volto (o il blocco schermo del telefono, se l'impronta non va).
  Future<bool> authenticate(String reason);
}

class DeviceBiometricLock implements BiometricLock {
  DeviceBiometricLock({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _key = 'piazly_biometric_lock';

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isEnabled() async {
    try {
      return await _storage.read(key: _key) == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setEnabled(bool value) async {
    if (value) {
      await _storage.write(key: _key, value: '1');
    } else {
      await _storage.delete(key: _key);
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}

/// Copre l'app con la schermata di sblocco quando l'impronta è attiva: all'apertura e ogni
/// volta che si torna nell'app.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.lock, required this.child});

  final BiometricLock lock;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _checking = true;
  bool _locked = false;
  bool _wentToBackground = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _start() async {
    final bool enabled = await widget.lock.isEnabled();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _locked = enabled;
    });
    if (enabled) await _unlock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _wentToBackground = true;
    } else if (state == AppLifecycleState.resumed && _wentToBackground && !_asking) {
      _wentToBackground = false;
      widget.lock.isEnabled().then((bool enabled) {
        if (enabled && mounted) {
          setState(() => _locked = true);
          _unlock();
        }
      });
    }
  }

  Future<void> _unlock() async {
    if (_asking) return;
    _asking = true;
    final bool ok = await widget.lock.authenticate('Sblocca Piazly');
    _asking = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_locked) return widget.child;
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NexusMark(size: 64),
                const SizedBox(height: 22),
                Text('Piazly è bloccata', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Usa l\'impronta o il volto per entrare.', textAlign: TextAlign.center),
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const ValueKey<String>('sblocca_app'),
                  onPressed: _unlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Sblocca'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

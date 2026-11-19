import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

/// Permessi del telefono mostrati in Privacy → Autorizzazioni, con lo stato vero.
enum PhonePermission {
  notifications('Notifiche', 'Messaggi, chiamate e avvisi', Icons.notifications_outlined),
  camera('Fotocamera', 'Foto, video, videochiamate e stati', Icons.photo_camera_outlined),
  microphone('Microfono', 'Messaggi vocali e chiamate', Icons.mic_none_rounded),
  location('Posizione', 'Mappa, annunci vicini e GPS in tempo reale', Icons.place_outlined),
  contacts('Contatti', 'Rubrica: trovare chi usa Piazly, con i nomi del telefono', Icons.contacts_outlined);

  const PhonePermission(this.title, this.use, this.icon);

  final String title;
  final String use;
  final IconData icon;
}

enum PermissionState {
  granted('Attivo'),
  limited('Attivo in parte'),
  denied('Non attivo'),
  blocked('Bloccato: va attivato dalle impostazioni'),
  unavailable('Non disponibile su questo telefono');

  const PermissionState(this.label);

  final String label;

  bool get on => this == granted || this == limited;
}

abstract class PhonePermissions {
  Future<PermissionState> status(PhonePermission p);

  Future<PermissionState> request(PhonePermission p);

  Future<void> openSettings();
}

class RealPhonePermissions implements PhonePermissions {
  const RealPhonePermissions();

  static Permission _of(PhonePermission p) => switch (p) {
    PhonePermission.notifications => Permission.notification,
    PhonePermission.camera => Permission.camera,
    PhonePermission.microphone => Permission.microphone,
    PhonePermission.location => Permission.locationWhenInUse,
    PhonePermission.contacts => Permission.contacts,
  };

  static PermissionState _map(PermissionStatus s) => switch (s) {
    PermissionStatus.granted => PermissionState.granted,
    PermissionStatus.limited || PermissionStatus.provisional => PermissionState.limited,
    PermissionStatus.permanentlyDenied => PermissionState.blocked,
    PermissionStatus.restricted => PermissionState.unavailable,
    _ => PermissionState.denied,
  };

  @override
  Future<PermissionState> status(PhonePermission p) async {
    try {
      return _map(await _of(p).status);
    } catch (_) {
      return PermissionState.unavailable;
    }
  }

  @override
  Future<PermissionState> request(PhonePermission p) async {
    try {
      return _map(await _of(p).request());
    } catch (_) {
      return PermissionState.unavailable;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }
}

/// Quale implementazione usare: nei test una versione finta.
@visibleForTesting
PhonePermissions phonePermissions = const RealPhonePermissions();

PhonePermissions get currentPhonePermissions => phonePermissions;

/// Elenco dei permessi con «Attivo / Non attivo» e un pulsante per attivarli o gestirli.
/// Si aggiorna da solo quando si torna dalle impostazioni del telefono.
class PhonePermissionsList extends StatefulWidget {
  const PhonePermissionsList({super.key});

  @override
  State<PhonePermissionsList> createState() => _PhonePermissionsListState();
}

class _PhonePermissionsListState extends State<PhonePermissionsList> with WidgetsBindingObserver {
  final Map<PhonePermission, PermissionState> _states = <PhonePermission, PermissionState>{};

  PhonePermissions get _p => currentPhonePermissions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    for (final PhonePermission p in PhonePermission.values) {
      final PermissionState s = await _p.status(p);
      if (!mounted) return;
      setState(() => _states[p] = s);
    }
  }

  Future<void> _act(PhonePermission p) async {
    final PermissionState? s = _states[p];
    if (s == PermissionState.denied) {
      final PermissionState after = await _p.request(p);
      if (!mounted) return;
      setState(() => _states[p] = after);
      if (after == PermissionState.blocked) await _p.openSettings();
    } else {
      await _p.openSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: [
        for (final PhonePermission p in PhonePermission.values)
          Builder(
            builder: (BuildContext context) {
              final PermissionState? s = _states[p];
              final bool on = s?.on ?? false;
              return ListTile(
                key: ValueKey<String>('permesso_${p.name}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(p.icon),
                title: Text(p.title),
                subtitle: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: s?.label ?? 'Controllo…',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: on ? const Color(0xFF15803D) : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextSpan(text: '\n${p.use}'),
                    ],
                  ),
                ),
                isThreeLine: true,
                trailing: s == null || s == PermissionState.unavailable
                    ? null
                    : TextButton(
                        key: ValueKey<String>('permesso_${p.name}_azione'),
                        onPressed: () => _act(p),
                        child: Text(on ? 'Gestisci' : s == PermissionState.denied ? 'Consenti' : 'Impostazioni'),
                      ),
              );
            },
          ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.photo_library_outlined),
          title: Text('Galleria'),
          subtitle: Text('Nessun accesso a tutta la galleria: scegli tu ogni foto o video.'),
        ),
      ],
    );
  }
}

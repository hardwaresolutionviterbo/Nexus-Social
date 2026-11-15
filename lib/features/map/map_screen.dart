import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'map_location.dart';
import 'map_surface.dart';

/// Servizi del telefono usati dalla Mappa. Senza (test di interfaccia, anteprime)
/// la schermata mostra al posto della mappa un riquadro neutro.
class MapServices {
  const MapServices({required this.location, required this.notices, required this.surface});

  factory MapServices.device() => MapServices(
    location: const GeolocatorDeviceLocation(),
    notices: SecureMapNoticeStore(),
    surface: MapLibreSurface.builder,
  );

  final DeviceLocation location;
  final MapNoticeStore notices;
  final MapSurfaceBuilder surface;
}

/// Mappa Sociale (Fase 3, Blocco 1): mappa 3D centrata sul telefono, avviso di sicurezza
/// al primo accesso (M3), permesso di posizione chiesto solo dopo la spiegazione.
///
/// La posizione resta sul telefono: in questo blocco non viene inviata a nessun server.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.active = true, this.services});

  /// Vero quando la scheda Mappa è quella aperta: solo allora si crea la mappa e si
  /// ascolta la posizione.
  final bool active;
  final MapServices? services;

  static const List<int> radiusOptions = <int>[1, 5, 10, 30];

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  int _radiusKm = 10;
  bool _started = false;
  bool _showNotice = false;
  bool _noticeChecked = false;
  LocationAccess? _access;
  bool _promptDismissed = false;
  bool _threeD = true;
  bool _centered = false;
  bool _foreground = true;
  GeoFix? _lastFix;
  MapSurfaceHandle? _handle;
  StreamSubscription<GeoFix>? _sub;

  MapServices? get _services => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !_started) _start();
    _syncListening();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _noticeChecked && !_showNotice) {
      // Ritorno dalle impostazioni del telefono: il permesso può essere cambiato.
      unawaited(_checkAccess());
    } else {
      _syncListening();
    }
  }

  Future<void> _start() async {
    _started = true;
    final MapServices? s = _services;
    if (s == null) return;
    final bool seen = await s.notices.seen();
    if (!mounted) return;
    setState(() {
      _noticeChecked = true;
      _showNotice = !seen;
    });
    if (seen) await _checkAccess();
  }

  Future<void> _acknowledgeNotice() async {
    final MapServices? s = _services;
    setState(() => _showNotice = false);
    if (s == null) return;
    await s.notices.markSeen();
    if (_access == null) {
      await _checkAccess();
    } else {
      _syncListening();
    }
  }

  Future<void> _checkAccess() async {
    final MapServices? s = _services;
    if (s == null) return;
    final LocationAccess access = await s.location.status();
    if (!mounted) return;
    setState(() => _access = access);
    _syncListening();
  }

  Future<void> _requestAccess() async {
    final MapServices? s = _services;
    if (s == null) return;
    final LocationAccess access = await s.location.request();
    if (!mounted) return;
    setState(() => _access = access);
    _syncListening();
  }

  /// Ascolta la posizione solo con la scheda aperta, l'app in primo piano e il permesso.
  void _syncListening() {
    final MapServices? s = _services;
    final bool want = s != null &&
        widget.active &&
        _foreground &&
        _access == LocationAccess.granted;
    if (want && _sub == null) {
      _sub = s.location.fixes().listen(_onFix, onError: (Object _) {
        // Localizzazione spenta mentre la mappa era aperta.
        _sub?.cancel();
        _sub = null;
        if (mounted) setState(() => _access = LocationAccess.serviceOff);
      });
    } else if (!want && _sub != null) {
      _sub!.cancel();
      _sub = null;
    }
  }

  void _onFix(GeoFix fix) {
    _lastFix = fix;
    final MapSurfaceHandle? h = _handle;
    if (h != null) {
      unawaited(h.showMe(fix));
      if (!_centered) {
        _centered = true;
        unawaited(h.flyTo(fix, threeD: _threeD));
      }
    }
    if (mounted) setState(() {});
  }

  void _onSurfaceReady(MapSurfaceHandle handle) {
    _handle = handle;
    final GeoFix? fix = _lastFix;
    if (fix != null) {
      unawaited(handle.showMe(fix));
      if (!_centered) {
        _centered = true;
        unawaited(handle.flyTo(fix, threeD: _threeD));
      }
    }
  }

  void _centerOnMe() {
    final GeoFix? fix = _lastFix;
    if (fix == null) {
      setState(() => _promptDismissed = false);
      return;
    }
    unawaited(_handle?.flyTo(fix, threeD: _threeD));
  }

  void _toggleThreeD() {
    setState(() => _threeD = !_threeD);
    unawaited(_handle?.setThreeD(_threeD));
  }

  @override
  Widget build(BuildContext context) {
    final MapServices? s = _services;
    final Widget surface = s != null && _started
        ? s.surface(context, _onSurfaceReady)
        : const _SurfacePlaceholder();
    final bool askLocation = s != null &&
        _noticeChecked &&
        !_showNotice &&
        !_promptDismissed &&
        _access != null &&
        _access != LocationAccess.granted;

    return Stack(
      children: [
        Positioned.fill(child: surface),
        Positioned(
          top: AppSpacing.sm,
          left: 12,
          right: 12,
          child: _MapHeader(
            radiusKm: _radiusKm,
            onRadiusChanged: (int v) => setState(() => _radiusKm = v),
          ),
        ),
        Positioned(
          right: 12,
          bottom: _MapLayout.controlsBottom,
          child: _MapControls(
            threeD: _threeD,
            onSafety: () => setState(() => _showNotice = true),
            onToggleThreeD: _toggleThreeD,
            onCenter: _centerOnMe,
          ),
        ),
        const Positioned(
          left: 12,
          bottom: _MapLayout.attributionBottom,
          child: _Attribution(),
        ),
        if (askLocation)
          Positioned(
            left: 12,
            right: 72,
            bottom: _MapLayout.controlsBottom,
            child: _LocationPrompt(
              access: _access!,
              onAllow: _requestAccess,
              onLater: () => setState(() => _promptDismissed = true),
              onOpenAppSettings: () => s!.location.openAppSettings(),
              onOpenLocationSettings: () => s!.location.openLocationSettings(),
            ),
          ),
        if (_showNotice) ...[
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Color(0x99000000)),
          ),
          Positioned.fill(
            child: Center(
              child: SafetyNoticeCard(onAcknowledge: _acknowledgeNotice),
            ),
          ),
        ],
      ],
    );
  }
}

abstract final class _MapLayout {
  /// Spazio lasciato alla barra delle sezioni, che galleggia sopra la mappa.
  static const double attributionBottom = 108;
  static const double controlsBottom = 140;
}

class _MapHeader extends StatelessWidget {
  const _MapHeader({required this.radiusKm, required this.onRadiusChanged});

  final int radiusKm;
  final ValueChanged<int> onRadiusChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.map_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text('Mappa Sociale', style: theme.textTheme.titleSmall),
                const Spacer(),
                Icon(Icons.radar_rounded, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Raggio $radiusKm km',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final int option in MapScreen.radiusOptions) ...[
                    ChoiceChip(
                      label: Text('$option km'),
                      selected: option == radiusKm,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => onRadiusChanged(option),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.threeD,
    required this.onSafety,
    required this.onToggleThreeD,
    required this.onCenter,
  });

  final bool threeD;
  final VoidCallback onSafety;
  final VoidCallback onToggleThreeD;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ButtonStyle style = IconButton.styleFrom(
      backgroundColor: scheme.surface.withValues(alpha: 0.95),
      foregroundColor: scheme.onSurface,
      elevation: 3,
      shadowColor: Colors.black38,
      fixedSize: const Size(48, 48),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Consigli di sicurezza',
          style: style,
          icon: const Icon(Icons.health_and_safety_outlined),
          onPressed: onSafety,
        ),
        const SizedBox(height: 10),
        IconButton(
          tooltip: threeD ? 'Vista in piano' : 'Vista 3D',
          style: style,
          icon: Text(
            threeD ? '2D' : '3D',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          onPressed: onToggleThreeD,
        ),
        const SizedBox(height: 10),
        IconButton(
          tooltip: 'Centra su di me',
          style: style.copyWith(
            backgroundColor: const WidgetStatePropertyAll<Color>(AppColors.brandOrange),
            foregroundColor: const WidgetStatePropertyAll<Color>(Colors.white),
          ),
          icon: const Icon(Icons.my_location_rounded),
          onPressed: onCenter,
        ),
      ],
    );
  }
}

/// Attribuzione dei dati della mappa, sempre visibile (licenza ODbL di OpenStreetMap).
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          MapRules.attribution,
          style: TextStyle(fontSize: 11, color: Color(0xFF334155)),
        ),
      ),
    );
  }
}

class _LocationPrompt extends StatelessWidget {
  const _LocationPrompt({
    required this.access,
    required this.onAllow,
    required this.onLater,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final LocationAccess access;
  final VoidCallback onAllow;
  final VoidCallback onLater;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (String title, String body, String action, VoidCallback onAction) = switch (access) {
      LocationAccess.deniedForever => (
        'Posizione non consentita',
        'Per vedere la mappa intorno a te, consenti la posizione a Piazly dalle '
            'impostazioni del telefono.',
        'Apri impostazioni',
        onOpenAppSettings,
      ),
      LocationAccess.serviceOff => (
        'Localizzazione spenta',
        'Accendi la localizzazione del telefono per centrare la mappa su di te.',
        'Attiva localizzazione',
        onOpenLocationSettings,
      ),
      _ => (
        'Mostra la mappa intorno a te',
        'Piazly usa la posizione solo con l\'app aperta, per centrare la mappa su di te. '
            'Si aggiorna circa ogni ${MapRules.updateDistanceMeters} metri, così consuma '
            'poca batteria. Per ora la posizione resta sul telefono e non viene inviata a '
            'nessuno; la tua posizione esatta non sarà mai visibile agli altri.',
        'Consenti posizione',
        onAllow,
      ),
    };
    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          key: const ValueKey<String>('richiesta_posizione'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onLater, child: const Text('Non ora')),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(onPressed: onAction, child: Text(action)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Avviso di sicurezza della Mappa (M3): al primo accesso e sempre dall'icona dello scudo.
class SafetyNoticeCard extends StatelessWidget {
  const SafetyNoticeCard({super.key, required this.onAcknowledge});

  final VoidCallback onAcknowledge;

  static const List<(IconData, String)> tips = <(IconData, String)>[
    (Icons.groups_2_outlined, 'Incontra le persone conosciute qui in luoghi pubblici e frequentati.'),
    (Icons.share_location_outlined, 'Prima di vederti con qualcuno, avvisa una persona di fiducia: dove vai, con chi e a che ora.'),
    (Icons.lock_outline, 'Non condividere indirizzo di casa, documenti, codici o dati bancari.'),
    (Icons.blur_on_rounded, 'La tua posizione esatta non è mai mostrata: gli annunci compaiono in una zona approssimata.'),
    (Icons.flag_outlined, 'Se qualcosa non ti convince, interrompi, blocca e segnala la persona.'),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Material(
        key: const ValueKey<String>('avviso_sicurezza'),
        color: scheme.surface,
        borderRadius: BorderRadius.circular(26),
        elevation: 8,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.health_and_safety_rounded, color: scheme.primary, size: 28),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Sicurezza sulla mappa', style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final (IconData icon, String text) in tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: onAcknowledge, child: const Text('Ho capito')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Al posto della mappa quando i servizi del telefono non ci sono (test, anteprime).
class _SurfacePlaceholder extends StatelessWidget {
  const _SurfacePlaceholder();

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: isDark ? const Color(0xFF0E1628) : const Color(0xFFE8EEF6),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'La mappa compare qui sul telefono.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

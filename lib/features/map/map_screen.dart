import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import '../privacy/privacy_repository.dart';
import '../profile/profile_repository.dart';
import 'latest_listings_screen.dart';
import 'listing_form_screen.dart';
import 'listing_models.dart';
import 'listing_repository.dart';
import 'listing_sheets.dart';
import 'social_repository.dart';
import 'map_location.dart';
import 'my_listings_screen.dart';
import 'map_surface.dart';
import 'safety_notice.dart';

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
  const MapScreen({
    super.key,
    this.active = true,
    this.services,
    this.listings,
    this.isMinor = false,
    this.pickImage = pickFromGallery,
    this.profiles,
    this.privacy,
    this.now = DateTime.now,
    this.social,
  });

  /// Vero quando la scheda Mappa è quella aperta: solo allora si crea la mappa e si
  /// ascolta la posizione.
  final bool active;
  final MapServices? services;

  /// Annunci sul server (Blocco 2): null finché il collegamento al server è spento.
  final MapListingRepository? listings;

  /// Minorenne: avviso di sicurezza ripetuto prima di un annuncio con punto preciso (M3).
  final bool isMinor;
  final PickImage pickImage;

  /// Profilo pubblico dell'autore di un annuncio e «Blocca» (Blocco 3).
  final ProfileRepository? profiles;
  final PrivacyRepository? privacy;
  final DateTime Function() now;

  /// Eventi, reazioni, commenti e notifiche (Blocco 4).
  final SocialRepository? social;

  static const List<int> radiusOptions = MapFilters.radiusOptions;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  MapFilters _filters = const MapFilters();
  List<NearbyListing> _nearby = const <NearbyListing>[];
  bool _loadingNearby = false;
  int _nearbyRequest = 0;
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
    if (widget.active && !old.active) unawaited(_refreshNearby());
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
      unawaited(_refreshNearby());
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
    // Nuova posizione (ogni ~300 m): si aggiornano gli annunci intorno.
    unawaited(_refreshNearby());
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
    if (_nearby.isNotEmpty) unawaited(handle.showListings(_nearby, _openListingById));
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

  GeoPoint? get _currentPoint {
    final GeoFix? f = _lastFix;
    return f == null ? null : GeoPoint(f.latitude, f.longitude);
  }

  /// Annunci intorno alla posizione attuale con i filtri scelti (solo con il server).
  Future<void> _refreshNearby() async {
    final MapListingRepository? repo = widget.listings;
    final GeoPoint? origin = _currentPoint;
    if (repo == null || origin == null || !widget.active) return;
    final int request = ++_nearbyRequest;
    if (mounted) setState(() => _loadingNearby = true);
    try {
      final List<NearbyListing> items = await repo.nearby(origin, _filters);
      // Una risposta vecchia (filtri cambiati nel frattempo) non sovrascrive la nuova.
      if (!mounted || request != _nearbyRequest) return;
      setState(() => _nearby = items);
      await _handle?.showListings(items, _openListingById);
    } on ListingFailure {
      // La mappa resta utilizzabile; si riprova al prossimo spostamento o filtro.
    } finally {
      if (mounted && request == _nearbyRequest) setState(() => _loadingNearby = false);
    }
  }

  void _setFilters(MapFilters f) {
    if (f == _filters) return;
    setState(() => _filters = f);
    unawaited(_refreshNearby());
  }

  ListingSheetServices? get _sheetServices {
    final MapListingRepository? repo = widget.listings;
    return repo == null
        ? null
        : ListingSheetServices(
            listings: repo,
            profiles: widget.profiles,
            privacy: widget.privacy,
            social: widget.social,
          );
  }

  Future<void> _openListingById(String id) async {
    final NearbyListing? listing = _nearby.where((NearbyListing l) => l.id == id).firstOrNull;
    final ListingSheetServices? services = _sheetServices;
    if (listing == null || services == null || !mounted) return;
    final bool? blocked = await showListingSheet(
      context,
      listing: listing,
      services: services,
      now: widget.now,
    );
    if (blocked ?? false) unawaited(_refreshNearby());
  }

  Future<void> _openFilters() async {
    final MapFilters? f = await showMapFilters(context, _filters);
    if (f != null) _setFilters(f);
  }

  Future<void> _openLatest() async {
    if (!_needsServer()) return;
    final ListingSheetServices services = _sheetServices!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LatestListingsScreen(
          services: services,
          origin: _currentPoint,
          filters: _filters,
          now: widget.now,
        ),
      ),
    );
    unawaited(_refreshNearby());
  }

  /// Annunci e pubblicazione richiedono il server; finché è spento lo si dice chiaramente.
  bool _needsServer() {
    if (widget.listings != null && _services != null) return true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Per vedere e pubblicare annunci serve il collegamento al server: si attiverà '
            'con il piano Blaze. La mappa intanto funziona.',
          ),
        ),
      );
    return false;
  }

  Future<void> _publish() async {
    if (!_needsServer()) return;
    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ListingFormScreen(
          repository: widget.listings!,
          surface: _services!.surface,
          currentPosition: _currentPoint,
          isMinor: widget.isMinor,
          pickImage: widget.pickImage,
        ),
      ),
    );
    if ((done ?? false) && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Annuncio pubblicato.')));
      unawaited(_refreshNearby());
    }
  }

  Future<void> _openMine() async {
    if (!_needsServer()) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MyListingsScreen(
          repository: widget.listings!,
          surface: _services!.surface,
          currentPosition: _currentPoint,
          isMinor: widget.isMinor,
          pickImage: widget.pickImage,
        ),
      ),
    );
    unawaited(_refreshNearby());
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
            filters: _filters,
            count: widget.listings == null ? null : _nearby.length,
            loading: _loadingNearby,
            onRadiusChanged: (int v) => _setFilters(_filters.copyWith(radiusKm: v)),
            onFilters: _openFilters,
            onLatest: _openLatest,
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
            onMine: _openMine,
          ),
        ),
        if (!askLocation)
          Positioned(
            left: 12,
            bottom: _MapLayout.controlsBottom,
            child: FilledButton.icon(
              key: const ValueKey<String>('pubblica_annuncio'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                elevation: 3,
              ),
              onPressed: _publish,
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Pubblica'),
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
              onOpenAppSettings: () => s.location.openAppSettings(),
              onOpenLocationSettings: () => s.location.openLocationSettings(),
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
  const _MapHeader({
    required this.filters,
    required this.count,
    required this.loading,
    required this.onRadiusChanged,
    required this.onFilters,
    required this.onLatest,
  });

  final MapFilters filters;

  /// Annunci visibili entro il raggio; null senza server.
  final int? count;
  final bool loading;
  final ValueChanged<int> onRadiusChanged;
  final VoidCallback onFilters;
  final VoidCallback onLatest;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int? n = count;
    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.map_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mappa Sociale',
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (n != null)
                        Text(
                          loading
                              ? 'Cerco annunci…'
                              : n == 1
                              ? '1 annuncio entro ${filters.radiusKm} km'
                              : '$n annunci entro ${filters.radiusKm} km',
                          key: const ValueKey<String>('conteggio_annunci'),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Filtri',
                  onPressed: onFilters,
                  icon: Badge(
                    isLabelVisible: filters.narrowed,
                    child: const Icon(Icons.tune_rounded),
                  ),
                ),
                IconButton(
                  tooltip: 'Ultimi annunci',
                  onPressed: onLatest,
                  icon: const Icon(Icons.dynamic_feed_rounded),
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final int option in MapScreen.radiusOptions) ...[
                    ChoiceChip(
                      label: Text('$option km'),
                      selected: option == filters.radiusKm,
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
    required this.onMine,
  });

  final bool threeD;
  final VoidCallback onMine;
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
          tooltip: 'I miei annunci',
          style: style,
          icon: const Icon(Icons.view_list_rounded),
          onPressed: onMine,
        ),
        const SizedBox(height: 10),
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
            // Su schermi stretti o con testo grande i pulsanti vanno a capo.
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: AppSpacing.sm,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                TextButton(onPressed: onLater, child: const Text('Non ora')),
                FilledButton(onPressed: onAction, child: Text(action)),
              ],
            ),
          ],
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

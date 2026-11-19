import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../business/business_models.dart';
import '../business/business_repository.dart';
import '../business/business_screens.dart';
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import '../privacy/privacy_repository.dart';
import '../profile/profile_repository.dart';
import '../chat/chat_thread_screen.dart' show openChatWith;
import 'latest_listings_screen.dart';
import 'listing_form_screen.dart';
import 'listing_models.dart';
import 'listing_repository.dart';
import 'listing_sheets.dart';
import 'live_location.dart';
import 'live_location_screens.dart';
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
    this.businesses,
  });

  /// Attività con sede fissa (Fase 6); se manca si usa [BusinessRegistry.current].
  final BusinessRepository? businesses;

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

  /// GPS in tempo reale (Blocco 15): chi condivide con me, ricaricato ogni 20 secondi.
  LiveLocationService? _live;
  Timer? _livePoll;

  MapServices? get _services => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _start();
    _live = LiveRegistry.current?..addListener(_showPeople);
    _syncLivePoll();
  }

  void _syncLivePoll() {
    final LiveLocationService? live = _live;
    final bool on = live != null && widget.active && _foreground;
    if (!on) {
      _livePoll?.cancel();
      _livePoll = null;
      return;
    }
    if (_livePoll != null) return;
    unawaited(live.loadPeople());
    _livePoll = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(live.loadPeople()));
  }

  void _showPeople() {
    final LiveLocationService? live = _live;
    if (live == null) return;
    unawaited(_handle?.showPeople(live.people, _openPerson));
  }

  Future<void> _openPerson(String id) async {
    final LiveLocationService? live = _live;
    final LivePerson? p = live?.people.where((LivePerson x) => x.userId == id).firstOrNull;
    if (live == null || p == null || !mounted) return;
    final String name = live.nameOf(p.userId, p.name);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, key: const ValueKey<String>('gps_persona_nome'), style: Theme.of(c).textTheme.titleLarge),
              Text('@${p.username}'),
              const SizedBox(height: 8),
              Text(
                'Posizione in tempo reale, ${liveAgoLabel(p.updatedAt, live.now)} · '
                '${liveUntilLabel(p.expiresAt, live.now)}',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.icon(
                    key: const ValueKey<String>('gps_persona_scrivi'),
                    onPressed: () {
                      Navigator.of(c).pop();
                      unawaited(openChatWith(context, userId: p.userId, name: name));
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Scrivi'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(c).pop();
                      unawaited(_handle?.flyTo(
                        GeoFix(latitude: p.latitude, longitude: p.longitude, time: p.updatedAt),
                        threeD: _threeD,
                      ));
                    },
                    icon: const Icon(Icons.center_focus_strong_outlined),
                    label: const Text('Centra'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !_started) _start();
    _syncListening();
    if (widget.active && !old.active) unawaited(_refreshNearby());
    _syncLivePoll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _livePoll?.cancel();
    _live?.removeListener(_showPeople);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncLivePoll();
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
    if (_businesses.isNotEmpty) unawaited(handle.showBusinesses(_businesses, _openBusiness));
    final LiveLocationService? live = _live;
    if (live != null && live.people.isNotEmpty) unawaited(handle.showPeople(live.people, _openPerson));
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
  /// Sedi delle attività intorno (Fase 6): segnaposti fissi, entro 20 km.
  List<BusinessPin> _businesses = const <BusinessPin>[];

  Future<void> _refreshBusinesses() async {
    final BusinessRepository? repo = widget.businesses ?? BusinessRegistry.current;
    final GeoPoint? origin = _currentPoint;
    if (repo == null || origin == null || !widget.active) return;
    try {
      final List<BusinessPin> pins = await repo.nearby(origin.latitude, origin.longitude);
      if (!mounted) return;
      _businesses = pins;
      await _handle?.showBusinesses(pins, _openBusiness);
    } on BusinessFailure {
      // Si riprova al prossimo spostamento.
    }
  }

  Future<void> _openBusiness(String id) async {
    final BusinessRepository? repo = widget.businesses ?? BusinessRegistry.current;
    if (repo == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => BusinessProfileScreen(repository: repo, id: id, now: widget.now)),
    );
  }

  Future<void> _refreshNearby() async {
    unawaited(_refreshBusinesses());
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
                minimumSize: const Size(0, 56),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                elevation: 4,
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
    final ButtonStyle square = IconButton.styleFrom(
      backgroundColor: scheme.surface,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      fixedSize: const Size(46, 46),
    );
    return Material(
      color: scheme.surface.withValues(alpha: 0.97),
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.map_rounded, size: 24, color: AppColors.brandOrange),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mappa Sociale',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
                  style: square,
                  onPressed: onFilters,
                  icon: Badge(
                    isLabelVisible: filters.narrowed,
                    child: const Icon(Icons.tune_rounded),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Ultimi annunci',
                  style: square,
                  onPressed: onLatest,
                  icon: const Icon(Icons.dynamic_feed_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final int option in MapScreen.radiusOptions) ...[
                    ChoiceChip(
                      label: Text('$option km'),
                      selected: option == filters.radiusKm,
                      // Nuova grafica: pillole, quella scelta arancione con la spunta bianca.
                      shape: const StadiumBorder(),
                      selectedColor: AppColors.brandOrange,
                      checkmarkColor: Colors.white,
                      side: BorderSide(
                        color: option == filters.radiusKm ? AppColors.brandOrange : scheme.outlineVariant,
                      ),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: option == filters.radiusKm ? Colors.white : scheme.onSurface,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    final ButtonStyle flat = style.copyWith(
      backgroundColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      elevation: const WidgetStatePropertyAll<double>(0),
    );
    // Nuova grafica: i tre comandi in un pannello verticale, il mirino arancione a parte.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: scheme.surface.withValues(alpha: 0.97),
          elevation: 4,
          shadowColor: Colors.black38,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'I miei annunci',
                  style: flat,
                  icon: const Icon(Icons.view_list_rounded),
                  onPressed: onMine,
                ),
                IconButton(
                  tooltip: 'Consigli di sicurezza',
                  style: flat,
                  icon: const Icon(Icons.shield_outlined),
                  onPressed: onSafety,
                ),
                IconButton(
                  tooltip: threeD ? 'Vista in piano' : 'Vista 3D',
                  style: flat,
                  icon: Text(
                    threeD ? '2D' : '3D',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  onPressed: onToggleThreeD,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        IconButton(
          tooltip: 'Centra su di me',
          style: style.copyWith(
            backgroundColor: const WidgetStatePropertyAll<Color>(AppColors.brandOrange),
            foregroundColor: const WidgetStatePropertyAll<Color>(Colors.white),
            fixedSize: const WidgetStatePropertyAll<Size>(Size(58, 58)),
          ),
          icon: const Icon(Icons.my_location_rounded, size: 28),
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

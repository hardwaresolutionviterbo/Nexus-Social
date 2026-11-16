import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/services/backend_bootstrap.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../chat/chat_screen.dart';
import '../map/listing_repository.dart';
import '../map/map_screen.dart';
import '../market/market_models.dart';
import '../market/market_repository.dart';
import '../market/market_section_screen.dart';
import '../market/market_deals_screen.dart';
import '../market/market_feedback.dart';
import '../market/swap_proposals_screen.dart';
import '../map/notifications_screen.dart';
import '../map/social_repository.dart';
import '../contacts/contacts_sync.dart';
import '../privacy/privacy_repository.dart';
import '../security/app_lock.dart';
import '../security/security_repository.dart';
import '../profile/profile_models.dart';
import '../profile/profile_repository.dart';
import '../profile/profile_screen.dart';

/// Impalcatura dell'app: barra in alto con marchio e notifiche, cinque sezioni in basso.
///
/// Ordine e apertura decisi dal titolare (A1, schermata iniziale): Chat, Mappa,
/// Scambia (pulsante centrale arancione), Vendita, Profilo; l'app si apre su Chat.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.backend = const BackendStatus.unconfigured(),
    this.onSignOut,
    this.profile,
    this.profiles,
    this.onProfileChanged,
    this.privacy,
    this.security,
    this.biometricLock,
    this.contacts,
    this.map,
    this.listings,
    this.today,
    this.social,
    this.market,
  });

  final BackendStatus backend;

  /// Profilo dell'utente (Blocco 2), presente quando il server è collegato.
  final MyProfile? profile;
  final ProfileRepository? profiles;
  final Future<void> Function()? onProfileChanged;
  final PrivacyRepository? privacy;
  final SecurityRepository? security;
  final BiometricLock? biometricLock;
  final ContactsRepository? contacts;

  /// Posizione, avviso di sicurezza e mappa del telefono (Fase 3, Blocco 1).
  final MapServices? map;

  /// Annunci della Mappa sul server (Fase 3, Blocco 2).
  final MapListingRepository? listings;

  /// Interazioni e notifiche della campanella (Fase 3, Blocco 4).
  final SocialRepository? social;

  /// Annunci di Scambia & Vendi (Fase 5).
  final MarketRepository? market;

  /// Data di oggi per il calcolo dell'età (nei test si fissa).
  final DateTime Function()? today;

  /// Uscita dall'account (presente solo con un utente collegato).
  final Future<void> Function()? onSignOut;

  /// Scheda mostrata all'apertura: Chat, come WhatsApp (D4).
  static const int initialIndex = 0;

  /// Etichette nell'ordine della barra.
  static const List<String> sections = <String>[
    'Chat',
    'Mappa',
    'Scambia',
    'Vendita',
    'Profilo',
  ];

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  List<Widget> get _screens => <Widget>[
    const ChatScreen(),
    MapScreen(
      active: _index == 1,
      services: widget.map,
      listings: widget.listings,
      isMinor: _isMinor,
      profiles: widget.profiles,
      privacy: widget.privacy,
      social: widget.social,
    ),
    MarketSectionScreen(
      section: MarketSection.swap,
      repository: widget.market,
      services: widget.map,
      social: widget.social,
    ),
    MarketSectionScreen(
      section: MarketSection.sale,
      repository: widget.market,
      services: widget.map,
      social: widget.social,
    ),
    ProfileScreen(
      backend: widget.backend,
      onSignOut: widget.onSignOut,
      profile: widget.profile,
      profiles: widget.profiles,
      onProfileChanged: widget.onProfileChanged,
      privacy: widget.privacy,
      security: widget.security,
      biometricLock: widget.biometricLock,
      contacts: widget.contacts,
      // Media dei feedback sul profilo dei privati (Fase 5, Blocco 4).
      feedback: widget.market == null || widget.profile == null || widget.profile!.isBusiness
          ? null
          : FeedbackSummaryTile(
              repository: widget.market!,
              userId: widget.profile!.id,
              name: widget.profile!.publicName,
            ),
    ),
  ];

  int _index = AppShell.initialIndex;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refreshUnread();
  }

  /// Contatore della campanella: all'avvio, al cambio di sezione e dopo le notifiche.
  Future<void> _refreshUnread() async {
    final SocialRepository? social = widget.social;
    if (social == null) return;
    try {
      final int n = await social.unreadCount();
      if (mounted && n != _unread) setState(() => _unread = n);
    } catch (_) {
      // Senza rete il contatore resta com'era.
    }
  }

  Future<void> _openNotifications() async {
    final MarketRepository? market = widget.market;
    await NotificationsScreen.open(
      context,
      widget.social!,
      openSwaps: market == null ? null : (BuildContext c) => SwapProposalsScreen.open(c, market),
      openDeals: market == null ? null : (BuildContext c) => MarketDealsScreen.open(c, market),
    );
    await _refreshUnread();
  }

  /// Minorenne secondo la data di nascita del profilo (M3).
  bool get _isMinor {
    final DateTime? birth = widget.profile?.birthDate;
    if (birth == null) return false;
    final DateTime now = (widget.today ?? DateTime.now)();
    final DateTime adult = DateTime(birth.year + 18, birth.month, birth.day);
    return now.isBefore(adult);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    // Barra di stato e navigazione di sistema leggibili su entrambi i temi:
    // icone scure sul chiaro, chiare sullo scuro.
    final SystemUiOverlayStyle overlayStyle =
        (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
              systemStatusBarContrastEnforced: false,
              systemNavigationBarContrastEnforced: false,
            );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Stack(
        children: [
          // Fondo con bagliori dietro tutta l'app, barra in alto compresa.
          ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: const SizedBox.expand(),
          ),
          NexusBackdrop(isDark: isDark),
          Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: AppBar(
          systemOverlayStyle: overlayStyle,
          titleSpacing: 18,
          toolbarHeight: 66,
          title: Row(
            children: [
              const NexusMark(size: 36),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const NexusWordmark(),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      AppShell.sections[_index],
                      key: ValueKey<int>(_index),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            NotificationBell(
              count: _unread,
              onPressed: widget.social == null ? null : _openNotifications,
            ),
            const SizedBox(width: 14),
          ],
        ),
        body: SafeArea(
          top: false,
          child: IndexedStack(index: _index, children: _screens),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [const Color(0xFF17213A), const Color(0xFF0E1527)]
                    : [Colors.white, const Color(0xFFF7F8FC)],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.09)
                    : AppColors.lightOutline,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.10),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: AppColors.brandOrange.withValues(
                    alpha: isDark ? 0.10 : 0.06,
                  ),
                  blurRadius: 40,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (int value) {
                  setState(() => _index = value);
                  _refreshUnread();
                },
                destinations: const [
                  NavigationDestination(
                    icon: _NavIcon(Icons.chat_bubble_outline_rounded),
                    selectedIcon: _NavIcon(
                      Icons.chat_bubble_rounded,
                      selected: true,
                    ),
                    label: 'Chat',
                  ),
                  NavigationDestination(
                    icon: _NavIcon(Icons.map_outlined),
                    selectedIcon: _NavIcon(Icons.map_rounded, selected: true),
                    label: 'Mappa',
                  ),
                  NavigationDestination(
                    icon: _ExchangeButton(),
                    selectedIcon: _ExchangeButton(selected: true),
                    label: 'Scambia',
                  ),
                  NavigationDestination(
                    icon: _NavIcon(Icons.sell_outlined),
                    selectedIcon: _NavIcon(Icons.sell_rounded, selected: true),
                    label: 'Vendita',
                  ),
                  NavigationDestination(
                    icon: _NavIcon(Icons.person_outline_rounded),
                    selectedIcon: _NavIcon(
                      Icons.person_rounded,
                      selected: true,
                    ),
                    label: 'Profilo',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }
}

/// Icona della barra; quella selezionata sta in una pillola arancio luminosa.
class _NavIcon extends StatelessWidget {
  const _NavIcon(this.icon, {this.selected = false});

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 54,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: selected
            ? scheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
      ),
      child: Icon(
        icon,
        size: 24,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Pulsante centrale «Scambia»: cerchio arancio in rilievo con bagliore.
class _ExchangeButton extends StatelessWidget {
  const _ExchangeButton({this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.orangeGradient,
        border: Border.all(
          color: Colors.white.withValues(alpha: selected ? 0.55 : 0.28),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandOrange.withValues(
              alpha: selected ? 0.60 : 0.38,
            ),
            blurRadius: selected ? 24 : 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(
        Icons.swap_horiz_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

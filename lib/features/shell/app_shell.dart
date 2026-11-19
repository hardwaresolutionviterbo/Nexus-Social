import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/services/backend_bootstrap.dart';
import '../../core/services/push_notifications.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../calls/call_screen.dart';
import '../calls/call_service.dart';
import '../chat/chat_screen.dart';
import '../chat/chat_service.dart';
import '../chat/chat_thread_screen.dart' show ChatRegistry, openChatFromNotification;
import '../map/listing_repository.dart';
import '../map/live_location.dart';
import '../map/map_screen.dart';
import '../market/market_repository.dart';
import '../market/sale_and_swap_screen.dart';
import '../market/market_deals_screen.dart';
import '../market/market_feedback.dart';
import '../market/swap_proposals_screen.dart';
import '../map/notifications_screen.dart';
import '../map/social_repository.dart';
import '../contacts/contacts_sync.dart';
import '../notifications/notification_settings.dart';
import '../privacy/privacy_repository.dart';
import '../security/app_lock.dart';
import '../security/security_repository.dart';
import '../profile/profile_models.dart';
import '../profile/profile_repository.dart';
import '../profile/profile_screen.dart';
import '../status/status_tab.dart';

/// Impalcatura dell'app: barra in alto con marchio e notifiche, cinque sezioni in basso.
///
/// Ordine e apertura decisi dal titolare (A1, schermata iniziale): Chat, Mappa,
/// Scambia (pulsante centrale arancione), Vendita, Profilo; l'app si apre su Chat.
/// Nuovo ordine del titolare (19/11/2026): Chat, Stati, Mappa (pulsante centrale arancione),
/// Vendita (con dentro Scambia), Profilo.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.backend = const BackendStatus.unconfigured(),
    this.onSignOut,
    this.profile,
    this.profiles,
    this.onProfileChanged,
    this.privacy,
    this.pushSettings,
    this.security,
    this.biometricLock,
    this.contacts,
    this.map,
    this.listings,
    this.today,
    this.social,
    this.market,
    this.chat,
    this.isAdmin,
  });

  /// Vero solo per gli amministratori di Piazly: vedono lo stato dei servizi e la diagnostica.
  final Future<bool> Function()? isAdmin;


  final BackendStatus backend;

  /// Profilo dell'utente (Blocco 2), presente quando il server è collegato.
  final MyProfile? profile;
  final ProfileRepository? profiles;
  final Future<void> Function()? onProfileChanged;
  final PrivacyRepository? privacy;

  /// Preferenze delle notifiche (Fase 4, Blocco 5).
  final PushSettingsRepository? pushSettings;
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

  /// Chat cifrata (Fase 4): presente quando il server è collegato.
  final ChatService? chat;

  /// Data di oggi per il calcolo dell'età (nei test si fissa).
  final DateTime Function()? today;

  /// Uscita dall'account (presente solo con un utente collegato).
  final Future<void> Function()? onSignOut;

  /// Scheda mostrata all'apertura: Chat, come WhatsApp (D4).
  static const int initialIndex = 0;

  /// Etichette nell'ordine della barra.
  static const List<String> sections = <String>[
    'Chat',
    'Stati',
    'Mappa',
    'Vendita',
    'Profilo',
  ];

  /// Posizione della Mappa nella barra (pulsante centrale).
  static const int mapIndex = 2;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  List<Widget> get _screens => <Widget>[
    ChatScreen(service: widget.chat, profiles: widget.profiles),
    StatusTab(chat: widget.chat, profiles: widget.profiles),
    MapScreen(
      active: _index == AppShell.mapIndex,
      services: widget.map,
      listings: widget.listings,
      isMinor: _isMinor,
      profiles: widget.profiles,
      privacy: widget.privacy,
      social: widget.social,
    ),
    SaleAndSwapScreen(repository: widget.market, services: widget.map, social: widget.social),
    ProfileScreen(
      backend: widget.backend,
      onSignOut: widget.onSignOut,
      profile: widget.profile,
      profiles: widget.profiles,
      onProfileChanged: widget.onProfileChanged,
      privacy: widget.privacy,
      pushSettings: widget.pushSettings,
      security: widget.security,
      biometricLock: widget.biometricLock,
      contacts: widget.contacts,
      isAdmin: widget.isAdmin,
      market: widget.market,
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
    _attachChat();
    WidgetsBinding.instance.addObserver(this);
    PushNotifications.openChat.addListener(_openFromPush);
    PushNotifications.chatPings.addListener(_ping);
    PushNotifications.openNotification.addListener(_openNotificationFromPush);
    // App aperta toccando la notifica: la chat si apre appena la schermata è pronta.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openFromPush();
      _openNotificationFromPush();
    });
  }

  /// Notifica toccata (Fase 4, Blocco 5): si apre la chat giusta.
  void _openFromPush() {
    final String? id = PushNotifications.openChat.value;
    final ChatService? chat = widget.chat;
    if (id == null || chat == null || !mounted) return;
    PushNotifications.openChat.value = null;
    setState(() => _index = 0);
    openChatFromNotification(context, chat: chat, conversationId: id, profiles: widget.profiles);
  }

  /// Notifica di un commento o di uno scambio toccata: si apre il suo annuncio.
  void _openNotificationFromPush() {
    final String? id = PushNotifications.openNotification.value;
    if (id == null || widget.social == null || !mounted) return;
    PushNotifications.openNotification.value = null;
    _openNotifications(openId: id);
  }

  /// Messaggio arrivato con l'app aperta: la chat si aggiorna subito.
  void _ping() => widget.chat?.ping();

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    if (old.chat != widget.chat) {
      old.chat?.removeListener(_onChat);
      old.chat?.statuses?.removeListener(_onChat);
      old.chat?.calls?.removeListener(_onCall);
      _attachChat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushNotifications.openChat.removeListener(_openFromPush);
    PushNotifications.chatPings.removeListener(_ping);
    PushNotifications.openNotification.removeListener(_openNotificationFromPush);
    widget.chat?.removeListener(_onChat);
    widget.chat?.statuses?.removeListener(_onChat);
    widget.chat?.calls?.removeListener(_onCall);
    if (ChatRegistry.current == widget.chat) {
      ChatRegistry.current = null;
      ChatRegistry.profiles = null;
    }
    super.dispose();
  }

  /// La chat parte con l'app e la usano anche i pulsanti «Contatta» degli annunci.
  void _attachChat() {
    final ChatService? chat = widget.chat;
    ChatRegistry.current = chat;
    ChatRegistry.profiles = widget.profiles;
    if (chat == null) return;
    chat.addListener(_onChat);
    chat.statuses?.addListener(_onChat);
    chat.calls?.addListener(_onCall);
    chat.start();
    // GPS in tempo reale (Blocco 15): riprende l'invio se una condivisione è ancora attiva.
    final LiveLocationService? live = LiveRegistry.current;
    if (live != null) {
      live.localName = chat.localName;
      unawaited(live.refresh());
    }
  }

  /// C'è una chiamata (in arrivo o appena partita): si apre la schermata a tutto schermo.
  bool _callOpen = false;

  void _onCall() {
    final CallService? calls = widget.chat?.calls;
    if (calls == null || !calls.showing || _callOpen || !mounted) return;
    _callOpen = true;
    CallScreen.open(context, calls).whenComplete(() => _callOpen = false);
  }

  void _onChat() {
    if (mounted) setState(() {});
  }

  int get _statusUnseen => widget.chat?.statuses?.unseenCount ?? 0;

  int get _chatUnread {
    final ChatService? chat = widget.chat;
    return chat == null || !chat.ready ? 0 : chat.unreadTotal;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.chat?.setForeground(state == AppLifecycleState.resumed);
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

  Future<void> _openNotifications({String? openId}) async {
    final MarketRepository? market = widget.market;
    await NotificationsScreen.open(
      context,
      widget.social!,
      openId: openId,
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
            // Lente: cerca nelle chat (Chat) o negli annunci (Vendita), come nei mockup.
            if ((_index == 0 && widget.chat != null && widget.chat!.ready) || _index == 3) ...[
              _HeaderButton(
                key: const ValueKey<String>('cerca'),
                icon: Icons.search_rounded,
                tooltip: 'Cerca',
                onPressed: _index == 0
                    ? () => ChatSearchScreen.open(context, widget.chat!, profiles: widget.profiles)
                    : SaleAndSwapScreen.requestSearch,
              ),
              const SizedBox(width: 8),
            ],
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
                destinations: [
                  NavigationDestination(
                    icon: _ChatIcon(count: _chatUnread),
                    selectedIcon: _ChatIcon(count: _chatUnread, selected: true),
                    label: 'Chat',
                  ),
                  NavigationDestination(
                    icon: _StatusIcon(count: _statusUnseen),
                    selectedIcon: _StatusIcon(count: _statusUnseen, selected: true),
                    label: 'Stati',
                  ),
                  const NavigationDestination(
                    icon: _CenterButton(),
                    selectedIcon: _CenterButton(selected: true),
                    label: 'Mappa',
                  ),
                  const NavigationDestination(
                    icon: _NavIcon(Icons.sell_outlined),
                    selectedIcon: _NavIcon(Icons.sell_rounded, selected: true),
                    label: 'Vendita',
                  ),
                  const NavigationDestination(
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

/// Icona della Chat con il numero di messaggi non letti (e richieste in attesa).
class _ChatIcon extends StatelessWidget {
  const _ChatIcon({required this.count, this.selected = false});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final Widget icon = _NavIcon(
      selected ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
      selected: selected,
    );
    if (count <= 0) return icon;
    return Badge(
      key: const ValueKey<String>('chat_non_lette'),
      backgroundColor: AppColors.brandOrange,
      offset: const Offset(-6, -2),
      label: Text(count > 99 ? '99+' : '$count'),
      child: icon,
    );
  }
}

/// Pulsante tondo dell'intestazione, come la campanella.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.9),
        side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.10) : theme.colorScheme.outline),
        fixedSize: const Size(44, 44),
      ),
      icon: Icon(icon, color: theme.colorScheme.onSurface),
    );
  }
}

/// Icona degli Stati con il numero di persone che hanno aggiornamenti nuovi.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.count, this.selected = false});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final Widget icon = _NavIcon(
      selected ? Icons.motion_photos_on_rounded : Icons.motion_photos_on_outlined,
      selected: selected,
    );
    if (count <= 0) return icon;
    return Badge(
      key: const ValueKey<String>('stati_nuovi'),
      backgroundColor: AppColors.brandOrange,
      offset: const Offset(-6, -2),
      label: Text(count > 99 ? '99+' : '$count'),
      child: icon,
    );
  }
}

/// Pulsante centrale «Mappa»: cerchio arancio in rilievo con bagliore.
class _CenterButton extends StatelessWidget {
  const _CenterButton({this.selected = false});

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
        Icons.map_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

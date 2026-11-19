import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../../core/widgets/piazly_ui.dart';
import '../chat/chat_thread_screen.dart' show openChatWith;
import '../map/listing_models.dart' show GeoPoint, ListingPlace;
import '../map/listing_repository.dart' show ListingFailure;
import '../map/listing_share.dart' show ShareListing, shareWithSystem;
import '../map/listing_sheets.dart' show ReportListingForm;
import '../map/map_location.dart' show GeoFix, MapRules;
import '../map/map_surface.dart' show MapLibreSurface, MapSurfaceHandle;
import '../map/listing_social_panel.dart';
import '../map/social_models.dart' show ListingSocial;
import '../map/social_repository.dart';
import 'market_feedback.dart';
import 'market_models.dart';
import 'market_publish_screen.dart' show AntiScamNotice, MarketPhoto, MarketPublishScreen;
import 'market_repository.dart';
import 'my_market_screen.dart' show pickDealCandidate;
import '../profile/avatar_view.dart';
import 'swap_offer_screen.dart';

/// Testo condiviso di un annuncio di Scambia & Vendi: mai la posizione.
String marketShareText(MarketListing l) {
  final StringBuffer b = StringBuffer('«${l.title}»');
  final String price = l.priceLabel;
  if (price.isNotEmpty) b.write('\n$price');
  if (l.description.trim().isNotEmpty) b.write('\n${l.description.trim()}');
  b.write('\n\nL\'ho trovato su Piazly, nella sezione '
      '${l.type == MarketType.sell ? 'Vendita' : 'Scambia'}.');
  return b.toString();
}

/// Scheda di un annuncio di Scambia & Vendi (Blocco 2): foto, prezzo, condizioni, consegna,
/// avviso antitruffa, «Contatta», «Segnala», Mi piace, commenti, Condividi.
class MarketListingScreen extends StatefulWidget {
  const MarketListingScreen({
    super.key,
    required this.listing,
    required this.repository,
    required this.catalog,
    this.social,
    this.origin,
    this.share = shareWithSystem,
    this.now = DateTime.now,
  });

  /// Quello arrivato dalla ricerca: si mostra subito e si aggiorna dal server.
  final MarketListing listing;
  final MarketRepository repository;
  final MarketCatalog catalog;

  /// Mi piace e commenti (Fase 3, Blocco 4); null finché il server non c'è.
  final SocialRepository? social;

  /// Punto della ricerca, solo per la distanza.
  final GeoPoint? origin;
  final ShareListing share;
  final DateTime Function() now;

  @override
  State<MarketListingScreen> createState() => _MarketListingScreenState();
}

class _MarketListingScreenState extends State<MarketListingScreen> {
  late MarketListing _l = widget.listing;
  bool _gone = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final MarketListing? fresh = await widget.repository.listing(_l.id, origin: widget.origin);
      if (!mounted) return;
      setState(() {
        if (fresh == null) {
          _gone = true;
        } else {
          _l = fresh;
        }
      });
    } on ListingFailure {
      // Resta quello della ricerca.
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// «Contatta»: chat cifrata con l'autore (Fase 4, Blocco 1).
  Future<void> _contact() =>
      openChatWith(context, userId: _l.ownerId, name: _l.ownerPublicName);

  Future<void> _propose() async {
    final bool? sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SwapOfferScreen(
          repository: widget.repository,
          targetTitle: _l.title,
          cashAllowed: _l.cashAdjustment,
          targetListingId: _l.id,
        ),
      ),
    );
    if ((sent ?? false) && mounted) {
      _toast('Proposta inviata: la trovi in «Proposte di scambio».');
    }
  }

  Future<void> _report() async {
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ReportListingForm(listingId: _l.id, report: widget.repository.report),
      ),
    );
    if ((sent ?? false) && mounted) {
      _toast('Grazie: la segnalazione è stata inviata alla moderazione.');
    }
  }

  final PageController _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (!_pages.hasClients) return;
    unawaited(_pages.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOut));
  }

  // Azioni dell'autore, come in «I miei annunci».
  Future<void> _editMine() async {
    try {
      final List<MyMarketListing> mine = await widget.repository.mine();
      final MyMarketListing? m = mine.where((MyMarketListing x) => x.id == _l.id).firstOrNull;
      if (m == null || !mounted) return;
      final MarketPublishResult? r = await Navigator.of(context).push<MarketPublishResult>(
        MaterialPageRoute<MarketPublishResult>(
          builder: (_) => MarketPublishScreen(
            repository: widget.repository,
            catalog: widget.catalog,
            section: m.type == MarketType.sell ? MarketSection.sale : MarketSection.swap,
            existing: m,
          ),
        ),
      );
      if (r != null) await _refresh();
    } on ListingFailure catch (f) {
      _toast(f.message);
    }
  }

  Future<void> _concludeMine() async {
    try {
      final List<DealCandidate> people = await widget.repository.dealCandidates(_l.id);
      if (!mounted) return;
      final DealCandidate? who = await pickDealCandidate(context, people);
      if (who == null) return;
      await widget.repository.markConcluded(_l.id, who.id);
      _toast('Abbiamo chiesto a ${who.publicName} di confermare.');
    } on ListingFailure catch (f) {
      _toast(f.message);
    }
  }

  Future<void> _closeMine() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Chiudere l\'annuncio?'),
        content: const Text('Non sarà più visibile e non si potrà riaprire.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Chiudi')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repository.close(_l.id);
      if (!mounted) return;
      _toast('Annuncio chiuso.');
      Navigator.of(context).pop();
    } on ListingFailure catch (f) {
      _toast(f.message);
    }
  }

  Future<void> _showOnMap() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => _PointMapScreen(point: _l.point, title: _l.title)),
  );

  Widget _gallery(MarketListing l, ThemeData theme) {
    Widget arrow(IconData icon, VoidCallback onTap) => Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, color: PiazlyColors.violet)),
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 290,
              child: Stack(
                children: [
                  PageView(
                    key: const ValueKey<String>('scheda_foto'),
                    controller: _pages,
                    onPageChanged: (int i) => setState(() => _page = i),
                    children: [
                      for (final String p in l.photos) MarketPhoto(path: p, repository: widget.repository),
                    ],
                  ),
                  if (l.photos.length > 1) ...[
                    if (_page > 0)
                      Positioned(left: 10, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_left_rounded, () => _go(_page - 1)))),
                    if (_page < l.photos.length - 1)
                      Positioned(right: 10, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_right_rounded, () => _go(_page + 1)))),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 15),
                              const SizedBox(width: 5),
                              Text('${_page + 1}/${l.photos.length}',
                                  style: theme.textTheme.labelMedium?.copyWith(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (l.photos.length > 1)
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              itemCount: l.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (BuildContext c, int i) => GestureDetector(
                key: ValueKey<String>('miniatura_$i'),
                onTap: () => _go(i),
                child: Container(
                  width: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: i == _page ? AppColors.brandOrange : Colors.transparent, width: 3),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: MarketPhoto(path: l.photos[i], repository: widget.repository),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final MarketListing l = _l;
    final MarketCategory? sub = widget.catalog.byId(l.categoryId);
    final MarketCategory? main = sub == null ? null : widget.catalog.parentOf(sub);
    final List<MarketAttribute> attrs = MarketRules.attributesFor(main?.slug ?? '');
    final bool published = l.review == ReviewStatus.published;
    final DateTime now = widget.now();
    final int days = l.expiresAt.difference(now).inDays;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Row(children: [NexusMark(size: 32), SizedBox(width: 10), NexusWordmark()]),
        actions: [
          if (!l.isMine && !_gone)
            IconButton(
              key: const ValueKey<String>('scheda_segnala'),
              tooltip: 'Segnala',
              onPressed: _report,
              icon: const Icon(Icons.flag_outlined),
            ),
        ],
      ),
      body: _gone
          ? Center(
              key: const ValueKey<String>('annuncio_non_disponibile'),
              child: Padding(
                padding: AppSpacing.pagePadding,
                child: Text(
                  'Questo annuncio non è più disponibile.',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (l.photos.isNotEmpty) _gallery(l, theme),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!published)
                        Container(
                          key: const ValueKey<String>('scheda_in_revisione'),
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'In revisione: lo vedi solo tu finché la moderazione non lo approva.',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 3),
                            child: Icon(Icons.sell_outlined, color: AppColors.brandOrange),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(l.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                      if (sub != null && main != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 32),
                          child: Text(
                            '${main.name} › ${sub.name}',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (l.priceLabel.isNotEmpty)
                            Text(
                              l.priceLabel,
                              key: const ValueKey<String>('scheda_prezzo'),
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandOrangeDeep,
                              ),
                            ),
                          _Tag(text: l.type.label, color: PiazlyColors.violet, filled: true),
                          if (published) const _Tag(text: 'Attivo', color: PiazlyColors.green, icon: Icons.check_circle_rounded),
                          if (l.ownerIsBusiness) _Tag(text: 'Azienda', color: scheme.tertiary),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SoftCard(
                        tint: PiazlyColors.violetSoft,
                        margin: EdgeInsets.zero,
                        child: Row(
                          children: [
                            const Icon(Icons.event_rounded, color: PiazlyColors.violet, size: 30),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    days <= 0 ? 'Scade oggi' : days == 1 ? 'Scade tra 1 giorno' : 'Scade tra $days giorni',
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    _dates(l, now),
                                    key: const ValueKey<String>('scheda_date'),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (l.condition != null) _Info(icon: Icons.verified_outlined, text: l.condition!.label),
                          if (l.pickup) const _Info(icon: Icons.handshake_outlined, text: 'Ritiro a mano'),
                          if (l.ships) const _Info(icon: Icons.local_shipping_outlined, text: 'Spedizione'),
                          if (l.openToSwap) const _Info(icon: Icons.swap_horiz_rounded, text: 'Valuta anche scambi'),
                          if (l.cashAdjustment) const _Info(icon: Icons.euro_rounded, text: 'Accetta conguaglio'),
                        ],
                      ),
                      if (l.wantedInExchange != null)
                        _Section(icon: Icons.swap_horiz_rounded, title: 'Cerca in cambio', child: Text(l.wantedInExchange!)),
                      if (l.description.trim().isNotEmpty || l.attributes.isNotEmpty)
                        _Section(
                          icon: Icons.description_outlined,
                          title: 'Descrizione',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (l.description.trim().isNotEmpty) Text(l.description, style: theme.textTheme.bodyMedium),
                              for (final MarketAttribute a in attrs)
                                if (l.attributes[a.key] != null)
                                  Text('${a.label}: ${l.attributes[a.key]}', style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      _Section(
                        icon: Icons.location_on_outlined,
                        title: 'Posizione',
                        trailing: OutlinedButton.icon(
                          key: const ValueKey<String>('scheda_mappa'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: PiazlyColors.violet,
                            backgroundColor: PiazlyColors.violetSoft,
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: _showOnMap,
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('Mostra sulla mappa'),
                        ),
                        child: Text(
                          <String>[
                            l.place == ListingPlace.approximateZone ? 'Zona approssimata' : 'Punto scelto',
                            if (l.distanceBandMeters != null) marketDistanceLabel(l.distanceBandMeters!),
                          ].join(' · '),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SoftCard(
                        margin: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(
                          children: [
                            AvatarView(name: l.ownerPublicName, path: l.ownerAvatarThumbPath, size: 54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.ownerIsBusiness ? 'Azienda' : 'Venditore', style: theme.textTheme.bodySmall),
                                  Text(l.ownerPublicName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                  Text('@${l.ownerUsername}', style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                            if (!l.isMine)
                              OutlinedButton.icon(
                                key: const ValueKey<String>('scheda_contatta'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: PiazlyColors.violet,
                                  side: const BorderSide(color: PiazlyColors.violet),
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: _contact,
                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                label: const Text('Contatta'),
                              ),
                          ],
                        ),
                        // Media dei feedback sul profilo dei privati (PDF, Fase 5).
                        if (!l.ownerIsBusiness)
                          Padding(
                            padding: const EdgeInsets.only(left: 66, top: 2),
                            child: FeedbackSummaryTile(
                              repository: widget.repository,
                              userId: l.ownerId,
                              name: l.ownerPublicName,
                              dense: true,
                            ),
                          ),
                          ],
                        ),
                      ),
                      if (published && !l.isMine && l.swappable) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            key: const ValueKey<String>('scheda_proponi'),
                            onPressed: _propose,
                            icon: const Icon(Icons.swap_horiz_rounded),
                            label: const Text('Proponi uno scambio'),
                          ),
                        ),
                      ],
                      if (l.isMine) ...[
                        const SizedBox(height: 12),
                        Text(
                          'È un tuo annuncio: lo gestisci da qui o da «I miei annunci».',
                          key: const ValueKey<String>('annuncio_mio'),
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _OwnerAction(
                                key: const ValueKey<String>('scheda_modifica'),
                                icon: Icons.edit_outlined,
                                label: 'Modifica',
                                onTap: _editMine,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (published && l.type != MarketType.swap) ...[
                              Expanded(
                                child: _OwnerAction(
                                  key: const ValueKey<String>('scheda_concluso'),
                                  icon: Icons.handshake_outlined,
                                  label: 'Concluso con…',
                                  onTap: _concludeMine,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: _OwnerAction(
                                key: const ValueKey<String>('scheda_chiudi'),
                                icon: Icons.check_circle_outline_rounded,
                                label: 'Chiudi',
                                primary: true,
                                onTap: _closeMine,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      const AntiScamNotice(),
                      if (published) ...[
                        const SizedBox(height: AppSpacing.md),
                        ListingSocialPanel(
                          listing: SocialTarget(
                            id: l.id,
                            title: l.title,
                            isMine: l.isMine,
                            firstPhoto: l.photos.isEmpty ? null : l.photos.first,
                            shareText: (ListingSocial? _) => marketShareText(l),
                          ),
                          downloadPhoto: widget.repository.downloadPhoto,
                          social: widget.social,
                          share: widget.share,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _dates(MarketListing l, DateTime now) {
    final int days = l.expiresAt.difference(now).inDays;
    return 'Pubblicato il ${_date(l.createdAt)} · '
        '${days <= 0 ? 'scade oggi' : days == 1 ? 'scade tra 1 giorno' : 'scade tra $days giorni'}';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.filled = false, this.icon});

  final String text;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 4)],
          Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: filled ? Colors.white : color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Blocco con icona e titolo (Descrizione, Posizione).
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child, this.trailing});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: PiazlyColors.violet),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                DefaultTextStyle.merge(style: theme.textTheme.bodyMedium, child: child),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _OwnerAction extends StatelessWidget {
  const _OwnerAction({super.key, required this.icon, required this.label, required this.onTap, this.primary = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => SoftCard(
    margin: EdgeInsets.zero,
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    radius: 16,
    tint: primary ? AppColors.brandOrange : null,
    onTap: onTap,
    child: Column(
      children: [
        Icon(icon, color: primary ? Colors.white : AppColors.brandOrange),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w700, color: primary ? Colors.white : null),
        ),
      ],
    ),
  );
}

/// «Mostra sulla mappa»: il punto pubblico dell'annuncio (zona approssimata o punto scelto).
class _PointMapScreen extends StatelessWidget {
  const _PointMapScreen({required this.point, required this.title});

  final GeoPoint point;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: Stack(
      children: [
        Positioned.fill(
          child: MapLibreSurface(
            onReady: (MapSurfaceHandle h) => h.flyTo(
              GeoFix(latitude: point.latitude, longitude: point.longitude, time: DateTime.now()),
              threeD: false,
            ),
          ),
        ),
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(Icons.location_on_rounded, color: AppColors.brandOrange, size: 48),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: const SoftCard(
            margin: EdgeInsets.zero,
            child: Text(
              'La posizione è indicativa: per la tua sicurezza è una zona approssimata o il punto '
              'd\'incontro scelto da chi ha pubblicato.\n${MapRules.attribution}',
            ),
          ),
        ),
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: theme.textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}

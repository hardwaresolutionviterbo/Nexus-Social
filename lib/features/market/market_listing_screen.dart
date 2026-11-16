import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../map/listing_models.dart' show GeoPoint, ListingPlace;
import '../map/listing_repository.dart' show ListingFailure;
import '../map/listing_share.dart' show ShareListing, shareWithSystem;
import '../map/listing_sheets.dart' show ReportListingForm;
import '../map/listing_social_panel.dart';
import '../map/social_models.dart' show ListingSocial;
import '../map/social_repository.dart';
import 'market_models.dart';
import 'market_publish_screen.dart' show AntiScamNotice, MarketPhoto;
import 'market_repository.dart';
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

  Future<void> _contact() async {
    // La chat tra le parti arriva con la Fase 4 (decisione D2): intanto i commenti.
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Chat in arrivo'),
        content: Text(
          'Potrai scrivere a ${_l.ownerPublicName} quando sarà attiva la chat di Piazly. '
          'Intanto puoi chiedere informazioni nei commenti dell\'annuncio.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Ok')),
        ],
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final MarketListing l = _l;
    final MarketCategory? sub = widget.catalog.byId(l.categoryId);
    final MarketCategory? main = sub == null ? null : widget.catalog.parentOf(sub);
    final List<MarketAttribute> attrs = MarketRules.attributesFor(main?.slug ?? '');
    final bool published = l.review == ReviewStatus.published;
    return Scaffold(
      appBar: AppBar(title: Text(l.type == MarketType.sell ? 'Vendita' : 'Scambia')),
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
                if (l.photos.isNotEmpty)
                  SizedBox(
                    height: 300,
                    child: Stack(
                      children: [
                        PageView(
                          key: const ValueKey<String>('scheda_foto'),
                          onPageChanged: (int i) => setState(() => _page = i),
                          children: [
                            for (final String p in l.photos)
                              MarketPhoto(path: p, repository: widget.repository),
                          ],
                        ),
                        if (l.photos.length > 1)
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0x99000000),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                child: Text(
                                  '${_page + 1}/${l.photos.length}',
                                  style: theme.textTheme.labelMedium?.copyWith(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: AppSpacing.pagePadding,
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Tag(text: l.type.label, color: AppColors.brandOrange),
                          if (l.ownerIsBusiness) _Tag(text: 'Azienda', color: scheme.tertiary),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (l.priceLabel.isNotEmpty)
                        Text(
                          l.priceLabel,
                          key: const ValueKey<String>('scheda_prezzo'),
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      Text(l.title, style: theme.textTheme.titleLarge),
                      if (sub != null && main != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${main.name} › ${sub.name}',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (l.condition != null)
                            _Info(icon: Icons.verified_outlined, text: l.condition!.label),
                          if (l.pickup) const _Info(icon: Icons.handshake_outlined, text: 'Ritiro a mano'),
                          if (l.ships) const _Info(icon: Icons.local_shipping_outlined, text: 'Spedizione'),
                          if (l.openToSwap)
                            const _Info(icon: Icons.swap_horiz_rounded, text: 'Valuta anche scambi'),
                          if (l.cashAdjustment)
                            const _Info(icon: Icons.euro_rounded, text: 'Accetta conguaglio'),
                          _Info(
                            icon: Icons.place_outlined,
                            text: <String>[
                              l.place == ListingPlace.approximateZone ? 'Zona approssimata' : 'Punto scelto',
                              if (l.distanceBandMeters != null) marketDistanceLabel(l.distanceBandMeters!),
                            ].join(' · '),
                          ),
                        ],
                      ),
                      if (l.wantedInExchange != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text('Cerca in cambio', style: theme.textTheme.titleSmall),
                        Text(l.wantedInExchange!, style: theme.textTheme.bodyMedium),
                      ],
                      if (l.description.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text('Descrizione', style: theme.textTheme.titleSmall),
                        Text(l.description, style: theme.textTheme.bodyMedium),
                      ],
                      if (l.attributes.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        for (final MarketAttribute a in attrs)
                          if (l.attributes[a.key] != null)
                            Text('${a.label}: ${l.attributes[a.key]}', style: theme.textTheme.bodyMedium),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          CircleAvatar(
                            child: Text(l.ownerPublicName.isEmpty ? '?' : l.ownerPublicName[0].toUpperCase()),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.ownerPublicName, style: theme.textTheme.titleSmall),
                                Text('@${l.ownerUsername}', style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dates(l, widget.now()),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const AntiScamNotice(),
                      const SizedBox(height: AppSpacing.md),
                      if (l.isMine)
                        Text(
                          'È un tuo annuncio: lo gestisci da «I miei annunci».',
                          key: const ValueKey<String>('annuncio_mio'),
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                key: const ValueKey<String>('scheda_contatta'),
                                onPressed: _contact,
                                icon: const Icon(Icons.chat_bubble_outline_rounded),
                                label: const Text('Contatta'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            OutlinedButton.icon(
                              key: const ValueKey<String>('scheda_segnala'),
                              onPressed: _report,
                              icon: const Icon(Icons.flag_outlined),
                              label: const Text('Segnala'),
                            ),
                          ],
                        ),
                      if (published && !l.isMine && l.swappable) ...[
                        const SizedBox(height: AppSpacing.sm),
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
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
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

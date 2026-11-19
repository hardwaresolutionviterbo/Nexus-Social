import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../../core/widgets/piazly_ui.dart';
import '../map/listing_models.dart' show expiryLabel;
import '../map/listing_repository.dart' show ListingFailure;
import '../map/map_screen.dart' show MapServices;
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import 'market_models.dart';
import 'market_publish_screen.dart';
import 'market_repository.dart';

/// I miei annunci di Scambia & Vendi: stato, revisione, scadenza, Rinnova, Modifica, Chiudi.
class MyMarketScreen extends StatefulWidget {
  const MyMarketScreen({
    super.key,
    required this.repository,
    required this.catalog,
    this.section,
    this.services,
    this.pickImage = pickFromGallery,
    this.now = DateTime.now,
  });

  final MarketRepository repository;
  final MarketCatalog catalog;
  /// Solo una vetrina; null per tutti gli annunci (Scambia & Vendi).
  final MarketSection? section;
  final MapServices? services;
  final PickImage pickImage;
  final DateTime Function() now;

  @override
  State<MyMarketScreen> createState() => _MyMarketScreenState();
}

/// «Con chi l'hai concluso?»: chi ha commentato o fatto una proposta (D6).
Future<DealCandidate?> pickDealCandidate(BuildContext context, List<DealCandidate> people) =>
    showModalBottomSheet<DealCandidate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext ctx) => ListView(
        key: const ValueKey<String>('scegli_controparte'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Con chi l\'hai concluso?', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            people.isEmpty
                ? 'Nessuno ha ancora commentato o fatto una proposta su questo annuncio. Chiedi alla '
                      'persona di scriverti nei commenti, poi torna qui.'
                : 'Chi ha commentato o fatto una proposta. Riceverà la richiesta di conferma.',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final DealCandidate c in people)
            ListTile(
              key: ValueKey<String>('controparte_${c.id}'),
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(c.publicName.isEmpty ? '?' : c.publicName[0].toUpperCase())),
              title: Text(c.publicName),
              subtitle: Text('@${c.username}'),
              onTap: () => Navigator.of(ctx).pop(c),
            ),
        ],
      ),
    );

class _MyMarketScreenState extends State<MyMarketScreen> {
  List<MyMarketListing>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<MyMarketListing> all = await widget.repository.mine();
      if (!mounted) return;
      setState(() {
        _items = <MyMarketListing>[
          for (final MyMarketListing l in all)
            if (widget.section?.types.contains(l.type) ?? true) l,
        ];
        _error = null;
      });
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(done)));
      }
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _close(MyMarketListing l) async {
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
    if (ok ?? false) await _run(() => widget.repository.close(l.id), 'Annuncio chiuso.');
  }

  /// «Concluso con…»: l'autore indica la persona, che poi conferma (D6).
  Future<void> _conclude(MyMarketListing l) async {
    List<DealCandidate> people;
    try {
      people = await widget.repository.dealCandidates(l.id);
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
      return;
    }
    if (!mounted) return;
    final DealCandidate? who = await pickDealCandidate(context, people);
    if (who == null || !mounted) return;
    await _run(
      () => widget.repository.markConcluded(l.id, who.id),
      'Abbiamo chiesto a ${who.publicName} di confermare.',
    );
  }

  Future<void> _edit(MyMarketListing l) async {
    final MarketPublishResult? r = await Navigator.of(context).push<MarketPublishResult>(
      MaterialPageRoute<MarketPublishResult>(
        builder: (_) => MarketPublishScreen(
          repository: widget.repository,
          catalog: widget.catalog,
          section: widget.section ?? (l.type == MarketType.sell ? MarketSection.sale : MarketSection.swap),
          services: widget.services,
          existing: l,
          pickImage: widget.pickImage,
        ),
      ),
    );
    if (r != null) await _load();
  }

  String _q = '';
  _MineFilter _filter = _MineFilter.all;

  Widget _action({Key? key, required IconData icon, required String label, required VoidCallback onTap}) => Expanded(
    child: InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: AppColors.brandOrange),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.brandOrangeDeep, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ),
  );

  Widget _card(MyMarketListing l, DateTime now) {
    final ThemeData theme = Theme.of(context);
    final bool canConclude = l.state == MarketListingState.active &&
        l.review == ReviewStatus.published &&
        l.type != MarketType.swap;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 108,
                  height: 108,
                  child: l.photos.isEmpty
                      ? const ColoredBox(
                          color: PiazlyColors.orangeSoft,
                          child: Icon(Icons.image_outlined, color: AppColors.brandOrange, size: 34),
                        )
                      : MarketPhoto(path: l.photos.first, repository: widget.repository),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    if (l.priceCents != null)
                      Text(
                        MarketRules.formatPrice(l.priceCents!),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppColors.brandOrangeDeep,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Tag(l.type.label, AppColors.brandCyan),
                        _Tag(
                          l.state.label,
                          l.state == MarketListingState.active ? AppColors.brandMint : theme.colorScheme.outline,
                        ),
                        if (l.review == ReviewStatus.pendingReview) const _Tag('In revisione', AppColors.brandAmber),
                        if (l.review == ReviewStatus.rejected) _Tag('Rifiutato', theme.colorScheme.error),
                      ],
                    ),
                    if (l.editable) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.event_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 5),
                          Expanded(child: Text(expiryLabel(l.expiresAt, now), style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (l.editable) ...[
            const Divider(height: 18),
            Row(
              children: [
                if (l.canRenew(now))
                  _action(
                    key: ValueKey<String>('rinnova_${l.id}'),
                    icon: Icons.autorenew_rounded,
                    label: 'Rinnova',
                    onTap: () => _run(() => widget.repository.renew(l.id), 'Rinnovato per altri 30 giorni.'),
                  ),
                _action(icon: Icons.edit_outlined, label: 'Modifica', onTap: () => _edit(l)),
                if (canConclude)
                  _action(
                    key: ValueKey<String>('concludi_${l.id}'),
                    icon: Icons.handshake_outlined,
                    label: 'Concluso con…',
                    onTap: () => _conclude(l),
                  ),
                _action(icon: Icons.check_circle_outline, label: 'Chiudi', onTap: () => _close(l)),
              ],
            ),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MyMarketListing>? items = _items;
    final DateTime now = widget.now();
    final String q = _q.trim().toLowerCase();
    final List<MyMarketListing> shown = <MyMarketListing>[
      for (final MyMarketListing l in items ?? const <MyMarketListing>[])
        if ((q.isEmpty || l.title.toLowerCase().contains(q)) &&
            switch (_filter) {
              _MineFilter.all => true,
              _MineFilter.active => l.state == MarketListingState.active,
              _MineFilter.done => l.state != MarketListingState.active,
            })
          l,
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Row(children: [NexusMark(size: 32), SizedBox(width: 10), NexusWordmark()]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('I miei annunci', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            widget.section == MarketSection.swap
                ? 'Gestisci i tuoi annunci di scambio'
                : widget.section == MarketSection.sale
                ? 'Gestisci i tuoi annunci di vendita'
                : 'Gestisci i tuoi annunci di vendita e scambio',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey<String>('miei_cerca'),
            onChanged: (String v) => setState(() => _q = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Cerca tra i miei annunci…',
              filled: true,
              fillColor: theme.colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
          ),
          PillTabs<_MineFilter>(
            padding: const EdgeInsets.symmetric(vertical: 12),
            tabs: const <PillTab<_MineFilter>>[
              PillTab<_MineFilter>(value: _MineFilter.all, label: 'Tutti', key: ValueKey<String>('miei_tutti')),
              PillTab<_MineFilter>(value: _MineFilter.active, label: 'Attivi', key: ValueKey<String>('miei_attivi')),
              PillTab<_MineFilter>(value: _MineFilter.done, label: 'Conclusi', key: ValueKey<String>('miei_conclusi')),
            ],
            selected: _filter,
            onChanged: (_MineFilter f) => setState(() => _filter = f),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (items == null && _error == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                items == null || items.isEmpty ? 'Non hai ancora annunci qui.' : 'Nessun annuncio con questi filtri.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final MyMarketListing l in shown) _card(l, now),
        ],
      ),
    );
  }
}

enum _MineFilter { all, active, done }

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

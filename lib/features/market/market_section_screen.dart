import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../map/listing_repository.dart' show ListingFailure;
import '../map/map_screen.dart' show MapServices;
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import 'category_picker.dart';
import 'market_catalog_data.dart';
import 'market_models.dart';
import 'market_publish_screen.dart';
import 'market_repository.dart';
import 'my_market_screen.dart';

/// Sezioni «Scambia» e «Vendita» (D10): un solo sistema di annunci, due vetrine.
/// Blocco 1: pubblicare e gestire i propri annunci. La ricerca arriva con il Blocco 2.
class MarketSectionScreen extends StatefulWidget {
  const MarketSectionScreen({
    super.key,
    required this.section,
    this.repository,
    this.services,
    this.pickImage = pickFromGallery,
  });

  final MarketSection section;

  /// null finché il server non è collegato.
  final MarketRepository? repository;
  final MapServices? services;
  final PickImage pickImage;

  @override
  State<MarketSectionScreen> createState() => _MarketSectionScreenState();
}

class _MarketSectionScreenState extends State<MarketSectionScreen> {
  MarketCatalog? _catalog;

  /// Catalogo dal server (stato attivo aggiornato); se non arriva, quello dell'app.
  Future<MarketCatalog> _ensureCatalog() async {
    final MarketCatalog? c = _catalog;
    if (c != null) return c;
    List<MarketCategory> list = builtInMarketCatalog;
    try {
      final List<MarketCategory> remote = await widget.repository!.categories();
      if (remote.isNotEmpty) list = remote;
    } on ListingFailure {
      // Si usa il catalogo incluso nell'app.
    }
    return _catalog = MarketCatalog(list);
  }

  bool _serverReady() {
    if (widget.repository != null) return true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Per pubblicare serve il collegamento al server: si attiverà con il piano Blaze.',
          ),
        ),
      );
    return false;
  }

  Future<void> _publish() async {
    if (!_serverReady()) return;
    final MarketCatalog catalog = await _ensureCatalog();
    if (!mounted) return;
    final MarketPublishResult? r = await Navigator.of(context).push<MarketPublishResult>(
      MaterialPageRoute<MarketPublishResult>(
        builder: (_) => MarketPublishScreen(
          repository: widget.repository!,
          catalog: catalog,
          section: widget.section,
          services: widget.services,
          pickImage: widget.pickImage,
        ),
      ),
    );
    if (r == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            r.pendingReview
                ? 'Annuncio inviato: lo vedranno gli altri dopo il controllo della moderazione.'
                : 'Annuncio pubblicato.',
          ),
        ),
      );
  }

  Future<void> _mine() async {
    if (!_serverReady()) return;
    final MarketCatalog catalog = await _ensureCatalog();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MyMarketScreen(
          repository: widget.repository!,
          catalog: catalog,
          section: widget.section,
          services: widget.services,
          pickImage: widget.pickImage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MarketCatalog preview = _catalog ?? MarketCatalog(builtInMarketCatalog);
    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        Text(widget.section.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          widget.section == MarketSection.swap
              ? 'Scambia, regala o cerca oggetti vicino a te. Sempre gratis.'
              : 'Vendi tra privati vicino a te. Gratis, senza commissioni.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: ValueKey<String>('pubblica_${widget.section.name}'),
                onPressed: _publish,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Pubblica'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _mine,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('I miei annunci'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const AntiScamNotice(),
        const SizedBox(height: AppSpacing.lg),
        Text('Categorie', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MarketCategory c in preview.mains)
              Chip(
                avatar: Icon(marketCategoryIcon(c.slug), size: 18),
                label: Text(c.name),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'La ricerca degli annunci vicino a te, con filtri e ordinamenti, arriva con il '
          'prossimo aggiornamento.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

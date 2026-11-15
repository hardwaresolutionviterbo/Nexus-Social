import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import 'listing_form_screen.dart';
import 'listing_models.dart';
import 'listing_repository.dart';
import 'map_surface.dart';

/// Gestione dei propri annunci della Mappa: stato, scadenza, modalità di posizione,
/// «Modifica» e «Chiudi» (Fase 3, Blocco 2).
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({
    super.key,
    required this.repository,
    required this.surface,
    this.currentPosition,
    this.isMinor = false,
    this.pickImage = pickFromGallery,
    this.now = DateTime.now,
  });

  final MapListingRepository repository;
  final MapSurfaceBuilder surface;
  final GeoPoint? currentPosition;
  final bool isMinor;
  final PickImage pickImage;
  final DateTime Function() now;

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  List<MyListing>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<MyListing> items = await widget.repository.mine();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _edit(MyListing item) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ListingFormScreen(
          repository: widget.repository,
          surface: widget.surface,
          currentPosition: widget.currentPosition,
          isMinor: widget.isMinor,
          existing: item,
          pickImage: widget.pickImage,
          now: widget.now,
        ),
      ),
    );
    if (saved ?? false) await _load();
  }

  Future<void> _close(MyListing item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Chiudere l\'annuncio?'),
        content: const Text('Sparisce dalla mappa e non si potrà riaprire.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Chiudi')),
        ],
      ),
    );
    if (!(confirm ?? false)) return;
    try {
      await widget.repository.close(item.id);
      await _load();
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _setAvailable(MyListing item, bool value) async {
    try {
      await widget.repository.setAvailableNow(item.id, value);
      if (!mounted) return;
      setState(() {
        _items = <MyListing>[
          for (final MyListing x in _items ?? const <MyListing>[])
            x.id == item.id ? x.copyWith(availableNow: value) : x,
        ];
      });
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MyListing>? items = _items;
    Widget body;
    if (items == null && _error == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items == null || items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            _error ?? 'Non hai ancora pubblicato annunci.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            for (final MyListing item in items)
              _ListingCard(
                item: item,
                now: widget.now(),
                repository: widget.repository,
                onEdit: () => _edit(item),
                onClose: () => _close(item),
                onAvailable: (bool v) => _setAvailable(item, v),
              ),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('I miei annunci')), body: body);
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.item,
    required this.now,
    required this.repository,
    required this.onEdit,
    required this.onClose,
    required this.onAvailable,
  });

  final MyListing item;
  final DateTime now;
  final MapListingRepository repository;
  final VoidCallback onEdit;
  final VoidCallback onClose;
  final ValueChanged<bool> onAvailable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool active = item.editable;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.photos.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: ListingPhotoView(path: item.photos.first, repository: repository),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Tag(
                            text: item.state.label,
                            color: active ? AppColors.brandMint : scheme.outline,
                          ),
                          _Tag(
                            text: item.place.title,
                            color: item.place == ListingPlace.chosenPoint
                                ? AppColors.brandAmber
                                : AppColors.brandCyan,
                          ),
                        ],
                      ),
                      if (active) ...[
                        const SizedBox(height: 4),
                        Text(
                          expiryLabel(item.expiresAt, now),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (active)
              SwitchListTile(
                key: ValueKey<String>('disponibile_${item.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Disponibile ora'),
                subtitle: const Text('Mostra agli altri che sei pronto a vederti adesso'),
                value: item.availableNow,
                onChanged: onAvailable,
              ),
            if (active)
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifica'),
                  ),
                  TextButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Chiudi'),
                  ),
                ],
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
}

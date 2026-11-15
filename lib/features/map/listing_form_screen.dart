import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import 'listing_models.dart';
import 'listing_repository.dart';
import 'map_surface.dart';
import 'point_picker_screen.dart';
import 'safety_notice.dart';

/// Pubblicazione e modifica di un annuncio della Mappa (Fase 3, Blocco 2).
///
/// - Categoria «Libera»: testo libero, gratuito (decisione del titolare).
/// - Foto facoltative (fino a 4), scadenza da 1 ora a 7 giorni (T5).
/// - Luogo: zona approssimata preselezionata oppure punto scelto a mano (P9); la modalità
///   attiva è sempre scritta sopra il pulsante di pubblicazione.
/// - Minorenni: prima di pubblicare un punto preciso si ripete l'avviso di sicurezza (M3).
class ListingFormScreen extends StatefulWidget {
  const ListingFormScreen({
    super.key,
    required this.repository,
    required this.surface,
    this.currentPosition,
    this.isMinor = false,
    this.existing,
    this.pickImage = pickFromGallery,
    this.now = DateTime.now,
  });

  final MapListingRepository repository;
  final MapSurfaceBuilder surface;

  /// Ultima posizione del telefono ricevuta dalla Mappa (resta sul telefono fino alla
  /// pubblicazione; il server la conserva privata e mostra solo la zona).
  final GeoPoint? currentPosition;
  final bool isMinor;

  /// Annuncio da modificare; null per un annuncio nuovo.
  final MyListing? existing;
  final PickImage pickImage;
  final DateTime Function() now;

  @override
  State<ListingFormScreen> createState() => _ListingFormScreenState();
}

/// Una foto del modulo: già pubblicata (percorso) oppure appena scelta (byte).
class _Photo {
  const _Photo.kept(this.path) : bytes = null;
  const _Photo.added(this.bytes) : path = null;

  final String? path;
  final Uint8List? bytes;
}

class _ListingFormScreenState extends State<ListingFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _details;
  late ListingPlace _place;
  GeoPoint? _chosenPoint;

  /// null in modifica = scadenza lasciata com'è.
  ListingExpiry? _expiry;
  final List<_Photo> _photos = <_Photo>[];
  bool _busy = false;
  String? _error;
  String? _titleError;

  MyListing? get _existing => widget.existing;
  bool get _editing => _existing != null;

  @override
  void initState() {
    super.initState();
    final MyListing? e = _existing;
    _title = TextEditingController(text: e?.title ?? '');
    _details = TextEditingController(text: e?.details ?? '');
    _place = e?.place ?? ListingPlace.approximateZone;
    _chosenPoint = e != null && e.place == ListingPlace.chosenPoint ? e.savedPoint : null;
    _expiry = e == null ? ListingExpiry.threeHours : null;
    if (e != null) _photos.addAll(e.photos.map(_Photo.kept));
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  GeoPoint? get _point => switch (_place) {
    ListingPlace.approximateZone => widget.currentPosition ?? _existing?.savedPoint,
    ListingPlace.chosenPoint => _chosenPoint,
  };

  Future<void> _addPhoto() async {
    final Uint8List? bytes = await widget.pickImage();
    if (bytes == null || !mounted) return;
    setState(() => _photos.add(_Photo.added(bytes)));
  }

  Future<void> _choosePoint() async {
    final GeoPoint? picked = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute<GeoPoint>(
        builder: (_) => PointPickerScreen(
          surface: widget.surface,
          start: _chosenPoint ?? widget.currentPosition,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _chosenPoint = picked;
      _place = ListingPlace.chosenPoint;
      _error = null;
    });
  }

  Future<bool> _minorSafetyCheck() async {
    if (!widget.isMinor || _place != ListingPlace.chosenPoint) return true;
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
        child: SafetyNoticeCard(onAcknowledge: () => Navigator.of(ctx).pop(true)),
      ),
    );
    return ok ?? false;
  }

  Future<void> _submit() async {
    final String? titleError = ListingRules.titleError(_title.text);
    final String? detailsError = ListingRules.detailsError(_details.text);
    setState(() {
      _titleError = titleError;
      _error = detailsError;
    });
    if (titleError != null || detailsError != null) return;
    final GeoPoint? point = _point;
    if (point == null) {
      setState(() {
        _error = _place == ListingPlace.chosenPoint
            ? 'Scegli il punto sulla mappa.'
            : 'Posizione non disponibile: consenti la posizione dalla Mappa oppure scegli '
                  'un punto sulla mappa.';
      });
      return;
    }
    if (!await _minorSafetyCheck() || !mounted) return;

    final DateTime expiresAt =
        _expiry?.resolve(widget.now()) ?? _existing?.expiresAt ?? widget.now();
    final ListingDraft draft = ListingDraft(
      title: _title.text.trim(),
      details: _details.text.trim(),
      expiresAt: expiresAt,
      place: _place,
      point: point,
      keptPhotos: <String>[for (final _Photo p in _photos) if (p.path != null) p.path!],
      newPhotos: <Uint8List>[for (final _Photo p in _photos) if (p.bytes != null) p.bytes!],
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final MyListing? e = _existing;
      if (e == null) {
        await widget.repository.publish(draft);
      } else {
        await widget.repository.update(e.id, draft);
        if (draft.place != e.place || draft.point != e.savedPoint) {
          await widget.repository.move(e.id, draft.point, draft.place);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Modifica annuncio' : 'Nuovo annuncio')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  avatar: Icon(Icons.local_offer_outlined, size: 18, color: scheme.primary),
                  label: const Text('Libera · gratuito'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey<String>('annuncio_testo'),
              controller: _title,
              maxLength: ListingRules.titleMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Cosa proponi?',
                hintText: 'Es. Chi viene a prendere un caffè? · Ci manca uno per il calcetto',
                errorText: _titleError,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey<String>('annuncio_dettagli'),
              controller: _details,
              maxLength: ListingRules.detailsMax,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Dettagli (facoltativo)'),
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionTitle('Foto (facoltative, fino a ${ListingRules.maxPhotos})'),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (int i = 0; i < _photos.length; i++)
                    _PhotoTile(
                      photo: _photos[i],
                      repository: widget.repository,
                      onRemove: () => setState(() => _photos.removeAt(i)),
                    ),
                  if (_photos.length < ListingRules.maxPhotos)
                    _AddPhotoTile(onTap: _busy ? null : _addPhoto),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _SectionTitle('Scadenza'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (_editing)
                  ChoiceChip(
                    label: const Text('Lascia com\'è'),
                    selected: _expiry == null,
                    onSelected: (_) => setState(() => _expiry = null),
                  ),
                for (final ListingExpiry e in ListingExpiry.values)
                  ChoiceChip(
                    label: Text(e.label),
                    selected: _expiry == e,
                    onSelected: (_) => setState(() => _expiry = e),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const _SectionTitle('Dove mostrarlo'),
            const SizedBox(height: AppSpacing.sm),
            _PlaceOption(
              key: const ValueKey<String>('luogo_zona'),
              place: ListingPlace.approximateZone,
              selected: _place == ListingPlace.approximateZone,
              badge: 'Consigliata',
              warning: widget.currentPosition == null && !_editing
                  ? 'Serve la posizione: consentila dalla Mappa.'
                  : null,
              onTap: () => setState(() {
                _place = ListingPlace.approximateZone;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
            _PlaceOption(
              key: const ValueKey<String>('luogo_punto'),
              place: ListingPlace.chosenPoint,
              selected: _place == ListingPlace.chosenPoint,
              trailing: TextButton(
                onPressed: _busy ? null : _choosePoint,
                child: Text(_chosenPoint == null ? 'Scegli il punto' : 'Cambia punto'),
              ),
              onTap: () {
                if (_chosenPoint == null) {
                  _choosePoint();
                } else {
                  setState(() => _place = ListingPlace.chosenPoint);
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _ActiveModeBanner(place: _place, ready: _point != null),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                key: const ValueKey<String>('annuncio_errore'),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey<String>('annuncio_pubblica'),
                onPressed: _busy ? null : _submit,
                child: Text(_busy
                    ? 'Attendi…'
                    : _editing
                    ? 'Salva le modifiche'
                    : 'Pubblica'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);
}

class _PlaceOption extends StatelessWidget {
  const _PlaceOption({
    super.key,
    required this.place,
    required this.selected,
    required this.onTap,
    this.badge,
    this.warning,
    this.trailing,
  });

  final ListingPlace place;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  final String? warning;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? scheme.primary : scheme.outline, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(place.title, style: theme.textTheme.titleSmall),
                        if (badge != null)
                          Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(color: scheme.secondary),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(place.explanation, style: theme.textTheme.bodySmall),
                    if (warning != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        warning!,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                      ),
                    ],
                    if (trailing != null) Align(alignment: Alignment.centerLeft, child: trailing),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La modalità di posizione attiva, sempre visibile prima di pubblicare.
class _ActiveModeBanner extends StatelessWidget {
  const _ActiveModeBanner({required this.place, required this.ready});

  final ListingPlace place;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool zone = place == ListingPlace.approximateZone;
    return Container(
      key: const ValueKey<String>('modalita_attiva'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (zone ? AppColors.brandMint : AppColors.brandAmber).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(zone ? Icons.blur_on_rounded : Icons.place_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Modalità di posizione: ${place.title}'
              '${ready ? '' : ' (da completare)'}',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const ValueKey<String>('aggiungi_foto'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 92,
            height: 92,
            child: Icon(Icons.add_a_photo_outlined, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.repository, required this.onRemove});

  final _Photo photo;
  final MapListingRepository repository;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final Widget image = photo.bytes != null
        ? Image.memory(photo.bytes!, fit: BoxFit.cover, errorBuilder: _broken)
        : ListingPhotoView(path: photo.path!, repository: repository);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(width: 92, height: 92, child: image),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton.filledTonal(
              tooltip: 'Togli la foto',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _broken(BuildContext context, Object error, StackTrace? stack) =>
      const ColoredBox(color: Color(0x22000000), child: Icon(Icons.image_not_supported_outlined));
}

/// Foto di un annuncio scaricata dal server.
class ListingPhotoView extends StatelessWidget {
  const ListingPhotoView({super.key, required this.path, required this.repository});

  final String path;
  final MapListingRepository repository;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: repository.downloadPhoto(path),
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
        final Uint8List? bytes = snap.data;
        if (bytes == null) {
          return const ColoredBox(color: Color(0x14000000), child: SizedBox.expand());
        }
        return Image.memory(bytes, fit: BoxFit.cover, errorBuilder: _PhotoTile._broken);
      },
    );
  }
}

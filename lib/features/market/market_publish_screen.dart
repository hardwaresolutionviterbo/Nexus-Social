import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/piazly_ui.dart';
import '../map/listing_models.dart' show GeoPoint, ListingPlace;
import '../map/listing_repository.dart' show ListingFailure;
import '../map/map_location.dart';
import '../map/map_screen.dart' show MapServices;
import '../map/point_picker_screen.dart';
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import 'category_picker.dart';
import 'comune_picker_screen.dart';
import 'comuni_italia.dart';
import 'market_models.dart';
import 'market_repository.dart';

/// Elenco dei divieti (specifica del titolare, sezione 9), sempre consultabile.
const List<String> marketProhibitedItems = <String>[
  'Armi e munizioni non autorizzate',
  'Droghe e sostanze illegali',
  'Farmaci soggetti a prescrizione',
  'Prodotti contraffatti',
  'Beni rubati',
  'Prodotti pericolosi o vietati dalla normativa',
  'Animali vivi (solo accessori e attrezzature)',
  'Altri beni proibiti dalle leggi applicabili',
];

/// Pubblicazione e modifica di un annuncio di Scambia & Vendi (Fase 5, Blocco 1).
class MarketPublishScreen extends StatefulWidget {
  const MarketPublishScreen({
    super.key,
    required this.repository,
    required this.catalog,
    required this.section,
    this.services,
    this.existing,
    this.pickImage = pickFromGallery,
  });

  final MarketRepository repository;
  final MarketCatalog catalog;
  final MarketSection section;

  /// Posizione e mappa del telefono (per la zona approssimata e il punto scelto).
  final MapServices? services;
  final MyMarketListing? existing;
  final PickImage pickImage;

  @override
  State<MarketPublishScreen> createState() => _MarketPublishScreenState();
}

class _Photo {
  const _Photo.kept(this.path) : bytes = null;
  const _Photo.added(this.bytes) : path = null;

  final String? path;
  final Uint8List? bytes;
}

class _MarketPublishScreenState extends State<MarketPublishScreen> {
  late MarketType _type;
  MarketCategory? _sub;
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _wanted = TextEditingController();
  final Map<String, TextEditingController> _attr = <String, TextEditingController>{};
  ItemCondition? _condition;
  bool _ships = false;
  bool _pickup = true;
  bool _openToSwap = false;
  bool _cash = false;
  final List<_Photo> _photos = <_Photo>[];
  ListingPlace _place = ListingPlace.approximateZone;
  GeoPoint? _here;
  GeoPoint? _chosen;

  /// Località dell'annuncio: un comune d'Italia (richiesta del titolare, 19/11/2026). Il punto
  /// pubblico è il centro del comune, oppure un punto d'incontro scelto a mano.
  Comune? _comune;
  bool _locating = false;
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  MyMarketListing? get _existing => widget.existing;

  /// Il conguaglio vale per lo Scambio e per la Vendita che accetta scambi.
  bool get _cashAllowed =>
      _type == MarketType.swap || (_type == MarketType.sell && _openToSwap);
  bool get _editing => _existing != null;

  @override
  void initState() {
    super.initState();
    _type = widget.section.types.first;
    final MyMarketListing? e = _existing;
    if (e != null) {
      _type = e.type;
      _sub = widget.catalog.byId(e.categoryId);
      _title.text = e.title;
      _description.text = e.description;
      if (e.priceCents != null) _price.text = (e.priceCents! / 100).toStringAsFixed(2).replaceAll('.', ',');
      _wanted.text = e.wantedInExchange ?? '';
      _condition = e.condition;
      _ships = e.ships;
      _pickup = e.pickup;
      _openToSwap = e.openToSwap;
      _cash = e.cashAdjustment;
      _photos.addAll(e.photos.map(_Photo.kept));
      _place = e.place;
      _here = e.savedPoint;
      if (e.place == ListingPlace.chosenPoint) _chosen = e.savedPoint;
      final GeoPoint saved = e.savedPoint;
      ComuniItalia.load().then((ComuniItalia d) {
        if (!mounted) return;
        final Comune c = d.nearest(saved);
        setState(() {
          _comune = c;
          // Se il punto salvato è proprio il centro del comune, non è un punto d'incontro.
          if (c.point == saved) _place = ListingPlace.approximateZone;
        });
      });
      for (final MapEntry<String, Object> a in e.attributes.entries) {
        _attr[a.key] = TextEditingController(text: '${a.value}');
      }
      _confirmed = true;
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _title,
      _description,
      _price,
      _wanted,
      ..._attr.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _mainSlug {
    final MarketCategory? s = _sub;
    return s == null ? null : widget.catalog.parentOf(s)?.slug;
  }

  bool get _objectFields =>
      _type != MarketType.wanted && !MarketRules.noObjectFields(_mainSlug ?? '');

  TextEditingController _attrController(String key) =>
      _attr.putIfAbsent(key, TextEditingController.new);

  Future<void> _chooseCategory() async {
    final MarketCategory? current = _sub;
    final MarketCategory? s = await pickMarketCategory(
      context,
      widget.catalog,
      initialMainId: current?.parentId,
    );
    if (s == null || !mounted) return;
    setState(() {
      _sub = s;
      _error = null;
    });
  }

  Future<void> _addPhoto() async {
    final Uint8List? bytes = await widget.pickImage();
    if (bytes == null || !mounted) return;
    setState(() => _photos.add(_Photo.added(bytes)));
  }

  /// Posizione attuale una volta sola, per la zona approssimata.
  Future<void> _locate() async {
    final MapServices? s = widget.services;
    if (s == null) return;
    setState(() => _locating = true);
    try {
      LocationAccess access = await s.location.status();
      if (access == LocationAccess.denied) access = await s.location.request();
      if (access != LocationAccess.granted) {
        setState(() => _error = 'Consenti la posizione oppure scegli un punto sulla mappa.');
        return;
      }
      final GeoFix fix = await s.location.fixes().first.timeout(const Duration(seconds: 20));
      final GeoPoint here = GeoPoint(fix.latitude, fix.longitude);
      final ComuniItalia d = await ComuniItalia.load();
      if (mounted) {
        setState(() {
          _here = here;
          _comune = d.nearest(here);
        });
      }
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Posizione non trovata: riprova o scegli un punto.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _choosePoint() async {
    final MapServices? s = widget.services;
    if (s == null) return;
    final GeoPoint? p = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute<GeoPoint>(
        builder: (_) => PointPickerScreen(surface: s.surface, start: _chosen ?? _here),
      ),
    );
    if (p == null || !mounted) return;
    setState(() {
      _chosen = p;
      _place = ListingPlace.chosenPoint;
    });
  }

  /// Controlli dell'app: gli stessi del server, per dire subito cosa manca.
  String? _validate(Map<String, Object> attributes, int? priceCents) {
    final MarketCategory? sub = _sub;
    if (sub == null) return 'Scegli la categoria e la sottocategoria.';
    final int t = _title.text.trim().length;
    if (t < MarketRules.titleMin || t > MarketRules.titleMax) {
      return 'Il titolo deve avere da 3 a 120 caratteri.';
    }
    if (_type.priceRequired && priceCents == null) return 'Per la vendita il prezzo è obbligatorio.';
    if (_type.photosRequired && _photos.isEmpty) return 'Aggiungi almeno una foto.';
    if (_objectFields && _condition == null) return 'Indica le condizioni dell\'oggetto.';
    if (_objectFields && !_ships && !_pickup) return 'Scegli ritiro a mano, spedizione o entrambi.';
    for (final String key in MarketRules.requiredAttributes(sub, _mainSlug!, _type)) {
      if (!attributes.containsKey(key)) {
        final String label = MarketRules.attributesFor(_mainSlug!)
            .firstWhere((MarketAttribute a) => a.key == key)
            .label;
        return 'Indica il campo «$label».';
      }
    }
    if (_comune == null) return 'Scegli il comune dell\'annuncio, o tocca «Usa la mia posizione».';
    if (_place == ListingPlace.chosenPoint && _chosen == null) return 'Scegli il punto d\'incontro sulla mappa.';
    if (!_confirmed) return 'Conferma che non pubblichi prodotti vietati.';
    return null;
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    int? priceCents;
    final Map<String, Object> attributes = <String, Object>{};
    try {
      priceCents = _type.priceAllowed ? MarketRules.parsePriceCents(_price.text) : null;
      for (final MarketAttribute a in MarketRules.attributesFor(_mainSlug ?? '')) {
        final String v = _attrController(a.key).text.trim();
        if (v.isEmpty) continue;
        if (a.numeric) {
          final int? n = int.tryParse(v.replaceAll('.', ''));
          if (n == null || (a.min != null && n < a.min!) || (a.max != null && n > a.max!)) {
            throw FormatException('${a.label} non valido');
          }
          attributes[a.key] = n;
        } else {
          attributes[a.key] = v;
        }
      }
    } on FormatException catch (e) {
      setState(() => _error = '${e.message}.');
      return;
    }
    final String? problem = _validate(attributes, priceCents);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final MarketDraft draft = MarketDraft(
      type: _type,
      categoryId: _sub!.id,
      title: _title.text.trim(),
      description: _description.text.trim(),
      priceCents: priceCents,
      condition: _objectFields ? _condition : null,
      ships: _objectFields && _ships,
      pickup: _objectFields && _pickup,
      attributes: attributes,
      // Sempre «preciso» per il server: il punto è il centro del comune (pubblico) o il punto
      // d'incontro scelto; la posizione del telefono non si invia mai.
      place: ListingPlace.chosenPoint,
      point: _place == ListingPlace.chosenPoint ? _chosen! : _comune!.point,
      keptPhotos: <String>[for (final _Photo p in _photos) if (p.path != null) p.path!],
      newPhotos: <Uint8List>[for (final _Photo p in _photos) if (p.bytes != null) p.bytes!],
      wantedInExchange: _type == MarketType.swap ? _wanted.text : null,
      noProhibitedItems: _confirmed,
      openToSwap: _type == MarketType.sell && _openToSwap,
      cashAdjustment: _cashAllowed && _cash,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final MyMarketListing? e = _existing;
      final MarketPublishResult r = e == null
          ? await widget.repository.publish(draft)
          : await widget.repository.update(e.id, draft);
      if (mounted) Navigator.of(context).pop(r);
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showProhibited() => showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Cosa non si può pubblicare'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final String p in marketProhibitedItems) Text('• $p')],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Ho capito')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MarketCategory? sub = _sub;
    final MarketCategory? main = sub == null ? null : widget.catalog.parentOf(sub);
    final List<MarketAttribute> attrs = MarketRules.attributesFor(main?.slug ?? '');
    final Set<String> required = sub == null || main == null
        ? const <String>{}
        : MarketRules.requiredAttributes(sub, main.slug, _type);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Modifica annuncio' : 'Nuovo annuncio')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.section.types.length > 1 && !_editing) ...[
              const _Title('Tipo di annuncio'),
              Wrap(
                spacing: 8,
                children: [
                  for (final MarketType t in widget.section.types)
                    ChoiceChip(
                      label: Text(t.label),
                      selected: _type == t,
                      onSelected: (_) => setState(() {
                        _type = t;
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            const _Title('Categoria'),
            Material(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                key: const ValueKey<String>('scegli_categoria'),
                leading: Icon(main == null ? Icons.category_outlined : marketCategoryIcon(main.slug)),
                title: Text(sub == null ? 'Scegli categoria e sottocategoria' : sub.name),
                subtitle: main == null ? null : Text(main.name),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _busy ? null : _chooseCategory,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _Title(_type.photosRequired
                ? 'Foto (almeno 1, fino a ${MarketRules.maxPhotos})'
                : 'Foto (facoltative, fino a ${MarketRules.maxPhotos})'),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (int i = 0; i < _photos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: SizedBox(
                              width: 92,
                              height: 92,
                              child: _photos[i].bytes != null
                                  ? Image.memory(_photos[i].bytes!, fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0x22000000)))
                                  : MarketPhoto(path: _photos[i].path!, repository: widget.repository),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: IconButton.filledTonal(
                              tooltip: 'Togli la foto',
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              onPressed: () => setState(() => _photos.removeAt(i)),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_photos.length < MarketRules.maxPhotos)
                    Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        key: const ValueKey<String>('mercato_aggiungi_foto'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: _busy ? null : _addPhoto,
                        child: const SizedBox(width: 92, height: 92, child: Icon(Icons.add_a_photo_outlined)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey<String>('mercato_titolo'),
              controller: _title,
              maxLength: MarketRules.titleMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Titolo',
                hintText: _type == MarketType.wanted ? 'Es. Cerco passeggino gemellare' : 'Es. iPhone 13 128 GB',
              ),
            ),
            TextField(
              key: const ValueKey<String>('mercato_descrizione'),
              controller: _description,
              maxLength: MarketRules.descriptionMax,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Descrizione'),
            ),
            if (_type.priceAllowed)
              TextField(
                key: const ValueKey<String>('mercato_prezzo'),
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: switch (_type) {
                    MarketType.sell => 'Prezzo (€)',
                    MarketType.wanted => 'Prezzo massimo (€, facoltativo)',
                    _ => 'Valore indicativo (€, facoltativo)',
                  },
                ),
              ),
            if (_type == MarketType.swap) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey<String>('mercato_in_cambio'),
                controller: _wanted,
                maxLength: MarketRules.wantedInExchangeMax,
                decoration: const InputDecoration(
                  labelText: 'Cosa cerchi in cambio (facoltativo)',
                  hintText: 'Es. una bici da corsa o una console',
                ),
              ),
            ],
            if (_type == MarketType.sell)
              CheckboxListTile(
                key: const ValueKey<String>('mercato_valuto_scambi'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Valuto anche scambi'),
                subtitle: const Text('Chi cerca «disponibili allo scambio» troverà il tuo annuncio'),
                value: _openToSwap,
                onChanged: (bool? v) => setState(() => _openToSwap = v ?? false),
              ),
            if (_cashAllowed)
              CheckboxListTile(
                key: const ValueKey<String>('mercato_conguaglio'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Accetto un conguaglio in denaro'),
                subtitle: const Text('Se gli oggetti hanno valori diversi, si pareggia con dei soldi'),
                value: _cash,
                onChanged: (bool? v) => setState(() => _cash = v ?? false),
              ),
            if (attrs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _Title('Dettagli di ${main!.name.toLowerCase()}'),
              for (final MarketAttribute a in attrs)
                TextField(
                  key: ValueKey<String>('mercato_campo_${a.key}'),
                  controller: _attrController(a.key),
                  keyboardType: a.numeric ? TextInputType.number : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: required.contains(a.key) ? a.label : '${a.label} (facoltativo)',
                    hintText: a.hint,
                  ),
                ),
            ],
            if (_objectFields) ...[
              const SizedBox(height: AppSpacing.md),
              const _Title('Condizioni'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ItemCondition c in ItemCondition.values)
                    ChoiceChip(
                      label: Text(c.label),
                      selected: _condition == c,
                      onSelected: (_) => setState(() => _condition = c),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const _Title('Consegna'),
              CheckboxListTile(
                key: const ValueKey<String>('mercato_ritiro'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Ritiro a mano'),
                value: _pickup,
                onChanged: (bool? v) => setState(() => _pickup = v ?? false),
              ),
              CheckboxListTile(
                key: const ValueKey<String>('mercato_spedizione'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Spedizione'),
                subtitle: const Text('Accordi e pagamento tra voi: l\'app non gestisce i soldi'),
                value: _ships,
                onChanged: (bool? v) => setState(() => _ships = v ?? false),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const _Title('Dove'),
            SoftCard(
              key: const ValueKey<String>('mercato_localita'),
              margin: const EdgeInsets.only(bottom: 8),
              onTap: () async {
                final Comune? c = await ComunePickerScreen.open(context);
                if (c != null && mounted) setState(() => _comune = c);
              },
              child: Row(
                children: [
                  const IconTile(Icons.location_city_rounded, color: AppColors.brandOrange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _comune?.label ?? 'Scegli il comune',
                          key: const ValueKey<String>('mercato_comune_scelto'),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _comune == null
                              ? 'Regione, provincia e comune: tutti i comuni d\'Italia'
                              : '${_comune!.province} · ${_comune!.region}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.brandOrange),
                ],
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>('mercato_mia_posizione'),
              onPressed: _locating || widget.services == null ? null : _locate,
              icon: const Icon(Icons.my_location_rounded),
              label: Text(_locating ? 'Cerco…' : 'Usa la mia posizione (trova il comune)'),
            ),
            SwitchListTile(
              key: const ValueKey<String>('mercato_punto_incontro'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Indica anche un punto d\'incontro'),
              subtitle: const Text('Facoltativo: un luogo pubblico per il ritiro. Altrimenti gli altri '
                  'vedono solo il comune.'),
              value: _place == ListingPlace.chosenPoint,
              onChanged: (bool v) => setState(() => _place = v ? ListingPlace.chosenPoint : ListingPlace.approximateZone),
            ),
            if (_place == ListingPlace.chosenPoint)
              OutlinedButton.icon(
                onPressed: widget.services == null ? null : _choosePoint,
                icon: const Icon(Icons.place_rounded),
                label: Text(_chosen == null ? 'Scegli il punto' : 'Cambia punto'),
              ),
            const SizedBox(height: AppSpacing.md),
            const AntiScamNotice(),
            CheckboxListTile(
              key: const ValueKey<String>('mercato_conferma_divieti'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Confermo che non pubblico prodotti vietati, illegali o rubati'),
              subtitle: InkWell(
                onTap: _showProhibited,
                child: Text(
                  'Vedi l\'elenco dei divieti',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              value: _confirmed,
              onChanged: (bool? v) => setState(() => _confirmed = v ?? false),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                key: const ValueKey<String>('mercato_errore'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey<String>('mercato_pubblica'),
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

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Foto di un annuncio di Scambia & Vendi scaricata dal server.
class MarketPhoto extends StatefulWidget {
  const MarketPhoto({super.key, required this.path, required this.repository});

  final String path;
  final MarketRepository repository;

  @override
  State<MarketPhoto> createState() => _MarketPhotoState();
}

/// La foto si scarica una volta sola, non a ogni ridisegno.
class _MarketPhotoState extends State<MarketPhoto> {
  late Future<Uint8List?> _bytes = widget.repository.downloadPhoto(widget.path);

  @override
  void didUpdateWidget(MarketPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _bytes = widget.repository.downloadPhoto(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) => snap.data == null
        ? const ColoredBox(color: Color(0x14000000), child: SizedBox.expand())
        : Image.memory(snap.data!, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(color: Color(0x22000000))),
  );
}

/// Avviso antitruffa (PDF, Fase 5): sempre visibile negli annunci e prima di pubblicare.
class AntiScamNotice extends StatelessWidget {
  const AntiScamNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('avviso_antitruffa'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandAmber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Attenzione alle truffe: non pagare in anticipo a sconosciuti, non condividere '
              'codici o dati bancari, vedi l\'oggetto prima di pagare. Piazly non gestisce i '
              'pagamenti.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

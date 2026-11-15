import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../map/listing_models.dart' show GeoPoint;
import '../map/listing_repository.dart' show ListingFailure;
import '../map/map_screen.dart' show MapServices;
import '../map/point_picker_screen.dart';
import 'market_location.dart';
import 'market_models.dart';

/// I 13 filtri di ricerca (specifica, sezione 7). Restituisce la nuova ricerca con
/// «Mostra risultati»; tornando indietro non cambia nulla.
class MarketFiltersScreen extends StatefulWidget {
  const MarketFiltersScreen({
    super.key,
    required this.section,
    required this.catalog,
    required this.initial,
    this.services,
  });

  final MarketSection section;
  final MarketCatalog catalog;
  final MarketQuery initial;

  /// Posizione e mappa del telefono; senza, resta solo «Ovunque».
  final MapServices? services;

  @override
  State<MarketFiltersScreen> createState() => _MarketFiltersScreenState();
}

class _MarketFiltersScreenState extends State<MarketFiltersScreen> {
  late MarketQuery _q = widget.initial;
  late final TextEditingController _min = TextEditingController(text: _euro(widget.initial.priceMinCents));
  late final TextEditingController _max = TextEditingController(text: _euro(widget.initial.priceMaxCents));
  bool _locating = false;
  String? _error;

  static String _euro(int? cents) =>
      cents == null ? '' : (cents % 100 == 0 ? '${cents ~/ 100}' : (cents / 100).toStringAsFixed(2).replaceAll('.', ','));

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _set(MarketQuery q) => setState(() {
    _q = q;
    _error = null;
  });

  Future<void> _useMyPosition() async {
    final MapServices? s = widget.services;
    if (s == null) return;
    setState(() => _locating = true);
    try {
      final GeoPoint p = await marketOneShotPosition(s);
      _set(_q.copyWith(origin: SearchOrigin.myPosition, point: () => p));
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _choosePoint() async {
    final MapServices? s = widget.services;
    if (s == null) return;
    final GeoPoint? p = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute<GeoPoint>(
        builder: (_) => PointPickerScreen(surface: s.surface, start: _q.point),
      ),
    );
    if (p == null || !mounted) return;
    _set(_q.copyWith(origin: SearchOrigin.chosenPoint, point: () => p));
  }

  void _apply() {
    int? min;
    int? max;
    try {
      min = MarketRules.parsePriceCents(_min.text);
      max = MarketRules.parsePriceCents(_max.text);
    } on FormatException {
      setState(() => _error = 'Prezzo non valido.');
      return;
    }
    if (min != null && max != null && min > max) {
      setState(() => _error = 'Il prezzo minimo supera il massimo.');
      return;
    }
    MarketQuery q = _q.copyWith(priceMinCents: () => min, priceMaxCents: () => max);
    if (q.sort == MarketSort.nearest && !q.hasPoint) q = q.copyWith(sort: MarketSort.recent);
    Navigator.of(context).pop(q);
  }

  void _reset() {
    _min.clear();
    _max.clear();
    _set(_q.cleared());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MarketCategory? main = _q.categoryId == null ? null : widget.catalog.byId(_q.categoryId!);
    final List<MarketCategory> subs =
        main == null ? const <MarketCategory>[] : widget.catalog.subsOf(main.id);
    final bool sale = widget.section == MarketSection.sale;
    final bool canLocate = widget.services != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filtri'),
        actions: [
          TextButton(
            key: const ValueKey<String>('filtri_azzera'),
            onPressed: _reset,
            child: const Text('Azzera'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (!sale) ...[
            const _Heading('Tipologia'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MarketType t in widget.section.types)
                  FilterChip(
                    key: ValueKey<String>('filtro_tipo_${t.serverValue}'),
                    label: Text(t.label),
                    selected: _q.types.contains(t),
                    onSelected: (bool on) => _set(
                      _q.copyWith(types: on ? (<MarketType>{..._q.types, t}) : (<MarketType>{..._q.types}..remove(t))),
                    ),
                  ),
              ],
            ),
          ],
          const _Heading('Categoria'),
          KeyedSubtree(
            key: const ValueKey<String>('filtro_categoria'),
            child: DropdownButtonFormField<String?>(
            key: ValueKey<String>('categoria_${_q.categoryId}'),
            initialValue: _q.categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Tutte le categorie')),
              for (final MarketCategory c in widget.catalog.mains)
                DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
            ],
            onChanged: (String? v) => _set(_q.copyWith(categoryId: () => v, subcategoryId: () => null)),
          ),
          ),
          if (main != null) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String?>(
              key: ValueKey<String>('filtro_sottocategoria_${main.id}_${_q.subcategoryId}'),
              initialValue: _q.subcategoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sottocategoria'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Tutte')),
                for (final MarketCategory c in subs)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (String? v) => _set(_q.copyWith(subcategoryId: () => v)),
            ),
          ],
          const _Heading('Prezzo'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('filtro_prezzo_min'),
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Minimo (€)'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('filtro_prezzo_max'),
                  controller: _max,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Massimo (€)'),
                ),
              ),
            ],
          ),
          const _Heading('Condizioni'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ItemCondition c in ItemCondition.values)
                FilterChip(
                  key: ValueKey<String>('filtro_condizione_${c.serverValue}'),
                  label: Text(c.label),
                  selected: _q.conditions.contains(c),
                  onSelected: (bool on) => _set(
                    _q.copyWith(
                      conditions: on
                          ? (<ItemCondition>{..._q.conditions, c})
                          : (<ItemCondition>{..._q.conditions}..remove(c)),
                    ),
                  ),
                ),
            ],
          ),
          const _Heading('Località'),
          RadioGroup<SearchOrigin>(
            groupValue: _q.hasPoint ? _q.origin : SearchOrigin.anywhere,
            onChanged: (SearchOrigin? v) {
              if (v == SearchOrigin.anywhere) {
                _set(_q.copyWith(origin: SearchOrigin.anywhere, point: () => null));
              } else if (v == SearchOrigin.myPosition) {
                _useMyPosition();
              } else if (v == SearchOrigin.chosenPoint) {
                _choosePoint();
              }
            },
            child: Column(
              children: [
                const RadioListTile<SearchOrigin>(
                  key: ValueKey<String>('filtro_ovunque'),
                  contentPadding: EdgeInsets.zero,
                  value: SearchOrigin.anywhere,
                  title: Text('Ovunque'),
                ),
                RadioListTile<SearchOrigin>(
                  key: const ValueKey<String>('filtro_mia_posizione'),
                  contentPadding: EdgeInsets.zero,
                  value: SearchOrigin.myPosition,
                  enabled: canLocate && !_locating,
                  title: const Text('Vicino a me'),
                  subtitle: Text(
                    _locating
                        ? 'Cerco la posizione…'
                        : 'Usata solo per questa ricerca, non viene salvata.',
                  ),
                ),
                RadioListTile<SearchOrigin>(
                  key: const ValueKey<String>('filtro_punto'),
                  contentPadding: EdgeInsets.zero,
                  value: SearchOrigin.chosenPoint,
                  enabled: canLocate,
                  title: const Text('Vicino a un punto sulla mappa'),
                ),
              ],
            ),
          ),
          if (_q.hasPoint) ...[
            Text('Raggio: ${_q.radiusKm} km', style: theme.textTheme.titleSmall),
            Slider(
              key: const ValueKey<String>('filtro_raggio'),
              min: MarketQuery.minRadiusKm.toDouble(),
              max: MarketQuery.maxRadiusKm.toDouble(),
              divisions: MarketQuery.maxRadiusKm - MarketQuery.minRadiusKm,
              value: _q.radiusKm.toDouble(),
              label: '${_q.radiusKm} km',
              onChanged: (double v) => _set(_q.copyWith(radiusKm: v.round())),
            ),
          ],
          const _Heading('Chi pubblica'),
          SegmentedButton<SellerKind>(
            key: const ValueKey<String>('filtro_venditore'),
            segments: [
              for (final SellerKind k in SellerKind.values)
                ButtonSegment<SellerKind>(value: k, label: Text(k.label)),
            ],
            selected: <SellerKind>{_q.seller},
            onSelectionChanged: (Set<SellerKind> v) => _set(_q.copyWith(seller: v.first)),
          ),
          const _Heading('Consegna e scambio'),
          SwitchListTile(
            key: const ValueKey<String>('filtro_spedizione'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Spedizione disponibile'),
            value: _q.ships,
            onChanged: (bool v) => _set(_q.copyWith(ships: v)),
          ),
          SwitchListTile(
            key: const ValueKey<String>('filtro_ritiro'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Ritiro a mano'),
            value: _q.pickup,
            onChanged: (bool v) => _set(_q.copyWith(pickup: v)),
          ),
          if (sale)
            SwitchListTile(
              key: const ValueKey<String>('filtro_scambio'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Disponibili allo scambio'),
              value: _q.openToSwap,
              onChanged: (bool v) => _set(_q.copyWith(openToSwap: v)),
            ),
          SwitchListTile(
            key: const ValueKey<String>('filtro_conguaglio'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Scambio con conguaglio'),
            value: _q.cashAdjustment,
            onChanged: (bool v) => _set(_q.copyWith(cashAdjustment: v)),
          ),
          const _Heading('Data di pubblicazione'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final PublishedWithin p in PublishedWithin.values)
                ChoiceChip(
                  key: ValueKey<String>('filtro_data_${p.name}'),
                  label: Text(p.label),
                  selected: _q.published == p,
                  onSelected: (_) => _set(_q.copyWith(published: p)),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              key: const ValueKey<String>('filtri_errore'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const ValueKey<String>('filtri_mostra'),
            onPressed: _apply,
            child: const Text('Mostra risultati'),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'market_models.dart';

/// Icona di ogni categoria principale (specifica, sezione 10: icone coerenti).
IconData marketCategoryIcon(String mainSlug) => switch (mainSlug) {
  'motori' => Icons.directions_car_rounded,
  'immobili' => Icons.home_work_rounded,
  'elettronica' => Icons.devices_other_rounded,
  'casa-arredamento' => Icons.chair_rounded,
  'elettrodomestici' => Icons.kitchen_rounded,
  'abbigliamento-accessori' => Icons.checkroom_rounded,
  'bambini-neonati' => Icons.child_friendly_rounded,
  'giardino-fai-da-te' => Icons.yard_rounded,
  'sport-outdoor' => Icons.sports_soccer_rounded,
  'musica-strumenti' => Icons.music_note_rounded,
  'collezionismo-arte' => Icons.palette_rounded,
  'libri-cultura' => Icons.menu_book_rounded,
  'animali-accessori' => Icons.pets_rounded,
  'attrezzature-professionali' => Icons.construction_rounded,
  'bellezza-cura-personale' => Icons.spa_rounded,
  'ufficio-cancelleria' => Icons.business_center_rounded,
  'servizi' => Icons.handyman_rounded,
  'giochi-hobby' => Icons.extension_rounded,
  _ => Icons.category_rounded,
};

/// Scelta a due passi (specifica, sezione 10): prima la categoria principale, poi solo le
/// sue sottocategorie. Restituisce la sottocategoria scelta.
class CategoryPicker extends StatefulWidget {
  const CategoryPicker({super.key, required this.catalog, this.initialMainId});

  final MarketCatalog catalog;
  final String? initialMainId;

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  late String? _mainId = widget.initialMainId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? mainId = _mainId;
    final MarketCategory? main = mainId == null ? null : widget.catalog.byId(mainId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 20, 8),
          child: Row(
            children: [
              if (main != null)
                IconButton(
                  tooltip: 'Torna alle categorie',
                  onPressed: () => setState(() => _mainId = null),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              else
                const SizedBox(width: 12),
              Expanded(
                child: Text(
                  main?.name ?? 'Scegli la categoria',
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: main == null
              ? GridView.count(
                  key: const ValueKey<String>('categorie_principali'),
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.95,
                  children: [
                    for (final MarketCategory c in widget.catalog.mains)
                      _MainTile(category: c, onTap: () => setState(() => _mainId = c.id)),
                  ],
                )
              : ListView(
                  key: const ValueKey<String>('sottocategorie'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    for (final MarketCategory s in widget.catalog.subsOf(main.id))
                      ListTile(
                        title: Text(s.name),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(s),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MainTile extends StatelessWidget {
  const _MainTile({required this.category, required this.onTap});

  final MarketCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.brandOrange.withValues(alpha: 0.15),
                child: Icon(marketCategoryIcon(category.slug), color: AppColors.brandOrangeDeep),
              ),
              const SizedBox(height: 8),
              Text(
                category.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<MarketCategory?> pickMarketCategory(
  BuildContext context,
  MarketCatalog catalog, {
  String? initialMainId,
}) => showModalBottomSheet<MarketCategory>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.85,
    child: CategoryPicker(catalog: catalog, initialMainId: initialMainId),
  ),
);

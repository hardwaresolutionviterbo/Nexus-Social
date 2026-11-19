import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'comuni_italia.dart';

/// Scelta della località dell'annuncio: cerca il comune per nome oppure sfoglia
/// Regione → Provincia → Comune. Restituisce il comune scelto.
class ComunePickerScreen extends StatefulWidget {
  const ComunePickerScreen({super.key});

  static Future<Comune?> open(BuildContext context) => Navigator.of(context).push<Comune>(
    MaterialPageRoute<Comune>(builder: (_) => const ComunePickerScreen()),
  );

  @override
  State<ComunePickerScreen> createState() => _ComunePickerScreenState();
}

class _ComunePickerScreenState extends State<ComunePickerScreen> {
  ComuniItalia? _data = ComuniItalia.loaded;
  String _q = '';
  String? _region;
  Provincia? _province;

  @override
  void initState() {
    super.initState();
    if (_data == null) {
      ComuniItalia.load().then((ComuniItalia d) {
        if (mounted) setState(() => _data = d);
      });
    }
  }

  bool _back() {
    if (_province != null) {
      setState(() => _province = null);
      return false;
    }
    if (_region != null) {
      setState(() => _region = null);
      return false;
    }
    return true;
  }

  Widget _comuneTile(Comune c, {bool showRegion = true}) => ListTile(
    key: ValueKey<String>('comune_${c.name}_${c.provinceCode}'),
    leading: const Icon(Icons.location_city_rounded, color: AppColors.brandOrange),
    title: Text(c.label),
    subtitle: showRegion ? Text('${c.province} · ${c.region}') : null,
    onTap: () => Navigator.of(context).pop(c),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ComuniItalia? d = _data;
    final String title = _province?.name ?? _region ?? 'Scegli la località';
    Widget body;
    if (d == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_q.trim().length >= 2) {
      final List<Comune> found = d.search(_q);
      body = found.isEmpty
          ? const Center(child: Text('Nessun comune con questo nome'))
          : ListView(children: [for (final Comune c in found) _comuneTile(c)]);
    } else if (_province != null) {
      body = ListView(children: [for (final Comune c in d.comuniOf(_province!.code)) _comuneTile(c, showRegion: false)]);
    } else if (_region != null) {
      body = ListView(
        children: [
          for (final Provincia p in d.provincesOf(_region!))
            ListTile(
              key: ValueKey<String>('provincia_${p.code}'),
              leading: const Icon(Icons.map_outlined),
              title: Text(p.name),
              subtitle: Text(p.code),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => setState(() => _province = p),
            ),
        ],
      );
    } else {
      body = ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Text('Oppure scegli la regione', style: theme.textTheme.labelLarge),
          ),
          for (final String r in d.regions)
            ListTile(
              key: ValueKey<String>('regione_$r'),
              leading: const Icon(Icons.public_rounded),
              title: Text(r),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => setState(() => _region = r),
            ),
        ],
      );
    }
    return PopScope(
      canPop: _region == null && _province == null,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                key: const ValueKey<String>('cerca_comune'),
                autofocus: _region == null,
                onChanged: (String v) => setState(() => _q = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Cerca il comune (es. Viterbo)',
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

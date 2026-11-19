import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../core/widgets/piazly_ui.dart';
import '../market/comuni_italia.dart';

/// Un posto suggerito mentre si scrive: un comune (dall'elenco nell'app) o un luogo e un
/// indirizzo da OpenStreetMap (servizio gratuito Photon, richiesta del titolare 19/11/2026).
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lng,
    this.comune,
    this.street = '',
    this.houseNumber = '',
    this.city = '',
    this.postcode = '',
  });

  /// Parti dell'indirizzo, quando il servizio le dà (per compilare la sede di un'attività).
  final String street;
  final String houseNumber;
  final String city;
  final String postcode;

  /// «Porano (TR)» oppure «Bar Centrale».
  final String title;

  /// «Umbria» oppure «Via Roma 3, Orvieto (TR)».
  final String subtitle;
  final double lat;
  final double lng;

  /// Il comune, se il suggerimento viene dall'elenco dei comuni.
  final Comune? comune;

  bool get isComune => comune != null;

  /// Testo da mettere nel campo dopo la scelta.
  String get label => subtitle.isEmpty ? title : '$title · $subtitle';

  @override
  bool operator ==(Object other) =>
      other is PlaceSuggestion && other.title == title && other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(title, subtitle);
}

/// Ricerca di luoghi e indirizzi in rete. Nei test: una versione finta.
abstract class PlaceLookup {
  Future<List<PlaceSuggestion>> search(String query, {double? nearLat, double? nearLng});
}

/// Photon (komoot), basato su OpenStreetMap: gratis, senza chiave, «da usare con
/// giudizio». Si chiede solo dopo una pausa nella scrittura e solo in Italia.
class PhotonPlaceLookup implements PlaceLookup {
  PhotonPlaceLookup({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  static const String _italy = '6.6,35.4,18.6,47.1';

  @override
  Future<List<PlaceSuggestion>> search(String query, {double? nearLat, double? nearLng}) async {
    final Uri uri = Uri.https('photon.komoot.io', '/api', <String, String>{
      'q': query,
      'lang': 'it',
      'limit': '8',
      'bbox': _italy,
      if (nearLat != null && nearLng != null) 'lat': nearLat.toStringAsFixed(3),
      if (nearLat != null && nearLng != null) 'lon': nearLng.toStringAsFixed(3),
    });
    final HttpClientRequest req = await _client.getUrl(uri).timeout(const Duration(seconds: 6));
    req.headers.set(HttpHeaders.userAgentHeader, 'Piazly/1.0 (app Android)');
    final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return const <PlaceSuggestion>[];
    }
    final String body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 6));
    return parsePhoton(body);
  }

  /// Trasforma la risposta (GeoJSON) in suggerimenti leggibili.
  static List<PlaceSuggestion> parsePhoton(String body) {
    final Object? j = jsonDecode(body);
    if (j is! Map<String, dynamic>) return const <PlaceSuggestion>[];
    final List<PlaceSuggestion> out = <PlaceSuggestion>[];
    for (final Object? f in (j['features'] as List<dynamic>? ?? const <dynamic>[])) {
      if (f is! Map<String, dynamic>) continue;
      final Object? coords = (f['geometry'] as Map<String, dynamic>?)?['coordinates'];
      final Map<String, dynamic> p = (f['properties'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      if (coords is! List || coords.length < 2 || coords[0] is! num || coords[1] is! num) continue;
      if (p['countrycode'] is String && p['countrycode'] != 'IT') continue;
      String s(String k) => p[k] is String ? (p[k] as String).trim() : '';
      final String street = <String>[s('street'), s('housenumber')].where((x) => x.isNotEmpty).join(' ');
      final String city = s('city').isNotEmpty ? s('city') : (s('town').isNotEmpty ? s('town') : s('village'));
      final String name = s('name');
      final String title = name.isNotEmpty ? name : (street.isNotEmpty ? street : city);
      if (title.isEmpty) continue;
      final List<String> where = <String>[
        if (street.isNotEmpty && street != title) street,
        if (city.isNotEmpty && city != title) city,
        if (s('county').isNotEmpty && s('county') != city && s('county') != title) s('county'),
        if (s('state').isNotEmpty) s('state'),
      ];
      final PlaceSuggestion sug = PlaceSuggestion(
        title: title,
        subtitle: where.join(', '),
        lat: (coords[1] as num).toDouble(),
        lng: (coords[0] as num).toDouble(),
        street: s('street'),
        houseNumber: s('housenumber'),
        city: city.isNotEmpty ? city : (const <String>{'city', 'town', 'village'}.contains(s('osm_value')) ? name : ''),
        postcode: s('postcode'),
      );
      if (!out.contains(sug)) out.add(sug);
    }
    return out;
  }
}

/// Chi cerca i posti nell'app (la versione vera la imposta main.dart).
abstract final class PlaceRegistry {
  static PlaceLookup? online;
}

/// Comuni dall'elenco nell'app: subito, anche senza rete.
List<PlaceSuggestion> comuniSuggestions(ComuniItalia? data, String query, {int max = 5}) => <PlaceSuggestion>[
  for (final Comune c in data?.search(query).take(max) ?? const <Comune>[])
    PlaceSuggestion(
      title: c.label,
      subtitle: c.region,
      lat: c.point.latitude,
      lng: c.point.longitude,
      comune: c,
    ),
];

/// Campo «Dove» con i suggerimenti mentre si scrive: prima i comuni, poi luoghi e
/// indirizzi da OpenStreetMap. [onSelected] riceve il posto scelto (null se il testo
/// è stato cambiato a mano dopo la scelta).
class PlaceField extends StatefulWidget {
  const PlaceField({
    super.key,
    required this.controller,
    this.onSelected,
    this.label = 'Dove',
    this.hint = 'Scrivi un paese, un locale o un indirizzo',
    this.onlyComuni = false,
    this.lookup,
    this.comuni,
    this.nearLat,
    this.nearLng,
    this.fieldKey,
  });

  final TextEditingController controller;
  final ValueChanged<PlaceSuggestion?>? onSelected;
  final String label;
  final String hint;

  /// Solo comuni (località degli annunci): niente indirizzi precisi.
  final bool onlyComuni;

  /// Ricerca in rete; se manca si usa [PlaceRegistry.online].
  final PlaceLookup? lookup;

  /// Elenco dei comuni; se manca si usa quello caricato dall'app.
  final ComuniItalia? comuni;
  final double? nearLat;
  final double? nearLng;
  final Key? fieldKey;

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  List<PlaceSuggestion> _local = const <PlaceSuggestion>[];
  List<PlaceSuggestion> _online = const <PlaceSuggestion>[];
  Timer? _debounce;
  bool _searching = false;
  String _chosen = '';
  int _ticket = 0;
  ComuniItalia? _data;

  @override
  void initState() {
    super.initState();
    _data = widget.comuni ?? ComuniItalia.loaded;
    if (_data == null) {
      ComuniItalia.load().then((ComuniItalia d) {
        if (mounted) setState(() => _data = d);
      }, onError: (Object _) {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String text) {
    if (_chosen.isNotEmpty && text != _chosen) {
      _chosen = '';
      widget.onSelected?.call(null);
    }
    _debounce?.cancel();
    final String q = text.trim();
    final int ticket = ++_ticket;
    setState(() {
      _local = q.length < 2 ? const <PlaceSuggestion>[] : comuniSuggestions(_data, q);
      _online = const <PlaceSuggestion>[];
      _searching = false;
    });
    final PlaceLookup? lookup = widget.onlyComuni ? null : (widget.lookup ?? PlaceRegistry.online);
    if (lookup == null || q.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _searching = true);
      List<PlaceSuggestion> found = const <PlaceSuggestion>[];
      try {
        found = await lookup.search(q, nearLat: widget.nearLat, nearLng: widget.nearLng);
      } catch (_) {
        // Senza rete restano i comuni.
      }
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _searching = false;
        _online = <PlaceSuggestion>[for (final PlaceSuggestion s in found) if (!_local.contains(s)) s];
      });
    });
  }

  void _pick(PlaceSuggestion s) {
    _debounce?.cancel();
    _ticket++;
    _chosen = s.label;
    widget.controller.text = s.label;
    widget.controller.selection = TextSelection.collapsed(offset: s.label.length);
    setState(() {
      _local = const <PlaceSuggestion>[];
      _online = const <PlaceSuggestion>[];
      _searching = false;
    });
    FocusScope.of(context).unfocus();
    widget.onSelected?.call(s);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<PlaceSuggestion> all = <PlaceSuggestion>[..._local, ..._online];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: widget.fieldKey,
          controller: widget.controller,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.place_outlined),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
        ),
        if (all.isNotEmpty)
          Card(
            key: const ValueKey<String>('luogo_suggerimenti'),
            margin: const EdgeInsets.only(top: 4),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < all.length; i++)
                  ListTile(
                    key: ValueKey<String>('luogo_$i'),
                    dense: true,
                    leading: Icon(
                      all[i].isComune ? Icons.location_city_rounded : Icons.place_rounded,
                      color: all[i].isComune ? PiazlyColors.violet : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(all[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: all[i].subtitle.isEmpty
                        ? null
                        : Text(all[i].subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _pick(all[i]),
                  ),
                if (_online.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('Luoghi © OpenStreetMap', style: theme.textTheme.labelSmall),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

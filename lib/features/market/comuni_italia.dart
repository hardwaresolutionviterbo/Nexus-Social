import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../map/listing_models.dart' show GeoPoint;

/// Comuni d'Italia (elenco ISTAT, 7.904 comuni) con il centro di ciascuno: servono per la
/// località degli annunci di Scambia & Vendi (richiesta del titolare, 19/11/2026). Il file è
/// nell'app: nessuna ricerca va su internet.
class Comune {
  const Comune({
    required this.name,
    required this.provinceCode,
    required this.province,
    required this.region,
    required this.point,
  });

  final String name;

  /// Sigla della provincia, es. «TR».
  final String provinceCode;
  final String province;
  final String region;
  final GeoPoint point;

  /// «Porano (TR)».
  String get label => '$name ($provinceCode)';

  @override
  bool operator ==(Object other) => other is Comune && other.name == name && other.provinceCode == provinceCode;

  @override
  int get hashCode => Object.hash(name, provinceCode);
}

class Provincia {
  const Provincia({required this.code, required this.name, required this.region});

  final String code;
  final String name;
  final String region;
}

class ComuniItalia {
  ComuniItalia._(this.regions, this.provinces, this.comuni);

  /// Costruito da un JSON con la stessa forma del file dell'app (anche nei test).
  factory ComuniItalia.fromJson(Map<String, dynamic> j) {
    final List<String> regions = <String>[for (final Object? r in j['regioni'] as List<dynamic>) '$r'];
    final List<Provincia> provinces = <Provincia>[
      for (final Object? p in j['province'] as List<dynamic>)
        Provincia(code: '${(p as List<dynamic>)[0]}', name: '${p[1]}', region: regions[(p[2] as num).toInt()]),
    ];
    final List<Comune> comuni = <Comune>[
      for (final Object? c in j['comuni'] as List<dynamic>)
        Comune(
          name: '${(c as List<dynamic>)[0]}',
          provinceCode: provinces[(c[1] as num).toInt()].code,
          province: provinces[(c[1] as num).toInt()].name,
          region: provinces[(c[1] as num).toInt()].region,
          point: GeoPoint((c[2] as num).toDouble(), (c[3] as num).toDouble()),
        ),
    ];
    return ComuniItalia._(regions, provinces, comuni);
  }

  final List<String> regions;
  final List<Provincia> provinces;
  final List<Comune> comuni;

  static ComuniItalia? _cache;
  static Future<ComuniItalia>? _loading;

  /// Già caricato (null finché non serve la prima volta).
  static ComuniItalia? get loaded => _cache;

  /// Per i test: un elenco preparato a mano.
  static set testData(ComuniItalia? data) {
    _cache = data;
    _loading = null;
  }

  static Future<ComuniItalia> load() {
    final ComuniItalia? c = _cache;
    if (c != null) return Future<ComuniItalia>.value(c);
    // rootBundle.load e non loadString: per i file grandi loadString usa un isolate.
    return _loading ??= rootBundle.load('assets/data/comuni_italia.json').then((ByteData b) {
      final String s = utf8.decode(b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes));
      return _cache = ComuniItalia.fromJson(jsonDecode(s) as Map<String, dynamic>);
    });
  }

  List<Provincia> provincesOf(String region) =>
      <Provincia>[for (final Provincia p in provinces) if (p.region == region) p]
        ..sort((Provincia a, Provincia b) => a.name.compareTo(b.name));

  List<Comune> comuniOf(String provinceCode) =>
      <Comune>[for (final Comune c in comuni) if (c.provinceCode == provinceCode) c]
        ..sort((Comune a, Comune b) => a.name.compareTo(b.name));

  /// Cerca per nome (senza accenti), prima quelli che iniziano con il testo; al massimo 50.
  List<Comune> search(String query) {
    final String q = fold(query.trim());
    if (q.length < 2) return const <Comune>[];
    final List<Comune> starts = <Comune>[];
    final List<Comune> contains = <Comune>[];
    for (final Comune c in comuni) {
      final String n = fold(c.name);
      if (n.startsWith(q)) {
        starts.add(c);
      } else if (n.contains(q)) {
        contains.add(c);
      }
    }
    starts.sort((Comune a, Comune b) => a.name.length.compareTo(b.name.length));
    return <Comune>[...starts, ...contains].take(50).toList();
  }

  /// Il comune con il centro più vicino al punto.
  Comune nearest(GeoPoint p) {
    Comune best = comuni.first;
    double bestD = double.infinity;
    final double cosLat = math.cos(p.latitude * math.pi / 180);
    for (final Comune c in comuni) {
      final double dLat = c.point.latitude - p.latitude;
      final double dLng = (c.point.longitude - p.longitude) * cosLat;
      final double d = dLat * dLat + dLng * dLng;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  /// Toglie gli accenti e mette in minuscolo, per cercare «citta» e trovare «Città».
  static String fold(String s) {
    const Map<String, String> map = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'è': 'e', 'é': 'e', 'ê': 'e', 'ì': 'i', 'í': 'i', 'î': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ä': 'a', 'ö': 'o', 'ü': 'u',
      '’': "'",
    };
    final StringBuffer b = StringBuffer();
    for (final String ch in s.toLowerCase().split('')) {
      b.write(map[ch] ?? ch);
    }
    return b.toString();
  }
}

import 'dart:convert';

/// Messaggi «ricchi» (Blocco 18), cifrati come tutti gli altri: posizione, contatto,
/// sondaggio ed evento. Il contenuto è un JSON nel corpo del messaggio.
sealed class RichPayload {
  const RichPayload();

  String get kind;

  Map<String, Object?> toJsonBody();

  String encode() => jsonEncode(<String, Object?>{'k': kind, ...toJsonBody()});

  /// Testo breve per l'elenco delle chat e le notifiche.
  String get preview;

  /// Testo per «Rispondi» e per le segnalazioni.
  String get summary => preview;

  static const int maxBytes = 4000;

  static RichPayload? decode(String body) {
    try {
      if (body.length > maxBytes) return null;
      final Object? j = jsonDecode(body);
      if (j is! Map<String, dynamic>) return null;
      return switch (j['k']) {
        'loc' => RichLocation.fromJson(j),
        'contact' => RichContact.fromJson(j),
        'poll' => RichPoll.fromJson(j),
        'event' => RichEvent.fromJson(j),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

String _str(Object? v, int max) {
  final String s = v is String ? v.trim() : '';
  return s.length > max ? s.substring(0, max) : s;
}

/// Posizione: attuale, un luogo cercato, o «in tempo reale» fino a un'ora.
class RichLocation extends RichPayload {
  const RichLocation({required this.lat, required this.lng, this.name = '', this.address = '', this.liveUntil});

  final double lat;
  final double lng;
  final String name;
  final String address;

  /// Se è in tempo reale: fino a quando (si segue sulla Mappa di chi la riceve).
  final DateTime? liveUntil;

  static RichLocation? fromJson(Map<String, dynamic> j) {
    final double? lat = _num(j['lat']);
    final double? lng = _num(j['lng']);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
    return RichLocation(
      lat: lat,
      lng: lng,
      name: _str(j['n'], 120),
      address: _str(j['a'], 200),
      liveUntil: j['live'] is String ? DateTime.tryParse(j['live'] as String)?.toLocal() : null,
    );
  }

  @override
  String get kind => 'loc';

  @override
  Map<String, Object?> toJsonBody() => <String, Object?>{
    'lat': double.parse(lat.toStringAsFixed(6)),
    'lng': double.parse(lng.toStringAsFixed(6)),
    if (name.isNotEmpty) 'n': name,
    if (address.isNotEmpty) 'a': address,
    if (liveUntil != null) 'live': liveUntil!.toUtc().toIso8601String(),
  };

  @override
  String get preview => liveUntil != null
      ? '📍 Posizione in tempo reale'
      : name.isNotEmpty
      ? '📍 $name'
      : '📍 Posizione';
}

/// Contatto della rubrica: nome e numeri.
class RichContact extends RichPayload {
  const RichContact({required this.name, required this.phones});

  final String name;
  final List<String> phones;

  static RichContact? fromJson(Map<String, dynamic> j) {
    final String name = _str(j['n'], 100);
    final List<String> phones = <String>[
      for (final Object? p in (j['p'] as List<dynamic>? ?? const <dynamic>[]).take(5))
        if (p is String && RegExp(r'^[+0-9 ()\-]{3,25}$').hasMatch(p)) p,
    ];
    if (name.isEmpty && phones.isEmpty) return null;
    return RichContact(name: name, phones: phones);
  }

  @override
  String get kind => 'contact';

  @override
  Map<String, Object?> toJsonBody() => <String, Object?>{'n': name, 'p': phones};

  @override
  String get preview => '👤 ${name.isEmpty ? 'Contatto' : name}';
}

/// Sondaggio: domanda e da 2 a 12 risposte, una sola o più di una.
class RichPoll extends RichPayload {
  const RichPoll({required this.question, required this.options, this.multiple = false});

  static const int maxOptions = 12;

  final String question;
  final List<String> options;
  final bool multiple;

  static RichPoll? fromJson(Map<String, dynamic> j) {
    final String q = _str(j['q'], 300);
    final List<String> o = <String>[
      for (final Object? x in (j['o'] as List<dynamic>? ?? const <dynamic>[]).take(maxOptions))
        if (_str(x, 100).isNotEmpty) _str(x, 100),
    ];
    if (q.isEmpty || o.length < 2) return null;
    return RichPoll(question: q, options: o, multiple: j['m'] == true);
  }

  @override
  String get kind => 'poll';

  @override
  Map<String, Object?> toJsonBody() => <String, Object?>{'q': question, 'o': options, if (multiple) 'm': true};

  @override
  String get preview => '📊 Sondaggio: $question';

  /// Voto codificato: indici scelti separati da virgola ('' = nessun voto).
  static List<int> parseVote(String v, int options) => <int>[
    for (final String s in v.split(','))
      if (int.tryParse(s) != null && int.parse(s) >= 0 && int.parse(s) < options) int.parse(s),
  ];

  /// Quanti voti per ogni risposta.
  List<int> counts(Map<String, String> answers) {
    final List<int> c = List<int>.filled(options.length, 0);
    for (final String v in answers.values) {
      for (final int i in parseVote(v, options.length).toSet()) {
        c[i]++;
      }
    }
    return c;
  }
}

/// Evento: titolo, quando, dove, nota. Gli altri rispondono «Ci sono» o «Non ci sono».
class RichEvent extends RichPayload {
  const RichEvent({required this.title, required this.at, this.place = '', this.note = '', this.lat, this.lng});

  final String title;
  final DateTime at;
  final String place;
  final String note;
  final double? lat;
  final double? lng;

  static RichEvent? fromJson(Map<String, dynamic> j) {
    final String t = _str(j['t'], 120);
    final DateTime? at = j['w'] is String ? DateTime.tryParse(j['w'] as String)?.toLocal() : null;
    if (t.isEmpty || at == null) return null;
    return RichEvent(
      title: t,
      at: at,
      place: _str(j['p'], 200),
      note: _str(j['x'], 500),
      lat: _num(j['lat']),
      lng: _num(j['lng']),
    );
  }

  @override
  String get kind => 'event';

  @override
  Map<String, Object?> toJsonBody() => <String, Object?>{
    't': title,
    'w': at.toUtc().toIso8601String(),
    if (place.isNotEmpty) 'p': place,
    if (note.isNotEmpty) 'x': note,
    'lat': ?lat,
    'lng': ?lng,
  };

  @override
  String get preview => '📅 Evento: $title';

  static const String yes = 'si';
  static const String no = 'no';
}

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

/// OPRF(P-256, SHA-256) in modalità OPRF (RFC 9497, §4.3), lato telefono.
///
/// Rubrica (decisione S6): il telefono «acceca» ogni numero con un fattore casuale prima di
/// inviarlo; il server applica la sua chiave segreta senza vedere il numero; il telefono
/// toglie il fattore e ottiene un codice che non permette di risalire al numero senza la
/// chiave del server. Verificata con i vettori di prova ufficiali (RFC 9497 A.3.1, RFC 9380).
abstract final class P256 {
  static final BigInt p = BigInt.parse(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    radix: 16,
  );
  static final BigInt n = BigInt.parse(
    'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',
    radix: 16,
  );
  static final BigInt a = p - BigInt.from(3);
  static final BigInt b = BigInt.parse(
    '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
    radix: 16,
  );
}

/// Punto in coordinate affini; null rappresenta il punto all'infinito.
class EcPoint {
  const EcPoint(this.x, this.y);

  final BigInt x;
  final BigInt y;

  /// Formato compresso SEC1 (33 byte), come SerializeElement di RFC 9497.
  Uint8List toCompressed() {
    final Uint8List out = Uint8List(33);
    out[0] = y.isEven ? 0x02 : 0x03;
    out.setRange(1, 33, _toBytes(x, 32));
    return out;
  }

  static EcPoint fromCompressed(Uint8List bytes) {
    if (bytes.length != 33 || (bytes[0] != 2 && bytes[0] != 3)) {
      throw const FormatException('Punto non valido');
    }
    final BigInt x = _fromBytes(bytes.sublist(1));
    if (x >= P256.p) throw const FormatException('Punto non valido');
    final BigInt rhs = (x * x * x + P256.a * x + P256.b) % P256.p;
    final BigInt? y0 = _sqrt(rhs);
    if (y0 == null) throw const FormatException('Punto non sulla curva');
    final bool wantOdd = bytes[0] == 3;
    final BigInt y = y0.isOdd == wantOdd ? y0 : (P256.p - y0) % P256.p;
    return EcPoint(x, y);
  }
}

// ------------------------------------------------------------------ aritmetica

BigInt _mod(BigInt v) => v % P256.p;

BigInt _inv(BigInt v) => v.modInverse(P256.p);

BigInt? _sqrt(BigInt v) {
  // p ≡ 3 (mod 4): radice = v^((p+1)/4), se esiste.
  final BigInt r = v.modPow((P256.p + BigInt.one) >> 2, P256.p);
  return (r * r) % P256.p == v % P256.p ? r : null;
}

Uint8List _toBytes(BigInt v, int len) {
  final Uint8List out = Uint8List(len);
  BigInt t = v;
  for (int i = len - 1; i >= 0; i--) {
    out[i] = (t & BigInt.from(0xff)).toInt();
    t = t >> 8;
  }
  return out;
}

BigInt _fromBytes(List<int> bytes) {
  BigInt v = BigInt.zero;
  for (final int byte in bytes) {
    v = (v << 8) | BigInt.from(byte);
  }
  return v;
}

/// Coordinate jacobiane (X, Y, Z): x = X/Z², y = Y/Z³. Z = 0 è il punto all'infinito.
class _Jac {
  const _Jac(this.x, this.y, this.z);

  final BigInt x;
  final BigInt y;
  final BigInt z;

  static final _Jac infinity = _Jac(BigInt.one, BigInt.one, BigInt.zero);

  bool get isInfinity => z == BigInt.zero;

  static _Jac from(EcPoint p) => _Jac(p.x, p.y, BigInt.one);

  EcPoint? toAffine() {
    if (isInfinity) return null;
    final BigInt zi = _inv(z);
    final BigInt zi2 = _mod(zi * zi);
    return EcPoint(_mod(x * zi2), _mod(y * zi2 * zi));
  }

  _Jac dbl() {
    if (isInfinity || y == BigInt.zero) return infinity;
    // a = -3: M = 3(X - Z²)(X + Z²)
    final BigInt z2 = _mod(z * z);
    final BigInt m = _mod(BigInt.from(3) * (x - z2) * (x + z2));
    final BigInt y2 = _mod(y * y);
    final BigInt s = _mod(BigInt.from(4) * x * y2);
    final BigInt x3 = _mod(m * m - BigInt.two * s);
    final BigInt y3 = _mod(m * (s - x3) - BigInt.from(8) * y2 * y2);
    final BigInt z3 = _mod(BigInt.two * y * z);
    return _Jac(x3, y3, z3);
  }

  _Jac add(_Jac o) {
    if (isInfinity) return o;
    if (o.isInfinity) return this;
    final BigInt z1z1 = _mod(z * z);
    final BigInt z2z2 = _mod(o.z * o.z);
    final BigInt u1 = _mod(x * z2z2);
    final BigInt u2 = _mod(o.x * z1z1);
    final BigInt s1 = _mod(y * o.z * z2z2);
    final BigInt s2 = _mod(o.y * z * z1z1);
    if (u1 == u2) {
      return s1 == s2 ? dbl() : infinity;
    }
    final BigInt h = _mod(u2 - u1);
    final BigInt r = _mod(s2 - s1);
    final BigInt h2 = _mod(h * h);
    final BigInt h3 = _mod(h2 * h);
    final BigInt u1h2 = _mod(u1 * h2);
    final BigInt x3 = _mod(r * r - h3 - BigInt.two * u1h2);
    final BigInt y3 = _mod(r * (u1h2 - x3) - s1 * h3);
    final BigInt z3 = _mod(h * z * o.z);
    return _Jac(x3, y3, z3);
  }

  /// Moltiplicazione scalare con finestra di 4 bit.
  _Jac mul(BigInt k) {
    final List<_Jac> table = List<_Jac>.filled(16, infinity);
    table[1] = this;
    for (int i = 2; i < 16; i++) {
      table[i] = table[i - 1].add(this);
    }
    _Jac r = infinity;
    final int bits = k.bitLength;
    final int top = ((bits + 3) ~/ 4) * 4;
    for (int i = top - 4; i >= 0; i -= 4) {
      r = r.dbl().dbl().dbl().dbl();
      final int w = ((k >> i) & BigInt.from(15)).toInt();
      if (w != 0) r = r.add(table[w]);
    }
    return r;
  }
}

EcPoint? _mul(EcPoint p, BigInt k) => _Jac.from(p).mul(k % P256.n).toAffine();

// ------------------------------------------------------------------ hash to curve (RFC 9380)

/// expand_message_xmd con SHA-256 (RFC 9380, §5.3.1).
Uint8List expandMessageXmd(List<int> msg, List<int> dst, int lenInBytes) {
  const int bInBytes = 32;
  const int sInBytes = 64;
  final int ell = (lenInBytes + bInBytes - 1) ~/ bInBytes;
  if (ell > 255 || lenInBytes > 65535 || dst.length > 255) {
    throw ArgumentError('Parametri non validi');
  }
  final List<int> dstPrime = <int>[...dst, dst.length];
  final List<int> b0 = sha256.convert(<int>[
    ...List<int>.filled(sInBytes, 0),
    ...msg,
    (lenInBytes >> 8) & 0xff,
    lenInBytes & 0xff,
    0,
    ...dstPrime,
  ]).bytes;
  final List<List<int>> blocks = <List<int>>[
    sha256.convert(<int>[...b0, 1, ...dstPrime]).bytes,
  ];
  for (int i = 2; i <= ell; i++) {
    final List<int> prev = blocks.last;
    final List<int> x = List<int>.generate(32, (int j) => b0[j] ^ prev[j]);
    blocks.add(sha256.convert(<int>[...x, i, ...dstPrime]).bytes);
  }
  return Uint8List.fromList(blocks.expand((List<int> e) => e).take(lenInBytes).toList());
}

/// hash_to_field per P-256 (m = 1, L = 48): [count] elementi del campo.
List<BigInt> hashToField(List<int> msg, List<int> dst, int count) {
  const int l = 48;
  final Uint8List bytes = expandMessageXmd(msg, dst, count * l);
  return <BigInt>[
    for (int i = 0; i < count; i++) _fromBytes(bytes.sublist(i * l, (i + 1) * l)) % P256.p,
  ];
}

/// Simplified SWU per P-256 (Z = -10), RFC 9380 §6.6.2.
EcPoint mapToCurveSswu(BigInt u) {
  final BigInt z = P256.p - BigInt.from(10);
  final BigInt u2 = _mod(u * u);
  final BigInt tv1Den = _mod(z * z * u2 * u2 + z * u2);
  BigInt x1;
  if (tv1Den == BigInt.zero) {
    x1 = _mod(P256.b * _inv(_mod(z * P256.a)));
  } else {
    final BigInt tv1 = _inv(tv1Den);
    x1 = _mod((P256.p - P256.b) * _inv(P256.a) * (BigInt.one + tv1));
  }
  final BigInt gx1 = _mod(x1 * x1 * x1 + P256.a * x1 + P256.b);
  final BigInt x2 = _mod(z * u2 * x1);
  final BigInt gx2 = _mod(x2 * x2 * x2 + P256.a * x2 + P256.b);
  final BigInt? y1 = _sqrt(gx1);
  BigInt x;
  BigInt y;
  if (y1 != null) {
    x = x1;
    y = y1;
  } else {
    x = x2;
    y = _sqrt(gx2)!;
  }
  if (u.isOdd != y.isOdd) y = _mod(P256.p - y);
  return EcPoint(x, y);
}

/// hash_to_curve P256_XMD:SHA-256_SSWU_RO_ (cofattore 1).
EcPoint hashToCurve(List<int> msg, List<int> dst) {
  final List<BigInt> u = hashToField(msg, dst, 2);
  final _Jac q = _Jac.from(mapToCurveSswu(u[0])).add(_Jac.from(mapToCurveSswu(u[1])));
  final EcPoint? r = q.toAffine();
  if (r == null) throw StateError('Punto all\'infinito');
  return r;
}

// ------------------------------------------------------------------ OPRF (RFC 9497)

/// Numero accecato pronto da inviare al server, con il fattore per toglierlo dopo.
class BlindedInput {
  const BlindedInput({required this.input, required this.blind, required this.blinded});

  final Uint8List input;
  final BigInt blind;

  /// Elemento accecato in formato compresso (33 byte).
  final Uint8List blinded;
}

abstract final class P256Oprf {
  /// contextString = "OPRFV1-" || I2OSP(modeOPRF = 0, 1) || "-" || "P256-SHA256".
  static final List<int> contextString = <int>[
    ...ascii.encode('OPRFV1-'),
    0,
    ...ascii.encode('-P256-SHA256'),
  ];

  static final List<int> hashToGroupDst = <int>[
    ...ascii.encode('HashToGroup-'),
    ...contextString,
  ];

  static BigInt randomScalar([Random? random]) {
    final Random r = random ?? Random.secure();
    while (true) {
      final BigInt k = _fromBytes(List<int>.generate(32, (_) => r.nextInt(256)));
      if (k > BigInt.zero && k < P256.n) return k;
    }
  }

  /// Blind(input): ritorna il fattore casuale e l'elemento da inviare.
  static BlindedInput blind(List<int> input, {BigInt? blind}) {
    final EcPoint h = hashToCurve(input, hashToGroupDst);
    final BigInt r = blind ?? randomScalar();
    final EcPoint? blinded = _mul(h, r);
    if (blinded == null) throw StateError('Elemento non valido');
    return BlindedInput(
      input: Uint8List.fromList(input),
      blind: r,
      blinded: blinded.toCompressed(),
    );
  }

  /// Finalize(input, blind, evaluatedElement) → 32 byte.
  static Uint8List finalize(BlindedInput b, Uint8List evaluated) {
    final EcPoint e = EcPoint.fromCompressed(evaluated);
    final EcPoint? unblinded = _mul(e, b.blind.modInverse(P256.n));
    if (unblinded == null) throw StateError('Elemento non valido');
    final Uint8List u = unblinded.toCompressed();
    return Uint8List.fromList(
      sha256.convert(<int>[
        (b.input.length >> 8) & 0xff,
        b.input.length & 0xff,
        ...b.input,
        (u.length >> 8) & 0xff,
        u.length & 0xff,
        ...u,
        ...ascii.encode('Finalize'),
      ]).bytes,
    );
  }

  /// BlindEvaluate lato server: solo per i test (la chiave vera sta solo sul server).
  static Uint8List blindEvaluateForTest(BigInt key, Uint8List blinded) =>
      _mul(EcPoint.fromCompressed(blinded), key)!.toCompressed();
}

String toHex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String hex) => Uint8List.fromList(<int>[
  for (int i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
]);

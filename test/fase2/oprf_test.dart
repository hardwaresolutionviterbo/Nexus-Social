import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/core/crypto/p256_oprf.dart';

/// Vettori di prova ufficiali: RFC 9380 J.1.1 (hash_to_curve) e RFC 9497 A.3.1 (OPRF P-256).
void main() {
  group('RFC 9380 · P256_XMD:SHA-256_SSWU_RO_', () {
    final List<int> dst = ascii.encode('QUUX-V01-CS02-with-P256_XMD:SHA-256_SSWU_RO_');
    final Map<String, (String, String)> vectors = <String, (String, String)>{
      '': (
        '2c15230b26dbc6fc9a37051158c95b79656e17a1a920b11394ca91c44247d3e4',
        '8a7a74985cc5c776cdfe4b1f19884970453912e9d31528c060be9ab5c43e8415',
      ),
      'abc': (
        '0bb8b87485551aa43ed54f009230450b492fead5f1cc91658775dac4a3388a0f',
        '5c41b3d0731a27a7b14bc0bf0ccded2d8751f83493404c84a88e71ffd424212e',
      ),
      'abcdef0123456789': (
        '65038ac8f2b1def042a5df0b33b1f4eca6bff7cb0f9c6c1526811864e544ed80',
        'cad44d40a656e7aff4002a8de287abc8ae0482b5ae825822bb870d6df9b56ca3',
      ),
    };
    vectors.forEach((String msg, (String, String) xy) {
      test('msg = "$msg"', () {
        final EcPoint p = hashToCurve(ascii.encode(msg), dst);
        expect(p.x.toRadixString(16).padLeft(64, '0'), xy.$1);
        expect(p.y.toRadixString(16).padLeft(64, '0'), xy.$2);
      });
    });

    test('u[0], u[1] di "abc"', () {
      final List<BigInt> u = hashToField(ascii.encode('abc'), dst, 2);
      expect(u[0].toRadixString(16).padLeft(64, '0'),
          'afe47f2ea2b10465cc26ac403194dfb68b7f5ee865cda61e9f3e07a537220af1');
      expect(u[1].toRadixString(16).padLeft(64, '0'),
          '379a27833b0bfe6f7bdca08e1e83c760bf9a338ab335542704edcd69ce9e46e0');
    });
  });

  group('RFC 9497 A.3.1 · OPRF(P-256, SHA-256)', () {
    final BigInt skSm = BigInt.parse(
      '159749d750713afe245d2d39ccfaae8381c53ce92d098a9375ee70739c7ac0bf',
      radix: 16,
    );
    final BigInt blind = BigInt.parse(
      '3338fa65ec36e0290022b48eb562889d89dbfa691d1cde91517fa222ed7ad364',
      radix: 16,
    );
    final List<(String, String, String, String)> vectors = <(String, String, String, String)>[
      (
        '00',
        '03723a1e5c09b8b9c18d1dcbca29e8007e95f14f4732d9346d490ffc195110368d',
        '030de02ffec47a1fd53efcdd1c6faf5bdc270912b8749e783c7ca75bb412958832',
        'a0b34de5fa4c5b6da07e72af73cc507cceeb48981b97b7285fc375345fe495dd',
      ),
      (
        '5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a',
        '03cc1df781f1c2240a64d1c297b3f3d16262ef5d4cf102734882675c26231b0838',
        '03a0395fe3828f2476ffcd1f4fe540e5a8489322d398be3c4e5a869db7fcb7c52c',
        'c748ca6dd327f0ce85f4ae3a8cd6d4d5390bbb804c9e12dcf94f853fece3dcce',
      ),
    ];
    for (final (String input, String blinded, String evaluated, String output) in vectors) {
      test('Input = $input', () {
        final BlindedInput b = P256Oprf.blind(fromHex(input), blind: blind);
        expect(toHex(b.blinded), blinded);
        expect(toHex(P256Oprf.blindEvaluateForTest(skSm, b.blinded)), evaluated);
        expect(toHex(P256Oprf.finalize(b, fromHex(evaluated))), output);
      });
    }

    test('con fattori casuali il risultato è sempre lo stesso', () {
      final BlindedInput b1 = P256Oprf.blind(utf8.encode('+393000000001'));
      final BlindedInput b2 = P256Oprf.blind(utf8.encode('+393000000001'));
      expect(toHex(b1.blinded), isNot(toHex(b2.blinded)));
      final String o1 = toHex(P256Oprf.finalize(b1, P256Oprf.blindEvaluateForTest(skSm, b1.blinded)));
      final String o2 = toHex(P256Oprf.finalize(b2, P256Oprf.blindEvaluateForTest(skSm, b2.blinded)));
      expect(o1, o2);
    });

    test('punto non valido dal server: rifiutato', () {
      expect(() => EcPoint.fromCompressed(fromHex('04${'00' * 32}')), throwsFormatException);
    });
  });
}

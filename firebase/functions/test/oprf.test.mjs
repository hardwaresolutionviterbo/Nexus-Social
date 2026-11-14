// Vettori di prova ufficiali RFC 9497 A.3.1 (OPRF P-256, SHA-256). Nessun emulatore.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { attest, blindEvaluate, evaluate, parseKey } from '../oprf.js';

const skSm = parseKey('159749d750713afe245d2d39ccfaae8381c53ce92d098a9375ee70739c7ac0bf');

const vettori = [
  {
    input: '00',
    blinded: '03723a1e5c09b8b9c18d1dcbca29e8007e95f14f4732d9346d490ffc195110368d',
    evaluated: '030de02ffec47a1fd53efcdd1c6faf5bdc270912b8749e783c7ca75bb412958832',
    output: 'a0b34de5fa4c5b6da07e72af73cc507cceeb48981b97b7285fc375345fe495dd',
  },
  {
    input: '5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a',
    blinded: '03cc1df781f1c2240a64d1c297b3f3d16262ef5d4cf102734882675c26231b0838',
    evaluated: '03a0395fe3828f2476ffcd1f4fe540e5a8489322d398be3c4e5a869db7fcb7c52c',
    output: 'c748ca6dd327f0ce85f4ae3a8cd6d4d5390bbb804c9e12dcf94f853fece3dcce',
  },
];

for (const v of vettori) {
  test(`RFC 9497 A.3.1 · Input = ${v.input}`, () => {
    assert.equal(blindEvaluate(skSm, v.blinded), v.evaluated);
    assert.equal(evaluate(skSm, Buffer.from(v.input, 'hex')), v.output);
  });
}

test('elementi non validi rifiutati', () => {
  assert.throws(() => blindEvaluate(skSm, '04' + '00'.repeat(64)));
  assert.throws(() => blindEvaluate(skSm, '02' + 'ff'.repeat(32)));
  assert.throws(() => blindEvaluate(skSm, 'nonhex'));
});

test('chiavi non valide rifiutate', () => {
  assert.throws(() => parseKey('00'.repeat(32)));
  assert.throws(() => parseKey('ff'.repeat(32)));
  assert.throws(() => parseKey('corta'));
});

test('firma per Supabase: deterministica, legata a tutti i campi', () => {
  const a = attest('chiave', 'u1', '+393000000001', 'ab', 1);
  assert.equal(a, attest('chiave', 'u1', '+393000000001', 'ab', 1));
  assert.notEqual(a, attest('chiave', 'u2', '+393000000001', 'ab', 1));
  assert.match(a, /^[0-9a-f]{64}$/);
});

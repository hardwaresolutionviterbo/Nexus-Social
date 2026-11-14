// OPRF(P-256, SHA-256), modalità OPRF (RFC 9497 §4.3), lato server. Rubrica (decisione S6).
//
// Il server riceve solo elementi «accecati» dal telefono e li moltiplica per la sua chiave
// segreta: non vede mai i numeri. Calcola in chiaro solo il codice del numero dell'utente
// stesso, preso dal suo token di accesso, per inserirlo nell'indice di chi vuole farsi
// trovare. Verificato con i vettori di prova ufficiali (test/oprf.test.mjs).
import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

import { hashToCurve, p256 } from '@noble/curves/p256';

const N = p256.CURVE.n;
const CONTEXT = Buffer.concat([
  Buffer.from('OPRFV1-'),
  Buffer.from([0]),
  Buffer.from('-P256-SHA256'),
]);
const DST_GROUP = Buffer.concat([Buffer.from('HashToGroup-'), CONTEXT]);

/** Chiave segreta (64 cifre esadecimali) → scalare valido. */
export function parseKey(hex) {
  if (typeof hex !== 'string' || !/^[0-9a-f]{64}$/i.test(hex.trim())) {
    throw new Error('Chiave OPRF non valida');
  }
  const k = BigInt(`0x${hex.trim()}`);
  if (k <= 0n || k >= N) throw new Error('Chiave OPRF non valida');
  return k;
}

/** BlindEvaluate: k · elemento accecato. Rifiuta punti non validi o all'infinito. */
export function blindEvaluate(key, blindedHex) {
  if (typeof blindedHex !== 'string' || !/^0[23][0-9a-f]{64}$/i.test(blindedHex)) {
    throw new Error('Elemento non valido');
  }
  const point = p256.ProjectivePoint.fromHex(blindedHex); // verifica che sia sulla curva
  point.assertValidity();
  return Buffer.from(point.multiply(key).toRawBytes(true)).toString('hex');
}

/** Evaluate(k, input) (RFC 9497 §3.3.1): codice in chiaro, solo per il proprio numero. */
export function evaluate(key, input) {
  const bytes = Buffer.from(input);
  const h = hashToCurve(bytes, { DST: DST_GROUP });
  const issued = Buffer.from(
    p256.ProjectivePoint.fromAffine(h.toAffine()).multiply(key).toRawBytes(true),
  );
  const len = (n) => Buffer.from([(n >> 8) & 0xff, n & 0xff]);
  return createHash('sha256')
    .update(Buffer.concat([len(bytes.length), bytes, len(issued.length), issued, Buffer.from('Finalize')]))
    .digest('hex');
}

/** Firma del server per Supabase: uid|telefono|codice|istante, con chiave condivisa. */
export function attest(attestKey, uid, phone, tag, ts) {
  return createHmac('sha256', attestKey).update(`${uid}|${phone}|${tag}|${ts}`).digest('hex');
}

export function sameHex(a, b) {
  const x = Buffer.from(a, 'hex');
  const y = Buffer.from(b, 'hex');
  return x.length === y.length && timingSafeEqual(x, y);
}

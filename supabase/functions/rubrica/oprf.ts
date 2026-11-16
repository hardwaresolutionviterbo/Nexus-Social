// OPRF(P-256, SHA-256), modalità OPRF (RFC 9497 §4.3), lato server. Rubrica (decisione S6).
//
// Stesso calcolo delle vecchie Cloud Functions (firebase/functions/oprf.js), ora dentro
// Supabase: il server riceve solo elementi «accecati» dal telefono e li moltiplica per la sua
// chiave segreta, senza vedere i numeri; calcola in chiaro solo il codice del numero
// dell'utente stesso, preso dal suo token di accesso. Verificato con i vettori ufficiali.
import { hashToCurve, p256 } from 'npm:@noble/curves@1.9.7/p256';

const N = p256.CURVE.n;
const enc = new TextEncoder();
const CONTEXT = concat(enc.encode('OPRFV1-'), new Uint8Array([0]), enc.encode('-P256-SHA256'));
const DST_GROUP = concat(enc.encode('HashToGroup-'), CONTEXT);

export function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let i = 0;
  for (const p of parts) {
    out.set(p, i);
    i += p.length;
  }
  return out;
}

export function toHex(b: Uint8Array): string {
  return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
}

export function fromHex(h: string): Uint8Array {
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.slice(2 * i, 2 * i + 2), 16);
  return out;
}

/** Chiave segreta (64 cifre esadecimali) → scalare valido. */
export function parseKey(hex: unknown): bigint {
  if (typeof hex !== 'string' || !/^[0-9a-f]{64}$/i.test(hex.trim())) {
    throw new Error('Chiave OPRF non valida');
  }
  const k = BigInt(`0x${hex.trim()}`);
  if (k <= 0n || k >= N) throw new Error('Chiave OPRF non valida');
  return k;
}

/** BlindEvaluate: k · elemento accecato. Rifiuta punti non validi o all'infinito. */
export function blindEvaluate(key: bigint, blindedHex: unknown): string {
  if (typeof blindedHex !== 'string' || !/^0[23][0-9a-f]{64}$/i.test(blindedHex)) {
    throw new Error('Elemento non valido');
  }
  const point = p256.ProjectivePoint.fromHex(blindedHex);
  point.assertValidity();
  return toHex(point.multiply(key).toRawBytes(true));
}

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new Uint8Array(data)));
}

/** Evaluate(k, input) (RFC 9497 §3.3.1): codice in chiaro, solo per il proprio numero. */
export async function evaluate(key: bigint, input: Uint8Array): Promise<string> {
  const h = hashToCurve(input, { DST: DST_GROUP });
  const issued = p256.ProjectivePoint.fromAffine(h.toAffine()).multiply(key).toRawBytes(true);
  const len = (n: number) => new Uint8Array([(n >> 8) & 0xff, n & 0xff]);
  return toHex(await sha256(concat(len(input.length), input, len(issued.length), issued, enc.encode('Finalize'))));
}

/** Firma per il database: uid|telefono|codice|istante, con la chiave condivisa (0006, 0018). */
export async function attest(
  attestKey: string,
  uid: string,
  phone: string,
  tag: string,
  ts: number,
): Promise<string> {
  const k = await crypto.subtle.importKey('raw', enc.encode(attestKey), { name: 'HMAC', hash: 'SHA-256' }, false, [
    'sign',
  ]);
  return toHex(new Uint8Array(await crypto.subtle.sign('HMAC', k, enc.encode(`${uid}|${phone}|${tag}|${ts}`))));
}

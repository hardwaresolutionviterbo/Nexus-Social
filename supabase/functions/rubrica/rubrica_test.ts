// Test della funzione `rubrica` (Deno, senza servizi reali): vettori ufficiali RFC 9497,
// controllo dei token Firebase con chiavi di prova generate qui, regole e limiti.
import { assert, assertEquals, assertRejects, assertThrows } from 'jsr:@std/assert@1';
import { createLocalJWKSet, exportJWK, generateKeyPair, type JWTVerifyGetKey, SignJWT } from 'npm:jose@5.9.6';

import { attest, blindEvaluate, evaluate, fromHex, parseKey } from './oprf.ts';
import { TokenError, verifyFirebaseToken } from './firebase_token.ts';
import { type Deps, handle, MAX_NUMERI } from './handler.ts';

const SK_HEX = '159749d750713afe245d2d39ccfaae8381c53ce92d098a9375ee70739c7ac0bf';
const SK = parseKey(SK_HEX);
const VETTORI = [
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

for (const v of VETTORI) {
  Deno.test(`RFC 9497 A.3.1 · Input = ${v.input}`, async () => {
    assertEquals(blindEvaluate(SK, v.blinded), v.evaluated);
    assertEquals(await evaluate(SK, fromHex(v.input)), v.output);
  });
}

Deno.test('elementi e chiavi non validi rifiutati', () => {
  assertThrows(() => blindEvaluate(SK, '04' + '00'.repeat(64)));
  assertThrows(() => blindEvaluate(SK, '02' + 'ff'.repeat(32)));
  assertThrows(() => blindEvaluate(SK, 'nonhex'));
  assertThrows(() => parseKey('00'.repeat(32)));
  assertThrows(() => parseKey('ff'.repeat(32)));
  assertThrows(() => parseKey(null));
});

Deno.test('firma uguale a quella che controlla il database (register_my_phone)', async () => {
  assertEquals(
    await attest('chiave-di-firma-solo-per-test-0123456789', 'utenteA', '+393331234567', 'abcd', 1700000000),
    '17d6834efb5ecfc2143752cbfc59da28a1e0dc97b90b1340f2cfa7f7abd1e848',
  );
});

// ---------------------------------------------------------------- token Firebase di prova
const PROJECT = 'progetto-di-prova';
const { publicKey, privateKey } = await generateKeyPair('RS256');
const jwk = { ...(await exportJWK(publicKey)), kid: 'prova', alg: 'RS256' };
const KEYS: JWTVerifyGetKey = createLocalJWKSet({ keys: [jwk] });

function firebaseToken(over: Record<string, unknown> = {}, opts: { exp?: string; key?: CryptoKey } = {}) {
  const claims = {
    phone_number: '+393331234567',
    firebase: { sign_in_provider: 'phone' },
    ...over,
  };
  return new SignJWT(claims)
    .setProtectedHeader({ alg: 'RS256', kid: 'prova' })
    .setIssuer((over.iss as string) ?? `https://securetoken.google.com/${PROJECT}`)
    .setAudience((over.aud as string) ?? PROJECT)
    .setSubject((over.sub as string) ?? 'utenteA')
    .setIssuedAt()
    .setExpirationTime(opts.exp ?? '1h')
    .sign(opts.key ?? privateKey);
}

Deno.test('token valido con accesso dal telefono', async () => {
  const u = await verifyFirebaseToken(await firebaseToken(), PROJECT, KEYS);
  assertEquals(u, { uid: 'utenteA', phone: '+393331234567' });
});

Deno.test('token di altri progetti, scaduti, falsi o senza telefono rifiutati', async () => {
  const other = await generateKeyPair('RS256');
  const casi = [
    await firebaseToken({ aud: 'altro-progetto' }),
    await firebaseToken({ iss: 'https://securetoken.google.com/altro-progetto' }),
    await firebaseToken({}, { exp: '-10m' }),
    await firebaseToken({}, { key: other.privateKey }),
    await firebaseToken({ firebase: { sign_in_provider: 'password' } }),
    await firebaseToken({ sub: 'uid con spazi' }),
    'non.un.token',
  ];
  for (const t of casi) {
    await assertRejects(() => verifyFirebaseToken(t, PROJECT, KEYS), TokenError);
  }
});

// ---------------------------------------------------------------- regole della funzione
function deps(over: Partial<Deps> & { used?: Map<string, number> } = {}): Deps {
  const used = over.used ?? new Map<string, number>();
  return {
    config: async () => ({
      oprfKey: SK_HEX,
      attestKey: 'chiave-di-firma-solo-per-test-0123456789',
      firebaseProjectId: PROJECT,
    }),
    consume: async (uid, kind, max) => {
      const k = `${uid}|${kind}`;
      const n = used.get(k) ?? 0;
      if (n >= max) return false;
      used.set(k, n + 1);
      return true;
    },
    verify: (token, projectId) => verifyFirebaseToken(token, projectId, KEYS),
    now: () => 1700000000000,
    ...over,
  };
}

async function call(body: unknown, token?: string, d: Deps = deps(), method = 'POST') {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await handle(
    new Request('http://localhost/rubrica', { method, headers, body: method === 'POST' ? JSON.stringify(body) : undefined }),
    d,
  );
  return { status: res.status, body: await res.json().catch(() => null) };
}

Deno.test('valuta: applica la chiave agli elementi accecati', async () => {
  const r = await call({ azione: 'valuta', elementi: [VETTORI[0].blinded] }, await firebaseToken());
  assertEquals(r.status, 200);
  assertEquals(r.body.valutati, [VETTORI[0].evaluated]);
});

Deno.test('senza accesso, con dati non validi o troppi numeri: rifiutata', async () => {
  const t = await firebaseToken();
  assertEquals((await call({ azione: 'valuta', elementi: [VETTORI[0].blinded] })).status, 401);
  assertEquals((await call({ azione: 'valuta', elementi: ['xx'] }, t)).status, 400);
  assertEquals((await call({ azione: 'valuta', elementi: [] }, t)).status, 400);
  const tanti = Array(MAX_NUMERI + 1).fill(VETTORI[0].blinded);
  assertEquals((await call({ azione: 'valuta', elementi: tanti }, t)).status, 400);
  assertEquals((await call({ azione: 'altro' }, t)).status, 400);
  assertEquals((await call(null, t, deps(), 'GET')).status, 405);
});

Deno.test('al massimo 3 sincronizzazioni al giorno', async () => {
  const t = await firebaseToken();
  const d = deps();
  for (let i = 0; i < 3; i++) {
    assertEquals((await call({ azione: 'valuta', elementi: [VETTORI[0].blinded] }, t, d)).status, 200);
  }
  const quarta = await call({ azione: 'valuta', elementi: [VETTORI[0].blinded] }, t, d);
  assertEquals(quarta.status, 429);
  assertEquals(quarta.body.errore, 'limite');
});

Deno.test('mio numero: codice del proprio numero, firmato per il database', async () => {
  const r = await call({ azione: 'mio_numero' }, await firebaseToken());
  assertEquals(r.status, 200);
  assertEquals(r.body.telefono, '+393331234567');
  assertEquals(r.body.istante, 1700000000);
  assertEquals(r.body.codice, await evaluate(SK, new TextEncoder().encode('+393331234567')));
  assertEquals(
    r.body.firma,
    await attest('chiave-di-firma-solo-per-test-0123456789', 'utenteA', '+393331234567', r.body.codice, 1700000000),
  );
  const senza = await call({ azione: 'mio_numero' }, await firebaseToken({ phone_number: undefined }));
  assertEquals(senza.status, 400);
});

Deno.test('rubrica non ancora pronta (chiavi assenti): 503 e nessun calcolo', async () => {
  const d = deps({
    config: async () => ({ oprfKey: null, attestKey: null, firebaseProjectId: PROJECT }),
  });
  const r = await call({ azione: 'valuta', elementi: [VETTORI[0].blinded] }, await firebaseToken(), d);
  assertEquals(r.status, 503);
  assert(r.body.valutati === undefined);
});

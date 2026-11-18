// Test della funzione `notifiche` senza rete e senza chiavi vere: la chiave di servizio è
// generata qui, l'invio a FCM è simulato.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { exportPKCS8, generateKeyPair, jwtVerify } from 'npm:jose@5.9.6';

import { buildMessage, FCM_SCOPE, parseServiceAccount, type QueueRow, readSendResult, signAssertion, TOKEN_URL } from './fcm.ts';
import { type Deps, handle, sameSecret } from './handler.ts';

async function fakeAccount() {
  const { privateKey, publicKey } = await generateKeyPair('RS256', { extractable: true });
  const pem = await exportPKCS8(privateKey);
  const raw = JSON.stringify({ project_id: 'progetto-prova', client_email: 'notifiche@prova.iam', private_key: pem });
  return { sa: parseServiceAccount(raw)!, publicKey };
}

const row = (n: number, fid = `fidTelefono${n}xxxxxxxxxxxx`): QueueRow => ({
  queue_id: n,
  fid,
  platform: 'android',
  kind: 'chat',
  conversation_id: '00000000-0000-4000-8000-000000000001',
  collapse_key: 'chat:00000000-0000-4000-8000-000000000001',
  title: 'Anna R.',
  body: 'Nuovo messaggio',
});

Deno.test('chiave di servizio: letta solo se completa', () => {
  assertEquals(parseServiceAccount(undefined), null);
  assertEquals(parseServiceAccount('non json'), null);
  assertEquals(parseServiceAccount(JSON.stringify({ project_id: 'x', client_email: 'y' })), null);
});

Deno.test('richiesta di accesso a Google firmata con la chiave di servizio', async () => {
  const { sa, publicKey } = await fakeAccount();
  const jwt = await signAssertion(sa, Math.floor(Date.now() / 1000));
  const { payload } = await jwtVerify(jwt, publicKey, { audience: TOKEN_URL, issuer: 'notifiche@prova.iam' });
  assertEquals(payload.scope, FCM_SCOPE);
  assert((payload.exp ?? 0) - (payload.iat ?? 0) <= 3600);
});

Deno.test('messaggio FCM: al telefono (FID), raggruppato per chat, senza contenuti', () => {
  const m = buildMessage(row(1)) as { message: Record<string, any> };
  assertEquals(m.message.fid, 'fidTelefono1xxxxxxxxxxxx');
  assertEquals(m.message.notification, { title: 'Anna R.', body: 'Nuovo messaggio' });
  assertEquals(m.message.android.notification.tag, 'chat:00000000-0000-4000-8000-000000000001');
  assertEquals(m.message.data.chat, '00000000-0000-4000-8000-000000000001');
  assertEquals(m.message.token, undefined);
  assertEquals(m.message.data.notifica, '');
});

Deno.test('notifica di un commento: porta l\'identificativo per aprire l\'annuncio', () => {
  const m = buildMessage({ ...row(1), kind: 'comment', conversation_id: null, collapse_key: 'n:abc-123' }) as {
    message: Record<string, any>;
  };
  assertEquals(m.message.data, { tipo: 'comment', chat: '', notifica: 'abc-123' });
});

Deno.test('risposte di FCM: ok, telefono sparito, errore temporaneo', () => {
  assertEquals(readSendResult(200, {}), { ok: true, gone: false });
  assertEquals(readSendResult(404, { error: { status: 'NOT_FOUND' } }), { ok: false, gone: true });
  assertEquals(readSendResult(400, { error: { details: [{ errorCode: 'UNREGISTERED' }] } }), { ok: false, gone: true });
  assertEquals(readSendResult(503, {}), { ok: false, gone: false });
});

Deno.test('segreto confrontato per intero', () => {
  assert(sameSecret('abc', 'abc'));
  assert(!sameSecret('abc', 'abd'));
  assert(!sameSecret('abc', 'abcd'));
});

function deps(over: Partial<Deps> & { queue?: QueueRow[] } = {}) {
  const queue = [...(over.queue ?? [])];
  const dropped: string[] = [];
  const sent: Record<string, unknown>[] = [];
  const d: Deps = {
    secret: async () => 'segreto',
    serviceAccount: () => ({ projectId: 'progetto-prova', clientEmail: 'x', privateKey: 'y' }),
    claim: async (limit) => queue.splice(0, limit),
    drop: async (fid) => {
      dropped.push(fid);
    },
    accessToken: async () => 'token-di-prova',
    send: async (_p, _t, m) => {
      sent.push(m);
      const fid = (m as any).message.fid as string;
      return fid.startsWith('fidSparito') ? { status: 404, body: {} } : { status: 200, body: {} };
    },
    ...over,
  };
  return { d, dropped, sent };
}

const post = (secret?: string) =>
  new Request('http://x/notifiche', { method: 'POST', headers: secret ? { 'x-push-secret': secret } : {} });

Deno.test('senza segreto giusto: 401, nessun invio', async () => {
  const { d, sent } = deps({ queue: [row(1)] });
  assertEquals((await handle(post(), d)).status, 401);
  assertEquals((await handle(post('sbagliato'), d)).status, 401);
  assertEquals(sent.length, 0);
});

Deno.test('senza chiave di servizio: 503', async () => {
  const { d } = deps({ serviceAccount: () => null });
  assertEquals((await handle(post('segreto'), d)).status, 503);
});

Deno.test('manda tutta la coda e toglie i telefoni non più registrati', async () => {
  const { d, dropped, sent } = deps({ queue: [row(1), row(2, 'fidSparitoxxxxxxxxxxxx'), row(3)] });
  const res = await handle(post('segreto'), d);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { inviate: 2, fallite: 1, rimosse: 1 });
  assertEquals(sent.length, 3);
  assertEquals(dropped, ['fidSparitoxxxxxxxxxxxx']);
});

Deno.test('chiamata in arrivo: la notifica scade dopo 45 secondi', () => {
  const m = buildMessage({ ...row(1), kind: 'call', collapse_key: 'call:00000000-0000-4000-8000-000000000001' }) as {
    message: Record<string, any>;
  };
  assertEquals(m.message.android.ttl, '45s');
  assertEquals(m.message.data.tipo, 'call');
  assertEquals((buildMessage(row(2)) as { message: Record<string, any> }).message.android.ttl, undefined);
});

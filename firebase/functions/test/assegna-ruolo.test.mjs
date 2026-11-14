// Test della Cloud Function assegnaRuolo sugli emulatori locali (Auth e Functions).
// Progetto fittizio demo-nexus-social: nessun collegamento a Firebase reale (regola F8).
import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';

import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const PROJECT = 'demo-nexus-social';
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const FUNCTIONS = 'http://127.0.0.1:5001';
const URL_FUNZIONE = `${FUNCTIONS}/${PROJECT}/europe-west1/assegnaRuolo`;
const KEY = 'chiave-finta-emulatore';

assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, 'I test girano solo sugli emulatori.');
assert.ok(PROJECT.startsWith('demo-'), 'Solo progetti fittizi demo-*.');

let app;
let adminAuth;

async function post(url, body, headers = {}) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

/** Accesso con numero di telefono sull'emulatore Auth (nessun SMS reale). */
async function accediConTelefono(numero) {
  const invio = await post(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=${KEY}`,
    { phoneNumber: numero, recaptchaToken: 'emulatore' },
  );
  assert.equal(invio.status, 200, 'invio del codice');
  const codici = await (await fetch(
    `${AUTH}/emulator/v1/projects/${PROJECT}/verificationCodes`,
  )).json();
  const codice = codici.verificationCodes
    .filter((c) => c.sessionInfo === invio.body.sessionInfo)
    .at(-1).code;
  const accesso = await post(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=${KEY}`,
    { sessionInfo: invio.body.sessionInfo, code: codice },
  );
  assert.equal(accesso.status, 200, 'accesso con codice');
  return { idToken: accesso.body.idToken, uid: accesso.body.localId };
}

async function accediConEmail(email) {
  const res = await post(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${KEY}`,
    { email, password: 'password-di-prova-123', returnSecureToken: true },
  );
  assert.equal(res.status, 200, 'registrazione con email');
  return { idToken: res.body.idToken, uid: res.body.localId };
}

function chiama(idToken) {
  const headers = idToken ? { Authorization: `Bearer ${idToken}` } : {};
  return post(URL_FUNZIONE, { data: {} }, headers);
}

function claimDelToken(idToken) {
  const payload = idToken.split('.')[1];
  return JSON.parse(Buffer.from(payload, 'base64url').toString());
}

describe('assegnaRuolo', () => {
  before(() => {
    app = initializeApp({ projectId: PROJECT }, 'test-assegna-ruolo');
    adminAuth = getAuth(app);
  });

  after(async () => {
    await deleteApp(app);
  });

  test('senza accesso: rifiutata, nessun ruolo assegnato', async () => {
    const res = await chiama(null);
    assert.equal(res.status, 401);
    assert.equal(res.body.error.status, 'UNAUTHENTICATED');
  });

  test('token falso o alterato: rifiutato', async () => {
    const { idToken } = await accediConTelefono('+393000000101');
    const [h, p] = idToken.split('.');
    const res = await chiama(`${h}.${p}.firma-falsa`);
    assert.equal(res.status, 401);
  });

  test('accesso con telefono: ruolo authenticated assegnato al solo chiamante', async () => {
    const a = await accediConTelefono('+393000000102');
    const b = await accediConTelefono('+393000000103');
    const res = await chiama(a.idToken);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.result, { ruolo: 'authenticated', aggiornato: true });
    assert.equal((await adminAuth.getUser(a.uid)).customClaims?.role, 'authenticated');
    assert.equal((await adminAuth.getUser(b.uid)).customClaims?.role, undefined);
  });

  test('seconda chiamata: nessuna modifica (assegnato una sola volta)', async () => {
    const a = await accediConTelefono('+393000000104');
    assert.equal((await chiama(a.idToken)).body.result.aggiornato, true);
    const seconda = await chiama(a.idToken);
    assert.equal(seconda.status, 200);
    assert.deepEqual(seconda.body.result, { ruolo: 'authenticated', aggiornato: false });
  });

  test('ruolo diverso già presente: sostituito con authenticated, altri claim invariati', async () => {
    const a = await accediConTelefono('+393000000105');
    await adminAuth.setCustomUserClaims(a.uid, { role: 'service_role', piano: 'prova' });
    const res = await chiama(a.idToken);
    assert.equal(res.status, 200);
    const claims = (await adminAuth.getUser(a.uid)).customClaims;
    assert.deepEqual(claims, { role: 'authenticated', piano: 'prova' });
  });

  test('accesso non con telefono: rifiutato', async () => {
    const e = await accediConEmail('prova@example.com');
    const res = await chiama(e.idToken);
    assert.equal(res.status, 403);
    assert.equal(res.body.error.status, 'PERMISSION_DENIED');
    assert.equal((await adminAuth.getUser(e.uid)).customClaims?.role, undefined);
  });

  test('dopo il rinnovo il token contiene role authenticated', async () => {
    const a = await accediConTelefono('+393000000106');
    assert.equal(claimDelToken(a.idToken).role, undefined);
    await chiama(a.idToken);
    const nuovo = await accediConTelefono('+393000000106');
    assert.equal(nuovo.uid, a.uid);
    assert.equal(claimDelToken(nuovo.idToken).role, 'authenticated');
  });
});

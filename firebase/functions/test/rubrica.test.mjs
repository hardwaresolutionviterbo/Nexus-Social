// Test delle funzioni della rubrica sugli emulatori (Auth, Functions, Firestore), progetto
// fittizio demo-nexus-social, chiave dei vettori di prova RFC 9497. Nessun servizio reale.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { attest, evaluate, parseKey } from '../oprf.js';

const PROJECT = 'demo-nexus-social';
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const BASE = `http://127.0.0.1:5001/${PROJECT}/europe-west1`;
const KEY = 'chiave-finta-emulatore';
const SK = parseKey('159749d750713afe245d2d39ccfaae8381c53ce92d098a9375ee70739c7ac0bf');
const FIRMA = 'chiave-di-firma-solo-per-emulatori-0123456789';
const BLINDED = '03723a1e5c09b8b9c18d1dcbca29e8007e95f14f4732d9346d490ffc195110368d';
const EVALUATED = '030de02ffec47a1fd53efcdd1c6faf5bdc270912b8749e783c7ca75bb412958832';

assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, 'I test girano solo sugli emulatori.');

async function post(url, body, headers = {}) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

async function accediConTelefono(numero) {
  const invio = await post(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=${KEY}`,
    { phoneNumber: numero, recaptchaToken: 'emulatore' },
  );
  const codici = await (await fetch(`${AUTH}/emulator/v1/projects/${PROJECT}/verificationCodes`)).json();
  const codice = codici.verificationCodes.filter((c) => c.sessionInfo === invio.body.sessionInfo).at(-1).code;
  const accesso = await post(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=${KEY}`,
    { sessionInfo: invio.body.sessionInfo, code: codice },
  );
  return { idToken: accesso.body.idToken, uid: accesso.body.localId };
}

function chiama(nome, dati, idToken) {
  const headers = idToken ? { Authorization: `Bearer ${idToken}` } : {};
  return post(`${BASE}/${nome}`, { data: dati }, headers);
}

describe('rubricaValuta', () => {
  test('applica la chiave all\'elemento accecato (vettore RFC 9497)', async () => {
    const u = await accediConTelefono('+393000000101');
    const r = await chiama('rubricaValuta', { elementi: [BLINDED] }, u.idToken);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.deepEqual(r.body.result.valutati, [EVALUATED]);
  });

  test('senza accesso, con email o con dati non validi: rifiutata', async () => {
    assert.notEqual((await chiama('rubricaValuta', { elementi: [BLINDED] })).status, 200);
    const email = await post(
      `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${KEY}`,
      { email: 'rubrica@example.com', password: 'password-di-prova-123', returnSecureToken: true },
    );
    assert.notEqual((await chiama('rubricaValuta', { elementi: [BLINDED] }, email.body.idToken)).status, 200);
    const u = await accediConTelefono('+393000000102');
    const troppi = await chiama('rubricaValuta', { elementi: Array(2001).fill(BLINDED) }, u.idToken);
    assert.equal(troppi.body.error.status, 'INVALID_ARGUMENT');
    const rotto = await chiama('rubricaValuta', { elementi: ['04' + '00'.repeat(64)] }, u.idToken);
    assert.equal(rotto.body.error.status, 'INVALID_ARGUMENT');
  });

  test('al massimo 3 sincronizzazioni al giorno', async () => {
    const u = await accediConTelefono('+393000000103');
    for (let i = 0; i < 3; i++) {
      assert.equal((await chiama('rubricaValuta', { elementi: [BLINDED] }, u.idToken)).status, 200);
    }
    const quarta = await chiama('rubricaValuta', { elementi: [BLINDED] }, u.idToken);
    assert.equal(quarta.body.error.status, 'RESOURCE_EXHAUSTED');
  });
});

describe('rubricaMioNumero', () => {
  test('codice del proprio numero e firma per Supabase', async () => {
    const u = await accediConTelefono('+393000000104');
    const r = await chiama('rubricaMioNumero', {}, u.idToken);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const { telefono, codice, istante, firma } = r.body.result;
    assert.equal(telefono, '+393000000104');
    assert.equal(codice, evaluate(SK, Buffer.from(telefono, 'utf8')));
    assert.equal(firma, attest(FIRMA, u.uid, telefono, codice, istante));
  });

  test('il codice non dipende da chi lo chiede: stesso numero, stesso codice', async () => {
    const tag = evaluate(SK, Buffer.from('+393000000104', 'utf8'));
    assert.match(tag, /^[0-9a-f]{64}$/);
  });
});

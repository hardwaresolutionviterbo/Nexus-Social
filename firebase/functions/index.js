// Nexus Social · Cloud Functions (Fase 2, decisione S1).
//
// assegnaRuolo: Supabase accetta i token Firebase solo se l'utente ha il claim
// personalizzato `role: "authenticated"`. Questa funzione lo assegna all'utente che la
// chiama, subito dopo l'accesso con numero di telefono. L'app poi rinnova il token.
//
// Regole:
// - solo utenti autenticati, e solo con accesso tramite numero di telefono;
// - l'utente può assegnare il ruolo solo a sé stesso;
// - il ruolo è sempre e solo "authenticated" (mai service_role o altri);
// - gli altri claim eventualmente presenti restano invariati;
// - nei log non compaiono uid, numeri di telefono o token.

import { setGlobalOptions } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { defineSecret } from 'firebase-functions/params';

import { attest, blindEvaluate, evaluate, parseKey } from './oprf.js';

export const RUOLO = 'authenticated';

initializeApp();

// Regione europea; poche istanze per contenere i costi (budget L2).
setGlobalOptions({ region: 'europe-west1', maxInstances: 5 });

export const assegnaRuolo = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Accesso richiesto.');
  }
  const provider = request.auth.token?.firebase?.sign_in_provider;
  if (provider !== 'phone') {
    throw new HttpsError('permission-denied', 'Serve l\'accesso con numero di telefono.');
  }

  const auth = getAuth();
  const user = await auth.getUser(uid);
  const claims = { ...(user.customClaims ?? {}) };
  if (claims.role === RUOLO) {
    return { ruolo: RUOLO, aggiornato: false };
  }
  claims.role = RUOLO;
  await auth.setCustomUserClaims(uid, claims);
  return { ruolo: RUOLO, aggiornato: true };
});

// ─── Rubrica (Fase 2, Blocco 5, decisione S6) ───────────────────────────────────────────
//
// rubricaValuta: applica la chiave OPRF agli elementi accecati inviati dal telefono. Il
//   server non vede i numeri. Al massimo 2.000 numeri e 3 sincronizzazioni al giorno.
// rubricaMioNumero: calcola il codice del numero dell'utente (dal suo token) e lo firma per
//   Supabase, che lo inserisce nell'indice di chi vuole farsi trovare (P8).
// Nei log non compaiono uid, numeri, elementi o codici.

const OPRF_KEY = defineSecret('OPRF_KEY');
const RUBRICA_ATTEST_KEY = defineSecret('RUBRICA_ATTEST_KEY');

export const MAX_NUMERI = 2000;
export const MAX_SINCRONIZZAZIONI_GIORNO = 3;
export const MAX_MIO_NUMERO_GIORNO = 5;

function utenteTelefono(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Accesso richiesto.');
  if (request.auth.token?.firebase?.sign_in_provider !== 'phone') {
    throw new HttpsError('permission-denied', 'Serve l\'accesso con numero di telefono.');
  }
  return uid;
}

/** Contatore giornaliero per utente (documento non leggibile dai client). */
async function consumaLimite(uid, tipo, massimo) {
  const giorno = new Date().toISOString().slice(0, 10);
  const ref = getFirestore().doc(`limiti_rubrica/${uid}`);
  await getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const dati = snap.exists ? snap.data() : {};
    const usati = dati.giorno === giorno ? (dati[tipo] ?? 0) : 0;
    if (usati >= massimo) {
      throw new HttpsError('resource-exhausted', 'Limite giornaliero raggiunto. Riprova domani.');
    }
    const base = dati.giorno === giorno ? dati : { giorno };
    tx.set(ref, { ...base, giorno, [tipo]: usati + 1, aggiornato: FieldValue.serverTimestamp() });
  });
}

export const rubricaValuta = onCall({ secrets: [OPRF_KEY] }, async (request) => {
  const uid = utenteTelefono(request);
  const elementi = request.data?.elementi;
  if (!Array.isArray(elementi) || elementi.length === 0 || elementi.length > MAX_NUMERI) {
    throw new HttpsError('invalid-argument', `Da 1 a ${MAX_NUMERI} numeri per sincronizzazione.`);
  }
  let chiave;
  try {
    chiave = parseKey(OPRF_KEY.value());
  } catch {
    throw new HttpsError('failed-precondition', 'Rubrica non ancora disponibile.');
  }
  let valutati;
  try {
    valutati = elementi.map((e) => blindEvaluate(chiave, e));
  } catch {
    throw new HttpsError('invalid-argument', 'Dati non validi.');
  }
  await consumaLimite(uid, 'sincronizzazioni', MAX_SINCRONIZZAZIONI_GIORNO);
  return { valutati };
});

export const rubricaMioNumero = onCall(
  { secrets: [OPRF_KEY, RUBRICA_ATTEST_KEY] },
  async (request) => {
    const uid = utenteTelefono(request);
    const telefono = request.auth.token?.phone_number;
    if (typeof telefono !== 'string' || !/^\+[1-9][0-9]{6,14}$/.test(telefono)) {
      throw new HttpsError('failed-precondition', 'Numero di telefono non disponibile.');
    }
    let chiave;
    try {
      chiave = parseKey(OPRF_KEY.value());
    } catch {
      throw new HttpsError('failed-precondition', 'Rubrica non ancora disponibile.');
    }
    const firma = RUBRICA_ATTEST_KEY.value();
    if (typeof firma !== 'string' || firma.length < 32) {
      throw new HttpsError('failed-precondition', 'Rubrica non ancora disponibile.');
    }
    await consumaLimite(uid, 'mioNumero', MAX_MIO_NUMERO_GIORNO);
    const codice = evaluate(chiave, Buffer.from(telefono, 'utf8'));
    const istante = Math.floor(Date.now() / 1000);
    return {
      telefono,
      codice,
      istante,
      firma: attest(firma, uid, telefono, codice, istante),
    };
  },
);

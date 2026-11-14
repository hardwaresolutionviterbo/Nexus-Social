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

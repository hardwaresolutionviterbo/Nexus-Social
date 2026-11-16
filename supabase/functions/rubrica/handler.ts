// Funzione `rubrica` di Supabase (al posto delle Cloud Functions rubricaValuta e
// rubricaMioNumero). Nei log non compaiono uid, numeri, elementi o codici.
//
// POST con il token Firebase dell'utente (Authorization: Bearer …) e uno di questi corpi:
//   { "azione": "valuta", "elementi": ["02…", …] }  → { "valutati": [...] }
//   { "azione": "mio_numero" }                      → { "telefono", "codice", "istante", "firma" }
// Errori: 401 accesso, 400 dati non validi, 429 limite del giorno, 503 rubrica non pronta.
import { attest, blindEvaluate, evaluate, parseKey } from './oprf.ts';
import { type FirebaseUser, TokenError, verifyFirebaseToken } from './firebase_token.ts';

export const MAX_NUMERI = 2000;
export const MAX_SINCRONIZZAZIONI_GIORNO = 3;
export const MAX_MIO_NUMERO_GIORNO = 5;

export interface ServerConfig {
  oprfKey: string | null;
  attestKey: string | null;
  firebaseProjectId: string | null;
}

export interface Deps {
  config(): Promise<ServerConfig>;
  /** true se l'uso è consentito (e viene contato). */
  consume(uid: string, kind: 'sincronizzazioni' | 'mio_numero', max: number): Promise<boolean>;
  verify(token: string, projectId: string): Promise<FirebaseUser>;
  now(): number;
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-device-id',
};

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

const fail = (status: number, errore: string) => reply(status, { errore });

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return fail(405, 'metodo');

  const cfg = await deps.config();
  if (!cfg.firebaseProjectId) return fail(503, 'non_disponibile');

  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) return fail(401, 'accesso');
  let user: FirebaseUser;
  try {
    user = await deps.verify(token, cfg.firebaseProjectId);
  } catch (e) {
    return fail(401, e instanceof TokenError ? 'accesso' : 'accesso');
  }

  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (typeof parsed !== 'object' || parsed === null) return fail(400, 'non_valido');
    body = parsed as Record<string, unknown>;
  } catch {
    return fail(400, 'non_valido');
  }

  let key: bigint;
  try {
    key = parseKey(cfg.oprfKey);
  } catch {
    return fail(503, 'non_disponibile');
  }

  if (body.azione === 'valuta') {
    const elementi = body.elementi;
    if (!Array.isArray(elementi) || elementi.length === 0 || elementi.length > MAX_NUMERI) {
      return fail(400, 'non_valido');
    }
    let valutati: string[];
    try {
      valutati = elementi.map((e) => blindEvaluate(key, e));
    } catch {
      return fail(400, 'non_valido');
    }
    if (!(await deps.consume(user.uid, 'sincronizzazioni', MAX_SINCRONIZZAZIONI_GIORNO))) {
      return fail(429, 'limite');
    }
    return reply(200, { valutati });
  }

  if (body.azione === 'mio_numero') {
    const phone = user.phone;
    if (typeof phone !== 'string' || !/^\+[1-9][0-9]{6,14}$/.test(phone)) {
      return fail(400, 'numero_assente');
    }
    const attestKey = cfg.attestKey;
    if (typeof attestKey !== 'string' || attestKey.length < 32) return fail(503, 'non_disponibile');
    if (!(await deps.consume(user.uid, 'mio_numero', MAX_MIO_NUMERO_GIORNO))) {
      return fail(429, 'limite');
    }
    const codice = await evaluate(key, new TextEncoder().encode(phone));
    const istante = Math.floor(deps.now() / 1000);
    return reply(200, {
      telefono: phone,
      codice,
      istante,
      firma: await attest(attestKey, user.uid, phone, codice, istante),
    });
  }

  return fail(400, 'non_valido');
}

export { verifyFirebaseToken };

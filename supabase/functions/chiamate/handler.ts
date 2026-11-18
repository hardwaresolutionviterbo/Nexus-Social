// Funzione `chiamate`: dà al telefono le credenziali temporanee del ponte TURN di Cloudflare
// per una chiamata. Le chiavi di Cloudflare restano nei secret di Supabase; al telefono arrivano
// solo credenziali che scadono dopo un'ora. Nei log solo esiti, mai identificativi.
import { type FirebaseUser, TokenError } from './firebase_token.ts';

/** Credenziali al giorno per persona (ogni chiamata ne usa una). */
export const MAX_CREDENZIALI_GIORNO = 60;
export const DURATA_SECONDI = 3600;

export interface IceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
}

export interface Deps {
  firebaseProjectId(): Promise<string | null>;
  verify(token: string, projectId: string): Promise<FirebaseUser>;
  consume(uid: string): Promise<boolean>;
  turn(): { keyId: string; apiToken: string } | null;
  generate(keyId: string, apiToken: string, ttl: number): Promise<{ status: number; body: unknown }>;
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...CORS } });
}

/** Ponte di riserva senza account: solo STUN (gratis), per quando TURN non c'è. */
export const STUN_ONLY: IceServer[] = [{ urls: ['stun:stun.cloudflare.com:3478'] }];

/** Tiene solo server validi (stun:, turn:, turns:) con le credenziali. */
export function cleanIceServers(body: unknown): IceServer[] | null {
  const list = (body as { iceServers?: unknown })?.iceServers;
  const raw = Array.isArray(list) ? list : (list && typeof list === 'object' ? [list] : []);
  const out: IceServer[] = [];
  for (const s of raw) {
    if (!s || typeof s !== 'object') continue;
    const u = (s as IceServer).urls;
    const urls = (Array.isArray(u) ? u : [u]).filter((x): x is string =>
      typeof x === 'string' && /^(stun|turn|turns):/.test(x)
    );
    if (urls.length === 0) continue;
    const item: IceServer = { urls };
    if (typeof (s as IceServer).username === 'string') item.username = (s as IceServer).username;
    if (typeof (s as IceServer).credential === 'string') item.credential = (s as IceServer).credential;
    out.push(item);
  }
  return out.length ? out : null;
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return reply(405, { errore: 'metodo' });
  const projectId = await deps.firebaseProjectId();
  if (!projectId) return reply(503, { errore: 'non_disponibile' });
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) return reply(401, { errore: 'accesso' });
  let user: FirebaseUser;
  try {
    user = await deps.verify(token, projectId);
  } catch (e) {
    return reply(401, { errore: e instanceof TokenError ? 'accesso' : 'accesso' });
  }
  if (!(await deps.consume(user.uid))) return reply(429, { errore: 'troppe_chiamate' });
  const turn = deps.turn();
  if (!turn) {
    console.log('chiamate: ponte non configurato, solo STUN');
    return reply(200, { iceServers: STUN_ONLY, ponte: false });
  }
  try {
    const r = await deps.generate(turn.keyId, turn.apiToken, DURATA_SECONDI);
    const servers = r.status >= 200 && r.status < 300 ? cleanIceServers(r.body) : null;
    if (!servers) {
      console.log(`chiamate: ponte non disponibile (${r.status}), solo STUN`);
      return reply(200, { iceServers: STUN_ONLY, ponte: false });
    }
    return reply(200, { iceServers: servers, ponte: true, scade: DURATA_SECONDI });
  } catch {
    console.log('chiamate: ponte irraggiungibile, solo STUN');
    return reply(200, { iceServers: STUN_ONLY, ponte: false });
  }
}

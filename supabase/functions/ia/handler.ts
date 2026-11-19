// Funzione `ia`: «Piazly AI» (chat) e «Immagini IA» con Cloudflare Workers AI (richiesta del
// titolare, 19/11/2026). Le chiavi di Cloudflare restano nei secret di Supabase. Nei log solo
// esiti: mai identificativi, mai testi delle domande o delle risposte.
import { type FirebaseUser, TokenError } from './firebase_token.ts';

/** Domande al giorno per persona e immagini al giorno per persona (si azzerano a mezzanotte). */
export const MAX_DOMANDE_GIORNO = 40;
export const MAX_IMMAGINI_GIORNO = 5;

export const MAX_MESSAGGI = 16;
export const MAX_CARATTERI_MESSAGGIO = 2000;
export const MAX_CARATTERI_PROMPT = 400;

export const MODELLO_TESTO = '@cf/meta/llama-3.1-8b-instruct-fast';
export const MODELLO_IMMAGINI = '@cf/black-forest-labs/flux-1-schnell';

/**
 * Le «istruzioni» di Piazly AI: è qui che l'assistente viene «addestrato» per l'app.
 * Più avanti si potrà aggiungere un adattatore LoRA addestrato sui testi dell'app.
 */
export const ISTRUZIONI = [
  'Sei «Piazly AI», l\'assistente dell\'app Piazly. Rispondi sempre in italiano, in modo breve,',
  'chiaro e gentile, come in una chat sul telefono (al massimo 8 frasi, niente tabelle).',
  'Piazly è un\'app italiana con: Chat cifrate (anche gruppi, vocali, foto, chiamate e videochiamate),',
  'Stati che spariscono dopo 24 ore, la Mappa sociale con i posti e le persone che condividono la',
  'posizione in tempo reale, e Vendita (compra, vendi, scambia e regala oggetti con annunci nel proprio',
  'comune). Nel Profilo ci sono privacy, notifiche, backup della chat e blocchi.',
  'Aiuta a usare l\'app, a scrivere annunci e messaggi, a organizzare incontri e a rispondere a domande',
  'di ogni giorno. Per incontri di persona con sconosciuti consiglia luoghi pubblici e la funzione',
  '«Condividi l\'incontro». Non chiedere mai numeri di telefono, password, codici o dati bancari.',
  'Non inventare funzioni che l\'app non ha: se non sai, dillo. Non dare consigli medici, legali o',
  'finanziari come se fossi un professionista. Non leggi le chat delle persone: vedi solo questa.',
].join(' ');

export interface ChatTurn {
  role: 'user' | 'assistant';
  content: string;
}

export interface Deps {
  firebaseProjectId(): Promise<string | null>;
  verify(token: string, projectId: string): Promise<FirebaseUser>;
  consume(uid: string, kind: 'ia_testo' | 'ia_immagini', max: number): Promise<boolean>;
  cloudflare(): { accountId: string; apiToken: string; textModel?: string; imageModel?: string } | null;
  run(accountId: string, apiToken: string, model: string, input: unknown): Promise<{ status: number; body: unknown }>;
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...CORS } });
}

/** Tiene solo i turni validi, gli ultimi [MAX_MESSAGGI], con l'ultimo della persona. */
export function cleanMessages(raw: unknown): ChatTurn[] | null {
  if (!Array.isArray(raw)) return null;
  const out: ChatTurn[] = [];
  for (const m of raw) {
    if (!m || typeof m !== 'object') continue;
    const role = (m as ChatTurn).role;
    const content = (m as ChatTurn).content;
    if ((role !== 'user' && role !== 'assistant') || typeof content !== 'string') continue;
    const text = content.trim().slice(0, MAX_CARATTERI_MESSAGGIO);
    if (text) out.push({ role, content: text });
  }
  const last = out.slice(-MAX_MESSAGGI);
  if (last.length === 0 || last[last.length - 1].role !== 'user') return null;
  return last;
}

function textOf(body: unknown): string | null {
  const r = (body as { result?: { response?: unknown } })?.result?.response;
  return typeof r === 'string' && r.trim() ? r.trim() : null;
}

function imageOf(body: unknown): string | null {
  const r = (body as { result?: { image?: unknown } })?.result?.image;
  return typeof r === 'string' && /^[A-Za-z0-9+/=]{100,}$/.test(r) ? r : null;
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
  let input: { azione?: unknown; messaggi?: unknown; prompt?: unknown };
  try {
    input = await req.json();
  } catch {
    return reply(400, { errore: 'richiesta' });
  }
  const cf = deps.cloudflare();
  if (!cf) {
    console.log('ia: Cloudflare non configurato');
    return reply(503, { errore: 'non_configurato' });
  }
  if (input.azione === 'chat') {
    const messages = cleanMessages(input.messaggi);
    if (!messages) return reply(400, { errore: 'richiesta' });
    if (!(await deps.consume(user.uid, 'ia_testo', MAX_DOMANDE_GIORNO))) return reply(429, { errore: 'limite' });
    try {
      const r = await deps.run(cf.accountId, cf.apiToken, cf.textModel || MODELLO_TESTO, {
        messages: [{ role: 'system', content: ISTRUZIONI }, ...messages],
        max_tokens: 600,
        temperature: 0.6,
      });
      const text = r.status >= 200 && r.status < 300 ? textOf(r.body) : null;
      if (!text) {
        console.log(`ia: risposta non valida (${r.status})`);
        return reply(r.status === 429 ? 429 : 502, { errore: r.status === 429 ? 'limite_servizio' : 'servizio' });
      }
      return reply(200, { risposta: text });
    } catch {
      console.log('ia: servizio irraggiungibile');
      return reply(502, { errore: 'servizio' });
    }
  }
  if (input.azione === 'immagine') {
    const prompt = typeof input.prompt === 'string' ? input.prompt.trim().slice(0, MAX_CARATTERI_PROMPT) : '';
    if (prompt.length < 3) return reply(400, { errore: 'richiesta' });
    if (!(await deps.consume(user.uid, 'ia_immagini', MAX_IMMAGINI_GIORNO))) return reply(429, { errore: 'limite' });
    try {
      const r = await deps.run(cf.accountId, cf.apiToken, cf.imageModel || MODELLO_IMMAGINI, { prompt, steps: 4 });
      const image = r.status >= 200 && r.status < 300 ? imageOf(r.body) : null;
      if (!image) {
        console.log(`ia: immagine non valida (${r.status})`);
        const blocked = r.status === 400;
        return reply(blocked ? 422 : 502, { errore: blocked ? 'rifiutata' : 'servizio' });
      }
      return reply(200, { immagine: image, tipo: 'image/jpeg' });
    } catch {
      console.log('ia: servizio irraggiungibile');
      return reply(502, { errore: 'servizio' });
    }
  }
  return reply(400, { errore: 'richiesta' });
}

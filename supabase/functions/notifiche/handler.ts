// Funzione `notifiche`: la chiama il database (pg_net) quando c'è qualcosa in coda.
// Prende le notifiche, le manda con FCM e toglie i telefoni non più registrati.
// Nei log: solo conteggi, mai identificativi, titoli o testi.
import { buildMessage, type QueueRow, readSendResult, type SendResult, type ServiceAccount } from './fcm.ts';

export interface Deps {
  secret(): Promise<string | null>;
  serviceAccount(): ServiceAccount | null;
  claim(limit: number): Promise<QueueRow[]>;
  drop(fid: string): Promise<void>;
  accessToken(sa: ServiceAccount): Promise<string>;
  send(projectId: string, accessToken: string, message: Record<string, unknown>): Promise<{ status: number; body: unknown }>;
}

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

/** Confronto a tempo costante tra due stringhe. */
export function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== 'POST') return reply(405, { errore: 'Metodo non consentito' });
  const expected = await deps.secret();
  const given = req.headers.get('x-push-secret') ?? '';
  if (!expected || !sameSecret(given, expected)) return reply(401, { errore: 'Non autorizzato' });
  const sa = deps.serviceAccount();
  if (!sa) return reply(503, { errore: 'Chiave delle notifiche non configurata' });

  let token: string;
  try {
    token = await deps.accessToken(sa);
  } catch {
    return reply(502, { errore: 'Accesso a Firebase non riuscito' });
  }
  let sent = 0;
  let failed = 0;
  let removed = 0;
  for (let round = 0; round < 5; round++) {
    const rows = await deps.claim(200);
    if (rows.length === 0) break;
    for (const row of rows) {
      let result: SendResult;
      try {
        const r = await deps.send(sa.projectId, token, buildMessage(row));
        result = readSendResult(r.status, r.body);
      } catch {
        result = { ok: false, gone: false };
      }
      if (result.ok) sent++;
      else failed++;
      if (result.gone) {
        await deps.drop(row.fid);
        removed++;
      }
    }
  }
  console.log(`notifiche: inviate=${sent} fallite=${failed} telefoni_rimossi=${removed}`);
  return reply(200, { inviate: sent, fallite: failed, rimosse: removed });
}

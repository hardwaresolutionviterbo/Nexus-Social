// Invio con Firebase Cloud Messaging (API HTTP v1, gratuita, senza Blaze).
// La chiave di servizio arriva dal secret FIREBASE_SERVICE_ACCOUNT di Supabase: non è mai nel
// repository e non compare mai nei log.
import { importPKCS8, SignJWT } from 'npm:jose@5.9.6';

export interface ServiceAccount {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

/** Legge il JSON della chiave di servizio; null se manca o non è valido. */
export function parseServiceAccount(raw: string | undefined | null): ServiceAccount | null {
  if (!raw) return null;
  try {
    const j = JSON.parse(raw);
    if (
      typeof j?.project_id !== 'string' || typeof j?.client_email !== 'string' ||
      typeof j?.private_key !== 'string' || !j.private_key.includes('PRIVATE KEY')
    ) return null;
    return { projectId: j.project_id, clientEmail: j.client_email, privateKey: j.private_key };
  } catch {
    return null;
  }
}

export const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
export const TOKEN_URL = 'https://oauth2.googleapis.com/token';

/** Firma della richiesta di accesso a Google (JWT RS256, valido un'ora). */
export async function signAssertion(sa: ServiceAccount, nowSeconds: number): Promise<string> {
  const key = await importPKCS8(sa.privateKey, 'RS256');
  return await new SignJWT({ scope: FCM_SCOPE })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.clientEmail)
    .setAudience(TOKEN_URL)
    .setIssuedAt(nowSeconds)
    .setExpirationTime(nowSeconds + 3600)
    .sign(key);
}

export interface QueueRow {
  queue_id: number;
  fid: string;
  platform: string;
  kind: 'chat' | 'comment' | 'market' | 'call';
  conversation_id: string | null;
  collapse_key: string;
  title: string;
  body: string;
}

/** Messaggio FCM per un telefono. Solo titolo e testo generici: mai contenuti dei messaggi. */
export function buildMessage(row: QueueRow): Record<string, unknown> {
  const tag = row.collapse_key.slice(0, 64);
  if (row.kind === 'call') {
    // Chiamata: solo dati, così il telefono mostra lui la chiamata a tutto schermo con la
    // suoneria (anche bloccato). Scade dopo 45 secondi: una chiamata vecchia non squilla.
    return {
      message: {
        fid: row.fid,
        data: { tipo: 'call', chat: row.conversation_id ?? '', notifica: '', titolo: row.title, testo: row.body },
        android: { priority: 'HIGH', ttl: '45s', collapse_key: tag },
        apns: { headers: { 'apns-collapse-id': tag, 'apns-priority': '10' } },
      },
    };
  }
  return {
    message: {
      fid: row.fid,
      notification: { title: row.title, body: row.body },
      // Notifiche della campanella: il tocco apre l'annuncio o il commento (n:<id>).
      data: {
        tipo: row.kind,
        chat: row.conversation_id ?? '',
        notifica: row.collapse_key.startsWith('n:') ? row.collapse_key.slice(2) : '',
      },
      android: {
        priority: 'HIGH',
        collapse_key: tag,
        notification: { channel_id: 'nexus_social_default', tag, icon: 'ic_stat_nexus' },
      },
      apns: { headers: { 'apns-collapse-id': tag } },
    },
  };
}

export interface SendResult {
  ok: boolean;
  /** Il telefono non è più registrato: va tolto. */
  gone: boolean;
}

/** Interpreta la risposta di FCM. */
export function readSendResult(status: number, body: unknown): SendResult {
  if (status >= 200 && status < 300) return { ok: true, gone: false };
  const text = JSON.stringify(body ?? '');
  return { ok: false, gone: status === 404 || text.includes('UNREGISTERED') };
}

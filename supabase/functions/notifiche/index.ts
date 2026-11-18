// Punto d'ingresso della funzione `notifiche` (Edge Function, verify_jwt = false: la chiama
// solo il database con il segreto condiviso x-push-secret). Vedi docs/fase4/BLOCCO5_ESITO.md.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

import { parseServiceAccount, type ServiceAccount, signAssertion, TOKEN_URL } from './fcm.ts';
import { handle } from './handler.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
});

let secretCache: { at: number; value: string | null } | undefined;
let tokenCache: { until: number; value: string } | undefined;
const account = parseServiceAccount(Deno.env.get('FIREBASE_SERVICE_ACCOUNT'));

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (tokenCache && tokenCache.until > now + 60) return tokenCache.value;
  const assertion = await signAssertion(sa, now);
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  const json = await res.json();
  if (!res.ok || typeof json?.access_token !== 'string') throw new Error('accesso negato');
  tokenCache = { until: now + Number(json.expires_in ?? 3600), value: json.access_token };
  return json.access_token;
}

Deno.serve((req) =>
  handle(req, {
    secret: async () => {
      if (secretCache && Date.now() - secretCache.at < 60_000) return secretCache.value;
      const { data, error } = await admin.rpc('push_server_config');
      const row = Array.isArray(data) ? data[0] : data;
      const value = error || !row ? null : (row.push_secret as string | null);
      if (!error) secretCache = { at: Date.now(), value };
      return value;
    },
    serviceAccount: () => account,
    claim: async (limit) => {
      const { data, error } = await admin.rpc('push_claim', { p_limit: limit });
      if (error) throw new Error('coda non leggibile');
      return (data ?? []) as never;
    },
    drop: async (fid) => {
      await admin.rpc('push_drop_device', { p_fid: fid });
    },
    accessToken,
    send: async (projectId, token, message) => {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify(message),
      });
      let body: unknown = null;
      try {
        body = await res.json();
      } catch {
        body = null;
      }
      return { status: res.status, body };
    },
  })
);

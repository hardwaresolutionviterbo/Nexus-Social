// Punto d'ingresso della funzione `chiamate` (verify_jwt = false: il token è di Firebase e si
// controlla qui dentro, come per `rubrica`). Secret: CLOUDFLARE_TURN_KEY_ID e
// CLOUDFLARE_TURN_API_TOKEN, creati dal titolare. Vedi docs/fase4/BLOCCO8_ESITO.md.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

import { verifyFirebaseToken } from './firebase_token.ts';
import { handle, MAX_CREDENZIALI_GIORNO } from './handler.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
});

let project: { at: number; id: string | null } | undefined;
const keyId = Deno.env.get('CLOUDFLARE_TURN_KEY_ID') ?? '';
const apiToken = Deno.env.get('CLOUDFLARE_TURN_API_TOKEN') ?? '';

Deno.serve((req) =>
  handle(req, {
    firebaseProjectId: async () => {
      if (project && Date.now() - project.at < 60_000) return project.id;
      const { data, error } = await admin.rpc('rubrica_server_config');
      const row = Array.isArray(data) ? data[0] : data;
      const id = error || !row ? null : (row.firebase_project_id as string | null);
      if (!error) project = { at: Date.now(), id };
      return id;
    },
    verify: (token, projectId) => verifyFirebaseToken(token, projectId),
    consume: async (uid) => {
      const { data, error } = await admin.rpc('rubrica_consume_limit', {
        p_uid: uid,
        p_kind: 'turn',
        p_max: MAX_CREDENZIALI_GIORNO,
      });
      if (error) throw new Error('limite non verificabile');
      return data === true;
    },
    turn: () => (keyId && apiToken ? { keyId, apiToken } : null),
    generate: async (id, tokenValue, ttl) => {
      const res = await fetch(
        `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(id)}/credentials/generate-ice-servers`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${tokenValue}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ ttl }),
        },
      );
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

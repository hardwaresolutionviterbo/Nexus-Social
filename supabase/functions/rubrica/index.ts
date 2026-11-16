// Punto d'ingresso della funzione `rubrica` su Supabase (Edge Function).
// Da pubblicare con il controllo del token fatto qui dentro (verify_jwt = false), perché i
// token sono di Firebase: vedi docs/server/RUBRICA_SU_SUPABASE.md.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

import { handle, type ServerConfig } from './handler.ts';
import { verifyFirebaseToken } from './firebase_token.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
});

let cached: { at: number; cfg: ServerConfig } | undefined;

async function config(): Promise<ServerConfig> {
  if (cached && Date.now() - cached.at < 60_000) return cached.cfg;
  const { data, error } = await admin.rpc('rubrica_server_config');
  const row = Array.isArray(data) ? data[0] : data;
  const cfg: ServerConfig = error || !row
    ? { oprfKey: null, attestKey: null, firebaseProjectId: null }
    : { oprfKey: row.oprf_key, attestKey: row.attest_key, firebaseProjectId: row.firebase_project_id };
  if (!error) cached = { at: Date.now(), cfg };
  return cfg;
}

Deno.serve((req) =>
  handle(req, {
    config,
    consume: async (uid, kind, max) => {
      const { data, error } = await admin.rpc('rubrica_consume_limit', { p_uid: uid, p_kind: kind, p_max: max });
      if (error) throw new Error('limite non verificabile');
      return data === true;
    },
    verify: (token, projectId) => verifyFirebaseToken(token, projectId),
    now: () => Date.now(),
  })
);

// Punto d'ingresso della funzione `ia` (verify_jwt = false: il token è di Firebase e si
// controlla qui dentro, come per `rubrica` e `chiamate`). Secret creati dal titolare:
// CLOUDFLARE_AI_ACCOUNT_ID e CLOUDFLARE_AI_API_TOKEN (facoltativi CLOUDFLARE_AI_TEXT_MODEL e
// CLOUDFLARE_AI_IMAGE_MODEL). Vedi docs/fase4/BLOCCO18_ESITO.md.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

import { verifyFirebaseToken } from './firebase_token.ts';
import { handle } from './handler.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
});

let project: { at: number; id: string | null } | undefined;
const accountId = Deno.env.get('CLOUDFLARE_AI_ACCOUNT_ID') ?? '';
const apiToken = Deno.env.get('CLOUDFLARE_AI_API_TOKEN') ?? '';
const textModel = Deno.env.get('CLOUDFLARE_AI_TEXT_MODEL') ?? '';
const imageModel = Deno.env.get('CLOUDFLARE_AI_IMAGE_MODEL') ?? '';

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
    consume: async (uid, kind, max) => {
      const { data, error } = await admin.rpc('rubrica_consume_limit', { p_uid: uid, p_kind: kind, p_max: max });
      if (error) throw new Error('limite non verificabile');
      return data === true;
    },
    cloudflare: () => (accountId && apiToken ? { accountId, apiToken, textModel, imageModel } : null),
    run: async (account, tokenValue, model, input) => {
      const res = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(account)}/ai/run/${model}`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${tokenValue}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(input),
          signal: AbortSignal.timeout(60_000),
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

// Test della funzione `chiamate` senza rete: Firebase e Cloudflare simulati.
import { assertEquals } from 'jsr:@std/assert@1';

import { TokenError } from './firebase_token.ts';
import { cleanIceServers, type Deps, handle, STUN_ONLY } from './handler.ts';

function deps(over: Partial<Deps> = {}): Deps {
  return {
    firebaseProjectId: async () => 'progetto-prova',
    verify: async (token) => {
      if (token !== 'token-buono') throw new TokenError('no');
      return { uid: 'utenteProva0000000000000001', phone: null };
    },
    consume: async () => true,
    turn: () => ({ keyId: 'chiave', apiToken: 'segreto' }),
    generate: async () => ({
      status: 201,
      body: {
        iceServers: [
          { urls: ['stun:stun.cloudflare.com:3478'] },
          { urls: ['turn:turn.cloudflare.com:3478?transport=udp', 'https://non-valido'], username: 'u', credential: 'c' },
        ],
      },
    }),
    ...over,
  };
}

const post = (token?: string) =>
  new Request('http://x/chiamate', {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: '{}',
  });

Deno.test('senza token Firebase valido: 401', async () => {
  assertEquals((await handle(post(), deps())).status, 401);
  assertEquals((await handle(post('falso'), deps())).status, 401);
});

Deno.test('credenziali del ponte per chi ha fatto l\'accesso, solo indirizzi validi', async () => {
  const res = await handle(post('token-buono'), deps());
  assertEquals(res.status, 200);
  const j = await res.json();
  assertEquals(j.ponte, true);
  assertEquals(j.iceServers[1], {
    urls: ['turn:turn.cloudflare.com:3478?transport=udp'],
    username: 'u',
    credential: 'c',
  });
});

Deno.test('troppe chiamate in un giorno: 429', async () => {
  assertEquals((await handle(post('token-buono'), deps({ consume: async () => false }))).status, 429);
});

Deno.test('ponte non configurato o non disponibile: solo STUN, la chiamata prova lo stesso', async () => {
  const none = await (await handle(post('token-buono'), deps({ turn: () => null }))).json();
  assertEquals(none, { iceServers: STUN_ONLY, ponte: false });
  const down = await (await handle(post('token-buono'), deps({ generate: async () => ({ status: 500, body: {} }) }))).json();
  assertEquals(down.ponte, false);
});

Deno.test('risposta di Cloudflare con un solo server (oggetto)', () => {
  assertEquals(cleanIceServers({ iceServers: { urls: 'turns:turn.cloudflare.com:443', username: 'a', credential: 'b' } }), [
    { urls: ['turns:turn.cloudflare.com:443'], username: 'a', credential: 'b' },
  ]);
  assertEquals(cleanIceServers({}), null);
});

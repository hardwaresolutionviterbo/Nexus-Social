// Controllo del token di accesso Firebase dentro la funzione di Supabase.
//
// Si verifica la firma con le chiavi pubbliche di Google (securetoken), l'emittente e il
// destinatario del nostro progetto, la scadenza, e che l'accesso sia avvenuto con il numero
// di telefono. Nessuna chiave segreta: le chiavi pubbliche sono pubbliche.
import { createRemoteJWKSet, type JWTPayload, jwtVerify, type JWTVerifyGetKey } from 'npm:jose@5.9.6';

export const GOOGLE_JWKS =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

let remote: JWTVerifyGetKey | undefined;

export function googleKeys(): JWTVerifyGetKey {
  remote ??= createRemoteJWKSet(new URL(GOOGLE_JWKS));
  return remote;
}

export interface FirebaseUser {
  uid: string;
  phone: string | null;
}

export class TokenError extends Error {}

export async function verifyFirebaseToken(
  token: string,
  projectId: string,
  keys: JWTVerifyGetKey = googleKeys(),
): Promise<FirebaseUser> {
  let payload: JWTPayload;
  try {
    ({ payload } = await jwtVerify(token, keys, {
      algorithms: ['RS256'],
      issuer: `https://securetoken.google.com/${projectId}`,
      audience: projectId,
      clockTolerance: 30,
    }));
  } catch {
    throw new TokenError('Accesso non valido');
  }
  const uid = payload.sub;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new TokenError('Accesso non valido');
  }
  const firebase = payload.firebase as { sign_in_provider?: string } | undefined;
  if (firebase?.sign_in_provider !== 'phone') {
    throw new TokenError('Serve l\'accesso con numero di telefono');
  }
  const phone = typeof payload.phone_number === 'string' ? payload.phone_number : null;
  return { uid, phone };
}

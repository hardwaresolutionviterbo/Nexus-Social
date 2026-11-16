# Rubrica su Supabase (senza Blaze)

Ramo `server/rubrica-supabase`. Nessuna modifica a `main`, a Firebase o al database reale.

## Cosa cambia
- Il calcolo protetto dei numeri (OPRF, RFC 9497) passa dalle Cloud Functions alla funzione
  `rubrica` di Supabase (`supabase/functions/rubrica`), gratuita nel piano free.
- La funzione controlla da sola il token Firebase: firma con le chiavi pubbliche di Google,
  progetto, scadenza, accesso con il numero di telefono.
- Migrazione 0018: le chiavi `oprf_key` e `rubrica_attest_key` nascono a caso dentro il
  database; nessuno le copia, nemmeno il titolare. Le legge solo la funzione (ruolo di servizio).
- I limiti (3 sincronizzazioni e 5 registrazioni del proprio numero al giorno) si contano nel
  database invece che in Firestore.
- App: chiama `rubrica` con il client di Supabase; il resto della rubrica non cambia.

## Controlli automatici
- Deno: vettori ufficiali RFC 9497, firma identica a quella controllata dal database, token
  Firebase falsi/scaduti/di altri progetti/senza telefono rifiutati, limiti, errori.
- Supabase (database temporaneo): casi Y1–Y2 e controprova `rubrica_chiavi_esposte`.

## Per attivarla (solo con autorizzazione del titolare)
1. Applicare le migrazioni fino alla 0018 al database reale.
2. Pubblicare la funzione `rubrica` con il controllo del token lasciato alla funzione:
   `supabase functions deploy rubrica --no-verify-jwt` (si potrà fare anche da GitHub Actions
   con un token di accesso Supabase impostato dal titolare tra i secret del repository).
3. Le vecchie Cloud Functions della rubrica restano nel repository ma non servono più.

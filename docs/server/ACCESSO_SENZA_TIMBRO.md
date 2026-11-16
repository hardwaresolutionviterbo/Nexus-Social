# Accesso al server senza «timbro» (scelta C del titolare)

Ramo `server/senza-timbro`. Nessuna modifica a `main`, a Firebase o al database reale.

## Perché
Supabase dà il ruolo `authenticated` solo ai token Firebase con il claim `role: authenticated`,
che richiede una Cloud Function (piano Blaze) o una chiave di servizio. Senza claim la richiesta
arriva come `anon`, ma con la firma Firebase già verificata da Supabase.

## Cosa cambia (migrazione 0017)
- Controllo iniziale di ogni richiesta (pre-request): senza un'identità Firebase valida del
  nostro progetto il server non risponde a nulla, tranne `ping`. Respinge anche i token con il
  ruolo `authenticated` che non vengono da Firebase.
- `anon` ha esattamente i permessi di `authenticated`, né più né meno (funzioni, tabelle,
  colonne, policy delle tabelle e delle foto). Le regole restano quelle di sempre, basate su
  `current_uid()`, con il controllo del telefono e del PIN invariato.
- Regola per le migrazioni future: terminano con `select private.align_anon_with_authenticated();`.
  Se manca, il caso Z4 dei test lo segnala (e nel frattempo non si apre nulla).
- App: niente più chiamata alla Cloud Function `assegnaRuolo`; controllo di avvio con `ping`.

## Controlli automatici
- Tutti i 149 casi passano con token Firebase **senza** `role` (come quelli veri senza Cloud
  Function), più i nuovi Z1–Z4; tutte le controprove rilevano il difetto, compresa la nuova
  `senza_controllo_iniziale` (Z1).
- APK: `nexus-social-0.1.0+23601-f631ae5-server-senza-timbro` (il codice dell'app non è più cambiato dopo).

## Per collegare davvero il server (solo con autorizzazione del titolare)
1. Supabase → Authentication → Third-Party Auth → aggiungere Firebase con l'ID del progetto.
2. Applicare le migrazioni 0003–0017 al database reale.
3. Compilare l'app con `SERVER_LINK_ENABLED=true`.

## Ancora legato a Blaze
- La **rubrica** (trovare i contatti che usano Piazly) usa le Cloud Functions per il calcolo
  protetto dei numeri (OPRF). Per renderla gratuita va spostata su una funzione di Supabase
  (Edge Function), con una chiave nostra generata dal titolare nel pannello di Supabase.

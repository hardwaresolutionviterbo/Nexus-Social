# Fase 6 · Blocco 4 — Recensioni verificate e avvisi delle promozioni vicine

Dal piano (Fase 6): recensioni verificate nel profilo attività; notifiche alle persone vicine solo
se le hanno accettate.

## Recensioni verificate

- Le scrive solo chi ha **usato in cassa un coupon** di quell'attività (convalidato dal titolare):
  così sono di clienti veri. Una per persona e attività, da 1 a 5 stelle con un testo facoltativo;
  si corregge o si cancella.
- Il titolare non può recensirsi; può **rispondere** (e correggere la risposta).
- Gli **amministratori** possono togliere una recensione dalla scheda.
- Nella scheda attività: media, numero e ultime recensioni con il nome pubblico dell'autore (mai
  altri dati). Chi ha bloccato (o è bloccato) non vede le recensioni dell'altro.

## Avvisi delle promozioni vicine

- **Spenti finché non li accendi** (Promozioni ed eventi della Mappa, oppure I miei coupon);
  raggio 500 m, 1 km o 3 km.
- Funzionano **con Piazly aperta**: quando si torna nell'app, ogni 10 minuti mentre è aperta e
  quando la Mappa si aggiorna. Usano l'ultima posizione già nota del telefono (non accendono il GPS).
  In sottofondo, con l'app chiusa, servirebbe il permesso «Consenti sempre» della posizione: per
  ora non lo chiediamo.
- Al massimo **3 avvisi al giorno**, mai due volte per la stessa promozione, mai per le proprie.
- La posizione resta sul telefono: al server va solo la richiesta delle promozioni intorno, come fa
  già la Mappa. Le preferenze si salvano sul telefono.

## Server

Migrazione `0037_recensioni.sql`: tabella `business_reviews` (solo tramite funzioni),
`reviews_of`, `review_save`, `review_delete_mine`, `review_reply`, `review_admin_delete`.

## Test

- `test/fase6/reviews_alerts_test.dart`: recensione negata a chi non è cliente e a chi ha solo preso
  il coupon, ammessa dopo la convalida; media; risposta del titolare; avvisi spenti di default,
  raggio, 3 al giorno, mai due volte, mai le proprie; interruttore e raggio.
- `supabase/tests/rls_test.py` RV1–RV4; controprova `recensioni_da_chiunque` (deve far fallire RV1).
- Anteprima `aziende_11_recensioni`.

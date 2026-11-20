# Fase 6 · Blocco 2 — Abbonamento Premium (modalità prova) e badge «Verificato»

Dal piano (Fase 6): abbonamento 9,99 € al mese con 7 giorni di prova gratuita; pagina Premium;
badge «Verificato» solo per aziende approvate con abbonamento attivo, che sparisce alla scadenza.

Il titolare non ha ancora l'account Google Play Console (20/11/2026): il pagamento vero con Google
Play (e App Store) si collegherà dopo la pubblicazione. Il server prevede già le fonti
`google_play` e `app_store`.

## Cosa c'è

- **Pagina Piazly Premium** (da «La mia attività»): prezzo, 7 giorni gratis, cosa si ottiene, stato
  dell'abbonamento con la scadenza e i giorni rimasti. Il pulsante «Abbonati · 9,99 €/mese» è
  visibile ma spento, con la spiegazione: nessun pagamento finto.
- **Prova gratuita di 7 giorni**: una sola volta per azienda e per partita IVA (cambiare account o
  partita IVA non ne dà un'altra). Non si rinnova da sola.
- **Amministratori** («Aziende da verificare»): vedono fino a quando è attivo Premium (e se è la
  prova); «+1 mese Premium» (da oggi o dalla scadenza) e «Ferma Premium».
- **Badge «Verificato»**: compare (scheda pubblica, segnaposto con bordo blu, «La mia attività»)
  solo se l'azienda è approvata **e** Premium è attivo; alla scadenza sparisce da solo.
- I dati dell'abbonamento sono privati: li vedono solo l'azienda e gli amministratori; l'azienda non
  può allungarselo da sola.

## Server

Migrazione `0035_abbonamenti.sql`: tabella `business_subscriptions`, registro privato delle prove
usate, funzioni `subscription_start_trial`, `subscription_mine`, `subscription_admin_extend`,
`subscription_admin_stop`; `business_mine`, `business_page_get`, `businesses_nearby` e
`business_review_queue` aggiornate per il badge e i dati di Premium.

## Test

- `test/fase6/business_test.dart`: badge assente dopo la sola approvazione e presente con +1 mese
  dall'admin; prova di 7 giorni, scadenza dopo 8 giorni, niente seconda prova; pulsante di pagamento
  spento.
- `supabase/tests/rls_test.py` AB1–AB3; controprova `badge_senza_abbonamento` (deve far fallire AB1).
- Anteprime `aziende_6_premium`, `aziende_7_premium_attivo`.

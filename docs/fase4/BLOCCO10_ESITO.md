# Fase 4 · Blocco 10 · Chiudere la Fase 4 — esito (in corso)

Ramo `fase4/blocco10`, nato da `fase4/blocco9b`. Tre cose da fare, scelte dal titolare il
18/11/2026:
1. Chiamata a tutto schermo con il telefono bloccato.
2. Testo del messaggio nella notifica.
3. Chiamate di gruppo.

## 1 · Chiamata a tutto schermo — fatto
- La notifica di una chiamata ora arriva come «chiamata» (solo dati, priorità alta, scade dopo
  45 secondi), non più come notifica normale.
- Il telefono mostra la chiamata a tutto schermo anche con lo schermo bloccato:
  - canale «Chiamate in arrivo» con la suoneria del telefono, che suona finché si risponde o
    per 45 secondi;
  - in silenzioso resta muta.
  - Toccandola si apre l'app sulla chiamata, con Rispondi e Rifiuta.
- Con l'app già aperta suona solo la schermata dell'app: niente doppia suoneria.
- **Android:** permessi `USE_FULL_SCREEN_INTENT` e `VIBRATE`. L'attività principale si mostra
  sopra il blocco schermo e accende lo schermo.
- **Server:** funzione `notifiche` ripubblicata il 18/11/2026 (autorizzata), versione 6.
- **Controlli:** 314 test dell'app e i test Deno della funzione sono superati.

## 2 · Testo nella notifica — fatto
- **Chiave dell'anteprima:** ogni telefono ha una chiave sua per ogni chat e la manda agli
  altri membri dentro la chat cifrata (MLS):
  - la prima volta;
  - quando la chat cambia generazione, per esempio con un telefono nuovo o un membro nuovo
    nel gruppo.
- **Anteprima:** chi scrive cifra con quella chiave un'anteprima di al massimo 100 caratteri
  (per gli allegati «📷 Foto», «🎤 Messaggio vocale»…). Il server la passa alla notifica così
  com'è.
- **Con l'app chiusa** il telefono di chi riceve la decifra e sostituisce «Nuovo messaggio» con
  il testo. Se non riesce (app vecchia, chiave mancante) resta «Nuovo messaggio».
- **«Mostra chi scrive» spento:** l'anteprima non parte nemmeno.
- **Server** (migrazione `0027_anteprima_cifrata.sql`):
  - `chat_send_preview`;
  - due colonne nella coda delle notifiche;
  - `push_claim` restituisce anteprima, autore e conteggio, ed è solo per il ruolo di servizio.
- **Controlli:**
  - app: 317 test;
  - database: AP1–AP3 e la controprova `anteprima_senza_consenso`, che deve far fallire AP2;
  - funzione: test Deno.
- **Server reale (19/11/2026, autorizzato):**
  - migrazione 0027 applicata dal commit `ae510b5`, con impronta verificata;
  - funzione `notifiche` ripubblicata (versione 7).
- **Nota:** le versioni dell'app precedenti alla 30101 mostrano la chiave come «messaggio
  non leggibile». Vanno aggiornati tutti e due i telefoni.

## 3 · Chiamate di gruppo — da fare

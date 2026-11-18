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

## 2 · Testo nella notifica — da fare
## 3 · Chiamate di gruppo — da fare

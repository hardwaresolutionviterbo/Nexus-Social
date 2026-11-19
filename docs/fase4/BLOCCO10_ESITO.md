# Fase 4 · Blocco 10 · Chiudere la Fase 4 — esito

Ramo `fase4/blocco10`, nato da `fase4/blocco9b`. Unito in `main` il 19/11/2026 con
l'autorizzazione del titolare, insieme ai Blocchi 5–9. Tre cose da fare, scelte dal titolare il
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

## 3 · Chiamate di gruppo — fatto (ramo `fase4/blocco10b`)
- **Pulsanti:** nei gruppi fino a 8 membri ci sono i pulsanti di chiamata vocale e di
  videochiamata, per chi è già dentro il gruppo cifrato.
- **Squillo:** squilla a tutti i membri, con la notifica «Calcetto · Anna R. · Videochiamata
  di gruppo». Valgono «Silenzia» e «Non disturbare».
- **Chi entra:**
  - entra chi risponde, fino a 4 persone insieme;
  - ognuno è collegato direttamente agli altri (WebRTC, ponte TURN se serve);
  - chi entra chiama chi c'è già.
- **Chi esce:** gli altri restano. L'ultimo rimasto chiude la chiamata.
- **Rifiuta:** vale solo per sé.
- **Nessuna risposta in 45 secondi:** la chiamata si chiude, e per gli altri è «persa».
- **Schermata:**
  - con il video: una, due o quattro finestre;
  - senza video: i nomi di chi è in chiamata;
  - durata e numero di persone.
- **Server** (migrazione `0028_chiamate_di_gruppo.sql`): `call_signal` accetta i gruppi solo
  per chi è dentro la cifratura e in gruppi fino a 8; la notifica dice «Chiamata di gruppo».
- **Controlli:**
  - app: 320 test, tra cui una chiamata a tre in cui ognuno è collegato a tutti, l'uscita,
    l'ultimo che chiude e nessuna risposta;
  - database: 201/201, con GC1–GC2.
- **Server reale (19/11/2026, autorizzato):** migrazione 0028 applicata dal commit `38a109a`,
  con impronta verificata.

## Limiti noti
- Oltre 4 persone in chiamata serve un collegamento centrale (SFU), che costa: non previsto
  per ora.
- **Sull'iPhone (fase delle build iOS):** chiamata a tutto schermo e testo nelle notifiche
  sono da rifare con gli strumenti di Apple (CallKit, Notification Service Extension).

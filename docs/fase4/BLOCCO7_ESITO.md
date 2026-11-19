# Fase 4 · Blocco 7 · Segnala, Condividi l'incontro, notifiche dei commenti — esito

Ramo `fase4/blocco7`, nato da `fase4/blocco6`.
Stato: **server attivo (autorizzato il 18/11/2026), da provare sul telefono**.

## Cosa fa
- **Segnala** (chat ⋮ → Segnala), come chiede il piano: «chi segnala sceglie quali messaggi
  allegare, e solo quelli sono visibili all'amministratore autorizzato».
  - Si scelgono il motivo e i messaggi da allegare: nessuno è già selezionato, al massimo 50.
  - Si può aggiungere una descrizione e, nelle chat a due, «Blocca anche questa persona».
  - Chi è segnalato non lo sa.
  - Per gli allegati vanno solo il tipo e la didascalia, mai il file.
- **Condividi l'incontro** (chat a due ⋮ → Condividi l'incontro):
  - si scrivono il luogo, il giorno, l'ora e una nota, e si sceglie una persona fidata dalla
    rubrica;
  - la persona fidata riceve un messaggio cifrato con chi si incontra, dove e quando, più
    «Se non ti scrivo dopo l'incontro, contattami».
- **Notifiche dei commenti e degli scambi** (completamento del Blocco 5): toccandole si apre
  subito l'annuncio con il commento evidenziato, come dalla campanella.

## Server
- **Migrazione `0024_chat_segnalazioni.sql`:**
  - tabella `chat_reports`, che leggono solo gli amministratori (`is_admin`);
  - nessuno la scrive direttamente: si passa solo da `chat_report`, che controlla chi fa parte
    della chat, il motivo, al massimo 50 messaggi di al massimo 4.000 caratteri, una
    segnalazione aperta per chat e al massimo 10 al giorno.
- **Funzione `notifiche`:** manda anche l'identificativo della notifica della campanella, per
  aprire l'annuncio. Va pubblicata di nuovo.
- La schermata degli amministratori per leggere le segnalazioni arriva con il gestionale
  (Fase 7).

## Controlli
- App: 302 test superati (segnalazione con i soli messaggi scelti e blocco, incontro arrivato
  alla persona fidata, notifica che apre il commento).
- Database: 189/189, compresi i nuovi W1–W4 e la controprova `segnalazioni_visibili` (W2).
- Funzione: test Deno aggiornati.
- Anteprime: chat_23 (Segnala), chat_24 (Condividi l'incontro).

## Server reale (18/11/2026, autorizzato)
- Migrazione 0024 applicata dal file del commit `2800355`, con impronta verificata:
  - RLS attiva, nessuna scrittura diretta;
  - permessi di anon allineati, come per tutte le funzioni dal Blocco 0017.
- Funzione `notifiche` pubblicata di nuovo (versione 2). Chiamata di prova: 200.

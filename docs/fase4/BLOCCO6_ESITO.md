# Fase 4 · Blocco 6 · Backup della chat — esito

Ramo `fase4/blocco6`, nato da `fase4/blocco5`.
Stato: **pronto, migrazione 0023 da applicare con l'autorizzazione del titolare**.

Il piano di lavoro non prevede questa funzione. L'ha chiesta il titolare il 16/11/2026: chi
cambia telefono deve ritrovare le chat, come con il backup di WhatsApp.

## Cosa fa
- **Profilo → Backup delle chat** (anche dalla lista delle chat): si sceglie una password
  (almeno 8 caratteri, lettere e un numero o un simbolo) e il backup parte subito.
- Si aggiorna da solo una volta al giorno, quando si apre l'app. Si può anche fare a mano.
- **Telefono nuovo:** dopo l'accesso con il numero, nella lista delle chat compare
  «Recupera le tue chat». Con la password tornano i messaggi, le risposte, le reazioni e le
  eliminazioni. Poi la chat continua normalmente.
- **«Non ora»:** la proposta non compare più. Il ripristino resta in Profilo → Backup.
- **Password dimenticata:** il backup non si apre. Si può creare un backup nuovo, che
  sostituisce il vecchio.
- **Disattiva:** il backup si cancella dal server.
- **Limite:** foto, video, vocali e documenti non sono nel backup. I messaggi ci sono, ma
  l'allegato dice che non si può più aprire.

## Sicurezza
- Tutto si cifra sul telefono. La chiave si ricava dalla password con Argon2id (19 MiB,
  2 passaggi, sale casuale). La cronologia si comprime e si cifra con AES-256-GCM.
- Il server riceve solo byte illeggibili e non conosce la password. Un file manomesso o con
  costi abbassati viene rifiutato.
- Sul telefono resta solo la chiave, nell'archivio sicuro, mai la password.
- **Server** (migrazione `0023_backup_chat.sql`):
  - bucket privato `chat-backups`, massimo 20 MB, solo byte cifrati;
  - un solo file per account, `{uid}/backup.bin`, che vede, sostituisce e cancella solo il
    proprietario.
- La chiave della chat cifrata (MLS) non è nel backup. Il telefono nuovo ha chiavi nuove,
  come già previsto dalla decisione C3.

## Controlli
- **App:** 298 test superati (analisi senza avvisi):
  - cifratura: password giusta e sbagliata, file manomesso, costi abbassati;
  - regole della password;
  - telefono nuovo con MLS vero: ripristino, nessun doppione, la chat continua;
  - backup automatico ogni giorno, «Non ora», disattiva, senza rete;
  - file del telefono esportati e reimportati;
  - schermate.
- **Database:** test V1–V4 sul backup, più la controprova `backup_altrui`, che deve far
  fallire V2.
- **Anteprime:** chat_19 (attiva), chat_20 (proposta nella lista), chat_21 (ripristino),
  chat_22 (backup attivo).

## Correzione ai test esistenti
Il limite di 48 ore di «elimina per tutti» confrontava l'ora vera con le date fisse dei test
(16/11). Dal 18/11 i test non passavano più. Adesso il motore riceve l'ora dall'esterno e i
test usano quella del server finto.
L'app non cambia.

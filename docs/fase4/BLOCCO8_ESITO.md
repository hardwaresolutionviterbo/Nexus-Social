# Fase 4 · Blocco 8 · Chiamate vocali e videochiamate — esito

Ramo `fase4/blocco8`, nato da `fase4/blocco7`.
Stato: **pronto. Per la migrazione 0025, la funzione `chiamate` e il nuovo invio di
`notifiche` serve l'autorizzazione del titolare.**

## Cosa fa
- Nelle chat a due già accettate ci sono due pulsanti in alto: **chiamata vocale** e
  **videochiamata**.
- La chiamata ha una schermata a tutto schermo:
  - **in arrivo:** Rispondi o Rifiuta, con vibrazione;
  - **in uscita:** «squilla…»;
  - **in corso:** durata, microfono, vivavoce o fotocamera, cambio di fotocamera, Chiudi;
  - **finita:** perché è finita (terminata, rifiutata, occupato, nessuna risposta).
- **Con l'app chiusa** arriva la notifica «Chiamata in arrivo» o «Videochiamata in arrivo».
  Toccandola si apre l'app e compare la chiamata, se è ancora in corso.
  - La notifica scade dopo 45 secondi.
  - Valgono «Silenzia», «Non disturbare» e «Messaggi».
- **Occupato:** chi chiama lo sa subito; chi riceve vede «Chiamata persa».
- **Registro nella chat:** «Chiamata vocale · 2:31», «Videochiamata persa», «Chiamata senza
  risposta», «Chiamata rifiutata».
- **Niente chiamate** dalle richieste di messaggio (sconosciuti), con un blocco, o più di
  30 volte l'ora.

## Come funziona
- **Collegamento:** offerta, risposta e chiusura sono messaggi della chat cifrati con MLS.
  Il server non li legge, e l'impronta della chiamata è protetta dalla cifratura della chat.
- **Audio e video:** vanno da telefono a telefono con WebRTC (`flutter_webrtc`, licenza MIT),
  cifrati DTLS-SRTP.
- **Ponte:** quando serve si passa dal ponte TURN di Cloudflare, che non può ascoltare.
  - Le credenziali le dà la funzione `chiamate`, dopo aver controllato l'accesso Firebase.
  - Durano un'ora, al massimo 60 al giorno per persona.
  - Le chiavi Cloudflare sono nei secret di Supabase, create dal titolare.
- **Costo:** con Cloudflare i primi 1.000 GB al mese sono gratuiti. Oltre si pagano 0,05 $/GB.
- **Server** (migrazione `0025_chiamate.sql`):
  - `call_signal` manda il messaggio con le regole della chat e dice alla notifica se
    squillare: solo l'offerta squilla;
  - il tipo di notifica `call`;
  - il limite di squilli.

## Cosa resta fuori (per ora)
- **Chiamate di gruppo:** il piano le prevede. Servono un collegamento centrale (SFU), sarà
  un blocco a parte.
- **Schermata di chiamata sopra il blocco schermo:** quella di sistema, come WhatsApp. Ora
  arriva una notifica normale; per la schermata a tutto schermo con l'app chiusa servono
  componenti di Android (ConnectionService) da aggiungere in un passo successivo.
- **iPhone:** serve CallKit, nella fase delle build iOS.

## Controlli
- **App:** 310 test superati (analisi senza avvisi):
  - chiamata risposta e chiusa;
  - videochiamata rifiutata;
  - occupato;
  - offerta vecchia, che diventa «Chiamata persa»;
  - nessuna risposta;
  - nessuna chiamata dalle richieste;
  - segnale incompleto rifiutato;
  - schermate.
- **Database:** 193/193, con i nuovi X1–X4 e la controprova `chiamate_squillano_sempre`
  (deve far fallire X1).
- **Funzioni:** test Deno di `chiamate` (accesso, limite, ponte mancante: solo STUN) e di
  `notifiche` (scadenza a 45 secondi).
- **Anteprime:** chat_25 (in arrivo), chat_26 (in corso).

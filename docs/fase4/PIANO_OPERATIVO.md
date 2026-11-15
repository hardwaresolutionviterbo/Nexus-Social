# Fase 4 · Piano operativo (proposta)

Stato: **in sospeso per decisione del titolare (15/11/2026)**: «questo blocco andrà studiato a
fondo», in particolare la cifratura e la sua licenza (C1). Nessun codice della Fase 4 finché il
titolare non riprende il piano e decide C1-C9.

Riferimento: `Nexus_Social_Piano_di_Lavoro_COMPLETO_AGGIORNATO.pdf`, «FASE 4 – Chat, chiamate e
notifiche» (SHA-256 `7da25d52…b8561eb`), più quanto spostato qui dalla Fase 3 (GPS in tempo reale).

## 1. Obiettivo e requisiti (dal PDF)

> Obiettivo: avere una chat completa come WhatsApp e Telegram, cifrata end-to-end.
>
> Cosa devi riuscire a provare sul telefono: due telefoni si scrivono, si chiamano e ricevono le
> notifiche con l'app chiusa; si verificano anche le notifiche dei commenti e l'assenza di
> notifiche per le reazioni.

| N. | Requisito | Blocco |
|---|---|---|
| R4.1 | Chat uno a uno cifrata end-to-end con un protocollo collaudato, non inventato | 1 |
| R4.2 | Testo, vocali, foto, video, file e documenti, con limite di peso e compressione | 2 |
| R4.3 | Inviato / consegnato / letto, risposta, inoltro, elimina per tutti, reazioni ai messaggi | 1, 3 |
| R4.4 | Richieste di messaggio dagli sconosciuti (accetta / rifiuta); agli sconosciuti mai il numero, solo il nome utente | 1 |
| R4.5 | Gruppi con amministratori, foto e link d'invito; permessi e ruoli lato server | 4 |
| R4.6 | Chiamate vocali e videochiamate, anche di gruppo, a tutto schermo | 6, 7 |
| R4.7 | Notifiche reali con l'app chiusa (messaggi, chiamate, avvisi), anteprima decifrata sul telefono; silenzia e «non disturbare» | 5 |
| R4.8 | «Condividi l'incontro con un amico»: luogo e orario a una persona fidata | 3 |
| R4.9 | Segnalazione di una chat: chi segnala sceglie i messaggi da allegare, visibili solo all'amministratore autorizzato | 3 |
| R4.10 | Notifiche dei commenti gestibili nelle preferenze (in-app e, se abilitate, push); il tocco apre annuncio o commento | 5 |
| R4.11 | Reazioni agli annunci: nel PDF nessuna notifica; **modificato dal titolare (Fase 3, 3.1)**: notifiche per i Mi piace, mai per i Non mi piace | 5 |
| R3.4 | GPS in tempo reale (dalla Fase 3): dalla chat, solo ai contatti in rubrica scelti uno per uno, fino a 8 ore, «Interrompi», cancellazione alla fine, regole per i minorenni | 3 |

## 2. Cosa serve fuori dal codice (da sapere prima)

- **Blaze è indispensabile per provare la Fase 4 sul telefono**: accesso con SMS, funzioni del
  server che inviano le notifiche push e Cloud Storage (dal 3 febbraio 2026 Cloud Storage for
  Firebase richiede sempre Blaze, anche con poco uso). Come nelle Fasi 2-3, tutto si costruisce e
  si prova nei test automatici; la prova tra due telefoni arriva con Blaze.
- **Chiamate**: quando due telefoni non riescono a collegarsi direttamente (reti mobili, Wi-Fi
  aziendali) serve un server di inoltro (TURN). Proposta in C5: servizio a consumo con 1.000 GB
  gratuiti al mese, poi 0,05 $/GB. Richiede un account del titolare.
- **iPhone**: notifiche push e chiamate in arrivo richiedono l'account sviluppatore Apple (già
  necessario per la pubblicazione) e la chiave per le notifiche Apple. Si prepara con Codemagic.
- Nessuna di queste attivazioni si fa senza l'autorizzazione esplicita del titolare.

## 3. Decisioni da prendere

| N. | Domanda | Proposta |
|---|---|---|
| C1 | **Libreria di cifratura** (vedi 3.1) | **vodozemac** (Olm per la chat a due, Megolm per i gruppi), con la licenza AGPL-3.0 accettata |
| C2 | Dove viaggiano i messaggi | Firestore, come previsto dal PDF: sul server solo testo cifrato e i dati minimi per consegnarlo |
| C3 | Telefoni per account | Uno solo per la chat, come WhatsApp all'inizio: le chiavi restano sul telefono; un telefono nuovo non riceve la cronologia passata (copia di sicurezza cifrata: fase successiva) |
| C4 | Limiti di peso | Foto ridotte a 2048 px; vocali fino a 15 minuti; video compressi a 720p fino a 100 MB; file e documenti fino a 100 MB. Cifrati sul telefono prima del caricamento |
| C5 | Inoltro per le chiamate (TURN) e chiamate di gruppo | Cloudflare Realtime: TURN e SFU con 1.000 GB al mese gratuiti, poi 0,05 $/GB. Le chiamate di gruppo con il loro server SFU (fino a 8 persone in Fase 4) |
| C6 | Chi può scrivere | Contatti in rubrica: chat diretta. Tutti gli altri (per esempio da «Contatta» su un annuncio): richiesta di messaggio da accettare. Mai il numero agli sconosciuti |
| C7 | Elimina per tutti | Fino a 48 ore dall'invio; resta «Messaggio eliminato» |
| C8 | Gruppi | Fino a 256 persone; ruoli Proprietario, Amministratore, Membro; link d'invito revocabile; foto del gruppo |
| C9 | Messaggi effimeri, chat archiviate, sondaggi | Non previsti dal PDF: non si fanno |

### 3.1 La cifratura (C1): la decisione più importante

Il PDF chiede un «protocollo collaudato, non inventato». Le opzioni serie per Flutter sono tre e
**sono tutte con licenza «copyleft»**: chi distribuisce l'app deve rendere disponibile il codice
sorgente dell'app con la stessa licenza. Il repository è già pubblico, ma è una scelta
legale e commerciale del titolare: va confermata, e conviene sentire un professionista.

| Opzione | Protocollo | Verifiche indipendenti | Licenza dei collegamenti Flutter | Note |
|---|---|---|---|---|
| **vodozemac** (proposta) | Olm (Double Ratchet, come Signal) per i due; Megolm per i gruppi | Audit Least Authority 2022; problemi segnalati a febbraio 2026 e corretti nella versione 0.10 | AGPL-3.0 | Usato da Matrix/Element; gruppi grandi già previsti |
| libsignal ufficiale | Signal Protocol | Libreria di Signal | AGPL-3.0 | Collegamenti Flutter recenti e di terze parti |
| libsignal_protocol_dart | Signal Protocol | Nessun audit (versione della comunità) | GPL-3.0 | Gruppi e più telefoni non completi |

Non propongo di scrivere una cifratura nostra né di usare librerie senza verifiche: sarebbe contro
il PDF. Se la licenza AGPL non è accettabile, la Fase 4 va rivista prima di iniziare.

## 4. Blocchi di lavoro

Ogni blocco: APK identificabile, schermate di anteprima, test automatici, approvazione.

1. **Chat a due cifrata (testo).** Chiavi sul telefono, sessione Olm, invio e ricezione su
   Firestore solo cifrati, inviato/consegnato/letto, elenco delle chat, richieste di messaggio
   dagli sconosciuti (accetta/rifiuta/blocca), «Contatta» degli annunci collegato alla chat.
2. **Allegati.** Vocali, foto, video, file e documenti cifrati, con compressione e limiti C4.
3. **Funzioni dei messaggi e sicurezza.** Rispondi, inoltra, elimina per tutti, reazioni ai
   messaggi; segnalazione con i messaggi scelti (visibili solo all'amministratore autorizzato);
   «Condividi l'incontro con un amico»; **posizione in tempo reale** ai contatti in rubrica
   (dalla Fase 3).
4. **Gruppi.** Creazione, foto, amministratori, link d'invito, permessi lato server, cifratura
   Megolm, uscita e rimozione.
5. **Notifiche reali.** Push con l'app chiusa (anteprima decifrata sul telefono), silenzia per
   chat, «non disturbare», preferenze dei commenti (in-app / push), commenti e Mi piace degli
   annunci anche push, mai per i Non mi piace.
6. **Chiamate a due.** Vocali e video a tutto schermo, chiamata in arrivo con l'app chiusa
   (schermata di sistema su Android e iPhone), cifrate (WebRTC).
7. **Chiamate di gruppo.** Vocali e video fino a 8 persone (C5).

## 5. Azioni che spettano al titolare

- Decidere C1-C9, in particolare la licenza (C1).
- Quando vorrà provare sul telefono: attivare Blaze; creare l'account per le chiamate (C5);
  per iPhone, la chiave delle notifiche Apple. Mai chiavi o account incollati in chat.

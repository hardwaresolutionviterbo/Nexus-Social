# Fase 1 · Test automatici di Supabase (regola R3)

Documento di supporto a `PIANO_OPERATIVO.md`, passaggio 1.7. **Nessun test viene eseguito sul
database reale.**

## 1. Dove girano i test

- In GitHub Actions, su un database Supabase **temporaneo** creato all'inizio della prova e
  cancellato alla fine (Supabase CLI in locale nella macchina di GitHub).
- Gli utenti e i dati di prova sono inventati: nessun dato reale, nessuna chiave reale.
- I token Firebase di prova sono firmati con una **chiave di prova** generata al momento.
  - Il database temporaneo si fida solo di quella chiave.
  - Il progetto Firebase reale non viene mai contattato.
- I log mostrano solo il nome del caso e l'esito (superato / fallito), mai token o contenuti.

**Verifica fatta nel passaggio 1.7 (14/11/2026):** come il Supabase locale accetta token esterni.

- L'integrazione «Firebase Auth» di Supabase verifica la firma dei token con le chiavi di
  Google: senza token Firebase reali non si può riprodurre in un database temporaneo.
- **Soluzione adottata:** token di prova firmati con la chiave del database temporaneo,
  con le stesse informazioni di un token Firebase (emittente
  `https://securetoken.google.com/<progetto>`, destinatario, soggetto, ruolo, emissione,
  scadenza).
- In questo modo sono provati fedelmente:
  - le regole di accesso;
  - i controlli dello schema su progetto, soggetto, emissione e scadenza (C4, C8);
  - il rifiuto delle firme non valide da parte del server (C3, C6).
- **Resta fuori** la firma vera di Google: va provata in Fase 2 con un account di prova.
- **Nota di trasparenza:** il piano chiedeva di proporre al titolare un'alternativa *prima* di
  scrivere i test, se la simulazione non fosse stata fedele. La soluzione è stata applicata
  direttamente e viene sottoposta al titolare con l'esito del Blocco 3.

Lo schema in prova è `supabase/migrations/0002_identita_firebase_e_dati_privati.sql`, applicato al database reale il 14/11/2026. Il
workflow «Supabase RLS» applica le migrazioni approvate a un database temporaneo e si ferma se
ne compaiono di non approvate.

**Controprova:** tre database temporanei, ciascuno con un difetto introdotto apposta:
- dati privati aperti → il caso B1 deve fallire;
- token di altri progetti accettati → il caso C4 deve fallire;
- punto esatto esposto → il caso D2.1 deve fallire.

Dimostra che i test rilevano davvero i problemi.

- Se l'ambiente locale non permette di simularla fedelmente, prima di scrivere i test si propone
  al titolare un'alternativa documentata.
- In nessun caso si riduce il numero di casi coperti.

## 2. Struttura dei dati da provare

| Parte | Contenuto | Chi può leggere |
|---|---|---|
| **Pubblica** | Nome abbreviato, @username, avatar, bio e link social (secondo P3), tipo di account | Utenti autenticati, salvo blocco (P12, quando arriverà in Fase 2) |
| **Privata** | Nome e cognome completi, data di nascita (D1, M1), altri dati personali previsti | **Solo il proprietario**. Mai altri utenti, mai chi non è autenticato |

Il numero di telefono non viene salvato in Supabase in questa fase: resta a Firebase
Authentication.

## 3. Casi di prova obbligatori

**A · Separazione tra dati pubblici e privati**

| N. | Caso | Esito atteso |
|---|---|---|
| A1 | L'utente A legge i propri dati privati | Consentito |
| A2 | L'utente A legge il profilo pubblico di B | Consentito, solo campi pubblici |
| A3 | Il profilo pubblico non contiene nome completo né data di nascita, in nessuna forma | Verificato sulle colonne restituite |
| A4 | Il nome pubblico è sempre abbreviato (es. «Carlo C.») | Verificato |

**B · Nessuna lettura dei dati privati altrui**

| N. | Caso | Esito atteso |
|---|---|---|
| B1 | A legge i dati privati di B direttamente | Zero righe o errore |
| B2 | A cerca i dati privati di B con filtri, ordinamenti o ricerche (nome, data di nascita) | Zero righe |
| B3 | A tenta di modificare o cancellare i dati di B | Rifiutato; dati di B invariati |
| B4 | A tenta di creare un profilo con l'identità di B | Rifiutato |
| B5 | A tenta di cambiare il proprio identificativo in quello di B | Rifiutato |
| B6 | Funzioni del database (es. `nearby_listings`) non restituiscono dati privati | Verificato sulle colonne restituite |
| B7 | Utente non autenticato (chiave pubblica senza token) | Nessun dato privato né pubblico dei profili |

**C · Token Firebase non validi o di altri utenti**

| N. | Caso | Esito atteso |
|---|---|---|
| C1 | Nessun token | Trattato come non autenticato (come B7) |
| C2 | Token scaduto | Rifiutato |
| C3 | Token con firma alterata o firmato da una chiave sconosciuta | Rifiutato |
| C4 | Token emesso per un **altro progetto Firebase** (destinatario o emittente diversi) | Rifiutato |
| C5 | Token valido dell'utente B usato per leggere i dati privati di A | Vede solo i dati di B, mai quelli di A |
| C6 | Token valido di A con il contenuto modificato per fingersi B | Rifiutato (firma non valida) |
| C7 | Token malformato o troncato | Rifiutato, senza dettagli sensibili nel messaggio di errore |
| C8 | Token con data di emissione nel futuro | Rifiutato |

**D · Regole già presenti nello schema (non devono peggiorare)**

| N. | Caso | Esito atteso |
|---|---|---|
| D1 | Un utente non diventa admin da solo | Rifiutato |
| D2 | Posizione degli annunci: rispettata la modalità scelta per ciascun annuncio (P9) | Vedi sezione 3-bis |
| D3 | Le segnalazioni di un utente non sono leggibili da altri utenti | Verificato |

**E · Nessun accesso amministrativo per percorsi alternativi (regola F10)**

| N. | Caso | Esito atteso |
|---|---|---|
| E1 | Un utente normale si inserisce nella tabella degli admin | Rifiutato |
| E2 | Un utente normale legge l'elenco degli admin | Vede al massimo sé stesso; nessun altro admin |
| E3 | Un utente normale crea o modifica sanzioni (sospensioni, ban) per sé o per altri | Rifiutato |
| E4 | Un utente normale legge o gestisce le segnalazioni di altri | Rifiutato |
| E5 | Un utente normale modifica campi protetti di profili o annunci altrui sfruttando l'eccezione prevista per gli admin | Rifiutato; dati invariati |
| E6 | Token di prova con ruoli falsificati (`admin`, `service_role`, `supabase_admin`) o permessi aggiuntivi | Nessun privilegio: rifiutato o trattato come utente normale |
| E7 | Chiave pubblica (`anon`) senza token | Nessun accesso a tabelle e funzioni amministrative |
| E8 | Funzioni del database con permessi elevati (`security definer`), chiamate da un utente normale | Non consentono azioni da admin né la lettura di dati riservati |

## 3-bis. Posizione degli annunci (decisione P9)

P9:
- la posizione **approssimata** è quella **predefinita**;
- per ogni annuncio l'autore può scegliere invece la posizione **precisa** scelta a mano.

I test verificano che sia rispettata la modalità di ciascun annuncio.

| N. | Caso | Esito atteso |
|---|---|---|
| D2.1 | Annuncio creato senza indicare la modalità | Modalità **approssimata**; gli altri utenti vedono solo la posizione approssimata e una distanza a fasce |
| D2.2 | Annuncio in modalità approssimata | Il punto preciso non è leggibile da altri utenti in nessun modo: né dalla tabella, né dalle funzioni come `nearby_listings`, né con filtri o ordinamenti per distanza |
| D2.3 | Annuncio in modalità **precisa** scelta dall'autore | Gli altri utenti autenticati vedono esattamente il punto scelto dall'autore |
| D2.4 | Stesso autore, due annunci con modalità diverse | Ogni annuncio rispetta la propria modalità; la scelta su uno non cambia l'altro |
| D2.5 | Un altro utente tenta di cambiare la modalità o la posizione di un annuncio non suo | Rifiutato; annuncio invariato |
| D2.6 | L'autore passa da precisa ad approssimata | Da quel momento il punto preciso non è più leggibile dagli altri |
| D2.7 | L'autore legge il proprio annuncio | Vede sempre la posizione salvata e la modalità scelta |
| D2.8 | Utente non autenticato | Nessuna posizione, né approssimata né precisa |

Note:
- Lo schema attuale (`0001`) salva sempre una posizione approssimata pubblica e una precisa
  riservata, ma non registra la modalità scelta. Lo schema `0002` del passaggio 1.7 aggiunge la
  modalità per ogni annuncio, con «approssimata» come valore predefinito.
- Il **GPS in tempo reale** (terza modalità di P9, con P10, P11 e M4) appartiene alla Fase 3 e
  sarà provato lì. Lo schema `0002` non deve impedirlo.

## 4. Criterio di superamento

- Tutti i casi A, B, C, D, D2.1-D2.8 ed E1-E8 superati in GitHub Actions.
- Se anche un solo caso fallisce, il passaggio 1.7 non è concluso e la migrazione non viene
  proposta per il database reale.
- L'applicazione al database reale resta comunque soggetta all'autorizzazione esplicita del
  titolare.

# Fase 3 · Piano operativo (proposta)

Stato: **piano approvato dal titolare il 15/11/2026** con le modifiche della sezione 3.1;
categorie della mappa decise dal titolare il 15/11/2026 (sezione 3.1, T4).

Riferimento: `Nexus_Social_Piano_di_Lavoro_COMPLETO_AGGIORNATO.pdf`, «FASE 3 – Mappa Sociale (il
cuore dell'app)» (SHA-256 `7da25d52…b8561eb`).

## 1. Obiettivo e requisiti (dal PDF)

> Obiettivo: avere la mappa 3D dell'Italia con annunci intorno alla posizione o al luogo scelto
> dall'utente.
>
> Cosa devi riuscire a provare sul telefono: pubblichi un annuncio: un secondo telefono vicino lo
> vede, uno lontano no; verifichi che la posizione privata esatta non sia pubblica e che le
> interazioni funzionino.

| N. | Requisito del PDF | Blocco |
|---|---|---|
| R3.1 | Mappa 3D dell'Italia centrata sulla posizione in tempo reale, aggiornata ogni poche centinaia di metri per risparmiare batteria | 1 |
| R3.2 | La posizione esatta privata non è mai pubblica: gli annunci personali compaiono in una zona approssimata | 2, 3 |
| R3.3 | Per ogni annuncio privato: zona approssimata, GPS in tempo reale facoltativo, oppure posizione scelta a mano | 2 |
| R3.4 | GPS in tempo reale spento di partenza, temporaneo, revocabile, visibile solo alle persone autorizzate | 5 |
| R3.5 | La posizione manuale vale solo per quell'annuncio | 2 |
| R3.6 | Modalità di posizione mostrata prima della pubblicazione e nella gestione dell'annuncio | 2 |
| R3.7 | Annuncio con foto, testo e scadenza | 2 |
| R3.8 | Avatar animati sulla mappa; toccandoli: nome abbreviato, @username, social e «Contatta» | 1, 3 |
| R3.9 | Raggio regolabile fino a 30 km (10 km di partenza); Milano non vede Torino | 3 |
| R3.10 | «Ultimi annunci» con due schede: Annunci (persone) e Promozioni (attività) | 3 |
| R3.11 | Filtri (categoria, distanza, orario), segnalazione annuncio, stato «Disponibile ora» | 3 |
| R3.12 | Eventi di gruppo con conteggio dei partecipanti («mancano 3 persone») | 4 |
| R3.13 | Mi piace / Non mi piace con conteggi e accesso ai commenti | 4 |

## 2. Decisioni già prese che valgono in Fase 3

- **F9 · Mappa:** MapLibre con tile OpenFreeMap. «3D» = inclinazione, rotazione ed edifici 3D; il
  rilievo del terreno quando MapLibre lo rilascerà ufficialmente. **Prototipo all'inizio della
  Fase 3**; se fallisce, si valuta un fornitore di riserva.
- **Attribuzione** «© OpenStreetMap contributors» sempre visibile; informativa privacy già aggiornata.
- **P9-P11:** zona approssimata preselezionata; GPS live con consenso esplicito, durata libera fino a
  8 ore, interrompibile; alla fine l'ultima posizione si cancella subito, nessuno storico.
- **P12:** chi è bloccato non commenta e non vede reazioni e commenti dell'altro.
- **P13:** il consenso al GPS live compare in Privacy → Autorizzazioni con data e «Revoca».
- **M3:** avviso di sicurezza della Mappa al primo accesso («Ho capito») e sempre da un'icona;
  per i minorenni ripetuto prima di ogni annuncio con posizione precisa o GPS live.
- **M4:** i minorenni condividono il GPS live solo con contatti riconosciuti dalla rubrica.
- **A5 e concept dei marker:** persona = marker rotondo con foto (o avatar illustrato); tipi
  distinguibili per forma, icona e colore; distanza arrotondata a fasce, calcolata dal server.
- **Schema Supabase esistente:** `listings`, `listing_locations`, `nearby_listings` (zone di 250 m),
  `set_listing_location_mode`, `reports`.
- **S1 in pausa:** tutto ciò che usa il server si prova con i test automatici; la prova sul
  telefono con Blaze. **Eccezione:** la mappa e la posizione (Blocco 1) non hanno bisogno del
  server e si possono provare **subito sul telefono**.

## 3. Decisioni da prendere (T1-T7)

| N. | Domanda | Proposta |
|---|---|---|
| T1 | Pacchetto mappa | `maplibre_gl` (versione 0.27, il pacchetto storico mantenuto da MapLibre) |
| T2 | Avatar illustrati 3D (A5) | In Fase 3 la persona compare con la propria foto (o l'iniziale). Il set di personaggi illustrati originali è un lavoro grafico a parte, da fare prima del lancio |
| T3 | Chi vede il GPS live (R3.4) | Le persone che l'autore sceglie una per una tra chi lo ha contattato o i contatti riconosciuti (per i minorenni solo questi, M4) |
| T4 | Categorie degli annunci | Incontro/evento, Sport, Gaming/hobby, Aiuto, Regalo, Altro (Scambia e Vendita restano nelle loro sezioni, Fase 5) |
| T5 | Scadenze | 1 ora, 3 ore, oggi, 3 giorni, 7 giorni (massimo 7) |
| T6 | Commenti in Fase 3 | Fase 3: Mi piace/Non mi piace con conteggi, elenco commenti e commento. Fase 5: modifica, moderazione, elenchi nominativi completi delle reazioni |
| T7 | «Contatta» prima della chat | In Fase 3 il pulsante c'è ma apre l'avviso «disponibile con la chat (Fase 4)» |

### 3.1 Decisioni del titolare (15/11/2026)

- **T1, T2, T3, T5, T7:** approvate come proposte.
- **T4 · Categorie della mappa (decisione del titolare, sostituisce la proposta):** sulla mappa
  esistono **solo due categorie**, senza sottocategorie:
  - **Libera** — le persone scrivono ciò che vogliono («chi viene a prendere un caffè con me?»,
    «ci manca una persona per il calcetto, chi viene?»); la richiesta è libera, senza
    sottocategorie, gratuita. Gli eventi di gruppo con «mancano N persone» sono annunci Liberi.
  - **Promozione / Pubblicità** — per le aziende, a pagamento (9,99 €/mese), attiva dalla Fase 6.
  - Le due categorie coincidono con le due schede di «Ultimi annunci» (Annunci / Promozioni);
    il filtro «categoria» del PDF (R3.11) diventa la scelta tra queste due.
  - Le eventuali categorie di **Scambia** e **Vendita** (Fase 5) restano da definire dal titolare
    prima della Fase 5.
  - Nota: la Fase 6 del PDF parla di «attività e privati che fanno pubblicità»; se anche i privati
    potranno acquistare la Promozione si decide in Fase 6.
- **T6 · Interazioni come Facebook (modifica):** già in Fase 3, sotto ogni annuncio o post:
  - Mi piace, Non mi piace e Commenta, con i conteggi; una sola reazione per persona,
    sostituibile o rimovibile;
  - elenchi visibili di chi ha messo Mi piace / Non mi piace e di chi ha commentato (solo nome
    abbreviato e @username);
  - risposte ai commenti, mostrate sotto il commento;
  - blocchi rispettati (P12).
- **Condividi (anticipato dalla fase finale del PDF):** pulsante su ogni annuncio o post per
  inviarlo ai social e alle altre app. Testo e foto con zona approssimata; mai posizione esatta né
  numero. Il link che apre l'annuncio nell'app arriverà con la pagina web (oggi i link diretti
  all'app non sono ammessi, F10).
- **Notifiche delle interazioni (modifica al PDF, Fase 4: «non inviare notifiche per Mi piace e
  Non mi piace»):**
  - all'autore: per i **Mi piace** (non per i Non mi piace) e per i commenti;
  - chi commenta **segue il post** in automatico: avvisi per i nuovi commenti e per le risposte;
  - chi riceve una risposta al proprio commento viene avvisato; la notifica apre il post sul
    commento;
  - «Disattiva notifiche per questo post», interruttori generali nelle preferenze, nessun avviso
    da persone bloccate né per le proprie azioni, Mi piace ravvicinati raggruppati;
  - in Fase 3 nella campanella dell'app; push ad app chiusa con il server attivo (Blaze, Fase 4).
- **Gratuità:** gli annunci delle persone sono sempre gratuiti; i post di promozione delle aziende
  costano 9,99 €/mese e si attivano in Fase 6 (scheda «Promozioni» vuota fino ad allora).

## 4. Blocchi di lavoro

Ogni blocco ha un APK identificabile e si ferma per la tua verifica e approvazione.

1. **Prototipo mappa (provabile subito sul telefono).** Mappa 3D dell'Italia (inclinazione,
   rotazione, edifici), posizione con aggiornamento ogni ~300 m, permesso posizione con
   spiegazione, avviso di sicurezza M3, attribuzione OpenStreetMap, marker rotondo animato di
   prova. Verifica di fluidità e batteria: se non va, si valuta il fornitore di riserva (F9).
2. **Pubblicare un annuncio.** Foto, testo, categoria, scadenza; scelta della posizione
   (approssimata preselezionata, punto scelto a mano sulla mappa); modalità sempre mostrata;
   gestione dell'annuncio (modifica, chiudi). Migrazione Supabase e foto su Storage.
3. **Annunci vicino a te.** Annunci sulla mappa in zone approssimate, raggio 1-30 km (10 di
   partenza), scheda della persona con «Contatta», «Ultimi annunci» con le schede Annunci e
   Promozioni (vuota fino alla Fase 6), filtri, «Disponibile ora», segnala annuncio.
4. **Eventi di gruppo e interazioni.** Partecipo/non partecipo con conteggio e «mancano N
   persone»; Mi piace / Non mi piace con elenchi, commenti con risposte, «Condividi», notifiche
   nella campanella (sezione 3.1); blocchi rispettati.
5. **GPS in tempo reale.** Consenso esplicito, durata fino a 8 ore, «Interrompi», solo persone
   autorizzate, cancellazione immediata alla fine (P11), consenso in Autorizzazioni (P13), regole
   per i minorenni (M3, M4).

## 5. Azioni che spettano al titolare

- Blocco 1: installare l'APK e provare la mappa sul telefono (nessun account, nessuna chiave).
- Blocchi 2-5: approvazione dalle schermate e dai test; prova sul telefono quando ci sarà Blaze,
  con due telefoni (vicino e lontano).
- Applicazione delle nuove migrazioni sul database reale: solo con autorizzazione.

## 6. Test previsti

- Database temporaneo: zone approssimate mai uguali alla posizione esatta; raggio rispettato
  (Milano non vede Torino); scadenze; posizione manuale solo per l'annuncio; GPS live solo agli
  autorizzati e cancellato alla fine; una sola reazione per persona; blocchi su commenti e
  reazioni; segnalazioni; controprove per i casi principali.
- App: schermate, filtri, raggio, modalità di posizione mostrata, avviso M3, minorenni (M4).
- Regressione F1-F11 e test delle Fasi 1-2.

## 7. Cosa NON si fa in Fase 3

- Chat e richieste di messaggio (Fase 4): «Contatta» resta in attesa.
- Scambia, Vendita, feedback e moderazione completa dei commenti (Fase 5).
- Promozioni, sedi delle attività e abbonamento (Fase 6).
- Nessuna pubblicazione, nessun servizio a pagamento, nessuna migrazione sul database reale senza
  autorizzazione.

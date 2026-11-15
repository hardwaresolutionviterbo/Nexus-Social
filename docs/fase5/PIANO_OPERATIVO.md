# Fase 5 · Piano operativo

Stato: **piano approvato dal titolare il 15/11/2026**, con la richiesta «foto obbligatorie» (D11).

Riferimenti:
- `Nexus_Social_Piano_di_Lavoro_COMPLETO_AGGIORNATO.pdf`, «FASE 5 – Scambia, Vendita e feedback»
  (SHA-256 `7da25d52…b8561eb`);
- **specifica del titolare** «PIAZLY – Marketplace SCAMBIA & VENDI v1.0»
  (`docs/fase5/CATALOGO_TITOLARE.md`), che amplia la Fase 5 del PDF: dove le due fonti
  differiscono vale la specifica del titolare, più recente.

## 1. Requisiti

| N. | Requisito | Fonte | Blocco |
|---|---|---|---|
| R5.1 | Catalogo gerarchico: 19 categorie con sottocategorie, ID e slug stabili, ordine, attivo/disattivo | Specifica 2-3 | 1 |
| R5.2 | Un solo sistema di annunci con 4 tipologie: Vendita, Scambio, Regalo, Cerco | Specifica 4 | 1 |
| R5.3 | Campi: titolo, descrizione, categoria, sottocategoria, tipologia, prezzo (obbligatorio Vendita, facoltativo Scambio, assente Regalo), condizioni, località, foto, stato, spedizione, ritiro a mano | Specifica 5, PDF | 1 |
| R5.4 | Selezione categoria → sottocategoria → campi specifici | Specifica 10 | 1 |
| R5.5 | Prodotti vietati, illegali o regolamentati; animali solo accessori | Specifica 9 | 1 |
| R5.6 | Avviso antitruffa sempre visibile, «Segnala annuncio», l'app non gestisce i soldi | PDF | 2 |
| R5.7 | Ricerca con 13 filtri e 5 ordinamenti, pagine progressive | Specifica 7, PDF | 2 |
| R5.8 | Mi piace / Non mi piace con elenchi; commenti; Condividi; Contatta | PDF | 2 |
| R5.9 | Scambi: cosa si cerca, proposte con annunci propri e conguaglio, controproposte, accetta/rifiuta, annulla, conclusione da entrambi, storico, notifiche; stati In attesa / Accettata / Rifiutata / Controproposta / Annullata / Completata | Specifica 6 | 3 |
| R5.10 | Concluso → feedback a stelle con commento; media sul profilo dei privati | PDF | 4 |
| R5.11 | Commenti: modifica, moderazione senza alterare l'identità, segnalazione, anti-spam, paginazione; notifiche separate dalle reazioni | PDF | 5 |
| R5.12 | Amministrazione delle categorie (crea, rinomina, attiva/disattiva, ordina, conteggi, archivia senza eliminare quelle usate) | Specifica 8 | 5 |

## 2. Cosa c'è già e cosa dipende da altro

- **Riutilizzati**: foto senza metadati, zona approssimata o punto scelto, raggio 1-30 km,
  segnalazioni, blocchi, Mi piace / Non mi piace, commenti con risposte, notifiche nella
  campanella, Condividi (Fasi 2-3).
- **Chat tra le parti**: con la Fase 4 (in sospeso). Fino ad allora proposte e conclusione
  funzionano senza chat, ci si scrive nei commenti e «Contatta» mostra l'avviso.
- **Pannello amministrativo**: in questa fase le funzioni del server per le categorie e la
  moderazione, provate dai test; le schermate per l'amministratore con la Fase 7 (Gestionale
  Admin), come previsto dal PDF.
- **Prova sul telefono**: server attivo (Blaze) e autorizzazione ad applicare le migrazioni.
  Nessuna migrazione sul database reale senza autorizzazione; nessun merge in `main` prima
  dell'approvazione del titolare (specifica, sezione 12).

## 3. Decisioni del titolare (15/11/2026)

| N. | Decisione |
|---|---|
| D1 | Categorie: quelle della specifica del titolare (19 categorie, sottocategorie elencate) |
| D2 | Scambio: proposte, controproposte, accetta/rifiuta e conclusione subito; chat tra le parti con la Fase 4 |
| D3 | Campi specifici: Motori anno e km; Immobili metri quadri e locali; Abbigliamento e scarpe taglia/numero; Elettronica memoria. Facoltativi, tranne l'anno per Auto e i metri quadri per Immobili |
| D4 | Barra di ricerca per parola (titolo e descrizione), con l'ordinamento «Più pertinenti» |
| D5 | Durata 30 giorni, rinnovabile con un tocco |
| D6 | Conclusione: l'autore indica la persona, l'altra conferma; poi un feedback a testa (1-5 stelle e commento, non modificabile). Per lo Scambio la conferma di entrambi è già nella specifica |
| D7 | Notifiche dei Mi piace come sulla Mappa (Mi piace sì, raggruppati; Non mi piace mai) |
| D8 | Commenti: modifica con «modificato», nascondi (autore dell'annuncio e amministratori) con l'identità invariata, segnalazione; vale anche per la Mappa |
| D9 | Anti-spam: commenti 10 al minuto e 100 al giorno; annunci nuovi 20 al giorno; proposte 30 al giorno; pagine da 20 |
| D11 | **Foto obbligatorie** (almeno una, fino a 10) per Vendita, Scambio e Regalo. Per «Cerco» restano facoltative, perché chi cerca spesso non ha l'oggetto: scelta mia da confermare |
| D10 | Due sezioni, un solo sistema: «Scambia» mostra Scambio, Regalo e Cerco; «Vendita» mostra Vendita. La barra in basso non cambia. Questi annunci non vanno sulla Mappa |

Scelte tecniche (proposte, approvate con il piano):
- **Slug**: la specifica dà alcuni esempi; per tutte le sottocategorie lo slug sarà
  `categoria-nome` senza articoli e congiunzioni (es. `motori-moto-scooter`). Una volta creati
  non cambiano più.
- **Prodotti vietati** (D-sicurezza): conferma obbligatoria «non vendo prodotti vietati» a ogni
  pubblicazione, elenco dei divieti sempre consultabile, parole a rischio nel testo che mettono
  l'annuncio in revisione (non pubblico finché un amministratore non lo approva), segnalazioni.
  Nessuna sottocategoria di animali vivi.
- **Prezzo**: in euro, da 0 a 999.999.999 (gli immobili superano i 99.999); conguaglio da 1 a
  999.999.
- **«Privato o azienda»**: dal tipo di account già presente (Fase 2).

## 4. Blocchi di lavoro

Ogni blocco: APK identificabile, schermate di anteprima, test automatici, migrazione provata
solo sul database temporaneo, approvazione.

1. **Catalogo e pubblicazione.** Tabella `marketplace_categories` con le 19 categorie e le
   sottocategorie; annunci con le 4 tipologie, condizioni, prezzo secondo la tipologia,
   spedizione e ritiro, campi specifici (D3); modulo con scelta categoria → sottocategoria;
   regole sui prodotti vietati; I miei annunci con rinnovo (D5).
2. **Ricerca e scheda.** Sezioni Scambia e Vendita (D10), barra di ricerca (D4), i 13 filtri e
   i 5 ordinamenti, pagine progressive; scheda con avviso antitruffa, Segnala, Mi piace,
   commenti, Condividi, Contatta.
3. **Proposte di scambio.** Cosa si cerca in cambio, proposte con annunci propri e conguaglio,
   controproposte, accetta/rifiuta/annulla, stati, notifiche, storico.
4. **Conclusione e feedback.** Conferma di entrambi (D6), feedback a stelle, elenco dei
   feedback e media sul profilo dei privati.
5. **Commenti completi e amministrazione.** Modifica, nascondi, segnala commento, anti-spam (D8,
   D9), anche sulla Mappa; funzioni del server per amministrare le categorie (R5.12).

## 5. Test di accettazione (specifica, sezione 12)

Tutte le 19 categorie presenti; sottocategorie associate correttamente; ID univoci; selezione
gerarchica; ricerca per categoria; quattro tipologie; filtri; pubblicazione da smartphone;
policy di sicurezza provate; migrazioni verificate su database temporaneo; nessuna regressione.

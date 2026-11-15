# Fase 5 · Piano operativo (proposta)

Stato: **proposta da approvare dal titolare**. Nessun codice della Fase 5 prima dell'approvazione
e delle categorie (S1).

Riferimento: `Nexus_Social_Piano_di_Lavoro_COMPLETO_AGGIORNATO.pdf`, «FASE 5 – Scambia, Vendita e
feedback» (SHA-256 `7da25d52…b8561eb`).

## 1. Obiettivo e requisiti (dal PDF)

> Obiettivo: permettere alle persone di scambiare e vendere oggetti gratuitamente, con interazioni
> social sugli annunci.
>
> Cosa devi riuscire a provare sul telefono: pubblichi un oggetto, un altro utente ti contatta,
> interagisce con l'annuncio, commenta, concludete e vi lasciate il feedback.

| N. | Requisito | Blocco |
|---|---|---|
| R5.1 | Scambia: «offro / cerco», foto, categorie, tasto Contatta | 1 |
| R5.2 | Vendita: foto, titolo, prezzo, consegna solo ritiro a mano o spedizione; accordi in chat, l'app non gestisce i soldi | 2 |
| R5.3 | Avviso antitruffa sempre visibile e «Segnala annuncio» | 1, 2 |
| R5.4 | «Segna come concluso»: solo dopo si può lasciare il feedback | 3 |
| R5.5 | Feedback a stelle con commento (stile eBay e Subito); media stelle sul profilo dei privati | 3 |
| R5.6 | Mi piace / Non mi piace, una reazione per persona, conteggi separati ed elenchi nominativi | 1, 2 (dalla Fase 3) |
| R5.7 | Reazioni senza notifiche (PDF) — **vedi S6** | 4 |
| R5.8 | Commenti: avatar/nome pubblico, testo, data e ora; l'autore modifica o elimina il proprio commento | 4 |
| R5.9 | Moderazione dell'autore dell'annuncio e degli amministratori senza alterare l'identità di chi ha scritto | 4 |
| R5.10 | Segnalazione dei commenti, blocco utenti, moderazione Admin, limiti anti-spam, paginazione e caricamento progressivo | 4 |
| R5.11 | Notifiche dei commenti separate dalle reazioni; mai per un proprio commento | 4 (già in Fase 3) |

## 2. Cosa c'è già e cosa dipende da altro

- **Riutilizzati dalla Fase 3**: foto senza metadati, zona approssimata o punto scelto, raggio
  1-30 km, segnalazione, blocchi, Mi piace / Non mi piace con elenchi, commenti con risposte,
  notifiche nella campanella, «Condividi».
- **«Contatta» e gli accordi in chat** dipendono dalla chat (Fase 4, in sospeso). Fino ad allora il
  pulsante resta l'avviso «Chat in arrivo» e ci si accorda nei commenti; la prova completa del PDF
  («un altro utente ti contatta») arriva con la Fase 4.
- **Prova sul telefono**: come le Fasi 2-3, serve il server attivo (Blaze) e l'autorizzazione ad
  applicare le migrazioni.
- **Gestionale Admin**: le funzioni di moderazione si preparano sul server e si provano nei test;
  le schermate per l'amministratore arrivano con la Fase 7.

## 3. Decisioni da prendere

| N. | Domanda | Proposta |
|---|---|---|
| S1 | **Categorie** di Scambia e Vendita | Le manda il titolare. Se preferisce una base: Abbigliamento e accessori · Casa e arredamento · Elettronica · Libri, musica e film · Bambini e giocattoli · Sport e tempo libero · Auto e moto (ricambi e accessori) · Hobby e collezionismo · Animali (accessori) · Altro |
| S2 | Dove valgono | Stesse regole della Mappa: zona approssimata o punto scelto, raggio 1-30 km (10 di partenza). Gli annunci compaiono nelle sezioni Scambia e Vendita, non sulla Mappa |
| S3 | Durata | 30 giorni, rinnovabili dall'autore |
| S4 | Vendita | Prezzo in euro da 0 a 99.999; «Ritiro a mano», «Spedizione» o entrambi; nessun pagamento nell'app; avviso antitruffa fisso in ogni annuncio e prima del contatto |
| S5 | Concluso e feedback | L'autore tocca «Segna come concluso» e sceglie con chi (tra chi ha commentato e, con la Fase 4, chi l'ha contattato); l'altra persona conferma. Solo dopo, ciascuno dei due lascia **un** feedback: 1-5 stelle e commento fino a 500 caratteri, non modificabile, visibile sul profilo. Media stelle solo sul profilo dei privati |
| S6 | Notifiche dei Mi piace | Il PDF (Fase 5) dice nessuna notifica per le reazioni; in Fase 3 hai deciso le notifiche dei Mi piace per la Mappa. Proposta: **stessa regola ovunque** (Mi piace sì, Non mi piace mai), salvo tua diversa indicazione |
| S7 | Commenti (novità del PDF) | Modifica del proprio commento con la scritta «modificato»; l'autore dell'annuncio e gli amministratori possono **nascondere** un commento (resta «Commento nascosto dalla moderazione», nome di chi l'ha scritto invariato); segnalazione dei commenti; vale anche per la Mappa |
| S8 | Limiti anti-spam | 10 commenti al minuto e 100 al giorno per persona; 20 annunci nuovi al giorno; elenchi e commenti a pagine da 20 con caricamento progressivo |
| S9 | Ricerca per parola, aste, pagamenti | Non previsti dal PDF: non si fanno |

## 4. Blocchi di lavoro

Ogni blocco: APK identificabile, schermate di anteprima, test automatici, approvazione.

1. **Scambia.** Schede «Offro» e «Cerco», pubblica (foto, titolo, descrizione, categoria, luogo),
   elenco vicino a te con filtri categoria e distanza, scheda dell'annuncio con avviso
   antitruffa, Contatta (avviso finché non c'è la chat), Segnala, Mi piace, commenti, Condividi.
2. **Vendita.** Come Scambia con prezzo e consegna; avviso «l'app non gestisce i pagamenti».
3. **Concluso e feedback.** Segna come concluso con conferma dell'altra persona, feedback a
   stelle con commento, elenco dei feedback e media sul profilo dei privati.
4. **Commenti completi e moderazione.** Modifica, nascondi (autore dell'annuncio e
   amministratori), segnala commento, limiti anti-spam, pagine da 20, notifiche dei commenti
   separate dalle reazioni; esteso anche agli annunci della Mappa.

## 5. Azioni che spettano al titolare

- Inviare o approvare le categorie (S1) e decidere S2-S9.

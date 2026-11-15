# Fase 5 · Blocco 2 — Esito (ricerca e scheda)

Ramo `fase5/blocco2` (parte da `fase5/blocco1`). Nessuna modifica a `main` né al database reale.

## Controlli automatici
- Supabase (database temporaneo, migrazione 0013): N0–N10 superati, 120 casi su 120; nuove
  controprove `ricerca_revisione_visibile` (N8) e `ricerca_punto_esatto` (N4) rilevano il difetto.
- App: analisi e test superati; APK `nexus-social-0.1.0+21601-05bb452-fase5-blocco2`
  (le modifiche successive riguardano solo le anteprime).
- Schermate: mercato_1 e mercato_7..9.

## Cosa c'è
- Sezioni Scambia (Scambio, Regalo, Cerco) e Vendita (Vendo) con barra di ricerca per parola
  (radici italiane, anche parti di parola nel titolo) e ordinamento «Più pertinenti» (D4).
- 13 filtri: categoria, sottocategoria, tipologia, prezzo min/max, condizioni, località
  (ovunque, vicino a me una volta sola, punto sulla mappa), raggio 1–200 km, privato o azienda,
  spedizione, ritiro a mano, disponibili allo scambio, conguaglio, data di pubblicazione.
- 5 ordinamenti; pagine da 20 con caricamento in fondo all'elenco (D9).
- Scheda: foto scorrevoli, prezzo, condizioni, consegna, scambio e conguaglio, campi specifici,
  zona e distanza arrotondata, autore, avviso antitruffa, Contatta (avviso: chat con la Fase 4),
  Segnala, Mi piace / Non mi piace, commenti, Condividi (mai la posizione).
- Modulo: «Valuto anche scambi» (Vendita) e «Accetto un conguaglio» (Scambio o Vendita che
  valuta scambi).

## Da dichiarare al titolare
- Due campi nuovi negli annunci: «valuta scambi» e «conguaglio», per i filtri della specifica.
- Il pannello delle interazioni e il modulo di segnalazione della Mappa ora servono anche a
  Scambia & Vendi (stesso codice, nessun cambiamento visibile sulla Mappa).
- Raggio massimo 200 km oppure «Ovunque»; la posizione non viene mai salvata.
- Aggiunte 2 schermate all'elenco chiuso del controllo F10 (filtri e scheda).

## Approvazione
- 16/11/2026: Blocco 2 approvato dal titolare.

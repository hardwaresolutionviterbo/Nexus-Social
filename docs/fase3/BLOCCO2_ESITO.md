# Fase 3 · Blocco 2 — Pubblicare un annuncio: esito

Stato: **approvato dal titolare il 15/11/2026** («al momento»), per le parti provate dai test
automatici. La prova sul telefono richiede il server attivo (Blaze) e l'applicazione della
migrazione 0007 al database reale, entrambe da autorizzare.

## Cosa contiene
- App: modulo «Nuovo annuncio» (categoria Libera, gratuita), testo e dettagli, fino a 4 foto
  ridotte e senza metadati, scadenze T5 (1 ora, 3 ore, oggi, 3 giorni, 7 giorni).
- Luogo (P9): zona approssimata preselezionata oppure punto scelto a mano sulla mappa;
  modalità sempre scritta prima di pubblicare e nell'elenco «I miei annunci».
- «I miei annunci»: stato, scadenza, modalità, «Modifica» e «Chiudi» con conferma.
- M3: per i minorenni l'avviso di sicurezza si ripete prima di un annuncio con punto preciso.
- Senza server «Pubblica» spiega che serve il collegamento; la mappa funziona comunque.
- Server, migrazione `0007_annunci_mappa.sql` (non applicata al reale): pubblicazione,
  modifica, spostamento e chiusura solo con funzioni; nessuna scrittura diretta; nessun
  passaggio da zona a punto preciso sul punto salvato; annunci nascosti tra bloccati (P12).

## Modifiche dichiarate e approvate
- Elenco F10 dei file che navigano: aggiunti `listing_form_screen`, `map_screen`,
  `my_listings_screen`, `point_picker_screen`.
- `set_listing_location_mode` accetta solo il passaggio verso la zona approssimata.
- `nearby_listings` esclude gli annunci tra persone bloccate.
- Limite noto: le foto degli annunci sono nel bucket pubblico `listing-photos` (link lunghi
  e casuali); chi è bloccato non vede l'annuncio ma un link già noto resta apribile.

## Verifiche
- App: 168 test superati; analisi statica pulita.
- Server: 83/83 casi su database temporaneo (nuovi J1-J9), 10 controprove (nuove J4, J8).
- Anteprime: `annuncio_1_nuovo`, `annuncio_2_scegli_punto`, `annuncio_3_punto_scelto`,
  `annuncio_4_miei_annunci`.

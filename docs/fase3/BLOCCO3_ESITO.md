# Fase 3 · Blocco 3 — Annunci vicino a te: esito

Stato: **approvato dal titolare il 15/11/2026**, per le parti provate dai test automatici. La
prova sul telefono richiede il server attivo (Blaze) e l'applicazione delle migrazioni 0007 e
0008 al database reale, da autorizzare.

## Cosa contiene
- Segnaposti rotondi con l'iniziale dell'autore (T2); arancione, verde se «Disponibile ora»,
  azzurro per i propri. Ricerca a ogni nuova posizione (~300 m), a ogni cambio di raggio o filtro.
- Raggio 1/5/10/30 km (10 di partenza) con il conteggio degli annunci nell'intestazione.
- Scheda dell'annuncio: autore (nome abbreviato, @username, profilo pubblico con social e
  «Blocca»), foto, testo, distanza arrotondata, modalità del luogo, scadenza, «Contatta»
  (avviso: chat dalla Fase 4, T7), «Segnala annuncio» con motivi chiusi.
- Filtri (R3.11): distanza, orario inteso come «pubblicati nell'ultima ora / 24 ore / 7 giorni»
  (interpretazione dichiarata e approvata con il blocco), «solo Disponibile ora».
- «Ultimi annunci» (R3.10): schede Annunci (categoria Libera) e Promozioni (vuota fino alla Fase 6).
- «I miei annunci»: interruttore «Disponibile ora».
- Server, migrazione `0008_annunci_vicini.sql` (non applicata al reale): `map_listings_nearby`
  (raggio limitato a 30 km e misurato sul punto pubblico, posizione di chi cerca non salvata,
  distanza arrotondata a 250 m, blocchi rispettati), `set_my_listing_available`,
  `my_map_listings` con «Disponibile ora», `report_listing` (motivi chiusi, una segnalazione
  aperta per annuncio, mai sui propri).

## Modifiche dichiarate e approvate
- Elenco F10 dei file che navigano: aggiunto `listing_sheets.dart` (apre il profilo dell'autore).

## Verifiche
- App: 186 test superati; analisi statica pulita.
- Server: 91/91 casi (nuovi K1-K8), 12 controprove (nuove K2 «raggio illimitato», K6 «blocchi
  ignorati»).
- Anteprime: `vicini_1_scheda`, `vicini_2_ultimi_annunci`, `vicini_3_filtri`.

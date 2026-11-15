# Fase 3 · Blocco 4 — Eventi di gruppo e interazioni come Facebook: esito

Stato: **approvato dal titolare il 15/11/2026** («approvo tutto»), per le parti provate dai test
automatici. La prova sul telefono richiede il server attivo (Blaze) e l'applicazione delle
migrazioni 0007-0009 al database reale, da autorizzare.

## Cosa contiene
- Evento di gruppo (R3.12): nel modulo «Evento di gruppo» con le persone cercate (1-50);
  «Partecipo» / «Non partecipo più», «mancano N persone», «Al completo», elenco dei partecipanti.
- Sotto ogni annuncio: Mi piace / Non mi piace con conteggi ed elenchi nominativi (una reazione
  per persona, sostituibile o rimovibile), Commenta, Condividi.
- Commenti come Facebook: risposte a un livello sotto il commento principale, Mi piace e
  Rispondi su ogni commento, Elimina (autore del commento o dell'annuncio).
- Notifiche nella campanella: Mi piace all'annuncio (raggruppati), commenti all'annuncio,
  risposte, commenti sui post seguiti (chi commenta segue il post), Mi piace ai propri
  commenti (raggruppati, interpretazione dichiarata e approvata); mai per i Non mi piace, mai
  per le proprie azioni né tra persone bloccate; «Disattiva notifiche per questo post»; la
  notifica apre il post sul commento evidenziato. Push ad app chiusa: con il server (Fase 4).
- Condividi (share_plus): testo e prima foto, mai posizione né distanza; link all'app con la
  pagina web (F10).
- P12: chi è bloccato non commenta, non reagisce, non partecipa e non vede reazioni,
  commenti e partecipanti dell'altro.
- Server, migrazione `0009_interazioni.sql` (non applicata al reale): tabelle accessibili solo
  dalle funzioni; `publish_map_listing` e `update_my_listing` con l'evento; annunci vicini e
  «I miei annunci» con posti e partecipanti.

## Modifiche dichiarate e approvate
- Nuova dipendenza `share_plus` 13.3.1.
- Elenco F10 dei file che navigano: aggiunti `comments_screen`, `listing_social_panel`,
  `notifications_screen`.
- Mi piace sui commenti con notifica a chi li ha scritti.

## Verifiche
- App: 206 test superati; analisi statica pulita.
- Server: 101/101 casi (nuovi L1-L10), 14 controprove (nuove L2 «notifica dei Non mi piace»,
  L7 «commenti dei bloccati visibili»).
- Anteprime: `interazioni_1_evento`, `interazioni_2_commenti`, `interazioni_3_notifiche`.

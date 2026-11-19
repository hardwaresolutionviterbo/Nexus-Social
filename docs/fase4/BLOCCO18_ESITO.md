# Fase 4 · Blocco 18 — Graffetta come WhatsApp, incontro via SMS, luoghi suggeriti, Piazly AI

Richiesta del titolare del 19/11/2026 (funzioni oltre il PDF, approvate dal titolare).

## Cosa c'è

- **Graffetta**: Galleria, Fotocamera, Video, Documento, **Posizione**, **Contatto**,
  **Sondaggio**, **Evento**, **Immagini IA**.
  - Posizione: quella attuale (una volta), **in tempo reale** (15 min / 1 ora / 8 ore, usa il GPS
    in tempo reale del Blocco 14 con le persone della chat), oppure un posto cercato.
  - Contatto: scelto dalla rubrica del telefono (nome e fino a 5 numeri); chi lo riceve può
    chiamare o copiare il numero.
  - Sondaggio: domanda, da 2 a 12 risposte, una o più scelte; i voti si vedono subito.
  - Evento: titolo, giorno e ora, luogo (con i suggerimenti), descrizione; «Ci sono» / «Non ci sono».
  - Tutto viaggia **cifrato end-to-end** come i messaggi (nuovi tipi `rich` e `ans` del contenuto).
    Le versioni vecchie dell'app li mostrano come «Messaggio non disponibile».
- **Condividi l'incontro**: se l'unico contatto su Piazly è la persona che si incontra, ora lo dice
  chiaramente (prima: «Nessun contatto della rubrica è su Piazly», sbagliato). Nuovo pulsante
  **«Manda con SMS o un'altra app»** (condivisione del telefono). Se il luogo è scelto dai
  suggerimenti, nel messaggio c'è anche il link della mappa.
- **Luoghi suggeriti mentre si scrive** (campo «Dove»): subito i comuni dall'elenco nell'app
  (es. «Poran» → «Porano (TR) · Umbria»), poi, dopo una breve pausa, posti e indirizzi da
  OpenStreetMap tramite **Photon** (servizio gratuito senza chiave, «da usare con giudizio»: si
  chiede solo dopo 0,6 s senza scrivere e solo in Italia). Usato in Condividi l'incontro, Evento,
  Posizione e località degli annunci (qui solo comuni).
- **Piazly AI**: chat fissata in cima all'elenco delle chat (come Meta AI su WhatsApp) e
  **Immagini IA** nella graffetta (anteprima, poi si manda come foto cifrata).
  - Server: nuova funzione Supabase `ia` → Cloudflare Workers AI. Testo:
    `@cf/meta/llama-3.1-8b-instruct-fast`; immagini: `@cf/black-forest-labs/flux-1-schnell`
    (cambiabili con i secret facoltativi `CLOUDFLARE_AI_TEXT_MODEL` / `CLOUDFLARE_AI_IMAGE_MODEL`).
  - Limiti per persona al giorno: 40 domande, 5 immagini (migrazione `0033_piazly_ai.sql`).
  - «Addestramento»: per ora sono **istruzioni** fisse (chi è Piazly AI, cosa fa l'app, regole di
    sicurezza) in `supabase/functions/ia/handler.ts`. Un vero addestramento (adattatore LoRA su
    testi dell'app) si può aggiungere dopo, se serve.
  - Avviso onesto nell'app: Piazly AI **non è cifrata** come le chat (la domanda va ai server per
    avere la risposta); la cronologia resta solo sul telefono, un file per account. Nei log della
    funzione solo esiti, mai testi o identificativi.

## Cosa deve fare il titolare (nessuna chiave in chat)

1. Su Cloudflare: creare un **token API** con permesso «Workers AI» e copiare l'**Account ID**.
2. Su Supabase → Edge Functions → Secrets: aggiungere `CLOUDFLARE_AI_ACCOUNT_ID` e
   `CLOUDFLARE_AI_API_TOKEN`.
3. Autorizzare: applicazione della migrazione 0033 sul database reale e pubblicazione della
   funzione `ia` (con `verify_jwt = false`, come `rubrica` e `chiamate`).

Senza questi passi l'app funziona lo stesso: Piazly AI risponde «non è ancora attiva».

Piano gratuito di Cloudflare Workers AI: 10.000 «Neurons» al giorno (si azzerano alle 00:00 UTC);
oltre serve il piano a pagamento Workers Paid.

## Test

- `test/fase4/rich_messages_test.dart`: codifica e controlli dei contenuti; sondaggio ed evento
  cifrati con voti tra due telefoni; graffetta con le nove scelte; contatto e posizione dallo
  schermo; evento con il luogo suggerito (comuni + Photon finto); risposta di Photon; Condividi
  l'incontro senza altri contatti e invio con altra app; Piazly AI in cima alle chat, risposta e
  limite; Immagini IA fino all'invio.
- `supabase/functions/ia/ia_test.ts`: token Firebase, istruzioni davanti, niente ruolo «system» dal
  telefono, limiti per tipo, richieste non valide senza consumare il limite, servizio giù.
- `supabase/tests/rls_test.py` IA1: limiti contati solo dal server, tipi sconosciuti rifiutati.
- Anteprime: chat_27 (sondaggio, evento, posizione, contatto), chat_28-29 (Piazly AI), chat_30
  (luoghi suggeriti).

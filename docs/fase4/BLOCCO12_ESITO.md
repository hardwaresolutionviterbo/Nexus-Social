# Fase 4 · Blocco 12 · Online e ultimo accesso — esito

Ramo `fase4/blocco12`, nato da `fase4/blocco11`. Richiesta del titolare del 19/11/2026.

## Cosa c'è
- Sotto il nome, nella chat a due: «online» (in verde) oppure «ultimo accesso oggi alle 18:40»,
  «ieri alle…», «il 12/11 alle…». Si aggiorna ogni 10 secondi mentre la chat è aperta.
- **Privacy → «Ultimo accesso e online»:** Tutti, I miei contatti (predefinito), Nessuno.
  È anche un passo del Controllo privacy (ora 9 passi).
- **Reciproco, come su WhatsApp:** chi sceglie «Nessuno» non vede nemmeno quello degli altri.
- Mai visibile tra persone bloccate.
- Con l'app aperta il telefono manda un segnale ogni 30 secondi; «online» vale 45 secondi.

## Controlli
- App: test della scritta, della scelta in Privacy e del Controllo privacy.
- Database: OL1–OL3 e la controprova `online_senza_reciprocita`, che deve far fallire OL2.
- Corretto anche un difetto trovato dai test: il Controllo privacy aveva il numero di passi
  scritto a mano e saltava l'ultima sezione; ora conta le sezioni da solo.
- **Server reale (19/11/2026, autorizzato):** migrazione 0030 applicata dal commit `9d12484`,
  con impronta verificata; nessuna differenza tra utenti anonimi e autenticati.

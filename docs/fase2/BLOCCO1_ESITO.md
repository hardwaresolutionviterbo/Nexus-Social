# Fase 2 · Blocco 1: esito della prova sul telefono

Data: 14/11/2026 · APK `nexus-social-0.1.0+15701-58d7de3-fase2-blocco1`.

## Esito: approvazione parziale del titolare

| Verifica | Esito |
|---|---|
| Nome «Piazly» sotto l'icona e nelle schermate (M-6) | ✅ |
| Schermata iniziale, scelta Privato/Azienda | ✅ |
| Data di nascita, blocco sotto i 14 anni, Azienda solo 18+ | ✅ |
| Termini e Privacy con «bozza non validata» (S7) | ✅ |
| Schermata del numero (+39) | ✅ |
| **Invio del codice con il numero di prova** | ⏸ **Punto aperto** |

## Punto aperto: accesso con telefono

- Configurazione del titolare completata in Firebase: provider Telefono attivo e due numeri di
  prova salvati (i codici restano solo nella console, non nel repository).
- All'invio del codice Firebase rifiuta la richiesta: il progetto è sul piano gratuito Spark e
  l'accesso con SMS richiede il piano **Blaze**, anche con i numeri di prova.
- È lo stesso ostacolo di S1 (prepagamento richiesto da Blaze). Decisione del titolare: si
  prosegue con gli altri blocchi e si riprova l'accesso appena Blaze sarà attivo.
- Il messaggio d'errore dell'app ora distingue i due casi («richiede il piano Blaze» con codice
  `billing-not-enabled`, oppure «non abilitato» con codice `operation-not-allowed`), così la
  prossima prova indica subito la causa.

## Conseguenza per i blocchi successivi

I Blocchi 2-5 richiedono un utente che ha fatto l'accesso: vengono sviluppati e verificati con i
test automatici (emulatori e database temporaneo). La prova sul telefono si farà quando Blaze sarà
attivo, insieme alla prova del Blocco 1.

# Fase 4 · Blocco 4 — Gruppi

Ramo: `fase4/blocco4`. Migrazione: `supabase/migrations/0021_chat_gruppi.sql` (applicata al database reale il 18/11/2026 con l'autorizzazione del titolare; file verificato con SHA-256 contro il commit 30762f7).

## Cosa c'è
- **Nuovo gruppo** (Chat → Nuova chat → Nuovo gruppo): nome e persone dalla rubrica, fino a 256.
- **Inviti**: chi ti ha in rubrica entra subito; gli altri ricevono un invito tra le Richieste («Invito al gruppo …»: Entra / Rifiuta). Mai il numero di telefono.
- **Codice d'invito** (10 caratteri): lo creano gli amministratori, si condivide, si rinnova o si disattiva; si usa da Nuova chat → «Entra con un codice», con l'anteprima del gruppo.
- **Info gruppo**: foto (privata, la vedono solo i membri), nome e descrizione, membri con il ruolo, «in attesa di entrare», invitati; per gli amministratori: aggiungi persone, nomina/togli amministratore, rimuovi, codice; per tutti: esci. Il gruppo non resta mai senza amministratori.
- **Nella conversazione**: nome colorato di chi scrive, avvisi del gruppo («Anna ha aggiunto Bruno»), reazioni con il conteggio, spunte blu quando tutti hanno letto.
- **Cifratura MLS di gruppo**: il server decide chi fa parte del gruppo; il telefono di un amministratore tiene allineato il gruppo cifrato da solo (aggiunge chi entra, toglie chi esce, riaggiunge chi cambia telefono). Chi entra non legge i messaggi precedenti; chi esce non riceve più nulla. Allegati e foto valgono anche nei gruppi.

## Test
- Database temporaneo: casi T1–T9 (creazione e inviti, solo amministratori, generazioni, messaggi solo a chi è dentro e cancellati quando tutti li hanno, accettazione senza messaggi precedenti, uscita e rientro con il codice, amministratori, telefono nuovo, foto e allegati) e la controprova `gruppo_senza_admin`. Esito: 175 su 175.
- App: cifratura MLS vera con 5 telefoni (creazione, invito accettato, uscita, telefono nuovo, ingresso con codice, permessi); schermate di nuovo gruppo, nomi nei fumetti, info, codice, invito con «Entra». Esito: 281 test superati.

## Limiti noti
- Il gruppo cifrato si aggiorna quando un amministratore ha l'app aperta (le notifiche arrivano nel Blocco 5).
- Non c'è ancora il QR code né il link cliccabile: si usa il codice.

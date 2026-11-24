# Fase 7 · Blocco 1 — Accesso riservato, segnalazioni, utenti e ban

Dal piano (Fase 7): accesso riservato all'account amministratore, con 2FA e biometria; coda delle
segnalazioni con motivo (ignora, elimina l'annuncio, avvisa o banna); utenti con profilo, storico,
ban temporaneo o definitivo e sblocco.

## Accesso riservato

- Si apre da **Profilo › Gestionale**, una scheda che vedono solo gli amministratori.
- Servono tre cose: essere in `admin_users`, avere la **verifica in due passaggi (PIN)** attiva e,
  se il telefono la ha, **impronta o volto** a ogni apertura.
- Il server ricontrolla ogni richiesta: senza PIN o da un telefono non verificato non risponde.

## Segnalazioni

- Una **coda unica** per annunci (Mappa e Vendita), commenti e chat. Ogni voce mostra il contenuto,
  i motivi, il numero di segnalazioni, le note di chi segnala e l'autore. Non mostra mai chi ha
  segnalato.
- Le segnalazioni dello stesso annuncio o commento sono raccolte in una sola voce.
- Per le **chat** si vedono solo i messaggi che chi segnala ha scelto di allegare. Il resto è
  cifrato, quindi la chat non si può «eliminare».
- Le azioni sono **Ignora**, **Elimina**, **Avvisa** e **Banna**. Con avviso e ban si può togliere
  anche il contenuto. La persona riceve un avviso con il testo scritto dall'amministratore. Ci
  sono testi pronti: Spam, Truffa, Contenuti, Molestie.
- La scheda «Gestite» mostra le segnalazioni chiuse negli ultimi 30 giorni.

## Utenti

- Si cercano per **nome utente o nome pubblico**. Il numero di telefono, il nome completo e la data
  di nascita non compaiono mai.
- La scheda dell'utente mostra il tipo di account, la data di iscrizione, gli annunci attivi, i
  commenti, le segnalazioni aperte e totali, e lo **storico** delle azioni con data, autore e motivo.
- Le azioni sono **Avvisa**, **Banna** (1, 7 o 30 giorni, oppure definitivo, sempre con un motivo)
  e **Sblocca**. Un amministratore non si può bannare.

## Per chi viene bannato o avvisato

- Chi è bannato vede la schermata **«Account sospeso»** con il motivo e la scadenza, e può uscire
  dall'account.
- Il server impedisce di pubblicare annunci, commenti, stati, promozioni e recensioni (con controlli
  sulle tabelle), oltre ai blocchi che c'erano già su chat, Vendita e proposte.
- Gli avvisi compaiono una volta, all'apertura dell'app.

Regole iniziali dei ban (24/11/2026): 1, 7 o 30 giorni oppure definitivo, sempre con un motivo
visibile. Il titolare può cambiarle.

## Server

Migrazione `0038_gestionale.sql`:
- tabella `moderation_notices` (avvisi, accessibile solo tramite le funzioni) e
  `private.moderation_log` (storico, solo amministratori);
- trigger di blocco per chi è bannato;
- funzioni `admin_access`, `admin_reports`, `admin_report_resolve`, `admin_users_search`,
  `admin_user_detail`, `admin_ban_user`, `admin_unban_user`, `admin_warn_user`, `my_moderation`,
  `moderation_notices_read`.

## Test

- `test/fase7/admin_test.dart`:
  - accesso negato a chi non è amministratore, senza PIN e con impronta sbagliata;
  - Elimina, ban con durata e rimozione del contenuto, avviso su una chat (senza «Elimina»);
  - ricerca, ban, sblocco e storico degli utenti;
  - «Account sospeso», avvisi mostrati una volta.
- `test/regression/f10_admin_test.dart` è aggiornato alla Fase 7. La regola della Fase 1 era
  «l'anteprima del gestionale non si apre da nessuna parte». Ora il gestionale si apre solo dalla
  sezione amministratori del Profilo, e chi non è amministratore vede solo «Area riservata», senza
  pulsanti.
- `supabase/tests/rls_test.py` GS1–GS5. Controprove `gestionale_senza_pin` (deve far fallire GS1)
  e `ban_ignorato` (deve far fallire GS4).
- Anteprime `gestionale_1…8`.

# Fase 4 · Blocco 5 · Notifiche — esito

Ramo `fase4/blocco5`. Stato: **server attivo (autorizzato il 18/11/2026), da provare sul telefono**.

## Cosa fa
- Arrivano le notifiche anche con l'app chiusa:
  - **messaggi** delle chat a due, dei gruppi e delle richieste;
  - **commenti**;
  - **scambi e vendite**.
- **Mi piace:** non arriva mai una notifica.
- **Cosa c'è scritto:** mai il testo dei messaggi (sono cifrati), solo «Nome · Nuovo messaggio».
  - Senza «Mostra chi scrive»: «Piazly · Hai un nuovo messaggio».
  - Più messaggi della stessa chat diventano una notifica sola («3 nuovi messaggi»).
- **Profilo → Notifiche:**
  - interruttori per messaggi, anteprima, commenti e scambi;
  - «Non disturbare» con orari scelti (22:00–07:00 se non si cambiano).
- **«Silenzia»:** dalla campanella in alto nella chat (8 ore, 1 settimana, sempre, riattiva).
  Nella lista compare la campanella barrata.
- **Notifica toccata:** si apre la chat giusta.
- **App aperta:** niente notifica, la chat si aggiorna subito.

## Come funziona
1. Il telefono si registra sul server con l'identificativo di installazione di Firebase (FID),
   tramite `push_register`. Un telefono appartiene a un solo account e ogni account ha al
   massimo 10 telefoni.
2. Quando arriva un messaggio o un commento, il database decide se notificare:
   - controlla preferenze, «Silenzia», «Non disturbare» e blocchi;
   - mette la notifica in coda (`private.push_queue`);
   - chiama la funzione `notifiche` con un segreto condiviso.
3. La funzione `notifiche` (`supabase/functions/notifiche`):
   - prende la coda;
   - manda le notifiche con FCM HTTP v1, gratuito e senza Blaze;
   - toglie i telefoni non più registrati.
4. La chiave di servizio Firebase è il secret `FIREBASE_SERVICE_ACCOUNT` di Supabase:
   - l'ha creata il titolare;
   - non è nel repository e non è mai passata in chat.

## Controlli
- App: 287 test superati (analisi senza avvisi).
- Database: 181/181 test di sicurezza, nuovi U1–U6, con la controprova `notifiche_per_i_like`.
- Funzione: test Deno (firma, messaggio, risposte di FCM, segreto, coda).
- Server reale (18/11/2026):
  - migrazione 0022 applicata dal file del commit `745eb05`, con impronta verificata;
  - permessi di anon allineati;
  - funzione pubblicata;
  - chiamata di prova a coda vuota: 200, accesso a Firebase riuscito.

## Da provare sul telefono
1. Installare l'APK `…-745eb05-fase4-blocco5` sui due telefoni e consentire le notifiche.
2. Chiudere l'app su un telefono e scrivergli dall'altro: la notifica deve arrivare.
3. Toccare la notifica: si deve aprire la chat giusta.
4. Provare «Silenzia» e «Mostra chi scrive».

Il titolare ha segnalato che ci sono notifiche da aggiungere o cambiare: le indicherà prima
dell'approvazione del blocco.

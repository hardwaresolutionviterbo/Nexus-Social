# Fase 4 · Blocco 9 · Chat e chiamate in tempo reale — esito

Ramo `fase4/blocco9`, nato da `fase4/blocco8`. Richiesta del titolare (18/11/2026):
messaggi e chiamate ci mettevano qualche secondo ad arrivare.

## Prima e dopo
- **Prima:** l'app chiedeva al server se c'era qualcosa di nuovo ogni 3 secondi con la chat
  aperta, ogni 10 secondi negli altri casi e ogni secondo durante una chiamata. Un messaggio
  poteva quindi arrivare con fino a 10 secondi di ritardo.
- **Adesso:** appena arriva qualcosa, il database manda un «tocco» al telefono di chi deve
  riceverlo, sul suo canale privato di Supabase Realtime. Il telefono si sincronizza subito,
  in meno di un secondo. Il tocco arriva per:
  - un messaggio;
  - un passaggio di una chiamata;
  - le spunte di consegnato e letto;
  - una richiesta accettata.
- I controlli periodici restano di riserva e diventano più radi quando il tempo reale è
  collegato.

## Sicurezza
- Il tocco è vuoto: contiene solo un identificativo casuale del tocco stesso, mai chi
  scrive, la chat o il testo.
- **Canale `u:<uid>`:** lo può ascoltare solo il proprietario, con un token Firebase valido.
  Nessuno ci scrive dall'app: i tocchi li manda solo il database.
- **Migrazione `0026_chat_in_tempo_reale.sql`:**
  - trigger su `chat_messages` (nuovo messaggio) e su `chat_members` (spunte, stato);
  - regola di lettura su `realtime.messages`;
  - se il tempo reale non risponde, i messaggi arrivano comunque, con il controllo periodico.

## Controlli
- App: 312 test superati (messaggio e chiamata arrivano senza aggiornare a mano; con il tempo
  reale spento si torna ai controlli periodici).
- Database: 196/196, con i nuovi RT1–RT3 e la controprova `canale_altrui_leggibile`, che deve
  far fallire RT3.
- I test del database ora avviano anche il servizio Realtime.

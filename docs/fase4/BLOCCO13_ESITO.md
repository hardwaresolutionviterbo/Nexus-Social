# Fase 4 · Blocco 13 · Stati — esito

Ramo `fase4/blocco13`, nato da `fase4/blocco12`. Richiesta del titolare del 19/11/2026.

## Cosa c'è
- **Dove:** in alto nella Chat c'è «Chat | Stati | Chiamate». Su «Stati» c'è il numero
  delle persone con stati nuovi.
- **Il mio stato:**
  - testo su sfondo colorato (8 colori, matita);
  - foto (scattata o dalla galleria) o video fino a 30 secondi, con didascalia (fotocamera);
  - dura 24 ore, poi sparisce da solo; si può eliminare prima;
  - «Visto da»: chi l'ha guardato e quando. Lo vede solo chi l'ha pubblicato.
- **Chi vede i miei stati:**
  - «I miei contatti»;
  - «I miei contatti tranne…»;
  - «Solo con…».
  - La scelta resta sul telefono e vale per i prossimi stati.
  - In ogni caso li vede solo chi hai in rubrica, mai chi hai bloccato.
- **Guardare:**
  - tocco a destra per andare avanti, a sinistra per tornare indietro, tieni premuto per fermare;
  - dopo l'ultimo si chiude; quelli visti passano in «Già visti».
- **Detto chiaramente nell'app:** gli stati sono protetti dalle regole del server, ma non sono
  cifrati end-to-end come i messaggi.

## Server (migrazione 0031)
- Tabelle degli stati, del pubblico scelto e delle visualizzazioni.
- Cartella privata `stati` per foto e video:
  - JPEG o MP4, al massimo 16 MB;
  - ognuno carica solo nella propria cartella;
  - il file lo apre solo chi può vedere lo stato.
- Al massimo 30 stati al giorno. All'avvio l'app cancella i propri stati scaduti e i loro file.

## Controlli
- App: test della pubblicazione, del pubblico, di «Visto da», di eliminazione e scadenza, e
  delle schermate.
- Database: ST1–ST4 e la controprova `stati_per_tutti`, che deve far fallire ST1.
- **Server reale (19/11/2026, autorizzato):** migrazione 0031 applicata dal commit `9d12484`,
  con impronta verificata; nessuna differenza tra utenti anonimi e autenticati.

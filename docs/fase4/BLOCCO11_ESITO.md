# Fase 4 · Blocco 11 · Sezione Chiamate e nomi della rubrica — esito

Ramo `fase4/blocco11`, nato da `main` dopo la Fase 4. Richieste del titolare del 19/11/2026.

## 1 · Sezione «Chiamate»
- **Dove:** in alto nella Chat c'è «Chat | Chiamate», con il numero delle chiamate perse nuove.
- **Elenco** (dalla più recente):
  - persona o gruppo;
  - in uscita, in arrivo, persa (in rosso) o senza risposta;
  - quando («Oggi, 18:05», «Ieri, 21:40») e quanto è durata;
  - icona per richiamare, vocale o video come la chiamata originale.
- Toccando una riga si apre la chat.
- Il registro resta solo sul telefono (file `chiamate.json` nella cartella privata
  dell'account), come su WhatsApp. Ne tiene 200.

## 2 · Nomi come nella rubrica
- **Come su WhatsApp:** nelle chat, nei contatti, nei nomi dei gruppi e nelle chiamate compare
  il nome che hai scritto nella rubrica del telefono. Se la persona non è in rubrica, resta il
  nome scelto su Piazly.
- **Come funziona:**
  - durante la sincronizzazione protetta della rubrica (Fase 2) il telefono chiede al server
    quale delle sue impronte corrisponde a quale persona già riconosciuta (nuova funzione
    `match_contact_tags`, migrazione 0029);
  - il telefono conserva «persona → numero» nell'archivio sicuro e legge il nome dalla rubrica
    al momento: se rinomini un contatto, il nome cambia anche in Piazly;
  - i nomi non vanno mai al server.
- **La prima volta dopo l'aggiornamento** parte da sola una sincronizzazione della rubrica (una
  delle 3 al giorno). Con la revoca della rubrica i dati si cancellano dal telefono.

## Controlli
- App: 324 test superati (nomi della rubrica, registro delle chiamate, file salvato, sezione
  con persa e richiama).
- Database: CN1–CN2 e la controprova `impronte_di_tutti`, che deve far fallire CN1.
- **Server reale (19/11/2026, autorizzato):** migrazione 0029 applicata dal commit `03e5d5f`,
  con impronta verificata.

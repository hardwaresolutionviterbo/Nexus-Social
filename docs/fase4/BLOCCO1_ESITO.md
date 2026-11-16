# Fase 4 · Blocco 1 — Chat a due di solo testo

Ramo: `fase4/blocco1`. Migrazione: `supabase/migrations/0019_chat_base.sql` (NON applicata al database reale: serve l'autorizzazione del titolare).

## Cosa c'è
- Chat a due cifrata end-to-end con MLS (decisione C1): le chiavi private restano sul telefono, nell'archivio sicuro; il database delle chiavi è cifrato.
- Spunte: orologio (in invio), una (inviato), due grigie (consegnato), due blu (letto); rossa con «tocca per riprovare» se non parte.
- Richieste di messaggio: chi non ti ha in rubrica scrive come «richiesta». Accetta o Rifiuta; finché non accetti chi scrive non vede consegnato/letto; se rifiuti non ricevi altro e chi scrive non lo sa. Al massimo 20 nuove richieste al giorno e 10 messaggi per richiesta in attesa.
- Mai il numero di telefono in chat: nome pubblico, @nome utente e foto.
- «Nuova chat» dai contatti della rubrica iscritti a Piazly; «Contatta» sugli annunci della Mappa e di Scambia & Vendi apre la chat con l'autore.
- Numero dei messaggi non letti sull'icona Chat.
- Telefono nuovo: la chat si riapre da sola al primo messaggio; i messaggi vecchi non si recuperano finché non c'è il backup (Blocco 5).

## Test
- Database temporaneo: casi R1–R10 (identità, pacchetti chiave, una chat per coppia, generazioni, solo base64 sul server, spunte e cancellazione dopo la consegna, richieste, rifiuto, blocco, telefono nuovo) e tre controprove (`chat_messaggi_leggibili`, `chat_estranei_nella_chat`, `chat_limiti_spenti`). Esito: 161 su 161.
- App: cifratura MLS vera tra «telefoni» in memoria (5 scenari, compreso il cambio di telefono e la scrittura simultanea), 7 test delle schermate. Esito: 272 test superati.

## Limiti di questo blocco
- I messaggi arrivano con l'app aperta (controllo ogni 3–10 secondi); le notifiche con l'app chiusa sono nel Blocco 5.
- Solo testo; foto, vocali e documenti nel Blocco 3; risposte, inoltri e reazioni nel Blocco 2.

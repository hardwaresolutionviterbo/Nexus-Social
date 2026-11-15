# Proposta · Verifica del numero con un centralino nostro («SMS al contrario»)

Stato: **proposta accolta come direzione dal titolare il 15/11/2026** («per me va bene»), da
progettare nei dettagli e approvare prima di scrivere codice. Non modifica nulla di quanto già
approvato finché non viene approvata la versione definitiva.

## 1. Perché

Il titolare preferisce un'infrastruttura propria per la verifica del numero, senza dipendere da
servizi esterni a pagamento (SMS di Firebase con Blaze, Telegram Gateway e simili).

Vincoli tecnici che restano veri con qualsiasi soluzione:
- un numero si dimostra solo passando dalla rete dell'operatore: serve almeno **una SIM nostra**;
- l'app non può leggere in modo affidabile il proprio numero (impossibile su iPhone, spesso vuoto
  su Android) e ciò che l'app «dichiara» può essere falsificato: non è una verifica;
- una notifica con un codice dentro l'app dimostra solo che l'app è installata, non il numero.

## 2. Come funziona

1. Nell'app la persona scrive il proprio numero (Android può proporre i numeri della SIM come
   suggerimento: solo comodità).
2. Il server crea una **richiesta di verifica**: codice casuale monouso (es. `PIAZLY 482913`),
   numero dichiarato, scadenza 10 minuti, legata a quel telefono.
3. L'app apre l'app SMS del telefono già compilata: destinatario il **numero del centralino**,
   testo il codice. La persona tocca solo «Invia» (nessun permesso speciale; Android e iPhone).
4. Il **centralino** — un telefono Android con una SIM nostra, sempre acceso e connesso, con una
   piccola app nostra — riceve l'SMS e lo inoltra al server in modo autenticato (chiave del
   centralino, collegamento cifrato), poi cancella l'SMS dal telefono.
5. Il server controlla: mittente = numero dichiarato, codice giusto e non scaduto, tentativi nei
   limiti. Se tutto torna, segna il numero come verificato e rilascia l'accesso all'app.
6. L'app, che aspetta la conferma, entra.

## 3. Sicurezza

- **Mittente falsificato** (servizi che alterano il mittente degli SMS): rischio ridotto, non
  nullo. Contromisure: solo numeri mobili italiani all'inizio; codice legato alla richiesta e al
  telefono; scadenza breve; limiti per numero, per telefono e per ora; avviso e blocco di
  sequenze sospette; il titolare può bloccare un numero.
- **Nessun dato inutile**: il centralino non conserva gli SMS; il server conserva solo l'esito e
  l'impronta (hash) del numero, come già per la rubrica (P1, rubrica OPRF della Fase 2).
- **Chiave del centralino**: creata dal titolare e salvata come segreto del server; mai in chat,
  mai nel repository pubblico.
- La rubrica (Fase 2, Blocco 5) oggi lega il numero all'account tramite Firebase: andrà legata
  alla nuova verifica (stesso livello di garanzia).

## 4. Affidabilità

- Se il centralino è spento o senza rete nessuno si registra: un **secondo centralino** di
  riserva (altra SIM, idealmente altro operatore) quando l'app cresce; il server segnala al
  titolare se un centralino non risponde.
- Ricevere SMS è gratuito e non rischia il blocco della SIM (a differenza dell'invio automatico di
  codici in massa da una SIM consumer).
- Costi: SIM con offerta base e un telefono Android usato; nessun costo a messaggio.

## 5. Cosa cambia rispetto a oggi (da decidere)

Oggi l'account nasce con l'SMS di Firebase (Fase 1-2). Con il centralino serve un **nostro
server che rilasci l'accesso**. Opzioni da studiare nella progettazione:

| Opzione | Come | Note |
|---|---|---|
| A | Il server, dopo la verifica, rilascia un accesso Firebase «personalizzato» | Firebase resta il sistema di accesso; servono una funzione del server e la chiave di servizio Firebase (impostata dal titolare) |
| B | L'accesso passa a Supabase | Meno servizi; da rivedere le regole già scritte e i test |

Va scelto dove gira il server (le funzioni di Supabase hanno un piano gratuito; le funzioni di
Firebase richiedono Blaze) e come trattare chi ha già un account.

## 6. Lavoro previsto (dopo l'approvazione del progetto)

1. App «Centralino Piazly» per il telefono Android (ricezione SMS, inoltro autenticato, stato).
2. Funzioni del server: richiesta di verifica, ricezione dal centralino, esito, limiti,
   accesso (opzione A o B).
3. Nell'app Piazly: nuova schermata di verifica con «Invia SMS di verifica» e attesa dell'esito.
4. Test automatici (codice sbagliato, scaduto, mittente diverso, troppi tentativi, centralino
   non autenticato) e controprove come per le fasi precedenti.

## 7. Azioni del titolare (quando si parte)

- Approvare il progetto e scegliere A o B.
- Procurare SIM e telefono per il centralino; creare la chiave del centralino come segreto.

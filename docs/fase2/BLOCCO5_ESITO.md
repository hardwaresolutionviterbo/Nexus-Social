# Fase 2 · Blocco 5: rubrica · esito dello sviluppo

Ramo `fase2/blocco5` (parte dal Blocco 4). Stato: **in attesa della verifica del titolare**.
Strada scelta dal titolare: **S1, Cloud Functions** (si attivano con Blaze).

## Cosa è stato fatto

| Requisito | Come |
|---|---|
| R2.6, P13 consenso | Spiegazione prima del permesso del sistema («Accetto e continua» / «Non ora»); consenso registrato con la data, visibile in Privacy → Autorizzazioni con «Revoca» |
| S6 protezione | OPRF(P-256, SHA-256) secondo RFC 9497: il telefono «acceca» ogni numero, la Cloud Function applica la chiave segreta senza vederlo, il telefono ottiene un codice. Verificato con i vettori ufficiali RFC 9497 e RFC 9380 sia sul telefono sia sul server |
| S6 limiti | Al massimo 2.000 numeri e 3 sincronizzazioni al giorno, controllati sia dalla Cloud Function sia da Supabase |
| R2.11 riconoscimento | Solo cellulari italiani (L3), senza doppioni; elenco «Contatti su Piazly» con nome abbreviato e @username |
| P5, P6 numero | Visibile solo a chi lo ha in rubrica ed è riconosciuto, e solo se l'utente sceglie «Contatti riconosciuti»; mai agli sconosciuti |
| P7 scadenza e revoca | «Revoca e cancella» cancella subito i dati derivati; senza nuova sincronizzazione scadono dopo 30 giorni |
| Aggiornamento automatico (richiesta del titolare) | Come WhatsApp: con il consenso attivo la rubrica si aggiorna da sola all'apertura, al ritorno nell'app e quando si salva un nuovo contatto; subito se la rubrica è cambiata (impronta locale senza numeri), altrimenti al massimo una volta al giorno. «Sincronizza ora» resta per aggiornare a mano. I 30 giorni scattano solo per chi smette di usare l'app |
| P8 trovarmi | Si accende con la propria attivazione della rubrica, si può spegnere; spento, nessuno ti riconosce |
| P12 blocchi | Chi è bloccato (in un verso o nell'altro) non compare tra i contatti |
| Proprio numero | Entra nell'indice solo con il codice calcolato e firmato dalla Cloud Function, e solo se uguale al numero dell'accesso |

## Test automatici

- Server OPRF: vettori ufficiali RFC 9497 A.3.1 superati; Cloud Functions sugli emulatori (valutazione,
  limiti, accessi non validi, codice del proprio numero e firma).
- Database temporaneo: **74 casi su 74** (10 nuovi, I1-I10) e **8 controprove**, una nuova (I4: numero
  esposto).
- App: **130 test superati**, compresi i vettori RFC 9380 e RFC 9497 sul telefono.

## Da fare all'attivazione (con Blaze, solo con autorizzazione del titolare)

1. Pubblicare le Cloud Functions `rubricaValuta` e `rubricaMioNumero`.
2. Creare due segreti in Firebase (`OPRF_KEY`: 64 cifre esadecimali casuali; `RUBRICA_ATTEST_KEY`:
   chiave di firma casuale). Mai nel repository, mai in chat.
3. Applicare la migrazione 0006 e inserire la stessa chiave di firma in `private.settings`
   (`rubrica_attest_key`) dall'editor SQL di Supabase.
4. Rifare la build iPhone su Codemagic per verificare il nuovo pacchetto dei contatti.

## Modifiche tecniche

- Android: permesso `READ_CONTACTS` (chiesto solo dopo il consenso). iPhone: `NSContactsUsageDescription`.
- Nuove dipendenze: app `crypto`, `flutter_contacts`; Cloud Functions `@noble/curves` 1.9.7.

## Limite da conoscere

Il limite di 3 aggiornamenti al giorno (S6) vale anche per quelli automatici: chi salva nuovi
contatti in più di 3 momenti diversi nella stessa giornata li vede riconosciuti il giorno dopo.

# Fase 2 · Blocco 3: privacy e blocchi · esito dello sviluppo

Ramo `fase2/blocco3` (parte dal Blocco 2). Stato: **in attesa della verifica del titolare**.

## Cosa è stato fatto

| Requisito | Come |
|---|---|
| R2.8 pagina Privacy | 7 sezioni con la scelta attuale sotto il titolo; collegamenti a Informativa, Termini e Regole (bozze non validate) |
| P3 profilo | Interruttori bio e social, salvati subito; anteprima «Come ti vedono gli altri» |
| P5, P6 numero | «Contatti riconosciuti dalla rubrica» (partenza) o «Nessuno»; nessuna opzione per gli sconosciuti; il server rifiuta qualsiasi altro valore |
| P7, P8 rubrica | Interruttori spenti finché non arriva la rubrica (Blocco 5), con la spiegazione dei 30 giorni |
| 3.4, 3.5 posizione e GPS | Testi fissi richiesti dal piano; le funzioni arrivano con la Mappa (Fase 3) |
| R2.7, P12 blocchi | «Blocca» dal profilo di un altro utente con conferma; elenco dei bloccati con «Sblocca». Il server nasconde profilo e foto di chi ti ha bloccato, anche con letture dirette, e non avvisa il bloccato. Chat, chiamate, commenti e reazioni useranno la stessa regola (Fasi 4-5) |
| 3.7, P13 autorizzazioni | Permessi del telefono usati oggi e sezione dei consensi (vuota finché non ce ne sono) |
| R2.9, P14, P15 Controllo privacy | 8 passi con «Avanti», «Indietro», «Esci»; riepilogo con «Modifica»; proposto subito dopo la creazione del profilo, con «Salta»; ogni scelta si salva subito e, se il server non la accetta, torna com'era con un messaggio |

## Correzione al Blocco 2 (P4)

La ragione sociale era pubblica: contrastava con **P4** (dati aziendali protetti fino alla Fase 6).
Ora è privata come la partita IVA. La migrazione 0003 non era ancora applicata al database reale.

## Test automatici

- Database temporaneo: **54 casi su 54** (8 nuovi, G1-G8) e **6 controprove**, una nuova (G4: blocco
  ignorato).
- App: **100 test superati**.
- Il test di regressione F10 ammetteva navigazione solo nel Profilo: ora ha un **elenco chiuso** dei
  file che navigano (Profilo, profilo pubblico, Privacy), rivisto; il controllo che l'anteprima
  admin non sia raggiungibile resta invariato.

## Cosa resta

- Prova sul telefono: con Blaze, insieme ai Blocchi 1 e 2.
- Migrazioni 0003 e 0004 sul database reale: solo con autorizzazione del titolare.
- «Scarica i miei dati» ed «Elimina account» (sezione 3.8): erano una **proposta non approvata**;
  da decidere (Fase 2 o al più tardi Fase 9).

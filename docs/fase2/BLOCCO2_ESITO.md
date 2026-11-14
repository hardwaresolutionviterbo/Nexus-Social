# Fase 2 · Blocco 2: profilo · esito dello sviluppo

Ramo `fase2/blocco2` · APK `nexus-social-0.1.0+16201-00e32cd-fase2-blocco2`.
Stato: **approvato dal titolare il 14/11/2026** per la parte provata con i test automatici;
prova sul telefono quando Blaze sarà attivo (come il Blocco 1).

## Cosa è stato fatto

| Requisito | Come |
|---|---|
| R2.3 @username univoco | Minuscole, numeri, punto e trattino basso (3-24); unico anche con maiuscole diverse; nomi che imitano l'app o lo staff non disponibili |
| R2.3 nome abbreviato | In pubblico solo «Carlo C.»; il nome completo resta privato |
| R2.4, S5 foto | Scelta dalla galleria, ritagliata quadrata; foto 512 px e miniatura 128 px in JPEG, senza metadati (posizione GPS); Supabase Storage privato, visibile solo agli utenti autenticati |
| R2.4, P3 bio e social | Bio fino a 300 caratteri; social solo come nome utente su 6 reti (niente link liberi); interruttori «Mostra nel profilo pubblico» accesi di partenza, applicati dal server |
| R2.10 profilo pubblico | Nome abbreviato, @username, foto, bio e social secondo gli interruttori; anteprima «Come ti vedono gli altri» nel Profilo |
| S4 Azienda | Ragione sociale e partita IVA (con cifra di controllo) private, come chiede P4 fino alla Fase 6; stato «in verifica»; il badge resta all'admin (Fase 7) |
| D1, M2, M6 | Età minima 14 anni e Azienda solo 18+ ricontrollate dal server; la data di nascita non si cambia dopo la creazione |

## Test automatici

- Database temporaneo: **46 casi su 46** (8 nuovi, F1-F8) e **5 controprove**, 2 nuove (F1 età, F3 bio nascosta).
- App: **89 test superati** (nuovi: regole del profilo, foto, creazione e modifica, profilo pubblico, ingresso dopo l'accesso).

## Cosa non si può ancora provare sul telefono

- Servono l'accesso con telefono e il collegamento al server, entrambi in attesa di **Blaze**
  (S1, punto aperto del Blocco 1). Fino ad allora l'APK si comporta come prima: Profilo con
  «Accesso effettuato» e nessuna schermata nuova.
- La **migrazione 0003** è stata provata solo sul database temporaneo. Sul database reale va
  applicata **solo con l'autorizzazione del titolare**, quando servirà.
- La **copia pubblica del profilo su Firestore** (per le chat) richiede la parte lato server
  (S1): si farà insieme alla ripresa di S1.

## Scelte di dettaglio (confermate dal titolare il 14/11/2026)

1. ~~La **ragione sociale** dell'Azienda compare nel profilo pubblico.~~ **Corretta il 14/11/2026:**
   contrastava con la decisione **P4** della Fase 0 (ragione sociale e partita IVA protette fino
   alla Fase 6). Ora la ragione sociale è privata; renderla pubblica richiede una modifica a P4.
2. **Nomi utente riservati** (admin, piazly…, assistenza, staff…) per evitare falsi account ufficiali.
3. **Social come nome utente** su Instagram, TikTok, Facebook, X, YouTube, LinkedIn: niente link
   liberi, per evitare link ingannevoli.

Richiesta del titolare alla conferma: **toccando un social nel profilo si apre direttamente
quel profilo** (app del social se installata, altrimenti il browser). Aggiunto con
`url_launcher` e coperto da test.

# Fase 1 · Checklist finale (passaggio 1.10)

Stato al 14 novembre 2026:
- **Fase 1 completata**: tutti i passaggi 1.1-1.10 sono fatti;
- Blocco 3 approvato dal titolare;
- **`main` portato a `7bfc835`** su autorizzazione del titolare, con un avanzamento diretto;
- **lo schema Supabase 0002 non è applicato al database reale**: anche questo richiede
  l'autorizzazione esplicita.

Rami (ognuno contiene il precedente):

| Ramo | Contenuto | Approvazione |
|---|---|---|
| `fase1/blocco1` | 1.1 documentazione, 1.2 APK identificabile | Approvato (14/11/2026) |
| `fase1/blocco2` | 1.3 test di non regressione, 1.4 barra A1 e apertura su Chat, 1.5 grafica | Approvato (14/11/2026) |
| `fase1/blocco3` | 1.6 servizi verificati dai log, 1.7 schema 0002 e test Supabase, 1.8 regole Firestore, 1.9 Codemagic solo iPhone, 1.10 questa checklist | Approvato (14/11/2026); portato su `main` |

## 1. Requisiti del PDF (Fase 1)

| Requisito | Esito | Prova |
|---|---|---|
| Progetto Flutter unico per Android e iPhone su GitHub | ✅ | Repository; build Android su GitHub Actions; build iOS configurata su Codemagic (non collegato) |
| Cartelle: account, chat, mappa, annunci, vendita, admin | ✅ | `docs/fase1/STRUTTURA_CARTELLE.md` |
| Firebase collegato (login, chat, notifiche) | ✅ | Build: «Verifica Firebase nell'APK»; telefono del titolare: «Collegato» e registrazione FCM «registrata» |
| Supabase collegato (annunci, distanza, gestionale) | ✅ | Build: «Verifica connessione Supabase» HTTP 200; telefono: «Collegato» (lettura reale dal server) |
| Codemagic per ottenere l'app | ✅ con modifica approvata (F11) | Android da GitHub Actions; `codemagic.yaml` solo iPhone, avvio manuale |
| Tema grafico e modalità scura | ✅ | Blocco 2 approvato; test F3 e A1 in chiaro e scuro |
| Barra in basso con campanella | ✅ con modifica approvata (A1) | Chat, Mappa, Scambia (centrale arancione), Vendita, Profilo; apertura su Chat; test A1 e F2 |
| Regole di sicurezza dei database fin da subito | ✅ | Firestore: 89 test sull'emulatore. Supabase: 38 casi su database temporaneo, con controprova |
| Dati pubblici separati dai privati | ✅ nello schema proposto | Supabase 0002: `profile_private` (nome completo, data di nascita) separata da `profiles`. Firestore: copia pubblica con soli campi ammessi |
| «L'app si installa, mostra la barra con le schermate vuote e i servizi collegati» | ✅ | Prove del titolare sul telefono (Blocchi 1 e 2) |

## 2. Regole del piano

| Regola | Esito | Prova |
|---|---|---|
| R1 · APK con versione, build, commit e ramo | ✅ | Nome del file, riepilogo della build e riga Versione. Riesecuzione reale: 13501 → 13502 |
| R2 · Restyling senza perdite | ✅ | Test F1-F11 verdi prima e dopo la grafica |
| R3 · Test RLS Supabase | ✅ | `docs/fase1/TEST_SUPABASE_RLS.md`: casi A, B, C, D, D2, E (38) superati. Controprova: tre difetti introdotti apposta vengono rilevati (B1, C4, D2.1) |
| F8 · Test isolati da Firebase reale | ✅ | Simulazione in memoria, emulatore `demo-nexus-social`, rete vietata nei test, nessuna chiave nei job di test |
| F10 · Nessun accesso admin per altre strade | ✅ | App: test F10 e controlli sull'APK (nessun deep link verso l'app, nessuna chiave privilegiata). Server: casi E1-E8 |
| Nessuna azione sui servizi reali senza autorizzazione | ✅ | Nessuna migrazione, pubblicazione, collegamento o spesa |

## 3. Passaggi

| N. | Esito | Note |
|---|---|---|
| 1.1 | ✅ | README, documento privacy allineato, modifiche al piano, cartelle |
| 1.2 | ✅ | Identificativi R1; build anche dai rami `fase1/...` |
| 1.3 | ✅ | F1-F11; aggiunta F11 (raggio della Mappa), funzione esistente non elencata in origine |
| 1.4 | ✅ | Barra A1, apertura su Chat |
| 1.5 | ✅ | Stile del mockup, chiaro e scuro |
| 1.6 | ✅ | Servizi verificati dai log della build, senza schermate nuove |
| 1.7 | ✅ | Schema 0002 **proposto**, in `supabase/proposte/`, testato solo su database temporaneo |
| 1.8 | ✅ | Regole Firestore invariate (già coerenti con lo schema 0002); un test in più |
| 1.9 | ✅ | `codemagic.yaml` solo iPhone; collegamento a cura del titolare, su autorizzazione |
| 1.10 | ✅ | Questa checklist |

## 4. Punti aperti (decisioni del titolare)

1. ~~Merge su `main` dei rami della Fase 1~~ — **fatto** il 14/11/2026 (`main` a `7bfc835`).
2. **Applicazione dello schema 0002 al database Supabase reale.** Prima di applicarlo:
   - verificare in sola lettura se il database reale contiene già dati, perché lo schema
     converte gli identificativi;
   - inserire l'identificativo del progetto Firebase in `private.settings`;
   - collegare Firebase come provider in Supabase (Third-Party Auth).

   Finché non è fatto, l'app continua a funzionare come oggi: nessun utente entra prima della
   Fase 2.

   **Controllo in sola lettura fatto il 14/11/2026** (query nell'editor SQL di Supabase,
   eseguita dal titolare):

   | Voce | Valore |
   |---|---|
   | Registro delle migrazioni della CLI (`supabase_migrations`) | Assente: lo schema `0001` è stato applicato a mano, non con la CLI |
   | Utenti Supabase Auth, profili, annunci, posizioni, segnalazioni, moderazione, admin, foto | **Tutti 0** |
   | Schema 0002 già presente | No |
   | PostGIS | Attivo |

   Esito: il database reale non contiene dati, quindi lo schema `0002` si può applicare senza
   conversione di dati esistenti. L'applicazione richiede comunque l'autorizzazione esplicita
   del titolare.
3. **Ruolo `authenticated` nei token Firebase (Fase 2).** Supabase accetta i token Firebase
   solo se ogni utente ha il claim personalizzato `role: authenticated`. Va assegnato lato
   server:
   - con Cloud Functions, che richiedono il piano Blaze (vedi L1);
   - oppure con una funzione su Supabase che usi credenziali Firebase, da custodire nei
     segreti di Supabase.

   Decisione da prendere nel progetto della Fase 2. Il ruolo non deve mai essere diverso da
   `authenticated`.
4. **Firma dei token nei test.** I test usano token firmati dalla chiave del database
   temporaneo, con le stesse informazioni di un token Firebase. La verifica della firma vera di
   Google la fa Supabase e non si può riprodurre senza token reali: sarà provata in Fase 2 con
   un account di prova (dettagli in `TEST_SUPABASE_RLS.md`).
5. **Collegamento di Codemagic** al repository (F11), quando il titolare lo autorizza.
6. **Tipo di account Azienda (regola M6).**
   - **Oggi:** alla creazione del profilo un utente può indicare da solo il tipo «Azienda»
     (`account_type = business`). Era così già nello schema `0001` e lo schema `0002` non lo
     cambia: non è una regressione.
   - **Regola da applicare:** la registrazione come Azienda deve essere accompagnata da
     verifiche adeguate. Tra queste, il controllo della **maggiore età**: per la regola M6
     Azienda e abbonamento sono solo per i maggiorenni.
   - **Altre verifiche** (partita IVA, abbonamento, badge assegnato solo dall'admin) seguono il
     PDF e le decisioni P4 e M6.
   - **Quando:** il tipo Azienda va reso modificabile solo dal server dopo le verifiche. Da
     progettare con la registrazione (Fase 2) e l'abbonamento Azienda (Fase 6), con i
     relativi test.

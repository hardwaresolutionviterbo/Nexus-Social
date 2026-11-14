# Fase 2 · Checklist per l'unione in `main`

Unione proposta: **avanzamento rapido (fast-forward)** di `main` da `c3e5720` all'ultimo commit di
`fase2/blocco5`, che contiene i Blocchi 1-5. Nessun merge commit, nessuna riscrittura della storia.
Si esegue **solo con l'autorizzazione esplicita del titolare**.

## Controlli

| Controllo | Esito |
|---|---|
| `main` è antenato di `fase2/blocco5` (fast-forward possibile, nessun conflitto) | ✅ |
| Blocchi 1-5 approvati dal titolare (parte provata con i test automatici) | ✅ |
| Build Android e test dell'app (130) | ✅ |
| Test di sicurezza Supabase su database temporaneo (74/74) e 8 controprove | ✅ |
| Cloud Functions sugli emulatori e vettori ufficiali OPRF | ✅ |
| Regole Firestore | ✅ |
| Nessun file di configurazione Firebase nel repository (F10) | ✅ |
| Nessuna chiave segreta nelle modifiche (`sb_secret_`, chiavi private, chiavi Google) | ✅ |
| `google-services.json`, SHA, progetto Firebase, identificativo `com.nexussocial.app` invariati | ✅ |
| Workflow temporaneo dei vettori RFC rimosso | ✅ |

## Cosa cambia con l'unione

- L'APK costruito da `main` resta con il collegamento al server spento (`SERVER_LINK_ENABLED=false`):
  si comporta come oggi, con il nome **Piazly** e la registrazione del Blocco 1. Profilo, Privacy,
  PIN e rubrica si attivano solo quando il server sarà collegato (Blaze, S1).
- Android: nuovi permessi `USE_BIOMETRIC` e `READ_CONTACTS` (chiesto solo dopo il consenso),
  `MainActivity` come `FlutterFragmentActivity`. iPhone: testi per Face ID, foto e contatti.

## Cosa NON fa l'unione

- Nessuna migrazione sul database reale (0003-0006 restano da applicare con autorizzazione).
- Nessun deploy di Cloud Functions, nessun segreto creato, nessuna spesa.
- Nessuna modifica a Firebase, Supabase o Codemagic.

## Punti aperti che restano

- Prova sul telefono dei Blocchi 1-5 con Blaze.
- Build iPhone su Codemagic con i nuovi pacchetti.
- «Scarica i miei dati» ed «Elimina account»: da decidere (al più tardi Fase 9).

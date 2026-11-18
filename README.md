# Piazly (ex Nexus Social)

App **Flutter** per Android e iPhone. Contiene:
- la **Mappa Sociale** con annunci e richieste vicino a te;
- la **chat cifrata end-to-end**, con gruppi, foto, vocali e notifiche;
- le sezioni **Scambia** e **Vendita**, con proposte e feedback;
- profili **Privato** e **Azienda**, con privacy, blocchi e sicurezza dell'account.

Si lavora a fasi e a blocchi. Alla fine di ogni blocco c'è un APK da provare sul telefono.
Niente arriva in `main` né sul database reale senza l'autorizzazione del titolare.

*Aggiornato il 18/11/2026.*

## Stato del lavoro

| Fase | Contenuto | Stato | Documenti |
| --- | --- | --- | --- |
| 0 | Account, chiavi, grafica, costi, regole | **Completata** | [`docs/FASE_0_CHECKLIST.md`](docs/FASE_0_CHECKLIST.md), [`docs/fase0/`](docs/fase0/) |
| 1 | Fondamenta: app installabile, servizi, tema, navigazione | **Completata** | [`docs/fase1/CHECKLIST.md`](docs/fase1/CHECKLIST.md) |
| 2 | Accesso con SMS, profilo, privacy e blocchi, sicurezza (PIN, impronta), rubrica | **Completata, in `main`** | [`docs/fase2/`](docs/fase2/) |
| 3 | Mappa Sociale 3D, annunci, annunci vicini e filtri, commenti, Mi piace, notifiche nell'app | **Completata, in `main`** | [`docs/fase3/`](docs/fase3/) |
| 4 | Chat cifrata, allegati, gruppi, notifiche, backup, chiamate | **In corso**: Blocchi 1–4 in `main`, Blocco 5 (notifiche) da provare, Blocco 6 (backup) da provare, Blocco 7 da provare, Blocco 8 (chiamate) da provare | [`docs/fase4/`](docs/fase4/) |
| 5 | Scambia e Vendita: categorie, annunci, ricerca, proposte, feedback | **Completata, in `main`** | [`docs/fase5/`](docs/fase5/) |
| 6 | Aziende, promozioni, abbonamento 9,99 €/mese | Da iniziare | |
| 7 | Gestionale Admin dentro l'app | Da iniziare | |
| 8 | Traduzione, gamification, ricerca avanzata | Da iniziare | |
| 9 | Test, sicurezza, GDPR, beta chiusa | Da iniziare | |
| 10 | Pubblicazione e lancio | Da iniziare | |

Il server funziona senza piano a pagamento (niente Blaze su Firebase). Firebase resta per
l'accesso con SMS e per l'invio delle notifiche. Tutto il resto è su Supabase. Spiegazione in
[`docs/server/`](docs/server/).

## Fase 4 · Chat

| Blocco | Contenuto | Stato | Esito |
| --- | --- | --- | --- |
| 1 | Chat a due cifrata (MLS), richieste da chi non è in rubrica, spunte | In `main` | [`BLOCCO1_ESITO.md`](docs/fase4/BLOCCO1_ESITO.md) |
| 2 | Rispondi, reazioni, inoltra, elimina per tutti | In `main` | [`BLOCCO2_ESITO.md`](docs/fase4/BLOCCO2_ESITO.md) |
| 3 | Foto, video, vocali e documenti cifrati | In `main` | [`BLOCCO3_ESITO.md`](docs/fase4/BLOCCO3_ESITO.md) |
| 4 | Gruppi cifrati, amministratori, codice d'invito | In `main` | [`BLOCCO4_ESITO.md`](docs/fase4/BLOCCO4_ESITO.md) |
| 5 | Notifiche ad app chiusa, «Silenzia», «Non disturbare» | Sul ramo `fase4/blocco5`, server attivo, da provare | [`BLOCCO5_ESITO.md`](docs/fase4/BLOCCO5_ESITO.md) |
| 6 | Backup della chat cifrato con password | Sul ramo `fase4/blocco6`, server attivo, da provare | [`BLOCCO6_ESITO.md`](docs/fase4/BLOCCO6_ESITO.md) |
| 7 | «Segnala» con i messaggi scelti, «Condividi l'incontro», notifiche dei commenti che aprono l'annuncio | Sul ramo `fase4/blocco7`, server attivo, da provare | [`BLOCCO7_ESITO.md`](docs/fase4/BLOCCO7_ESITO.md) |
| 8 | Chiamate vocali e videochiamate (chat a due) | Sul ramo `fase4/blocco8`, server attivo, da provare | [`BLOCCO8_ESITO.md`](docs/fase4/BLOCCO8_ESITO.md) |
| 9 | Chiamate di gruppo, schermata di chiamata di sistema | Da fare | |

Le scelte tecniche della chat sono in [`docs/fase4/DECISIONI.md`](docs/fase4/DECISIONI.md).

## Dove trovare le cose

| Cosa | Dove |
| --- | --- |
| Piano di lavoro ufficiale | `Nexus_Social_Piano_di_Lavoro_COMPLETO_AGGIORNATO.pdf` (non va modificato) |
| Modifiche approvate al piano | [`docs/fase1/MODIFICHE_AL_PIANO.md`](docs/fase1/MODIFICHE_AL_PIANO.md) |
| Piano e risultato di ogni blocco | `docs/faseN/PIANO_OPERATIVO.md` e `docs/faseN/BLOCCOn_ESITO.md` |
| Bozze legali (privacy, termini, regole), **non ancora verificate da un professionista** | [`docs/fase0/`](docs/fase0/) |
| Schema del database e regole di sicurezza | [`supabase/migrations/`](supabase/migrations/): `0001`–`0025`, tutte applicate al database reale |
| Funzioni del server | [`supabase/functions/`](supabase/functions/): `rubrica`, `notifiche` e `chiamate` |
| Test di sicurezza del database | [`supabase/tests/rls_test.py`](supabase/tests/rls_test.py), eseguiti su un database temporaneo (workflow Supabase RLS) |
| Codice dell'app | [`lib/`](lib/), una cartella per sezione in `lib/features/` |
| Test dell'app | [`test/`](test/), una cartella per fase |
| Anteprime delle schermate | [`tool/screenshots/`](tool/screenshots/) (workflow «Anteprime schermate») |

## Struttura del repository

```
lib/
  main.dart              avvio e collegamento dei servizi
  app.dart               tema, lingua, schermata di accesso
  core/                  configurazione, servizi (Firebase, Supabase, notifiche), tema, componenti
  features/
    onboarding/          accesso con SMS e registrazione
    shell/               barra in basso: Chat, Mappa, Scambia, Vendita, Profilo
    chat/                chat cifrata, allegati, gruppi
    notifications/       preferenze delle notifiche
    map/                 Mappa Sociale, annunci, commenti, notifiche nell'app
    market/              Scambia e Vendita
    profile/             profilo e profilo pubblico
    privacy/             privacy e persone bloccate
    security/            PIN e sblocco con impronta
    contacts/            rubrica (solo impronte dei numeri, mai i numeri in chiaro)
    admin/               gestionale (Fase 7)
supabase/migrations/     schema e regole di sicurezza
supabase/functions/      funzioni del server (Deno)
supabase/tests/          test di sicurezza del database
firebase/                regole e test di Firestore
test/                    test automatici dell'app
tool/screenshots/        anteprime delle schermate
docs/                    piani, esiti e decisioni di ogni fase
```

## Installare l'app sul telefono (senza PC)

**GitHub Actions (Android).** `.github/workflows/android.yml` si esegue a ogni push su `main` o
su un ramo di lavoro (`fase1/...`, `fase4/...`), oppure a mano. Esegue analisi, test e build.

1. Apri **Actions → Android APK** e scegli l'esecuzione.
2. In **Artifacts** scarica il file.
3. Aprilo sul telefono, consentendo l'installazione da origini sconosciute.

Ogni APK è identificabile (regola R1):
- **nome del file:** `nexus-social-<versione>+<build>-<commit>-<ramo>.apk`;
- **riepilogo dell'esecuzione:** la stessa tabella;
- **nell'app:** Profilo → Informazioni → Versione.

Il numero di build è `numero esecuzione × 100 + tentativo`, quindi anche una riesecuzione produce
un APK distinto.

**Codemagic (solo iPhone, decisione F11).**
- Il collegamento del repository richiede l'autorizzazione del titolare.
- Firebase su iOS: il file `GoogleService-Info.plist` non sta nel repository (regola F10). La
  build lo crea dal segreto `GOOGLE_SERVICE_INFO_PLIST` del gruppo `nexus_social`: istruzioni
  in [`docs/fase1/FIREBASE_IOS.md`](docs/fase1/FIREBASE_IOS.md).
- La build iOS senza firma si avvia manualmente.
- Per installare su iPhone serve un account Apple (Fasi 9-10).

## Sviluppo locale

Requisiti: Flutter 3.50 o successivo, JDK 17, Xcode per iOS.

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define-from-file=env.json
flutter build apk --debug   # APK di prova installabile
```

`env.json` non è versionato: copia `env.example.json` e compila i valori. Senza chiavi l'app
si avvia normalmente e segnala nel Profilo quali servizi non sono configurati.

## Privacy della posizione

La posizione esatta non è mai visibile agli altri utenti: resta in una tabella leggibile solo
dal proprietario e dagli amministratori, mentre la mappa usa una posizione approssimata a una
griglia di circa 550 metri. La ricerca per distanza filtra sulla posizione reale ma restituisce
distanze arrotondate a fasce di 250 metri, così non si può triangolare una persona. Il raggio è
regolabile fino a 30 km e parte da 10 km.

## Scelte tecniche

Le motivazioni iniziali sono in [`docs/ARCHITETTURA.md`](docs/ARCHITETTURA.md). Le scelte
principali:
- un solo codice Flutter per Android e iPhone;
- MapLibre con OpenFreeMap per la mappa 3D, senza chiavi a pagamento;
- Firebase solo per l'accesso con SMS e per l'invio delle notifiche;
- Supabase per tutto il resto: profili, annunci, mercato, rubrica e chat.

La chat è cifrata sul telefono con MLS (OpenMLS). Il server conserva i messaggi solo cifrati e
li cancella dopo la consegna. Le decisioni sono in
[`docs/fase4/DECISIONI.md`](docs/fase4/DECISIONI.md).

## Progetto precedente

Il vecchio prototipo **CSCSecurityCam** (app Android in Kotlin per la videosorveglianza) non fa
più parte del ramo di lavoro: resta nella cronologia git (`main`, commit `f24339b`) e può essere
recuperato da lì.

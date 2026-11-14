# Firebase su iOS (iPhone)

Stato al 14 novembre 2026:
- l'app iOS `com.nexussocial.app` è registrata nello stesso progetto Firebase di Android;
- il progetto Xcode è pronto;
- **build iOS su Codemagic riuscita** (14 novembre 2026, dal commit `3a97b9f`). Nel
  passaggio «Verifica Firebase nell'app iOS» sono superati tutti e quattro i controlli:
  1. `GoogleService-Info.plist` incluso in `Runner.app` (com.nexussocial.app);
  2. `FIREBASE_ENABLED=true`;
  3. SDK Firebase presente in `Runner.app`;
  4. build iOS solo con Swift Package Manager.

  Build senza firma: dimostra che il progetto compila con Firebase. Per installare l'app su un
  iPhone servono la firma e l'account Apple (sezione 4).

## 1. Regola F10: nessun file Firebase nel repository

- `ios/Runner/GoogleService-Info.plist` è escluso da Git (`.gitignore`), come
  `android/app/google-services.json`. Il repository è pubblico.
- Il progetto Xcode (`ios/Runner.xcodeproj/project.pbxproj`) contiene il **riferimento** al
  file, nel gruppo Runner e tra le risorse copiate nell'app. Il file vero lo crea la build su
  Codemagic.
- La build lo crea da un segreto, **dopo** analisi e test (isolamento F8), e verifica:
  - che sia un plist valido;
  - che il Bundle ID sia `com.nexussocial.app`;
  - che ci siano le chiavi obbligatorie;
  - alla fine, che il file sia dentro `Runner.app`.

  Il contenuto non viene mai stampato.
- Con il file presente, la build imposta `FIREBASE_ENABLED=true`. Senza il segreto la build
  si ferma con un messaggio chiaro.
- Un test automatico (`test/ios_firebase_config_test.dart`) controlla:
  - che il file non sia nel repository e resti escluso da Git;
  - che il progetto Xcode lo includa nel target Runner;
  - che il Bundle ID sia `com.nexussocial.app`.

## 2. Cosa inserire in Codemagic (a cura del titolare)

Solo dopo aver collegato il repository a Codemagic (decisione F11, su autorizzazione).

1. Codemagic → la tua app → **Environment variables**.
2. Crea una variabile con questi dati:

   | Campo | Valore |
   |---|---|
   | **Variable name** | `GOOGLE_SERVICE_INFO_PLIST` |
   | **Variable value** | l'intero contenuto del file `GoogleService-Info.plist` (da `<?xml` fino a `</plist>`), incollato così com'è. Va bene anche il file codificato in base64 |
   | **Group** | `nexus_social`, scritto esattamente così (lo usa `codemagic.yaml`) |
   | **Secure** | attivo (il valore resta nascosto anche nei log) |

3. Facoltative, nello stesso gruppo e sempre «Secure»: `SUPABASE_URL` e `SUPABASE_ANON_KEY`,
   gli stessi valori dei segreti di GitHub. Senza, l'app su iPhone mostra Supabase
   «Non configurato».
4. Avvia a mano il workflow **«Nexus Social · build iOS senza firma (iPhone)»**.

Il file non va mai incollato su GitHub, né nei commit, né nelle issue.

## 3. Compatibilità verificata (senza Mac)

| Elemento | Esito |
|---|---|
| Plist allegato | ✅ Valido; Bundle ID `com.nexussocial.app`; stesso progetto e stesso numero di progetto dell'app Android |
| Bundle ID del progetto Xcode (Debug, Release, Profile) | ✅ `com.nexussocial.app` |
| Avvio di Firebase | ✅ L'app usa `Firebase.initializeApp()` senza opzioni: su iOS legge `GoogleService-Info.plist` dal bundle. Nessun codice Swift aggiuntivo |
| `AppDelegate.swift` | ✅ Nessuna modifica necessaria |
| Firestore | ✅ Nessuna configurazione iOS aggiuntiva |
| Versione minima iOS | 15.0 nel progetto Xcode. Nella prima build Codemagic le dipendenze Firebase sono state scaricate e compilate senza errori di versione minima |

## 4. Ancora da completare (richiede account Apple Developer o Mac)

| Cosa | Perché | Quando |
|---|---|---|
| **Chiave APNs** (file `.p8`) caricata in Firebase Console → Impostazioni progetto → Cloud Messaging → app iOS | Senza, le notifiche push non arrivano sugli iPhone | Con l'account Apple Developer (Fasi 9-10, o prima se serve provare le push) |
| **Capability «Push Notifications»** (`aps-environment`) e **Background Modes → Remote notifications** nel target Runner | Necessarie per ricevere le push su iOS; richiedono la firma con l'account Apple | Insieme alla firma dell'app |
| **Login con SMS su iOS** (Fase 2): APNs per la verifica silenziosa, oppure lo schema URL dell'app (Encoded App ID) per la verifica reCAPTCHA | Richiesto da Firebase Authentication con numero di telefono su iPhone | Progetto della Fase 2 |
| **Firma e installazione su iPhone** | La build attuale è senza firma: serve solo a verificare che compili | Fasi 9-10 (account Apple a pagamento) |

Queste configurazioni non sono state aggiunte ora, perché senza account Apple non funzionerebbero
e non si potrebbero verificare.

## 5. Dipendenze iOS: solo Swift Package Manager (14 novembre 2026)

**Problema.** La prima build su Codemagic è fallita con «The sandbox is not in sync with the
Podfile.lock».

**Causa.**
- Il progetto Xcode del repository era già configurato **solo con Swift Package Manager**:
  il pacchetto `FlutterGeneratedPluginSwiftPackage` è collegato al target Runner e non ci sono
  fasi o riferimenti CocoaPods. Tutti i plugin, Firebase compreso, sono pacchetti Swift.
- Nel repository però era rimasto un `ios/Podfile` personalizzato, inutilizzato.
- Per questo, durante la build, Flutter applicava anche CocoaPods al progetto: aggiungeva la
  fase «[CP] Check Pods Manifest.lock», che confronta `Podfile.lock` con `Pods/Manifest.lock`.
  Il messaggio «your project still has CocoaPods integration» lo indica.
- Il controllo falliva, con ogni probabilità per due motivi (ricostruiti dai messaggi del log e
  dai file del progetto, senza il log completo):
  - i file `Flutter/Debug.xcconfig` e `Release.xcconfig` non includono le impostazioni
    CocoaPods, quindi le cartelle confrontate dal controllo risultano vuote;
  - non c'erano pod da installare.
- Il risultato era un'integrazione mista, che non può funzionare.
- Flutter non poteva sistemare tutto da solo perché il Podfile non era quello standard.

**Correzione strutturale.**
- Rimosso `ios/Podfile`. Non serviva `pod deintegrate`: il progetto Xcode del repository non
  conteneva integrazione CocoaPods, e la versione minima iOS 15.0 resta impostata nel progetto
  Xcode.
- `codemagic.yaml`:
  - attiva esplicitamente Swift Package Manager;
  - si ferma se ricompaiono `Podfile`, `Podfile.lock`, `Pods` o fasi CocoaPods;
  - non usa più la cache CocoaPods.
- La cache di Codemagic conteneva solo le specifiche CocoaPods scaricate, non i file di
  sincronizzazione: non era la causa. Rimossa comunque, perché inutile.
- Il test automatico `test/ios_firebase_config_test.dart` verifica:
  - assenza di Podfile e di integrazione CocoaPods;
  - pacchetto Swift collegato;
  - versione minima iOS 15.0.

**Controlli finali della build iOS:**
- `GoogleService-Info.plist` dentro `Runner.app`, valido e con Bundle ID corretto;
- `FIREBASE_ENABLED=true`;
- SDK Firebase presente nell'app;
- nessuna integrazione CocoaPods comparsa durante la build.

Se in futuro un plugin non supportasse Swift Package Manager, Flutter ricreerebbe da solo un
Podfile standard: andrebbe valutato allora, insieme a questi controlli.

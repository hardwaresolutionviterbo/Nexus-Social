# Fase 2 · Blocco 1: guida per il titolare

Ordine delle operazioni. Ognuna si fa solo dopo quella precedente.

## A. Già indicate (pannelli Firebase e Supabase)

1. **Firebase:**
   - piano Blaze attivo;
   - budget di 10 € con avvisi al 50%, 80% e 100% (L2);
   - SMS consentiti solo verso l'Italia (L3).
2. **Firebase:** accesso con telefono abilitato e due numeri di prova
   (`+39 300 000 0001`, `+39 300 000 0002`), ciascuno con un codice di 6 cifre scelto dal
   titolare. Nessun SMS vero, nessun costo.
3. **Supabase:** Third-Party Auth → **Firebase**, Project ID `nexus-social-e3eee`.

## B. Pubblicare la Cloud Function `assegnaRuolo` (Cloud Shell)

La funzione assegna a ogni nuovo utente il ruolo richiesto da Supabase (decisione S1). È
provata con 7 test sugli emulatori. La pubblicazione la fa il titolare, con il proprio
account: nessuna chiave passa dalla chat né dal repository.

1. Apri **console.cloud.google.com** e scegli in alto il progetto **Nexus Social**.
2. In alto a destra tocca l'icona **Cloud Shell** (`>_`) e attendi il terminale.
3. Incolla questi comandi, uno alla volta, e premi Invio:

   ```bash
   git clone https://github.com/hardwaresolutionviterbo/Nexus-Social.git
   cd Nexus-Social
   git checkout fase2/blocco1
   cd firebase/functions && npm ci && cd ../..
   npx --prefix firebase/functions firebase deploy --only functions:assegnaRuolo --project nexus-social-e3eee
   ```

4. Se compare la richiesta di accesso, esegui
   `npx --prefix firebase/functions firebase login --no-localhost`, apri il link, accedi con il
   tuo account Google, copia il codice nel terminale. Poi ripeti l'ultimo comando.
5. Se il deploy chiede di attivare servizi (Cloud Functions, Cloud Build, Artifact Registry,
   Cloud Run, Eventarc), conferma con `y`. Sono necessari alle Cloud Functions.
6. Se chiede per quanti giorni conservare le immagini dei container, rispondi `1`: occupano
   spazio a pagamento.
7. Alla fine deve comparire **«Deploy complete!»**. Mandane uno screenshot.

**Costi:** con l'uso di prova restano nelle quote gratuite di Blaze; l'avviso di budget (L2)
segnala qualunque spesa.

## C. Prova sul telefono

1. Installa l'APK del Blocco 1 (link nel messaggio di consegna).
2. Si apre la registrazione. Prova queste quattro cose:
   - **Sotto i 14 anni:** «Registrati come Privato», data `15/11/2012` → «Non puoi ancora
     registrarti». Tocca «Torna all'inizio».
   - **Azienda minorenne:** «Registrati come Azienda», data `15/11/2010` → «Account Azienda
     solo per maggiorenni».
   - **Registrazione vera:** «Registrati come Privato», una data da maggiorenne, apri e chiudi
     una bozza, spunta l'accettazione, numero `300 000 0001`, il codice che hai scelto in
     Firebase.
   - Deve comparire «Colleghiamo il tuo account…», poi l'app si apre su **Chat**.
3. **Profilo:**
   - «Accesso effettuato»;
   - Supabase e Firebase «Collegato»;
   - Diagnostica push: «Associazione account» deve diventare **collegato**.
4. **Esci** (con conferma): torna la registrazione. Rientra con lo stesso numero.
5. Chiudi l'app del tutto e riaprila: deve aprirsi su Chat senza chiedere di nuovo il numero.

Se compare «Accesso non completato», manda uno screenshot: il messaggio indica quale passaggio
non ha funzionato (funzione, Supabase o connessione).

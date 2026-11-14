# Fase 2 · Blocco 1: guida per il titolare

Ordine delle operazioni. Ognuna si fa solo dopo quella precedente.

## A. Pannello Firebase (fatto; l'invio del codice richiede Blaze, vedi BLOCCO1_ESITO.md)

1. **Authentication → Metodo di accesso** → **Telefono** → **Abilita**.
2. **Numeri di telefono per i test**: `+39 300 000 0001` e `+39 300 000 0002`, ciascuno con un
   codice di 6 cifre scelto dal titolare. Nessun SMS vero, nessun costo.

## B. In pausa (S1)

Restano rimandati finché il titolare non attiva Blaze:
- piano Blaze e budget;
- regione SMS;
- pubblicazione della Cloud Function `assegnaRuolo`;
- Third-Party Auth su Supabase.

La procedura di pubblicazione si troverà qui quando servirà.

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
   - Dopo il codice l'app si apre su **Chat**.
3. **Profilo:**
   - «Accesso effettuato», con la nota «Collegamento al server in attesa»;
   - Supabase e Firebase «Collegato»;
   - Diagnostica push: «Associazione account» deve diventare **collegato**.
4. **Esci** (con conferma): torna la registrazione. Rientra con lo stesso numero.
5. Chiudi l'app del tutto e riaprila: deve aprirsi su Chat senza chiedere di nuovo il numero.

Se qualcosa non va, manda uno screenshot.

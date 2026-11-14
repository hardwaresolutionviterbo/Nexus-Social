# Fase 2 · Blocco 4: sicurezza dell'account · esito dello sviluppo

Ramo `fase2/blocco4` (parte dal Blocco 3). Stato: **in attesa della verifica del titolare**.

## Cosa è stato fatto

| Requisito | Come |
|---|---|
| R2.5, S2 PIN | PIN di 6 cifre, come WhatsApp, da «Profilo → Sicurezza dell'account». Sul server c'è solo l'hash (bcrypt). Da un telefono nuovo l'app chiede il PIN prima di tutto; **il server non riconosce l'utente finché il PIN non è giusto**: nessun dato letto o modificato, nemmeno chiamando il server direttamente |
| Tentativi | 5 errori: attesa di 1 ora, poi 4, poi 24 |
| PIN dimenticato | Si chiede il ripristino; il PIN si può togliere solo dopo 7 giorni (come WhatsApp senza email) |
| Cambio e disattivazione | Solo con il PIN attuale |
| R2.5, S3 impronta o volto | Facoltativo; si attiva solo dopo averlo confermato; quando è attivo l'app si apre e si riprende dallo sfondo solo con impronta o volto (o il blocco schermo del telefono) |
| Uscita sicura | «Esci»: il telefono non resta attendibile (al prossimo accesso serve il PIN) e lo sblocco con impronta si spegne |

Il telefono è riconosciuto da un codice casuale nella memoria protetta (Keystore Android,
Keychain iPhone), inviato al server come `x-device-id`; il server conserva solo l'hash.

## Modifiche tecniche da conoscere

- Android: `MainActivity` diventa `FlutterFragmentActivity` (richiesto dal pacchetto dell'impronta)
  e si aggiunge il permesso `USE_BIOMETRIC`. Nessuna modifica a Firebase, `google-services.json`,
  SHA o identificativo.
- iPhone: testo per il Face ID in `Info.plist`. La build Codemagic va rifatta per verificare i due
  nuovi pacchetti (`flutter_secure_storage`, `local_auth`).
- Nuove dipendenze: `flutter_secure_storage` 10.3.4, `local_auth` 2.3.0.

## Test automatici

- Database temporaneo: **64 casi su 64** (10 nuovi, H1-H10) e **7 controprove**, una nuova
  (H3: PIN ignorato).
- App: **111 test superati**.

## Scelte di dettaglio da confermare

1. Attese dopo 5 errori: 1 ora, poi 4, poi 24.
2. PIN dimenticato: ripristino dopo 7 giorni dalla richiesta.
3. Impronta: richiesta ogni volta che si torna nell'app (come «Subito» su WhatsApp).
4. Al massimo 10 telefoni attendibili per account (i più vecchi escono).

## Limiti noti

- Le chat (Firestore, Fase 4) non usano ancora il controllo del PIN: si collegherà con la parte
  lato server (S1).
- Prova sul telefono e migrazione 0005 sul database reale: come per i Blocchi 1-3.

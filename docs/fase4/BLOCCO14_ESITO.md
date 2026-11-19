# Fase 4 · Blocco 14 · Correzioni chieste dal titolare e GPS in tempo reale — esito

Ramo `fase4/blocco14`, nato da `fase4/blocco13`. Richieste del titolare del 19/11/2026 (5 foto
cerchiate in rosso), con le scelte fatte una per una.

## 1 · Profilo
- **Riquadro «Informazioni» tolto:** via versione, fase, privacy e la scritta «Costruito una fase
  alla volta».
- **«Stato dei servizi», versione e «Diagnostica push»:** li vedono solo gli amministratori
  (tabella `admin_users` sul server). Senza account (configurazione iniziale) restano visibili.

## 2 · Privacy → Autorizzazioni
- **Per ogni permesso lo stato vero** (Notifiche, Fotocamera, Microfono, Posizione, Contatti):
  «Attivo», «Non attivo» o «Bloccato», con a cosa serve.
- **Il pulsante:**
  - «Consenti» chiede il permesso;
  - «Gestisci» o «Impostazioni» apre le impostazioni del telefono.
- Si aggiorna da solo quando si torna dalle impostazioni.
- Via i testi vecchi («Non usata, Fase 3», «Non usato, Fase 4», «Qui compariranno…»).
- Nuova libreria `permission_handler` 12 (la 13 richiede Android 37).

## 3 · GPS in tempo reale (migrazione 0032)
- **Dove:** Privacy → GPS in tempo reale → «Condividi la posizione».
  1. Scegli le persone, tra chi hai in rubrica.
  2. Scegli la durata: 15 minuti, 1 ora o 8 ore.
- **Smettere:** «Smetti di condividere», oppure la ✕ per una sola persona. L'ultima posizione si
  cancella subito; a tempo scaduto sparisce da sola.
- **Chi la vede:** le persone scelte, sulla loro Mappa, con un segnaposto viola con l'iniziale.
  - Toccandolo: nome, da quanto è aggiornata, fino a quando, «Scrivi» e «Centra».
  - Bloccare qualcuno chiude subito la condivisione con lui.
- **Quando si aggiorna:** mentre Piazly è aperta, ogni 20 metri circa e al massimo ogni 15
  secondi (o prima, se ci si sposta di più di 50 metri).
- **Detto nell'app:** non è cifrata end-to-end, la proteggono le regole del server.

## 4 · Chat, in alto
- Come su WhatsApp: nome intero e sotto «online» o l'ultimo accesso.
- «Silenzia» è passato nel menu ⋮; una campanella barrata accanto al nome indica la chat
  silenziata.

## Controlli
- **App:**
  - permessi con stato e pulsante;
  - GPS: scelta, invio non troppo frequente, smetti, scadenza, senza permesso;
  - profilo per amministratori e non;
  - silenzia dal menu.
- **Database:** GP1–GP4 e la controprova `gps_per_tutti`, che deve far fallire GP2.
- **Server reale (19/11/2026, autorizzato):** migrazione 0032 applicata dal commit `f3ffde1`,
  con impronta verificata.

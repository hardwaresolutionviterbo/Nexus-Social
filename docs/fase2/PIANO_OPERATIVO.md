# Fase 2 · Piano operativo (proposta)

Stato: **proposta da approvare. Nessun lavoro avviato.** Codice, database e servizi restano
invariati finché il titolare non approva il piano e non risponde alle decisioni della
sezione 4.

Riferimento: `Nexus_Social_Piano_di_Lavoro_COMPLETO_AGGIORNATO.pdf`, «FASE 2 – Account,
profili e privacy» (SHA-256 `7da25d52…b8561eb`).

## 1. Obiettivo e requisiti (dal PDF)

> Obiettivo: registrarsi, entrare e avere un profilo completo con controlli chiari su ciò che
> viene condiviso.
>
> Cosa devi riuscire a provare sul telefono: ti registri con il numero, completi il profilo,
> imposti la privacy, gestisci i contatti autorizzati ed entri di nuovo con l'impronta.

| N. | Requisito del PDF | Blocco |
|---|---|---|
| R2.1 | Schermata iniziale «Registrati come Privato» oppure «Registrati come Azienda» | 1 |
| R2.2 | Login con numero di telefono e codice SMS | 1 |
| R2.3 | Nome utente univoco; nome e cognome (in pubblico solo abbreviato, es. Carlo C.) | 2 |
| R2.4 | Foto profilo, bio e link ai social | 2 |
| R2.5 | Verifica in due passaggi (2FA) e accesso con impronta o volto | 4 |
| R2.6 | Rubrica solo con permesso e consenso esplicito, per trovare i contatti iscritti | 5 |
| R2.7 | Blocco degli utenti | 3 |
| R2.8 | Pagina Privacy (visibilità del profilo, numero, contatti, posizione, GPS, blocchi, autorizzazioni) | 3 |
| R2.9 | Percorso guidato «Controllo privacy» | 3 |
| R2.10 | Profilo sociale consultabile dagli utenti autenticati: nome abbreviato, @username, avatar, bio, social secondo le preferenze | 2 |
| R2.11 | Numero e dati di autenticazione privati; numero solo ai contatti riconosciuti, mai agli sconosciuti | 2, 3, 5 |
| R2.12 | Rubrica facoltativa e revocabile; niente SHA-256 semplice; PSI/OPRF o equivalente, con rate limit, anti-abuso, revoca, cancellazione, scadenza | 5 |

## 2. Decisioni già prese che valgono in Fase 2

| Decisione | Effetto in Fase 2 |
|---|---|
| P1-P15 (`docs/fase0/DECISIONI_PRIVACY_APPROVATE.md`, `PRIVACY_IMPOSTAZIONI.md`) | Contenuto della pagina Privacy e del Controllo privacy |
| P2 | Controlli lato server per ogni regola di privacy |
| P3 | Interruttori «Mostra nel profilo pubblico» per bio e social, accesi per impostazione predefinita |
| P5, P6 | Numero: di partenza ai «Contatti riconosciuti dalla rubrica»; accettare una chat non lo rende visibile |
| P7, P8 | Dati della rubrica scadono dopo 30 giorni; «Permetti di trovarmi» si accende con la propria sincronizzazione |
| P12 | Effetti del blocco applicati dal server |
| P14, P15 | Controllo privacy proposto alla fine della registrazione (saltabile); ogni scelta salvata subito |
| D1, M1, M2 | Età minima 14 anni con data di nascita (privata); sotto i 14 anni blocco senza salvare dati |
| D2, D3, M3 | Avviso di sicurezza a tutti al primo accesso, con richiamo per i minorenni |
| D4 | Esperienza simile a WhatsApp |
| M6 | Azienda e abbonamento solo per maggiorenni (punto aperto 6 della checklist della Fase 1) |
| L1, L2, L3 | Sviluppo con numeri di prova; prova del numero reale con Blaze, budget 10 €/mese, SMS solo +39 |
| A5 | Foto profilo usata anche come marker sulla mappa (Fase 3): miniatura compressa al caricamento |
| F10 | Nessuna chiave o file di configurazione nel repository |
| R1, R2, R3 | APK identificabili, nessuna regressione, test di sicurezza automatici |

## 3. Vincoli tecnici verificati (14 novembre 2026)

| Vincolo | Conseguenza |
|---|---|
| Supabase accetta i token Firebase solo se ogni utente ha `role: authenticated` come claim personalizzato; senza, il token vale come anonimo | Serve un componente lato server che lo assegni a ogni nuovo utente (decisione S1) |
| Le blocking functions di Firebase richiedono Identity Platform; in alternativa una Cloud Function `onCreate` con Admin SDK, con rinnovo forzato del primo token | Le Cloud Functions richiedono il piano Blaze (L1) |
| Supabase gratuito: 500.000 chiamate alle Edge Functions, 50.000 utenti mensili da Firebase, 1 GB di file | Un'alternativa gratuita lato server esiste, ma deve custodire credenziali Firebase |
| Le regole Firestore vietano scritture dei client sul profilo pubblico («le modifiche passano da Supabase») | Serve una sincronizzazione lato server da Supabase alla copia pubblica Firestore |
| La 2FA via SMS di Firebase richiede Identity Platform e la fatturazione | Decisione S2 |
| Cloud Storage for Firebase richiede Blaze dal 3 febbraio 2026 | Foto profilo su Supabase Storage (decisione S5) |
| Login SMS su iPhone: servono APNs o lo schema URL per la verifica reCAPTCHA; installazione solo con account Apple | In Fase 2 iOS solo compilato su Codemagic; prove sul telefono Android |

## 4. Decisioni da prendere (domande al titolare)

| N. | Domanda | Opzione consigliata |
|---|---|---|
| S1 | Componente lato server (ruolo `authenticated`, sincronizzazione del profilo pubblico Firestore, rubrica) | **Cloud Functions di Firebase (Blaze anticipato, budget 10 €/mese)**: nessuna chiave amministrativa esportata. Alternativa: Edge Functions di Supabase (resta gratuito, ma una chiave di servizio Firebase va custodita nei segreti di Supabase) |
| S2 | Verifica in due passaggi | **PIN di 6 cifre come WhatsApp**, chiesto alla registrazione di un nuovo telefono; gratuito. Alternativa: secondo SMS con Identity Platform (a pagamento) |
| S3 | Accesso con impronta o volto | **Facoltativo**: l'utente lo attiva; protegge l'apertura dell'app |
| S4 | Registrazione Azienda in Fase 2 | **Dati essenziali** (ragione sociale, partita IVA privata) e controllo della maggiore età (M6); stato «in verifica»; badge solo dall'admin (Fase 7), abbonamento in Fase 6 |
| S5 | Dove salvare le foto profilo | **Supabase Storage** (gratuito, regole già impostate su Firebase uid), con miniatura per la mappa |
| S6 | Rubrica | **OPRF standard (RFC 9497)** calcolata dal server con chiave segreta; limiti: 3 sincronizzazioni al giorno, 2.000 numeri; scadenza 30 giorni (P7) |
| S7 | Termini d'uso e Privacy Policy alla registrazione | **Mostrare le bozze con la scritta «bozza non validata»** e chiedere l'accettazione nelle build di prova; testi definitivi in Fase 9 |

## 5. Flusso di registrazione proposto

1. Benvenuto: «Registrati come Privato» / «Registrati come Azienda» (R2.1).
2. Numero di telefono (+39) e codice SMS (R2.2).
3. Data di nascita: sotto i 14 anni blocco senza salvare dati (M2); Azienda solo 18+ (M6).
4. Avviso di sicurezza (D3, M3), con richiamo per i minorenni.
5. Termini e Privacy (S7).
6. Profilo: @username univoco, nome e cognome, foto o avatar (A5), bio, social (R2.3, R2.4).
7. Verifica in due passaggi (S2) e impronta (S3), saltabili.
8. Controllo privacy (P14), saltabile.
9. Arrivo su Chat (D4).

## 6. Blocchi di lavoro

Ogni blocco segue le regole della Fase 1:
- ramo dedicato e commit per passaggio;
- APK identificabile (R1) e nessuna regressione (R2);
- test automatici sui database temporanei e sugli emulatori (R3, F8);
- pausa per la verifica del titolare a fine blocco.

| Blocco | Contenuto | Prova sul telefono Android |
|---|---|---|
| **1 · Registrazione e accesso** | Componente lato server (S1) con ruolo `authenticated`; flusso dei punti 1-5; logout | Registrazione con un **numero di prova** e codice fisso; dopo l'accesso il Profilo mostra «Utente collegato»; sotto i 14 anni la registrazione si blocca |
| **2 · Profilo** | Migrazione `0003` (foto, social, Azienda); @username univoco; nome abbreviato; foto (S5) con miniatura; bio e social (P3); dati Azienda (S4); copia pubblica Firestore sincronizzata dal server | Completi il profilo; con un secondo numero di prova vedi solo «Carlo C.», @username, foto, bio e social |
| **3 · Privacy e blocchi** | Pagina Privacy (7 sezioni) e Controllo privacy (8 passi) da `PRIVACY_IMPOSTAZIONI.md`; salvataggio immediato; blocco utenti applicato dal server (P12) | Cambi le impostazioni e le ritrovi dopo il riavvio; blocchi il secondo account e lui non vede più il tuo profilo |
| **4 · Sicurezza dell'account** | 2FA (S2); impronta o volto (S3); uscita sicura | Attivi PIN e impronta; chiudi e riapri l'app: entri con l'impronta; su un nuovo accesso ti viene chiesto il PIN |
| **5 · Rubrica** | Consenso esplicito e permesso Android; riconoscimento OPRF (S6); limiti, revoca, cancellazione, scadenza (P7); «Permetti di trovarmi» (P8); numero visibile solo ai riconosciuti (P5, P6) | Salvi in rubrica il numero di prova del secondo account: dopo la sincronizzazione compare tra i contatti; revochi e sparisce |
| **6 · Chiusura** | Prova con il **numero reale** (Blaze, budget 10 €, solo +39: L1-L3), checklist della Fase 2, merge su `main` con autorizzazione | Registrazione con il tuo numero vero e codice SMS reale |

## 7. Azioni che spettano al titolare (con guida passo passo)

Ognuna si fa solo quando serve e con l'autorizzazione esplicita del titolare.

| Quando | Azione |
|---|---|
| Blocco 1 | Firebase Console: attivare l'accesso con telefono e aggiungere due **numeri di prova** con codice fisso |
| Blocco 1 | Supabase: attivare **Third-Party Auth → Firebase** con l'identificativo del progetto |
| Blocco 1 (se S1 = Cloud Functions) | Attivare **Blaze** con avviso di budget a 10 € (L2) |
| Blocchi 2-5 | Applicare dall'editor SQL le migrazioni nuove, dopo i test sul database temporaneo |
| Blocco 6 | Prova con il numero reale (SMS solo verso +39, L3) |

## 8. Test previsti

- **Supabase** (database temporaneo e controprove, come in Fase 1):
  - ruolo e identità;
  - dati privati dell'Azienda;
  - blocchi (P12);
  - visibilità del numero (P5, P6);
  - limiti della rubrica e scadenza a 30 giorni;
  - foto: ognuno solo nella propria cartella.
- **Firestore** (emulatore): copia pubblica scritta solo dal server; nessun campo privato.
- **Funzioni lato server** (emulatori): ruolo assegnato una sola volta, mai diverso da
  `authenticated`; rubrica senza numeri in chiaro né nei dati né nei log.
- **App:**
  - test dell'interfaccia di ogni schermata;
  - blocco sotto i 14 anni senza dati salvati;
  - F1-F11 della Fase 1 sempre verdi.

## 9. Cosa NON si fa in Fase 2

- Mappa e posizione (Fase 3).
- Chat e chiamate (Fase 4).
- Annunci (Fase 5).
- Abbonamento Azienda e promozioni (Fase 6).
- Gestionale admin (Fase 7).
- Nessun servizio, piano a pagamento, migrazione o pubblicazione senza autorizzazione esplicita.

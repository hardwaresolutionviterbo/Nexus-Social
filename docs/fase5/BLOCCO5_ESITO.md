# Fase 5 · Blocco 5 — Esito (commenti completi e categorie)

Ramo `fase5/blocco5` (parte da `fase5/blocco4`). Nessuna modifica a `main` né al database reale.

## Controlli automatici
- Supabase (database temporaneo, migrazione 0016): Q0–Q7 superati, 145 casi su 145; nuove
  controprove `commento_nascosto_visibile` (Q2) e `categorie_senza_admin` (Q7).
- App: analisi e test superati; APK `nexus-social-0.1.0+22801-99f9f98-fase5-blocco5`.
- Schermata: mercato_15 (commenti con «modificato», nascosto e menu).

## Cosa c'è (Mappa e Scambia & Vendi)
- Menu «⋯» su ogni commento: Modifica (i propri), Nascondi / Mostra di nuovo (autore
  dell'annuncio e moderazione), Segnala (quelli altrui); «Elimina» resta com'era.
- «modificato» accanto all'ora dei commenti modificati.
- Commento nascosto: resta al suo posto con il nome di chi l'ha scritto; il testo lo vedono solo
  chi l'ha scritto, l'autore dell'annuncio e la moderazione; niente risposte né Mi piace.
- Segnalazione del commento alla moderazione (una sola aperta per persona e commento).
- Anti-spam: 10 commenti al minuto e 100 al giorno per persona, con un messaggio chiaro.
- Categorie (solo funzioni del server, per amministratori): creare, rinominare, descrivere,
  riordinare, attivare/disattivare, archiviare (una principale archivia anche le sue
  sottocategorie); slug dal nome con la regola del catalogo, mai modificato; gli annunci delle
  categorie archiviate restano integri.

## Da dichiarare al titolare
- Il pannello per gestire le categorie non c'è ancora: le funzioni sono pronte per il pannello
  amministratori previsto più avanti nel PDF.

## Approvazione
- 16/11/2026: Blocco 5 approvato dal titolare (menu «⋯» con icone e spiegazioni); autorizzata l'unione della Fase 5 in main.

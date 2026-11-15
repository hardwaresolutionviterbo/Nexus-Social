# Fase 5 · Blocco 1 — Esito (catalogo e pubblicazione)

Ramo `fase5/blocco1`. Nessuna modifica a `main` né al database reale.

## Controlli automatici
- Supabase (database temporaneo): M1–M8 superati, tutte le controprove (comprese `mercato_foto_facoltative` e `mercato_revisione_ignorata`) falliscono come previsto.
- App: analisi e test superati; APK `nexus-social-0.1.0+20901-3e043e6-fase5-blocco1`.
- Schermate: mercato_1..6.

## Da dichiarare al titolare
- Rimosse le vecchie schermate segnaposto di Scambia e Vendita (`lib/features/listings`, `lib/features/sale`).
- Aggiunte 4 schermate all'elenco chiuso del controllo F10.
- Slug generati con una regola fissa (es. `casa-arredamento-divani-poltrone`, non `casa-arredamento-divani`).
- Foto obbligatorie (1–10) per Vendo, Scambio e Regalo; facoltative per Cerco (da confermare).
- Prezzo massimo 999.999.999 €.
- Parole a rischio (armi, droghe, farmaci, contraffazione, beni rubati, animali vivi, documenti): annuncio "in revisione", visibile solo all'autore.
- Correzione durante il blocco: la pubblicazione inserisce la riga completa in un solo passaggio (prima falliva per il vincolo sui campi obbligatori).

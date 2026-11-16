# Fase 5 · Blocco 3 — Esito (proposte di scambio)

Ramo `fase5/blocco3` (parte da `fase5/blocco2`). Nessuna modifica a `main` né al database reale.

## Controlli automatici
- Supabase (database temporaneo, migrazione 0014): O0–O9 superati, 130 casi su 130; nuove
  controprove `proposte_altrui_visibili` e `proposta_senza_annunci` (O2) rilevano il difetto.
- App: analisi e test superati; APK `nexus-social-0.1.0+21901-944b9eb-fase5-blocco3`.
- Schermate: mercato_10 (proposta) e mercato_11 (proposte ricevute).

## Cosa c'è
- «Proponi uno scambio» nella scheda degli annunci di Scambio e delle Vendite che valutano scambi.
- Proposta: da 1 a 5 propri annunci attivi, conguaglio da 1 a 999.999 € (solo se l'annuncio lo
  accetta) con «lo aggiungo io / lo chiedo io», messaggio fino a 500 caratteri.
- «Proposte di scambio»: Ricevute, Inviate, Storico; Accetta e Rifiuta con conferma,
  Controproposta (scegliendo tra gli annunci di chi chiede), Annulla finché è in attesa.
- Stati: In attesa, Accettata, Rifiutata, Controproposta, Annullata, Completata (quest'ultimo
  con il Blocco 4).
- Notifiche nella campanella: nuova proposta, controproposta, accettazione; toccandole si aprono
  le proposte.
- Regole del server: solo le due parti vedono e toccano la proposta; una sola proposta in attesa
  per persona e annuncio; si accetta solo se gli annunci sono ancora disponibili; blocchi
  rispettati; 30 proposte al giorno (D9).

## Da dichiarare al titolare
- Un annuncio accettato resta pubblicato: la conclusione confermata da entrambi e il feedback
  arrivano con il Blocco 4.
- La chat tra le parti resta con la Fase 4 (D2): dopo l'accettazione ci si accorda nei commenti.
- Aggiunte 2 schermate all'elenco chiuso del controllo F10.

## Approvazione
- 16/11/2026: Blocco 3 approvato dal titolare.

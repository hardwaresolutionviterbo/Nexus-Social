# Fase 6 · Blocco 1 — Aziende: registrazione, profilo attività, sede fissa, verifica

Dal piano (Fase 6): registrazione Azienda con partita IVA, ragione sociale, indirizzo e documento
facoltativo; profilo attività con foto, indirizzo ufficiale completo, orari, prenotazione e
indicazioni; sede stabile e indipendente dal GPS del titolare con segnaposto permanente sulla mappa.

## Cosa c'è

- **Profilo › La mia attività** (per i Privati: «Hai un'attività?»).
  - Registrazione: ragione sociale e partita IVA (controllo della cifra), dichiarazione di
    maggiore età e titolarità. Un account Privato maggiorenne diventa Azienda.
  - Ragione sociale e partita IVA restano **private** (solo l'azienda e gli amministratori);
    una partita IVA può essere registrata una sola volta.
  - Documento facoltativo (PDF o foto) in un archivio privato: lo vedono solo l'azienda e gli
    amministratori.
  - Stato della verifica: In verifica / Verificata / Non approvata (con la nota dell'admin).
    Se si cambiano ragione sociale o partita IVA, la verifica ricomincia.
- **Profilo attività**: insegna, categoria, descrizione, fino a 6 foto, indirizzo ufficiale
  (via, civico, comune, CAP, provincia) con i suggerimenti mentre si scrive, orari per ogni giorno
  (fino a 2 fasce, anche oltre mezzanotte fino alle 6), telefono dell'attività, link per prenotare,
  interruttore «Visibile sulla Mappa».
- **Sede fissa**: il punto si prende dall'indirizzo scelto (o dal centro del comune) e si può
  regolare sulla mappa. Cambia solo modificando la sede: non segue mai il GPS del titolare.
  Il server accetta solo sedi in Italia.
- **Scheda pubblica**: foto, insegna, badge «Verificato», categoria, «Aperto ora · chiude alle…»,
  Indicazioni, Prenota, Chiama, Scrivi, sede ufficiale, orari della settimana.
- **Mappa**: segnaposti arancio fissi delle attività entro 20 km, bordo blu se verificata; si tocca
  e si apre la scheda. Chi ha bloccato (o è bloccato) non vede né la pagina né il segnaposto.
- **Amministratori** (Profilo, solo admin): «Aziende da verificare» con Approva / Rifiuta e nota.

Non ancora (blocchi successivi della Fase 6): abbonamento 9,99 €/mese con 7 giorni gratis (Google
Play), badge legato anche all'abbonamento attivo, promozioni (5 al giorno, fino a 7 giorni), eventi
con luogo diverso dalla sede, notifiche ai passanti, coupon con QR, pagina Premium, recensioni
verificate.

## Server

Migrazione `0034_aziende.sql`: tabella `business_pages`, controlli su orari, foto, indirizzo e
coordinate; funzioni `business_register`, `business_set_document`, `business_mine`,
`business_page_save`, `business_page_get`, `businesses_nearby`, `business_review_queue`,
`business_review`; archivi `aziende` (foto) e `aziende_documenti` (privato).

## Test

- `test/fase6/business_test.dart`: orari (anche dopo mezzanotte), indirizzo, sede in Italia;
  registrazione da Privato con errori, documento, pagina con indirizzo suggerito e orari copiati;
  sede che non si muove; scheda pubblica senza dati privati; approvazione e badge; segnaposti
  fissi sulla Mappa che non seguono il GPS.
- `supabase/tests/rls_test.py` BZ1–BZ5, controprova `aziende_iva_pubblica` (deve far fallire BZ2).
- Anteprime: `aziende_1`…`aziende_5`.

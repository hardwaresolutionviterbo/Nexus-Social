# Fase 6 · Blocco 3 — Promozioni, eventi fuori sede, coupon con QR

Dal piano (Fase 6): massimo 5 promozioni al giorno, durata fino a 7 giorni; eventi con posizione
separata (la sede non cambia); mappa delle promozioni; pulsante Condividi; coupon con QR e conteggio
dei clienti arrivati.

## Cosa c'è

- **La mia attività › Promozioni ed eventi** (titolare):
  - «Nuova»: Offerta o Evento, titolo, descrizione, inizio e fine (massimo 7 giorni, inizio entro 30
    giorni), per gli eventi «In un altro luogo» con i luoghi suggeriti; coupon facoltativo con testo
    (es. «Sconto 20%») e numero massimo.
  - «Oggi: N di 5»: al sesto il pulsante sparisce (e il server rifiuta).
  - Per ogni promozione: «Coupon presi · Clienti arrivati», Annulla.
  - Pulsante QR in alto: **Convalida coupon** con la fotocamera (mobile_scanner) o scrivendo il
    codice; ogni coupon vale una volta.
  - Solo con Premium attivo: senza Premium non si creano e quelle esistenti non si vedono.
- **Mappa**: segnaposti fucsia con «%» (offerte) o «★» (eventi); pulsante con l'etichetta e il
  numero delle promozioni intorno → elenco dalla più vicina.
- **Scheda della promozione**: quando, dove (sede o fuori sede), descrizione, Indicazioni, Vai
  all'attività, **Condividi** (SMS, WhatsApp…: titolo, quando, coupon, indirizzo e mappa; mai il
  codice personale), **Prendi il coupon gratis** → QR e codice di 8 caratteri (sempre lo stesso).
- **Profilo › I miei coupon**. **Scheda attività**: promozioni in corso.
- Privacy: il titolare vede solo i numeri (coupon presi, clienti arrivati), mai chi sono i clienti.
  Chi ha bloccato (o è bloccato) non vede le promozioni.

Ancora da fare nella Fase 6: avvisi a chi passa vicino (solo per chi li accetta), recensioni
verificate, pagamento Google Play (quando ci sarà l'account Play Console).

## Server

Migrazione `0036_promozioni_coupon.sql`: tabelle `promotions` e `coupons` (lette e scritte solo
dalle funzioni), `promotion_create`, `promotion_cancel`, `promotions_mine`, `promotions_nearby`,
`promotions_of`, `coupon_claim`, `coupons_mine`, `coupon_redeem`.

## Test

- `test/fase6/promotions_test.dart`: regole; offerta con coupon e limite di 5 al giorno; evento
  fuori sede con la sede ferma; coupon con QR e codice stabile, Condividi senza codice, convalida
  con fotocamera finta, già usato, codice sbagliato; Mappa con conteggio; senza Premium spariscono.
- `supabase/tests/rls_test.py` PR1–PR5; controprova `promozioni_senza_premium` (deve far fallire PR5).
- Anteprime `aziende_8_mie_promozioni`, `aziende_9_coupon`, `aziende_10_nuova_promo`.
- Nuove librerie: `qr_flutter` (BSD-3), `mobile_scanner` (BSD-3).

# Fase 4 · Decisioni

| # | Decisione | Scelta | Chi |
|---|---|---|---|
| C1 | Protocollo di cifratura | **MLS (RFC 9420)** con OpenMLS, pacchetto Dart `openmls` 4.0.0 (licenza MIT). Signal scartato: la sua licenza (AGPL/GPL) obbligherebbe a pubblicare il codice dell'app. | Il titolare ha lasciato la scelta («Vedi te», 16/11/2026) |
| C2 | Dove passano i messaggi | Supabase, come il resto dell'app: niente Firestore per la chat, niente Blaze. | Coerente con l'opzione C (server gratuito) |
| C3 | Un telefono per account | Come WhatsApp: l'ultimo telefono che apre la chat diventa quello della chat; le chat si riaprono da sole con una nuova «generazione». | Proposta |
| C4 | Arrivo dei messaggi | Nel Blocco 1 l'app controlla il server ogni 3 secondi con una chat aperta e ogni 10 secondi altrimenti, solo in primo piano. Le notifiche con l'app chiusa arrivano nel Blocco 5. | Proposta |
| C5 | Messaggi sul server | Solo cifrati e solo finché il destinatario non li riceve (al massimo 30 giorni). | Proposta |

Rischio noto: il collegamento Dart di OpenMLS è recente e mantenuto da una persona. Versione bloccata (4.0.0), test con la cifratura vera a ogni build.

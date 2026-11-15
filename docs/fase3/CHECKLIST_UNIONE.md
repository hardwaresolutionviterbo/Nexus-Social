# Fase 3 — Unione in main

Autorizzata dal titolare il 15/11/2026 («Si ti autorizzo!»). Avanzamento di `main` senza merge
commit (fast-forward), come per la Fase 2.

## Contenuto
- Piano operativo approvato con le decisioni del titolare (`PIANO_OPERATIVO.md`, sezione 3.1):
  categorie della Mappa Libera e Promozione, interazioni come Facebook, Condividi, notifiche dei
  Mi piace, GPS live solo ai contatti in rubrica e spostato nella Fase 4 con la chat.
- Blocco 1 · mappa 3D (MapLibre + OpenFreeMap), avviso M3, posizione ogni ~300 m.
- Blocco 2 · pubblicare, modificare e chiudere un annuncio (migrazione 0007).
- Blocco 3 · annunci vicini, scheda, filtri, Ultimi annunci, Disponibile ora, segnalazioni (0008).
- Blocco 4 · eventi di gruppo, Mi piace, commenti, Condividi, notifiche (0009).

## Cosa NON fa questa unione
- Nessuna migrazione applicata al database reale: 0003-0009 restano da autorizzare (Blaze).
- Nessun deploy, nessun servizio collegato, nessuna spesa.
- `SERVER_LINK_ENABLED` resta `false`: nell'app normale annunci e interazioni restano spenti e
  la mappa funziona senza server.

## Verifiche prima dell'unione
- App: 206 test superati, analisi statica pulita, APK compilato (`fase3/blocco4`).
- Server: 101/101 casi su database temporaneo, 14 controprove.

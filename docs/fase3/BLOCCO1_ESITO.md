# Fase 3 · Blocco 1 — Prototipo della mappa: esito

Stato: **approvato dal titolare il 15/11/2026**.

## Cosa contiene
- Mappa MapLibre (`maplibre_gl` 0.28) con stile OpenFreeMap Liberty: inclinazione, rotazione,
  edifici 3D, pulsante 2D/3D, «Centra su di me» (F9, R3.1).
- Posizione solo con l'app aperta e la scheda Mappa visibile, aggiornata ogni ~300 m
  (`geolocator`, precisione bilanciata); in background si ferma. In questo blocco resta sul
  telefono e non viene inviata al server.
- Avviso di sicurezza M3 al primo accesso («Ho capito») e sempre dall'icona dello scudo.
- Spiegazione prima della richiesta di permesso; casi «negato per sempre» e «localizzazione
  spenta» con il collegamento alle impostazioni.
- Segnaposto rotondo animato (sorgente di posizione manuale di MapLibre), attribuzione
  «© OpenStreetMap contributors · OpenFreeMap» sempre visibile.
- Raggio 1/5/10/30 km mantenuto nell'intestazione (F11); filtrerà gli annunci dal Blocco 3.

## Modifiche dichiarate e approvate
- Android: permessi `ACCESS_COARSE_LOCATION` e `ACCESS_FINE_LOCATION` (solo in uso).
- iOS: `NSLocationWhenInUseUsageDescription`; versione minima **15.5** (prima 15.0), richiesta da
  MapLibre; aggiornato di conseguenza il test della configurazione iOS.
- CI: rami `fase3/**` tra quelli che compilano l'APK; sui rami della Fase 3 un secondo APK
  «mappa-senza-accesso» (senza chiavi Firebase/Supabase) per provare la mappa finché l'accesso
  con SMS richiede Blaze.

## Verifiche
- 146 test superati (15 nuovi in `test/fase3/map_test.dart`), analisi statica pulita.
- Anteprime: `tool/screenshots/map_screenshots_test.dart` (avviso, permesso, mappa).
- APK: `nexus-social-0.1.0+19201-70bcf11-fase3-blocco1` e `…-mappa-senza-accesso`.

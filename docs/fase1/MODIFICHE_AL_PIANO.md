# Modifiche approvate al piano originale

Elenco delle differenze tra il piano ufficiale e le decisioni prese dal titolare.

- Piano ufficiale: `Nexus_Social_Piano_di_Lavoro_COMPLETO_AGGIORNATO.pdf`, SHA-256
  `7da25d52be13b242d9e0db3b87c740212b2d80fb7c0d4dd75d8e7e541b8561eb`.
- **Il PDF non viene modificato.** Dove questo elenco e il PDF differiscono, vale la decisione
  approvata qui riportata.
- Restano escluse le scelte di dettaglio che il PDF lascia aperte, per esempio P1-P15, che sono
  in `docs/fase0/DECISIONI_PRIVACY_APPROVATE.md`. Qui ci sono solo i punti in cui una decisione
  cambia qualcosa che il PDF scrive esplicitamente.

| N. | Cosa dice il PDF | Cosa vale | Decisione | Data | Fase interessata |
|---|---|---|---|---|---|
| M-1 | Barra in basso «Mappa, Chat, Scambia, Vendita, Profilo» (Fase 1) | Stesse cinque voci, nell'ordine **Chat, Mappa, Scambia** (pulsante centrale arancione), **Vendita, Profilo**, con lo stile grafico del mockup. Funzioni invariate; niente Home né Community | A1 | 14/11/2026 | 1 (restyling, Blocco successivo) |
| M-2 | Nessuna indicazione sulla schermata iniziale; prima voce della barra: Mappa | All'apertura l'app mostra **Chat**, come WhatsApp (D4) | Schermata iniziale | 14/11/2026 | 1 (Blocco successivo) |
| M-3 | «Configurare Codemagic per ottenere l'app da installare sul telefono a ogni modifica» (Fase 1) | APK Android compilato da **GitHub Actions**; Codemagic solo per la build iPhone | F11 | 13/11/2026 | 1 |
| M-4 | Il numero può essere mostrato ai contatti riconosciuti tramite rubrica «e agli amici/contatti accettati, se consentito» (Fase 2) | Il numero si vede **solo** con il riconoscimento dalla rubrica; accettare una chat non lo rende visibile. È una scelta più restrittiva, che il PDF consente («può essere mostrato») | P6 | 13/11/2026 | 2, 4 |
| M-5 | «Nome definitivo dell'app dopo il controllo sugli store» (decisioni ancora da prendere) | Nome **Nexus Social** confermato; l'identificativo `com.nexussocial.app`, già usato su Google Play da un'altra app, va cambiato entro la Fase 9, prima del primo caricamento | F8 | 13/11/2026 | 9 |
| M-6 | Nome dell'app «Nexus Social» | Nome visibile **Piazly** (sostituisce la conferma di M-5; scartati VoxGram e VoxLine per conflitti con marchi e servizi esistenti): nome sotto l'icona Android e iPhone, scritta e monogramma «P» nelle schermate, testi e bozze legali. Restano invariati per ora identificativo `com.nexussocial.app`, progetto Firebase, nome del repository e nomi interni del codice; il cambio dell'identificativo resta in Fase 9 insieme a M-5. Prima della pubblicazione serve una verifica del marchio da parte di un professionista | Nome app | 14/11/2026 | 2, 9 |

Note:

- **M-1 e M-2:** applicate nel codice nel Blocco 2 (passaggio 1.4, ramo `fase1/blocco2`) e
  coperte da test automatici.
- **M-3:** `codemagic.yaml` va allineato nel passaggio 1.9. Oggi contiene ancora la build Android.
- Decisioni che **aggiungono** dettagli senza contraddire il PDF (D1-D4, M1-M7, L1-L3, A5, R1-R3)
  non compaiono qui. Sono in:
  - `docs/fase0/DECISIONI_PRIVACY_APPROVATE.md`;
  - `docs/fase1/PIANO_OPERATIVO.md`.

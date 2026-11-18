# Fase 4 · Blocco 3 — Foto, video, vocali e documenti

Ramo: `fase4/blocco3`. Migrazione: `supabase/migrations/0020_chat_allegati.sql` (NON applicata al database reale: serve l'autorizzazione del titolare).

## Cosa c'è
- **Graffetta**: Galleria, Fotocamera, Video, Documento; anteprima prima di inviare, con didascalia.
- **Microfono** (quando il campo è vuoto): registrazione con tempo, Annulla o Invia; massimo 5 minuti.
- **Cifratura**: ogni allegato è cifrato sul telefono con AES-256-GCM e una chiave nuova; sul server (contenitore privato `chat-media`) ci sono solo byte illeggibili; la chiave viaggia dentro il messaggio, cifrato a sua volta con MLS.
- **Foto**: ridotte a 1600 px (JPEG 80%), con anteprima sfocata minuscola dentro il messaggio; si scaricano da sole (fino a 15 MB), come i vocali.
- **Video e documenti**: si scaricano toccandoli; i documenti si aprono con le app del telefono.
- **Server**: chi riceve cancella il file appena scaricato; «Elimina per tutti» lo cancella subito; **Inoltra** cifra di nuovo il file con una chiave nuova per ogni chat.
- **Limiti**: 50 MB per file (i video non vengono compressi: circa 1–2 minuti), 200 allegati al giorno a persona.
- **Permessi nuovi**: microfono (Android `RECORD_AUDIO`, iOS `NSMicrophoneUsageDescription`), fotocamera su iOS (`NSCameraUsageDescription`). Chiesti solo al primo uso. Firebase, google-services e SHA non toccati.

## Test
- Database temporaneo: casi S1–S5 (carica solo chi è nella chat e nella propria cartella, solo byte cifrati, ≤ 50 MB; scarica solo l'altra persona; niente dopo un rifiuto o con un blocco; nessuna modifica; cancella chi riceve) e la controprova `chat_allegati_aperti`.
- App: foto e documento cifrati e decifrati, file cancellato dal server dopo lo scaricamento, inoltro con chiave nuova, file manomesso rifiutato, elimina per tutti, limite di peso; schermate di graffetta, anteprima, vocale, microfono negato. Esito: 278 test superati.

## Limiti noti
- I video non sono compressi (servirebbe un componente nativo in più): oltre 50 MB vanno tagliati.
- Un file mai scaricato da chi riceve resta sul server finché la chat esiste (pulizia periodica da aggiungere).

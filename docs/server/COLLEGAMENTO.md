# Collegamento del server (database reale)

## 16/11/2026 · fatto con l'autorizzazione del titolare
- Migrazioni 0003–0018 applicate al progetto Supabase di Piazly (0001–0002 erano già state
  applicate a mano il 14/11). Ogni file è stato scaricato dal commit `4cbe93f` e applicato solo
  se la sua impronta SHA-256 coincideva con quella del repository; lo strumento temporaneo
  (estensione `http` e tabella di appoggio) è stato rimosso subito dopo.
- Controlli dopo l'applicazione: 19 categorie e 271 sottocategorie; chiavi della rubrica
  generate nel database; nessuna differenza di permessi tra `anon` e `authenticated`;
  controllo iniziale delle richieste attivo (senza accesso tutto chiuso, «ping» aperto).
- Funzione `rubrica` pubblicata (versione 1) con il controllo del token fatto dalla funzione.
- Avvisi di sicurezza di Supabase: quelli sulle funzioni eseguibili da `anon`/`authenticated`
  sono voluti (l'app usa solo funzioni, con i controlli dentro e il controllo iniziale);
  13 piccole funzioni di supporto senza `search_path` fisso, da sistemare in una migrazione
  successiva.

## Da fare
1. Titolare: Supabase → Authentication → Sign In / Providers → Third-Party Auth → Add provider →
   Firebase, con l'ID del progetto Firebase.
2. Variabile del repository `SERVER_LINK_ENABLED=true` e nuovo APK.
3. Prova su due telefoni con i numeri di prova.

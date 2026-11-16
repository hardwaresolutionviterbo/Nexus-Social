# Fase 5 · Checklist per unire in `main`

Da eseguire solo con l'autorizzazione esplicita del titolare.

1. Blocchi 1–5 approvati (vedi `BLOCCO1..5_ESITO.md`).
2. I rami sono in fila: `fase5/piano` → `blocco1` → `blocco2` → `blocco3` → `blocco4` → `blocco5`;
   basta unire `fase5/blocco5` in `main` con fast-forward.
3. Prima dell'unione: CI verde su `fase5/blocco5` (Supabase RLS, Android APK, Anteprime).
4. Il database reale NON cambia con l'unione: le migrazioni 0003–0016 si applicano solo con
   un'autorizzazione separata del titolare.

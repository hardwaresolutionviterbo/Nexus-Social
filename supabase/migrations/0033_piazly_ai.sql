-- Fase 4 · Blocco 18: «Piazly AI» e «Immagini IA» con Cloudflare Workers AI.
--
-- La funzione `ia` controlla il token di Firebase e conta, per persona e per giorno (ora
-- italiana), le domande alla chat AI e le immagini generate, con la stessa funzione dei limiti
-- della rubrica e del ponte delle chiamate. Nessuna domanda o risposta si salva sul server.
alter table private.contacts_limits drop constraint if exists contacts_limits_kind_check;
alter table private.contacts_limits
  add constraint contacts_limits_kind_check
  check (kind in ('sincronizzazioni', 'mio_numero', 'turn', 'ia_testo', 'ia_immagini'));

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

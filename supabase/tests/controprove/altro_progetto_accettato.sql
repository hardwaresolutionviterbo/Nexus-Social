-- Difetto introdotto apposta: accetta token di qualsiasi progetto (anche nel controllo
-- iniziale delle richieste, migrazione 0017). Deve far fallire C4.
create or replace function public.current_uid()
returns text language sql stable as $$ select auth.jwt() ->> 'sub' $$;
create or replace function public.current_uid_raw()
returns text language sql stable as $$ select auth.jwt() ->> 'sub' $$;

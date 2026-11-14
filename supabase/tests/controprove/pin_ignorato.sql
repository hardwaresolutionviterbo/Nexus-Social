-- Difetto introdotto apposta: il server non richiede più il PIN ai telefoni nuovi.
-- Deve far fallire H3.
create or replace function public.device_trusted(p_uid text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select true;
$$;

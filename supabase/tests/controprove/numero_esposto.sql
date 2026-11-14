-- Difetto introdotto apposta: il numero si vede a chiunque. Deve far fallire I4.
create or replace function public.contact_phone(p_id text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select n.phone_e164 from private.phone_numbers n where n.user_id = p_id;
$$;

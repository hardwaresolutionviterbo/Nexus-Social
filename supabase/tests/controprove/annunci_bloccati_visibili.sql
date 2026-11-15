-- Difetto introdotto apposta: i blocchi non nascondono più gli annunci. Deve far fallire J8.
create or replace function public.hidden_by_block(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select false;
$$;

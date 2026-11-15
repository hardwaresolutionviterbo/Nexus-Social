-- Difetto introdotto apposta: gli annunci vicini ignorano i blocchi. Deve far fallire K6.
create or replace function public.hidden_by_block(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select false;
$$;

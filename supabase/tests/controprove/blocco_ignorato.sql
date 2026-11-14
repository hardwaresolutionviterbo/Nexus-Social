-- Difetto introdotto apposta: il blocco non nasconde più il profilo. Deve far fallire G4.
create or replace function public.blocked_by(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select false;
$$;

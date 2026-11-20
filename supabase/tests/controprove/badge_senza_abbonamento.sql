-- Difetto introdotto apposta: il badge «Verificato» non guarda l'abbonamento.
-- Deve far fallire AB1.
create or replace function private.business_verified(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.business_private b where b.id = p_id and b.status = 'verified');
$$;

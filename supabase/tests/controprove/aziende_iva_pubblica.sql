-- Difetto introdotto apposta: la scheda pubblica mostra ragione sociale e partita IVA.
-- Deve far fallire BZ2.
create or replace function public.business_page_get(p_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select (to_jsonb(pg) - 'created_at') || jsonb_build_object(
    'username', p.username::text,
    'verified', b.status = 'verified',
    'mine', pg.id = public.current_uid(),
    'business_name', b.business_name,
    'vat_number', b.vat_number)
  from public.business_pages pg
  join public.profiles p on p.id = pg.id
  join public.business_private b on b.id = pg.id
  where public.current_uid() is not null
    and pg.id = p_id
    and (pg.id = public.current_uid() or public.is_admin()
         or (pg.published and not public.is_blocked_between(pg.id, public.current_uid())));
$$;

select private.align_anon_with_authenticated();

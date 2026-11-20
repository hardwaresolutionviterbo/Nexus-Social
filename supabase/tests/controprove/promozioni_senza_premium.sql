-- Difetto introdotto apposta: le promozioni restano visibili anche senza Premium.
-- Deve far fallire PR5.
create or replace function private.promotion_visible(p public.promotions, p_viewer text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p.canceled_at is null
     and p.ends_at > now()
     and p.starts_at <= now() + interval '7 days'
     and exists (select 1 from public.business_pages pg where pg.id = p.business_id
                 and (pg.published or pg.id = p_viewer))
     and (p.business_id = p_viewer or not public.is_blocked_between(p.business_id, p_viewer));
$$;

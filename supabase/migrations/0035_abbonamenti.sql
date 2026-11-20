-- Fase 6 · Blocco 2: abbonamento Premium delle aziende (9,99 € al mese, 7 giorni gratis).
--
-- Il titolare non ha ancora l'account Google Play Console (20/11/2026): il pagamento vero con
-- Google Play / App Store si collegherà più avanti (fonti 'google_play' e 'app_store', già previste).
-- Per ora:
-- - prova gratuita di 7 giorni, una sola volta per azienda (e per partita IVA);
-- - un amministratore può attivare o prolungare l'abbonamento a mano, oppure fermarlo;
-- - il badge «Verificato» compare solo se l'azienda è approvata E l'abbonamento è attivo, e
--   sparisce da solo alla scadenza (piano, Fase 6).
-- I dati dell'abbonamento sono privati: li vedono solo l'azienda e gli amministratori.

create table public.business_subscriptions (
  id text primary key references public.business_private (id) on delete cascade,
  source text not null check (source in ('trial', 'admin', 'google_play', 'app_store')),
  started_at timestamptz not null default now(),
  current_period_end timestamptz not null,
  auto_renew boolean not null default false,
  updated_at timestamptz not null default now()
);

create trigger business_subscriptions_touch_updated_at
  before update on public.business_subscriptions
  for each row execute function public.touch_updated_at();

-- Prove gratuite già usate: per azienda e per partita IVA (cambiare account o IVA non ne dà un'altra).
create table private.business_trials (
  vat_number text primary key,
  used_by text not null,
  used_at timestamptz not null default now()
);

alter table public.business_subscriptions enable row level security;
create policy "solo token del progetto Firebase" on public.business_subscriptions
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "il mio abbonamento e gli admin"
  on public.business_subscriptions for select to authenticated
  using (id = public.current_uid() or public.is_admin());
revoke all on public.business_subscriptions from anon, authenticated;
grant select on public.business_subscriptions to authenticated;

create or replace function private.subscription_active(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.business_subscriptions s where s.id = p_id and s.current_period_end > now()
  );
$$;
revoke all on function private.subscription_active(text) from public, anon, authenticated;

-- Badge «Verificato»: approvata dall'admin e con l'abbonamento attivo.
create or replace function private.business_verified(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.business_private b where b.id = p_id and b.status = 'verified')
     and private.subscription_active(p_id);
$$;
revoke all on function private.business_verified(text) from public, anon, authenticated;

create or replace function private.subscription_json(p_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'active', coalesce(s.current_period_end > now(), false),
    'source', s.source,
    'period_end', s.current_period_end,
    'auto_renew', coalesce(s.auto_renew, false),
    'trial_used', exists (
      select 1 from private.business_trials t
      join public.business_private b on b.id = p_id
      where t.used_by = p_id or t.vat_number = b.vat_number))
  from (select p_id as id) x
  left join public.business_subscriptions s on s.id = x.id;
$$;
revoke all on function private.subscription_json(text) from public, anon, authenticated;

-- ------------------------------------------------------------ azienda
create or replace function public.subscription_start_trial()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_vat text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select vat_number into v_vat from public.business_private where id = v_uid;
  if v_vat is null then
    raise exception 'Registra prima l''azienda' using errcode = '22023';
  end if;
  if exists (select 1 from private.business_trials where used_by = v_uid or vat_number = v_vat) then
    raise exception 'La prova gratuita è già stata usata' using errcode = '22023';
  end if;
  if private.subscription_active(v_uid) then
    raise exception 'L''abbonamento è già attivo' using errcode = '22023';
  end if;
  insert into private.business_trials (vat_number, used_by) values (v_vat, v_uid);
  insert into public.business_subscriptions as s (id, source, started_at, current_period_end, auto_renew)
  values (v_uid, 'trial', now(), now() + interval '7 days', false)
  on conflict (id) do update set source = 'trial', started_at = now(),
    current_period_end = now() + interval '7 days', auto_renew = false;
  return private.subscription_json(v_uid);
end;
$$;

create or replace function public.subscription_mine()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when exists (select 1 from public.business_private where id = public.current_uid())
    then private.subscription_json(public.current_uid()) end;
$$;

-- ------------------------------------------------------------ amministratori
-- Attiva o prolunga di [p_months] mesi (da oggi o dalla scadenza, se più avanti).
create or replace function public.subscription_admin_extend(p_id text, p_months integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo per gli amministratori' using errcode = '42501';
  end if;
  if p_months is null or p_months not between 1 and 12 then
    raise exception 'Da 1 a 12 mesi' using errcode = '22023';
  end if;
  if not exists (select 1 from public.business_private where id = p_id) then
    raise exception 'Azienda non trovata' using errcode = '22023';
  end if;
  insert into public.business_subscriptions as s (id, source, started_at, current_period_end, auto_renew)
  values (p_id, 'admin', now(), now() + make_interval(months => p_months), false)
  on conflict (id) do update set source = 'admin',
    current_period_end = greatest(s.current_period_end, now()) + make_interval(months => p_months);
end;
$$;

create or replace function public.subscription_admin_stop(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo per gli amministratori' using errcode = '42501';
  end if;
  update public.business_subscriptions set current_period_end = now(), auto_renew = false where id = p_id;
end;
$$;

-- ------------------------------------------------------------ badge legato all'abbonamento
create or replace function public.business_mine()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when b.id is null then null else jsonb_build_object(
    'business_name', b.business_name,
    'vat_number', b.vat_number,
    'status', b.status,
    'review_note', b.review_note,
    'has_document', b.document_path is not null,
    'verified_badge', private.business_verified(b.id),
    'subscription', private.subscription_json(b.id),
    'page', (select to_jsonb(pg) - 'created_at' from public.business_pages pg where pg.id = b.id)
  ) end
  from (select public.current_uid() as uid) me
  left join public.business_private b on b.id = me.uid
  where me.uid is not null;
$$;

create or replace function public.business_page_get(p_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select (to_jsonb(pg) - 'created_at') || jsonb_build_object(
    'username', p.username::text,
    'verified', private.business_verified(pg.id),
    'mine', pg.id = public.current_uid())
  from public.business_pages pg
  join public.profiles p on p.id = pg.id
  where public.current_uid() is not null
    and pg.id = p_id
    and (pg.id = public.current_uid() or public.is_admin()
         or (pg.published and not public.is_blocked_between(pg.id, public.current_uid())));
$$;

create or replace function public.businesses_nearby(p_lat double precision, p_lng double precision, p_radius_km integer)
returns table (id text, display_name text, category text, lat double precision, lng double precision, verified boolean)
language sql
stable
security definer
set search_path = public
as $$
  select pg.id, pg.display_name, pg.category, pg.lat, pg.lng, private.business_verified(pg.id)
  from public.business_pages pg
  where public.current_uid() is not null
    and p_lat between -90 and 90 and p_lng between -180 and 180
    and p_radius_km between 1 and 50
    and pg.published
    and not public.is_blocked_between(pg.id, public.current_uid())
    and pg.lat between p_lat - p_radius_km / 111.0 and p_lat + p_radius_km / 111.0
    and 6371 * 2 * asin(sqrt(
          power(sin(radians(pg.lat - p_lat) / 2), 2)
          + cos(radians(p_lat)) * cos(radians(pg.lat)) * power(sin(radians(pg.lng - p_lng) / 2), 2)
        )) <= p_radius_km
  order by (pg.lat - p_lat) ^ 2 + (pg.lng - p_lng) ^ 2
  limit 200;
$$;

drop function public.business_review_queue();
create function public.business_review_queue()
returns table (
  id text, username text, business_name text, vat_number text, status public.business_status,
  has_document boolean, document_path text, display_name text, city text, province text,
  submitted_at timestamptz, subscription_end timestamptz, subscription_source text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo per gli amministratori' using errcode = '42501';
  end if;
  return query
  select b.id, p.username::text, b.business_name, b.vat_number, b.status,
         b.document_path is not null, b.document_path, pg.display_name, pg.city, pg.province,
         b.submitted_at, s.current_period_end, s.source
  from public.business_private b
  join public.profiles p on p.id = b.id
  left join public.business_pages pg on pg.id = b.id
  left join public.business_subscriptions s on s.id = b.id
  order by (b.status = 'pending') desc, b.submitted_at desc
  limit 200;
end;
$$;

revoke all on function public.subscription_start_trial() from public, anon;
revoke all on function public.subscription_mine() from public, anon;
revoke all on function public.subscription_admin_extend(text, integer) from public, anon;
revoke all on function public.subscription_admin_stop(text) from public, anon;
revoke all on function public.business_review_queue() from public, anon;
grant execute on function public.subscription_start_trial() to authenticated;
grant execute on function public.subscription_mine() to authenticated;
grant execute on function public.subscription_admin_extend(text, integer) to authenticated;
grant execute on function public.subscription_admin_stop(text) to authenticated;
grant execute on function public.business_review_queue() to authenticated;

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

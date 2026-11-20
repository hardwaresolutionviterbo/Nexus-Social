-- Fase 6 · Blocco 3: promozioni, eventi fuori sede e coupon con QR.
--
-- Dal piano (Fase 6):
-- - massimo 5 promozioni al giorno per azienda (giorno italiano), ognuna dura al massimo 7 giorni;
-- - gli eventi possono avere un luogo diverso dalla sede: la sede non cambia;
-- - le promozioni compaiono sulla mappa delle promozioni e si possono condividere;
-- - coupon con codice QR e conteggio dei clienti arrivati.
-- Le promozioni sono una funzione Premium: si creano e si vedono solo con l'abbonamento attivo
-- (alla scadenza spariscono). Chi ha bloccato (o è bloccato) non le vede.
-- Il coupon è personale: l'azienda, quando lo convalida, vede solo che il codice è buono, non
-- chi è il cliente.

create table public.promotions (
  id uuid primary key default gen_random_uuid(),
  business_id text not null references public.business_pages (id) on delete cascade,
  kind text not null check (kind in ('offerta', 'evento')),
  title text not null check (char_length(btrim(title)) between 3 and 80),
  description text check (description is null or char_length(description) <= 500),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  -- Dove: la sede (copiata alla creazione) oppure, per un evento, un altro luogo.
  lat double precision not null check (lat between 35.4 and 47.2),
  lng double precision not null check (lng between 6.6 and 18.6),
  place_label text check (place_label is null or char_length(place_label) <= 160),
  at_site boolean not null default true,
  coupon_text text check (coupon_text is null or char_length(btrim(coupon_text)) between 2 and 60),
  coupon_limit integer check (coupon_limit is null or coupon_limit between 1 and 10000),
  created_at timestamptz not null default now(),
  canceled_at timestamptz,
  constraint promotions_durata check (ends_at > starts_at and ends_at <= starts_at + interval '7 days')
);

create index promotions_business_idx on public.promotions (business_id, created_at desc);
create index promotions_live_idx on public.promotions (ends_at) where canceled_at is null;

create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null references public.promotions (id) on delete cascade,
  user_id text not null references public.profiles (id) on delete cascade,
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  claimed_at timestamptz not null default now(),
  redeemed_at timestamptz,
  unique (promotion_id, user_id)
);

alter table public.promotions enable row level security;
alter table public.coupons enable row level security;
create policy "solo token del progetto Firebase" on public.promotions
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "solo token del progetto Firebase" on public.coupons
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
-- Letture e scritture solo con le funzioni qui sotto (con i controlli su Premium e blocchi).
revoke all on public.promotions from anon, authenticated;
revoke all on public.coupons from anon, authenticated;

-- Promozione visibile a chi guarda: in corso (o evento che inizia entro 7 giorni), non annullata,
-- azienda con pagina pubblicata e Premium attivo, nessun blocco tra le due persone.
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
     and private.subscription_active(p.business_id)
     and exists (select 1 from public.business_pages pg where pg.id = p.business_id
                 and (pg.published or pg.id = p_viewer))
     and (p.business_id = p_viewer or not public.is_blocked_between(p.business_id, p_viewer));
$$;
revoke all on function private.promotion_visible(public.promotions, text) from public, anon, authenticated;

create or replace function private.promotion_json(p public.promotions, p_viewer text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id, 'business_id', p.business_id, 'kind', p.kind, 'title', p.title,
    'description', p.description, 'starts_at', p.starts_at, 'ends_at', p.ends_at,
    'lat', p.lat, 'lng', p.lng, 'place_label', p.place_label, 'at_site', p.at_site,
    'coupon_text', p.coupon_text, 'coupon_limit', p.coupon_limit,
    'business_name', pg.display_name, 'category', pg.category,
    'business_address', pg.street || ' ' || pg.civic || ', ' || pg.cap || ' ' || pg.city || ' (' || pg.province || ')',
    'verified', private.business_verified(p.business_id),
    'mine', p.business_id = p_viewer,
    'my_coupon', (select c.code from public.coupons c where c.promotion_id = p.id and c.user_id = p_viewer),
    'my_coupon_used', (select c.redeemed_at is not null from public.coupons c
                       where c.promotion_id = p.id and c.user_id = p_viewer),
    'coupons_left', case when p.coupon_limit is null then null else
      greatest(p.coupon_limit - (select count(*) from public.coupons c where c.promotion_id = p.id), 0) end)
  from public.business_pages pg
  where pg.id = p.business_id;
$$;
revoke all on function private.promotion_json(public.promotions, text) from public, anon, authenticated;

-- ------------------------------------------------------------ azienda
create or replace function public.promotion_create(
  p_kind text,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_description text default null,
  p_lat double precision default null,
  p_lng double precision default null,
  p_place_label text default null,
  p_coupon_text text default null,
  p_coupon_limit integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_site public.business_pages;
  v_today integer;
  v_id uuid;
  v_elsewhere boolean := p_lat is not null and p_lng is not null;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select * into v_site from public.business_pages where id = v_uid;
  if v_site.id is null then
    raise exception 'Crea prima il profilo attività' using errcode = '22023';
  end if;
  if not private.subscription_active(v_uid) then
    raise exception 'Le promozioni sono una funzione Premium: attiva la prova o l''abbonamento' using errcode = '22023';
  end if;
  if p_kind not in ('offerta', 'evento') then
    raise exception 'Tipo non valido' using errcode = '22023';
  end if;
  if v_elsewhere and p_kind <> 'evento' then
    raise exception 'Solo gli eventi possono avere un luogo diverso dalla sede' using errcode = '22023';
  end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'Controlla inizio e fine' using errcode = '22023';
  end if;
  if p_ends_at > p_starts_at + interval '7 days' then
    raise exception 'Una promozione dura al massimo 7 giorni' using errcode = '22023';
  end if;
  if p_starts_at < now() - interval '1 hour' or p_starts_at > now() + interval '30 days' then
    raise exception 'L''inizio deve essere da adesso a 30 giorni' using errcode = '22023';
  end if;
  select count(*) into v_today from public.promotions
   where business_id = v_uid
     and (created_at at time zone 'Europe/Rome')::date = (now() at time zone 'Europe/Rome')::date;
  if v_today >= 5 then
    raise exception 'Hai già creato 5 promozioni oggi: riprova domani' using errcode = '22023';
  end if;
  if (p_coupon_text is null or btrim(p_coupon_text) = '') and p_coupon_limit is not null then
    raise exception 'Il limite vale solo con il coupon' using errcode = '22023';
  end if;
  insert into public.promotions (business_id, kind, title, description, starts_at, ends_at, lat, lng,
                                 place_label, at_site, coupon_text, coupon_limit)
  values (v_uid, p_kind, btrim(p_title), nullif(btrim(coalesce(p_description, '')), ''),
          p_starts_at, p_ends_at,
          case when v_elsewhere then round(p_lat::numeric, 6)::double precision else v_site.lat end,
          case when v_elsewhere then round(p_lng::numeric, 6)::double precision else v_site.lng end,
          case when v_elsewhere then nullif(btrim(coalesce(p_place_label, '')), '') else null end,
          not v_elsewhere,
          nullif(btrim(coalesce(p_coupon_text, '')), ''), p_coupon_limit)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.promotion_cancel(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.promotions set canceled_at = now()
   where id = p_id and business_id = public.current_uid() and canceled_at is null;
  if not found then
    raise exception 'Promozione non trovata' using errcode = '22023';
  end if;
end;
$$;

-- Le mie promozioni (anche finite), con i conteggi: coupon presi e clienti arrivati.
create or replace function public.promotions_mine()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb)
  from (
    select p.created_at, private.promotion_json(p, public.current_uid()) || jsonb_build_object(
      'canceled', p.canceled_at is not null,
      'claimed', (select count(*) from public.coupons c where c.promotion_id = p.id),
      'redeemed', (select count(*) from public.coupons c where c.promotion_id = p.id and c.redeemed_at is not null),
      'created_today', (p.created_at at time zone 'Europe/Rome')::date = (now() at time zone 'Europe/Rome')::date
    ) as j
    from public.promotions p
    where p.business_id = public.current_uid()
    order by p.created_at desc
    limit 100
  ) x;
$$;

-- ------------------------------------------------------------ tutti
-- Mappa delle promozioni: entro 50 km, al massimo 200.
create or replace function public.promotions_nearby(p_lat double precision, p_lng double precision, p_radius_km integer)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(private.promotion_json(p, public.current_uid()) order by p.ends_at), '[]'::jsonb)
  from public.promotions p
  where p.id in (
    select q.id from public.promotions q
    where public.current_uid() is not null
      and p_radius_km between 1 and 50
      and q.lat between p_lat - p_radius_km / 111.0 and p_lat + p_radius_km / 111.0
      and 6371 * 2 * asin(sqrt(
            power(sin(radians(q.lat - p_lat) / 2), 2)
            + cos(radians(p_lat)) * cos(radians(q.lat)) * power(sin(radians(q.lng - p_lng) / 2), 2)
          )) <= p_radius_km
      and private.promotion_visible(q, public.current_uid())
    order by q.ends_at
    limit 200
  );
$$;

-- Promozioni in corso di una attività (per la sua scheda).
create or replace function public.promotions_of(p_business_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(private.promotion_json(p, public.current_uid()) order by p.starts_at), '[]'::jsonb)
  from public.promotions p
  where public.current_uid() is not null
    and p.business_id = p_business_id
    and private.promotion_visible(p, public.current_uid());
$$;

-- Prendo il coupon (uno a persona per promozione; il titolare non può prendere i suoi).
create or replace function public.coupon_claim(p_promotion_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_p public.promotions;
  v_code text;
  v_taken integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select * into v_p from public.promotions where id = p_promotion_id for update;
  if v_p.id is null or not private.promotion_visible(v_p, v_uid) or v_p.starts_at > now() then
    raise exception 'Promozione non disponibile' using errcode = '22023';
  end if;
  if v_p.coupon_text is null then
    raise exception 'Questa promozione non ha coupon' using errcode = '22023';
  end if;
  if v_p.business_id = v_uid then
    raise exception 'Non puoi prendere i coupon della tua attività' using errcode = '22023';
  end if;
  select code into v_code from public.coupons where promotion_id = v_p.id and user_id = v_uid;
  if v_code is not null then
    return v_code;
  end if;
  if v_p.coupon_limit is not null then
    select count(*) into v_taken from public.coupons where promotion_id = v_p.id;
    if v_taken >= v_p.coupon_limit then
      raise exception 'Coupon esauriti' using errcode = '22023';
    end if;
  end if;
  loop
    -- 8 caratteri senza 0/O e 1/I, facili da leggere a voce.
    v_code := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + (get_byte(b, i) % 32), 1), '')
               from (select extensions.gen_random_bytes(8) as b) r, generate_series(0, 7) i);
    begin
      insert into public.coupons (promotion_id, user_id, code) values (v_p.id, v_uid, v_code);
      return v_code;
    exception when unique_violation then
      if exists (select 1 from public.coupons where promotion_id = v_p.id and user_id = v_uid) then
        return (select code from public.coupons where promotion_id = v_p.id and user_id = v_uid);
      end if;
    end;
  end loop;
end;
$$;

-- I miei coupon (ancora utili o usati di recente).
create or replace function public.coupons_mine()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(private.promotion_json(p, public.current_uid())
                            || jsonb_build_object('claimed_at', c.claimed_at, 'redeemed_at', c.redeemed_at)
                            order by c.claimed_at desc), '[]'::jsonb)
  from public.coupons c
  join public.promotions p on p.id = c.promotion_id
  where c.user_id = public.current_uid()
    and p.ends_at > now() - interval '7 days';
$$;

-- Il titolare convalida in cassa (dal QR o scrivendo il codice). Ogni coupon vale una volta.
create or replace function public.coupon_redeem(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_c public.coupons;
  v_p public.promotions;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if v_code like 'PIAZLY%' then
    v_code := substr(v_code, 7);
  end if;
  select c.* into v_c from public.coupons c
    join public.promotions p on p.id = c.promotion_id
   where c.code = v_code and p.business_id = v_uid
   for update of c;
  if v_c.id is null then
    raise exception 'Codice non valido per la tua attività' using errcode = '22023';
  end if;
  select * into v_p from public.promotions where id = v_c.promotion_id;
  if v_c.redeemed_at is not null then
    raise exception 'Coupon già usato' using errcode = '22023';
  end if;
  if v_p.canceled_at is not null or v_p.ends_at <= now() then
    raise exception 'Promozione finita' using errcode = '22023';
  end if;
  update public.coupons set redeemed_at = now() where id = v_c.id;
  return jsonb_build_object('title', v_p.title, 'coupon_text', v_p.coupon_text,
    'redeemed', (select count(*) from public.coupons where promotion_id = v_p.id and redeemed_at is not null));
end;
$$;

revoke all on function public.promotion_create(text, text, timestamptz, timestamptz, text, double precision,
  double precision, text, text, integer) from public, anon;
revoke all on function public.promotion_cancel(uuid) from public, anon;
revoke all on function public.promotions_mine() from public, anon;
revoke all on function public.promotions_nearby(double precision, double precision, integer) from public, anon;
revoke all on function public.promotions_of(text) from public, anon;
revoke all on function public.coupon_claim(uuid) from public, anon;
revoke all on function public.coupons_mine() from public, anon;
revoke all on function public.coupon_redeem(text) from public, anon;
grant execute on function public.promotion_create(text, text, timestamptz, timestamptz, text, double precision,
  double precision, text, text, integer) to authenticated;
grant execute on function public.promotion_cancel(uuid) to authenticated;
grant execute on function public.promotions_mine() to authenticated;
grant execute on function public.promotions_nearby(double precision, double precision, integer) to authenticated;
grant execute on function public.promotions_of(text) to authenticated;
grant execute on function public.coupon_claim(uuid) to authenticated;
grant execute on function public.coupons_mine() to authenticated;
grant execute on function public.coupon_redeem(text) to authenticated;

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

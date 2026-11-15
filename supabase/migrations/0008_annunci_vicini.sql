-- Piazly · Fase 3, Blocco 3: annunci vicino a te, «Ultimi annunci», filtri,
-- «Disponibile ora» e segnalazione di un annuncio.
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Decisioni (docs/fase3/PIANO_OPERATIVO.md, R3.8-R3.11):
--  • raggio da 1 a 30 km (10 di partenza, deciso dall'app); il server lo limita sempre;
--  • la posizione di chi cerca serve solo al calcolo e non viene salvata;
--  • gli altri ricevono solo il punto pubblico (zona o punto scelto) e una distanza
--    arrotondata a 250 m, mai il punto salvato;
--  • filtri: categoria (le schede Annunci = «libera» e Promozioni = «promozione»),
--    distanza (raggio), orario (pubblicati nelle ultime N ore), «Disponibile ora»;
--  • segnalazione: motivi da un elenco chiuso, una sola segnalazione aperta per annuncio.

-- ------------------------------------------------------------ annunci vicini
create or replace function public.map_listings_nearby(
  p_lat double precision,
  p_lon double precision,
  p_radius_m integer default 10000,
  p_category text default 'libera',
  p_published_within_hours integer default null,
  p_available_now boolean default false,
  p_limit integer default 200
)
returns table (
  id uuid,
  title text,
  details text,
  category text,
  photos text[],
  location_mode public.location_mode,
  lat double precision,
  lon double precision,
  distance_band_m integer,
  available_now boolean,
  expires_at timestamptz,
  created_at timestamptz,
  is_mine boolean,
  owner_id text,
  owner_username text,
  owner_public_name text,
  owner_avatar_thumb_path text,
  owner_is_business boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lon, p_lat), 4326)::extensions.geography as g
  )
  select
    l.id,
    l.title,
    l.description,
    l.category,
    l.photos,
    l.location_mode,
    st_y(l.approx_location::geometry),
    st_x(l.approx_location::geometry),
    -- Distanza dal punto pubblico, non da quello salvato: niente triangolazione.
    (floor(st_distance(l.approx_location, o.g) / 250.0) * 250)::integer,
    l.available_now,
    l.expires_at,
    l.created_at,
    l.owner_id = public.current_uid(),
    p.id,
    p.username::text,
    p.public_name,
    p.avatar_thumb_path,
    p.account_type = 'business'
  from public.listings l
  join public.profiles p on p.id = l.owner_id
  cross join origin o
  where public.current_uid() is not null
    and p_lat between -90 and 90
    and p_lon between -180 and 180
    and l.kind = 'social'
    and l.status = 'active'
    and l.expires_at > now()
    and l.category = coalesce(p_category, 'libera')
    and not public.hidden_by_block(l.owner_id)
    -- Raggio misurato sul punto pubblico: spostando il punto di ricerca non si ricava quello
    -- salvato.
    and st_dwithin(l.approx_location, o.g, least(greatest(coalesce(p_radius_m, 10000), 1000), 30000))
    and (p_published_within_hours is null
         or l.created_at >= now() - make_interval(hours => least(greatest(p_published_within_hours, 1), 24 * 7)))
    and (not coalesce(p_available_now, false) or l.available_now)
  order by l.created_at desc
  limit least(greatest(coalesce(p_limit, 200), 1), 300);
$$;

-- ------------------------------------------------------------ «Disponibile ora»
create or replace function public.set_my_listing_available(p_id uuid, p_available boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.my_active_listing(p_id);
  update public.listings set available_now = coalesce(p_available, false) where id = p_id;
end;
$$;

-- my_map_listings con lo stato «Disponibile ora» (cambia il tipo restituito).
drop function if exists public.my_map_listings();

create function public.my_map_listings()
returns table (
  id uuid,
  title text,
  details text,
  photos text[],
  location_mode public.location_mode,
  public_lat double precision,
  public_lon double precision,
  exact_lat double precision,
  exact_lon double precision,
  status text,
  available_now boolean,
  expires_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    l.id,
    l.title,
    l.description,
    l.photos,
    l.location_mode,
    st_y(l.approx_location::geometry),
    st_x(l.approx_location::geometry),
    st_y(ll.exact_location::geometry),
    st_x(ll.exact_location::geometry),
    case
      when l.status = 'active' and l.expires_at <= now() then 'expired'
      else l.status::text
    end,
    l.available_now,
    l.expires_at,
    l.created_at
  from public.listings l
  join public.listing_locations ll on ll.listing_id = l.id
  where l.owner_id = public.current_uid() and l.kind = 'social'
  order by l.created_at desc
  limit 100;
$$;

-- ------------------------------------------------------------ segnalazione
create or replace function public.report_listing(
  p_listing uuid,
  p_reason text,
  p_details text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_owner text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_reason is null or p_reason not in
     ('spam', 'truffa', 'contenuto_inappropriato', 'pericolo', 'falso', 'altro') then
    raise exception 'Motivo non valido' using errcode = '22023';
  end if;
  if char_length(coalesce(p_details, '')) > 1000 then
    raise exception 'Dettagli troppo lunghi (massimo 1000 caratteri)' using errcode = '22023';
  end if;
  select l.owner_id into v_owner
  from public.listings l
  where l.id = p_listing and l.status = 'active' and not public.hidden_by_block(l.owner_id);
  if v_owner is null then
    raise exception 'Annuncio non trovato' using errcode = '42501';
  end if;
  if v_owner = v_uid then
    raise exception 'Non puoi segnalare un tuo annuncio' using errcode = '22023';
  end if;
  insert into public.reports (reporter_id, target, target_id, reason, details)
  values (v_uid, 'listing', p_listing, p_reason, nullif(btrim(coalesce(p_details, '')), ''))
  on conflict (reporter_id, target, target_id) where status = 'open' do nothing;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.map_listings_nearby(double precision, double precision, integer, text, integer, boolean, integer)',
    'public.set_my_listing_available(uuid, boolean)',
    'public.my_map_listings()',
    'public.report_listing(uuid, text, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

-- Piazly · Fase 5, Blocco 2: ricerca e scheda di Scambia & Vendi.
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Decisioni (docs/fase5/PIANO_OPERATIVO.md, CATALOGO_TITOLARE.md sezione 7, D4, D9, D10):
--  • ricerca per parola su titolo e descrizione (italiano, con radici delle parole e anche
--    parti di parola nel titolo), ordinamento «Più pertinenti»;
--  • 13 filtri: categoria, sottocategoria, tipologia, prezzo minimo e massimo, condizioni,
--    località (punto di ricerca), raggio, privato o azienda, spedizione, ritiro a mano,
--    disponibilità allo scambio, scambio con conguaglio, data di pubblicazione;
--  • 5 ordinamenti: più recenti, prezzo crescente, prezzo decrescente, più vicini, più pertinenti;
--  • pagine da 20 (D9); raggio da 1 a 200 km oppure ovunque;
--  • il punto di ricerca serve solo al calcolo e non viene salvato; gli altri vedono solo il
--    punto pubblico e una distanza arrotondata a 250 m, mai il punto salvato;
--  • annunci in revisione: solo l'autore; persone bloccate: mai;
--  • Mi piace, commenti, elenchi e segnalazione: le stesse funzioni della Mappa (Fase 3),
--    ora valide anche per gli annunci pubblicati di Scambia & Vendi.

-- ------------------------------------------------------------ scambio e conguaglio
-- «Disponibile allo scambio»: una vendita che valuta anche scambi (lo Scambio lo è sempre).
-- «Conguaglio»: chi scambia accetta una differenza in denaro.
alter table public.listings
  add column open_to_swap boolean not null default false,
  add column cash_adjustment boolean not null default false;

alter table public.listings
  add constraint market_swap_options check (
    (not open_to_swap or (kind = 'market' and market_type = 'sell'))
    and (not cash_adjustment or (kind = 'market' and (market_type = 'swap' or open_to_swap)))
  );

create or replace function private.check_market_swap_options(
  p_type text,
  p_open_to_swap boolean,
  p_cash_adjustment boolean
)
returns void
language plpgsql
immutable
as $$
begin
  if coalesce(p_open_to_swap, false) and p_type <> 'sell' then
    raise exception '«Valuto anche scambi» vale solo per la vendita' using errcode = '22023';
  end if;
  if coalesce(p_cash_adjustment, false)
     and not (p_type = 'swap' or (p_type = 'sell' and coalesce(p_open_to_swap, false))) then
    raise exception 'Il conguaglio vale solo per gli scambi' using errcode = '22023';
  end if;
end;
$$;

revoke all on function private.check_market_swap_options(text, boolean, boolean)
  from public, anon, authenticated;

-- ------------------------------------------------------------ pubblicare e modificare
-- Stesse regole del Blocco 1, con le due opzioni di scambio.
drop function public.publish_market_listing(
  text, uuid, text, text, bigint, text, boolean, boolean, jsonb, double precision,
  double precision, public.location_mode, text[], text, boolean
);
drop function public.update_market_listing(
  uuid, uuid, text, text, bigint, text, boolean, boolean, jsonb, text[], text
);

create function public.publish_market_listing(
  p_type text,
  p_category uuid,
  p_title text,
  p_description text,
  p_price_cents bigint,
  p_condition text,
  p_ships boolean,
  p_pickup boolean,
  p_attributes jsonb,
  p_lat double precision,
  p_lon double precision,
  p_location_mode public.location_mode,
  p_photos text[],
  p_wanted_in_exchange text default null,
  p_no_prohibited_items boolean default false,
  p_open_to_swap boolean default false,
  p_cash_adjustment boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := public.current_uid();
  v_id uuid;
  v_reason text;
  v_slug text;
  v_exact extensions.geography;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if not coalesce(p_no_prohibited_items, false) then
    raise exception 'Conferma che non pubblichi prodotti vietati' using errcode = '22023';
  end if;
  if p_location_mode is null then
    raise exception 'Scegli dove mostrare l''annuncio' using errcode = '22023';
  end if;
  perform private.check_market_listing(
    p_type, p_category, p_title, p_description, p_price_cents, p_condition, p_ships, p_pickup,
    p_attributes, p_photos, p_wanted_in_exchange
  );
  perform private.check_market_swap_options(p_type, p_open_to_swap, p_cash_adjustment);
  -- Anti-spam (D9): 20 annunci nuovi al giorno.
  if (select count(*) from public.listings
      where owner_id = v_uid and kind = 'market' and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Hai raggiunto il limite di 20 annunci al giorno' using errcode = '22023';
  end if;

  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'Posizione non valida' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.user_moderation m
    where m.user_id = v_uid and m.banned_until is not null and m.banned_until > now()
  ) then
    raise exception 'Account sospeso' using errcode = '42501';
  end if;

  select slug into v_slug from public.marketplace_categories where id = p_category;
  v_reason := private.market_flag_reason(
    coalesce(p_title, '') || ' ' || coalesce(p_description, '') || ' ' || coalesce(p_wanted_in_exchange, '')
  );
  v_exact := st_setsrid(st_makepoint(p_lon, p_lat), 4326)::extensions.geography;
  -- Inserimento diretto (non create_listing): i campi di Scambia & Vendi sono obbligatori
  -- fin dalla nascita della riga (vincolo market_fields).
  insert into public.listings (
    owner_id, kind, title, description, category, photos, approx_location, location_mode,
    expires_at, market_type, market_category_id, market_price_cents, item_condition, ships,
    pickup, attributes, wanted_in_exchange, review_status, open_to_swap, cash_adjustment
  )
  values (
    v_uid, 'market', btrim(p_title), coalesce(p_description, ''), v_slug, coalesce(p_photos, '{}'),
    public.public_point(v_exact, p_location_mode), p_location_mode, now() + interval '30 days',
    p_type, p_category, p_price_cents, p_condition, coalesce(p_ships, false),
    coalesce(p_pickup, false), coalesce(p_attributes, '{}'::jsonb),
    nullif(btrim(coalesce(p_wanted_in_exchange, '')), ''),
    case when v_reason is null then 'published' else 'pending_review' end,
    p_type = 'sell' and coalesce(p_open_to_swap, false), coalesce(p_cash_adjustment, false)
  )
  returning id into v_id;
  insert into public.listing_locations (listing_id, exact_location) values (v_id, v_exact);
  return jsonb_build_object(
    'id', v_id,
    'review_status', case when v_reason is null then 'published' else 'pending_review' end
  );
end;
$$;


create function public.update_market_listing(
  p_id uuid,
  p_category uuid,
  p_title text,
  p_description text,
  p_price_cents bigint,
  p_condition text,
  p_ships boolean,
  p_pickup boolean,
  p_attributes jsonb,
  p_photos text[],
  p_wanted_in_exchange text default null,
  p_open_to_swap boolean default false,
  p_cash_adjustment boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.listings := private.my_market_listing(p_id);
  v_reason text;
  v_status text;
begin
  -- La tipologia non cambia: per cambiarla si pubblica un annuncio nuovo.
  perform private.check_market_listing(
    v_row.market_type, p_category, p_title, p_description, p_price_cents, p_condition, p_ships,
    p_pickup, p_attributes, p_photos, p_wanted_in_exchange
  );
  perform private.check_market_swap_options(v_row.market_type, p_open_to_swap, p_cash_adjustment);
  v_reason := private.market_flag_reason(
    coalesce(p_title, '') || ' ' || coalesce(p_description, '') || ' ' || coalesce(p_wanted_in_exchange, '')
  );
  -- Un annuncio rifiutato resta rifiutato; uno pubblicato torna in revisione se serve.
  v_status := case
    when v_row.review_status = 'rejected' then 'rejected'
    when v_reason is not null then 'pending_review'
    else v_row.review_status
  end;
  perform set_config('nexus.internal', 'on', true);
  update public.listings
  set title = btrim(p_title),
      description = coalesce(p_description, ''),
      category = (select slug from public.marketplace_categories where id = p_category),
      market_category_id = p_category,
      market_price_cents = p_price_cents,
      item_condition = p_condition,
      ships = coalesce(p_ships, false),
      pickup = coalesce(p_pickup, false),
      attributes = coalesce(p_attributes, '{}'::jsonb),
      photos = coalesce(p_photos, '{}'),
      wanted_in_exchange = nullif(btrim(coalesce(p_wanted_in_exchange, '')), ''),
      review_status = v_status,
      open_to_swap = v_row.market_type = 'sell' and coalesce(p_open_to_swap, false),
      cash_adjustment = coalesce(p_cash_adjustment, false)
  where id = p_id;
  perform set_config('nexus.internal', 'off', true);
  return jsonb_build_object('id', p_id, 'review_status', v_status);
end;
$$;


-- ------------------------------------------------------------ indice di ricerca
alter table public.listings
  add column search_tsv tsvector generated always as (
    setweight(to_tsvector('italian'::regconfig, coalesce(title, '')), 'A')
    || setweight(to_tsvector('italian'::regconfig, coalesce(description, '')), 'B')
  ) stored;

create index listings_market_search_idx on public.listings using gin (search_tsv)
  where kind = 'market';
create index listings_market_point_idx on public.listings using gist (approx_location)
  where kind = 'market';

-- ------------------------------------------------------------ annunci visibili
-- Gli annunci pubblicati di Scambia & Vendi hanno Mi piace, commenti ed elenchi come quelli
-- della Mappa. Quelli in revisione no (li vede solo l'autore, che non può interagirci).
create or replace function private.visible_listing_owner(p_listing uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner text;
begin
  if public.current_uid() is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select l.owner_id into v_owner
  from public.listings l
  where l.id = p_listing
    and (l.kind = 'social' or (l.kind = 'market' and l.review_status = 'published'))
    and l.status = 'active'
    and l.expires_at > now()
    and not public.hidden_by_block(l.owner_id);
  if v_owner is null then
    raise exception 'Annuncio non trovato' using errcode = '42501';
  end if;
  return v_owner;
end;
$$;

revoke all on function private.visible_listing_owner(uuid) from public, anon, authenticated;

-- Segnalazione: un annuncio in revisione non si può segnalare (per gli altri non esiste).
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.report_listing(uuid, text, text)'::regprocedure) into v_def;
  if position('and l.status = ''active'' and not public.hidden_by_block(l.owner_id)' in v_def) = 0 then
    raise exception 'report_listing: testo atteso non trovato';
  end if;
  execute replace(
    v_def,
    'and l.status = ''active'' and not public.hidden_by_block(l.owner_id)',
    'and l.status = ''active'' and l.expires_at > now() and l.kind in (''social'', ''market'') '
      || 'and (l.kind <> ''market'' or l.review_status = ''published'') '
      || 'and not public.hidden_by_block(l.owner_id)'
  );
end;
$$;

-- ------------------------------------------------------------ righe pubbliche
-- Una riga per annuncio, uguale per la ricerca e per la scheda.
create or replace function private.market_rows(p_lat double precision, p_lon double precision)
returns table (
  id uuid,
  market_type text,
  category_id uuid,
  parent_category_id uuid,
  title text,
  description text,
  price_cents bigint,
  item_condition text,
  ships boolean,
  pickup boolean,
  open_to_swap boolean,
  cash_adjustment boolean,
  attributes jsonb,
  wanted_in_exchange text,
  photos text[],
  location_mode public.location_mode,
  lat double precision,
  lon double precision,
  distance_band_m integer,
  distance_exact_m double precision,
  review_status text,
  expires_at timestamptz,
  created_at timestamptz,
  is_mine boolean,
  owner_id text,
  owner_username text,
  owner_public_name text,
  owner_avatar_thumb_path text,
  owner_is_business boolean,
  search_tsv tsvector
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with origin as (
    select case
      when p_lat between -90 and 90 and p_lon between -180 and 180
        then st_setsrid(st_makepoint(p_lon, p_lat), 4326)::extensions.geography
    end as g
  )
  select
    l.id, l.market_type, l.market_category_id, c.parent_id, l.title, l.description,
    l.market_price_cents, l.item_condition, l.ships, l.pickup, l.open_to_swap,
    l.cash_adjustment, l.attributes, l.wanted_in_exchange, l.photos, l.location_mode,
    st_y(l.approx_location::geometry), st_x(l.approx_location::geometry),
    -- Distanza dal punto pubblico, arrotondata: niente triangolazione.
    case when o.g is not null
      then (floor(st_distance(l.approx_location, o.g) / 250.0) * 250)::integer end,
    case when o.g is not null then st_distance(l.approx_location, o.g) end,
    l.review_status, l.expires_at, l.created_at,
    l.owner_id = public.current_uid(),
    p.id, p.username::text, p.public_name, p.avatar_thumb_path,
    p.account_type = 'business',
    l.search_tsv
  from public.listings l
  join public.profiles p on p.id = l.owner_id
  join public.marketplace_categories c on c.id = l.market_category_id
  cross join origin o
  where public.current_uid() is not null
    and l.kind = 'market'
    and l.status = 'active'
    and l.expires_at > now()
    and (l.review_status = 'published' or l.owner_id = public.current_uid())
    and not public.hidden_by_block(l.owner_id);
$$;

revoke all on function private.market_rows(double precision, double precision)
  from public, anon, authenticated;

-- ------------------------------------------------------------ ricerca
create or replace function public.market_search(
  p_section text,
  p_query text default null,
  p_category uuid default null,
  p_subcategory uuid default null,
  p_types text[] default null,
  p_price_min_cents bigint default null,
  p_price_max_cents bigint default null,
  p_conditions text[] default null,
  p_lat double precision default null,
  p_lon double precision default null,
  p_radius_km integer default null,
  p_seller text default null,
  p_ships boolean default false,
  p_pickup boolean default false,
  p_open_to_swap boolean default false,
  p_cash_adjustment boolean default false,
  p_published_within_days integer default null,
  p_sort text default 'recent',
  p_offset integer default 0
)
returns table (
  id uuid,
  market_type text,
  category_id uuid,
  title text,
  description text,
  price_cents bigint,
  item_condition text,
  ships boolean,
  pickup boolean,
  open_to_swap boolean,
  cash_adjustment boolean,
  attributes jsonb,
  wanted_in_exchange text,
  photos text[],
  location_mode public.location_mode,
  lat double precision,
  lon double precision,
  distance_band_m integer,
  review_status text,
  expires_at timestamptz,
  created_at timestamptz,
  is_mine boolean,
  owner_id text,
  owner_username text,
  owner_public_name text,
  owner_avatar_thumb_path text,
  owner_is_business boolean
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_section_types text[];
  v_q text := nullif(btrim(coalesce(p_query, '')), '');
  v_ts tsquery;
  v_like text;
  v_has_origin boolean := coalesce(p_lat between -90 and 90 and p_lon between -180 and 180, false);
  v_radius_m double precision;
begin
  if public.current_uid() is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  -- Due sezioni, un solo sistema (D10).
  v_section_types := case p_section
    when 'swap' then array['swap', 'free', 'wanted']
    when 'sale' then array['sell']
  end;
  if v_section_types is null then
    raise exception 'Sezione non valida' using errcode = '22023';
  end if;
  if p_types is not null and not (p_types <@ v_section_types) then
    raise exception 'Tipologia non valida per questa sezione' using errcode = '22023';
  end if;
  if p_sort is null or p_sort not in ('recent', 'price_asc', 'price_desc', 'nearest', 'relevant') then
    raise exception 'Ordinamento non valido' using errcode = '22023';
  end if;
  if p_sort = 'nearest' and not v_has_origin then
    raise exception 'Per «Più vicini» serve un punto di ricerca' using errcode = '22023';
  end if;
  if p_seller is not null and p_seller not in ('private', 'business') then
    raise exception 'Venditore non valido' using errcode = '22023';
  end if;
  if p_conditions is not null and not (p_conditions <@ array['new', 'like_new', 'excellent', 'good', 'fair', 'to_repair']) then
    raise exception 'Condizioni non valide' using errcode = '22023';
  end if;
  if p_price_min_cents is not null and p_price_max_cents is not null
     and p_price_min_cents > p_price_max_cents then
    raise exception 'Il prezzo minimo supera il massimo' using errcode = '22023';
  end if;
  if char_length(coalesce(v_q, '')) > 100 then
    raise exception 'Ricerca troppo lunga' using errcode = '22023';
  end if;
  if v_q is not null then
    v_ts := websearch_to_tsquery('italian'::regconfig, v_q);
    v_like := '%' || replace(replace(replace(lower(v_q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;
  if p_radius_km is not null and v_has_origin then
    v_radius_m := least(greatest(p_radius_km, 1), 200) * 1000.0;
  end if;

  return query
  select
    r.id, r.market_type, r.category_id, r.title, r.description, r.price_cents,
    r.item_condition, r.ships, r.pickup, r.open_to_swap, r.cash_adjustment, r.attributes,
    r.wanted_in_exchange, r.photos, r.location_mode, r.lat, r.lon, r.distance_band_m,
    r.review_status, r.expires_at, r.created_at, r.is_mine, r.owner_id, r.owner_username,
    r.owner_public_name, r.owner_avatar_thumb_path, r.owner_is_business
  from private.market_rows(
    case when v_has_origin then p_lat end, case when v_has_origin then p_lon end
  ) r
  where r.market_type = any (coalesce(p_types, v_section_types))
    and (p_category is null or r.parent_category_id = p_category or r.category_id = p_category)
    and (p_subcategory is null or r.category_id = p_subcategory)
    and (p_price_min_cents is null or r.price_cents >= p_price_min_cents)
    and (p_price_max_cents is null or r.price_cents <= p_price_max_cents)
    and (p_conditions is null or r.item_condition = any (p_conditions))
    and (v_radius_m is null or r.distance_exact_m <= v_radius_m)
    and (p_seller is null or r.owner_is_business = (p_seller = 'business'))
    and (not coalesce(p_ships, false) or r.ships)
    and (not coalesce(p_pickup, false) or r.pickup)
    and (not coalesce(p_open_to_swap, false) or r.market_type = 'swap' or r.open_to_swap)
    and (not coalesce(p_cash_adjustment, false) or r.cash_adjustment)
    and (p_published_within_days is null
         or r.created_at >= now() - make_interval(days => least(greatest(p_published_within_days, 1), 30)))
    and (v_q is null or r.search_tsv @@ v_ts or lower(r.title) like v_like)
  order by
    case when p_sort = 'relevant' and v_q is not null then
      ts_rank(r.search_tsv, v_ts) + case when lower(r.title) like v_like then 1 else 0 end
    end desc nulls last,
    case when p_sort = 'price_asc' then r.price_cents end asc nulls last,
    case when p_sort = 'price_desc' then r.price_cents end desc nulls last,
    case when p_sort = 'nearest' then r.distance_exact_m end asc nulls last,
    r.created_at desc,
    r.id
  offset least(greatest(coalesce(p_offset, 0), 0), 10000)
  limit 20;
end;
$$;

-- ------------------------------------------------------------ scheda
create or replace function public.market_listing(
  p_id uuid,
  p_lat double precision default null,
  p_lon double precision default null
)
returns table (
  id uuid,
  market_type text,
  category_id uuid,
  title text,
  description text,
  price_cents bigint,
  item_condition text,
  ships boolean,
  pickup boolean,
  open_to_swap boolean,
  cash_adjustment boolean,
  attributes jsonb,
  wanted_in_exchange text,
  photos text[],
  location_mode public.location_mode,
  lat double precision,
  lon double precision,
  distance_band_m integer,
  review_status text,
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
  select
    r.id, r.market_type, r.category_id, r.title, r.description, r.price_cents,
    r.item_condition, r.ships, r.pickup, r.open_to_swap, r.cash_adjustment, r.attributes,
    r.wanted_in_exchange, r.photos, r.location_mode, r.lat, r.lon, r.distance_band_m,
    r.review_status, r.expires_at, r.created_at, r.is_mine, r.owner_id, r.owner_username,
    r.owner_public_name, r.owner_avatar_thumb_path, r.owner_is_business
  from private.market_rows(p_lat, p_lon) r
  where r.id = p_id;
$$;

-- I miei annunci con le due opzioni di scambio (cambia il tipo restituito).
drop function public.my_market_listings();

create function public.my_market_listings()
returns table (
  id uuid,
  market_type text,
  category_id uuid,
  title text,
  description text,
  price_cents bigint,
  item_condition text,
  ships boolean,
  pickup boolean,
  attributes jsonb,
  photos text[],
  wanted_in_exchange text,
  location_mode public.location_mode,
  exact_lat double precision,
  exact_lon double precision,
  status text,
  review_status text,
  expires_at timestamptz,
  created_at timestamptz,
  open_to_swap boolean,
  cash_adjustment boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    l.id, l.market_type, l.market_category_id, l.title, l.description, l.market_price_cents,
    l.item_condition, l.ships, l.pickup, l.attributes, l.photos, l.wanted_in_exchange,
    l.location_mode,
    st_y(ll.exact_location::geometry), st_x(ll.exact_location::geometry),
    case when l.status = 'active' and l.expires_at <= now() then 'expired' else l.status::text end,
    l.review_status, l.expires_at, l.created_at, l.open_to_swap, l.cash_adjustment
  from public.listings l
  join public.listing_locations ll on ll.listing_id = l.id
  where l.owner_id = public.current_uid() and l.kind = 'market'
  order by l.created_at desc
  limit 200;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.publish_market_listing(text, uuid, text, text, bigint, text, boolean, boolean, jsonb, double precision, double precision, public.location_mode, text[], text, boolean, boolean, boolean)',
    'public.update_market_listing(uuid, uuid, text, text, bigint, text, boolean, boolean, jsonb, text[], text, boolean, boolean)',
    'public.market_search(text, text, uuid, uuid, text[], bigint, bigint, text[], double precision, double precision, integer, text, boolean, boolean, boolean, boolean, integer, text, integer)',
    'public.market_listing(uuid, double precision, double precision)',
    'public.my_market_listings()'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

-- Piazly · Fase 3, Blocco 2: pubblicare un annuncio sulla Mappa.
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
-- Nei test gira solo sul database temporaneo di GitHub Actions.
--
-- Decisioni (docs/fase3/PIANO_OPERATIVO.md):
--  • categorie della Mappa: «libera» (persone, gratuita) e «promozione» (aziende, Fase 6);
--    qui si pubblica solo «libera»;
--  • scadenze T5: da 1 ora a 7 giorni;
--  • P9: zona approssimata preselezionata (griglia ~550 m) oppure punto scelto a mano
--    (bar, punto d'incontro), che gli altri vedono esattamente;
--  • un annuncio nato con la zona approssimata non può diventare «preciso» senza un punto
--    scelto a mano: altrimenti si mostrerebbe la posizione reale del telefono;
--  • P12: tra persone bloccate gli annunci non si vedono, in nessuna delle due direzioni.

-- ------------------------------------------------------------ categorie
alter table public.listings
  add constraint listings_map_category
  check (kind <> 'social' or category is null or category in ('libera', 'promozione'));

-- ------------------------------------------------------------ blocchi (P12)
create or replace function public.hidden_by_block(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_uid() is not null
    and p_owner <> public.current_uid()
    and public.is_blocked_between(p_owner, public.current_uid());
$$;

revoke all on function public.hidden_by_block(text) from public, anon;
grant execute on function public.hidden_by_block(text) to authenticated, service_role;

create policy "annunci nascosti tra persone bloccate"
  on public.listings as restrictive for select to authenticated
  using (not public.hidden_by_block(owner_id));

-- ------------------------------------------------------------ scritture solo da funzioni
-- L'autore non modifica più la riga direttamente (per esempio non può riattivare un
-- annuncio rimosso dalla moderazione): usa le funzioni qui sotto.
revoke update on public.listings from authenticated;

create or replace function public.protect_listing_write()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if current_setting('nexus.internal', true) = 'on' or public.is_admin() then
    return new;
  end if;
  if new.owner_id is distinct from old.owner_id
     or new.kind is distinct from old.kind
     or st_astext(new.approx_location) is distinct from st_astext(old.approx_location)
     or new.location_mode is distinct from old.location_mode
     or new.created_at is distinct from old.created_at
     or (new.status is distinct from old.status
         and (old.status in ('hidden', 'removed') or new.status in ('hidden', 'removed'))) then
    raise exception 'Campi non modificabili' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ------------------------------------------------------------ controlli comuni
create or replace function private.check_map_listing(
  p_title text,
  p_details text,
  p_expires_at timestamptz,
  p_photos text[]
)
returns void
language plpgsql
stable
security definer
set search_path = public, storage
as $$
declare
  v_uid text := public.current_uid();
  v_photo text;
begin
  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'Il testo deve avere da 3 a 120 caratteri' using errcode = '22023';
  end if;
  if char_length(coalesce(p_details, '')) > 2000 then
    raise exception 'Dettagli troppo lunghi (massimo 2000 caratteri)' using errcode = '22023';
  end if;
  if p_expires_at is null
     or p_expires_at < now() + interval '30 minutes'
     or p_expires_at > now() + interval '7 days 5 minutes' then
    raise exception 'Scadenza non valida (da 1 ora a 7 giorni)' using errcode = '22023';
  end if;
  if coalesce(array_length(p_photos, 1), 0) > 4 then
    raise exception 'Al massimo 4 foto' using errcode = '22023';
  end if;
  foreach v_photo in array coalesce(p_photos, '{}') loop
    if split_part(v_photo, '/', 1) <> v_uid or v_photo !~ '^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+\.jpg$'
       or not exists (
         select 1 from storage.objects o
         where o.bucket_id = 'listing-photos' and o.name = v_photo
       ) then
      raise exception 'Foto non valida' using errcode = '22023';
    end if;
  end loop;
end;
$$;

revoke all on function private.check_map_listing(text, text, timestamptz, text[])
  from public, anon, authenticated;

-- ------------------------------------------------------------ pubblicare
create or replace function public.publish_map_listing(
  p_title text,
  p_details text,
  p_lat double precision,
  p_lon double precision,
  p_location_mode public.location_mode,
  p_expires_at timestamptz,
  p_photos text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if public.current_uid() is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_location_mode is null then
    raise exception 'Scegli dove mostrare l''annuncio' using errcode = '22023';
  end if;
  perform private.check_map_listing(p_title, p_details, p_expires_at, p_photos);
  return public.create_listing(
    'social', p_title, coalesce(p_details, ''), p_lat, p_lon, 'libera', null,
    coalesce(p_photos, '{}'), false, p_expires_at, p_location_mode
  );
end;
$$;

-- ------------------------------------------------------------ modificare
create or replace function private.my_active_listing(p_id uuid)
returns public.listings
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.listings;
begin
  select * into v_row from public.listings
  where id = p_id and owner_id = public.current_uid() and kind = 'social';
  if v_row.id is null then
    raise exception 'Annuncio non trovato o non tuo' using errcode = '42501';
  end if;
  if v_row.status <> 'active' then
    raise exception 'Annuncio chiuso o rimosso' using errcode = '42501';
  end if;
  return v_row;
end;
$$;

revoke all on function private.my_active_listing(uuid) from public, anon, authenticated;

create or replace function public.update_my_listing(
  p_id uuid,
  p_title text,
  p_details text,
  p_expires_at timestamptz,
  p_photos text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.my_active_listing(p_id);
  perform private.check_map_listing(p_title, p_details, p_expires_at, p_photos);
  update public.listings
  set title = btrim(p_title),
      description = coalesce(p_details, ''),
      expires_at = p_expires_at,
      photos = coalesce(p_photos, '{}')
  where id = p_id;
end;
$$;

-- Nuovo punto (o nuova modalità) per un annuncio: la posizione esatta resta privata.
create or replace function public.move_my_listing(
  p_id uuid,
  p_lat double precision,
  p_lon double precision,
  p_location_mode public.location_mode
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_exact extensions.geography;
begin
  perform private.my_active_listing(p_id);
  if p_lat is null or p_lon is null or p_location_mode is null
     or p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'Posizione non valida' using errcode = '22023';
  end if;
  v_exact := st_setsrid(st_makepoint(p_lon, p_lat), 4326)::extensions.geography;
  perform set_config('nexus.internal', 'on', true);
  update public.listing_locations set exact_location = v_exact where listing_id = p_id;
  update public.listings
  set location_mode = p_location_mode,
      approx_location = public.public_point(v_exact, p_location_mode)
  where id = p_id;
  perform set_config('nexus.internal', 'off', true);
end;
$$;

create or replace function public.close_my_listing(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.my_active_listing(p_id);
  update public.listings
  set status = 'completed', completed_at = now()
  where id = p_id;
end;
$$;

-- Solo verso la zona approssimata: rendere preciso il punto salvato esporrebbe la
-- posizione del telefono. Per un punto preciso si usa move_my_listing con un punto scelto.
create or replace function public.set_listing_location_mode(
  p_listing_id uuid,
  p_mode public.location_mode
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := public.current_uid();
  v_owner text;
  v_mode public.location_mode;
  v_exact extensions.geography;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select l.owner_id, l.location_mode, ll.exact_location into v_owner, v_mode, v_exact
  from public.listings l
  join public.listing_locations ll on ll.listing_id = l.id
  where l.id = p_listing_id;
  if v_owner is null or (v_owner <> v_uid and not public.is_admin()) then
    raise exception 'Annuncio non trovato o non tuo' using errcode = '42501';
  end if;
  if p_mode = 'precise' and v_mode <> 'precise' then
    raise exception 'Per un punto preciso scegli il punto sulla mappa' using errcode = '22023';
  end if;
  perform set_config('nexus.internal', 'on', true);
  update public.listings
  set location_mode = p_mode,
      approx_location = public.public_point(v_exact, p_mode)
  where id = p_listing_id;
  perform set_config('nexus.internal', 'off', true);
end;
$$;

-- ------------------------------------------------------------ i miei annunci
create or replace function public.my_map_listings()
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
    l.expires_at,
    l.created_at
  from public.listings l
  join public.listing_locations ll on ll.listing_id = l.id
  where l.owner_id = public.current_uid() and l.kind = 'social'
  order by l.created_at desc
  limit 100;
$$;

-- ------------------------------------------------------------ ricerca (P12)
-- Stessa ricerca della 0002, senza gli annunci di chi ha un blocco con chi cerca.
create or replace function public.nearby_listings(
  p_lat double precision,
  p_lon double precision,
  p_radius_m integer default 10000,
  p_kind public.listing_kind default null,
  p_limit integer default 100
)
returns table (
  id uuid,
  owner_id text,
  kind public.listing_kind,
  title text,
  description text,
  category text,
  price_cents integer,
  currency text,
  photos text[],
  location_mode public.location_mode,
  approx_lat double precision,
  approx_lon double precision,
  distance_band_m integer,
  available_now boolean,
  expires_at timestamptz,
  created_at timestamptz
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
    l.owner_id,
    l.kind,
    l.title,
    l.description,
    l.category,
    l.price_cents,
    l.currency,
    l.photos,
    l.location_mode,
    st_y(l.approx_location::geometry) as approx_lat,
    st_x(l.approx_location::geometry) as approx_lon,
    (floor(st_distance(ll.exact_location, o.g) / 250.0) * 250)::integer as distance_band_m,
    l.available_now,
    l.expires_at,
    l.created_at
  from public.listings l
  join public.listing_locations ll on ll.listing_id = l.id
  cross join origin o
  where public.current_uid() is not null
    and l.status = 'active'
    and l.expires_at > now()
    and not public.hidden_by_block(l.owner_id)
    and st_dwithin(ll.exact_location, o.g, least(greatest(p_radius_m, 1000), 30000))
    and (p_kind is null or l.kind = p_kind)
  order by ll.exact_location <-> o.g
  limit least(greatest(p_limit, 1), 200);
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.publish_map_listing(text, text, double precision, double precision, public.location_mode, timestamptz, text[])',
    'public.update_my_listing(uuid, text, text, timestamptz, text[])',
    'public.move_my_listing(uuid, double precision, double precision, public.location_mode)',
    'public.close_my_listing(uuid)',
    'public.set_listing_location_mode(uuid, public.location_mode)',
    'public.my_map_listings()',
    'public.nearby_listings(double precision, double precision, integer, public.listing_kind, integer)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

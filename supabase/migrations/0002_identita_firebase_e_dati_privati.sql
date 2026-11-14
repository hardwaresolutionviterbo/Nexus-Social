-- Nexus Social · Migrazione 0002 (Fase 1, passaggio 1.7)
--
-- ✅ APPLICATA al database reale il 14 novembre 2026, su autorizzazione del titolare, dall'editor
--    SQL di Supabase (come la 0001). Verifica in sola lettura: 10 controlli su 10 OK.
--    Le migrazioni successive vanno applicate solo con autorizzazione esplicita del titolare.
--    I test la eseguono anche su un database temporaneo in GitHub Actions («Supabase RLS»).
--
-- Cosa cambia rispetto a 0001:
--  1. Identità Firebase: gli utenti sono identificati dal loro uid Firebase (testo), letto
--     dal token tramite public.current_uid(). Il token è accettato solo se emesso per il
--     progetto Firebase configurato (iss/aud), con soggetto valido e non scaduto.
--     L'identificativo del progetto NON sta nel repository: va in private.settings.
--  2. Dati privati separati: nome e cognome completi e data di nascita stanno in
--     public.profile_private, leggibile solo dal proprietario (e dagli admin).
--     public.profiles contiene solo dati pubblici: nome abbreviato, @username, avatar, bio,
--     link social, tipo di account, valutazioni.
--  3. Posizione degli annunci (decisione P9): modalità per ogni annuncio, «approssimata»
--     predefinita oppure «precisa» scelta dall'autore. Il GPS in tempo reale (Fase 3) si
--     aggiungerà estendendo il tipo public.location_mode.
--  4. Policy restrittive: su ogni tabella nessun accesso con token di altri progetti.

-- ------------------------------------------------------------ configurazione privata
create schema if not exists private;
revoke all on schema private from public;

create table if not exists private.settings (
  key text primary key,
  value text not null
);
revoke all on private.settings from public;

-- ------------------------------------------------------------ identità dal token
create or replace function public.current_uid()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_claims jsonb := auth.jwt();
  v_project text;
  v_now numeric := extract(epoch from now());
begin
  select s.value into v_project from private.settings s where s.key = 'firebase_project_id';
  if v_project is null or v_claims is null then
    return null;
  end if;
  if (v_claims ->> 'iss') is distinct from ('https://securetoken.google.com/' || v_project) then
    return null;
  end if;
  if not (
    v_claims -> 'aud' = to_jsonb(v_project)
    or (jsonb_typeof(v_claims -> 'aud') = 'array' and (v_claims -> 'aud') ? v_project)
  ) then
    return null;
  end if;
  if coalesce(v_claims ->> 'sub', '') !~ '^[A-Za-z0-9_-]{1,128}$' then
    return null;
  end if;
  if (v_claims ->> 'iat') is null or (v_claims ->> 'iat') !~ '^[0-9]+(\.[0-9]+)?$'
     or (v_claims ->> 'iat')::numeric > v_now + 60 then
    return null;
  end if;
  if (v_claims ->> 'exp') is null or (v_claims ->> 'exp') !~ '^[0-9]+(\.[0-9]+)?$'
     or (v_claims ->> 'exp')::numeric <= v_now then
    return null;
  end if;
  return v_claims ->> 'sub';
end;
$$;

-- ------------------------------------------------------------ via le policy di 0001
drop policy if exists "profili visibili agli utenti" on public.profiles;
drop policy if exists "crea il proprio profilo" on public.profiles;
drop policy if exists "aggiorna il proprio profilo" on public.profiles;
drop policy if exists "annunci attivi visibili" on public.listings;
drop policy if exists "aggiorna i propri annunci" on public.listings;
drop policy if exists "elimina i propri annunci" on public.listings;
drop policy if exists "posizione esatta del proprietario" on public.listing_locations;
drop policy if exists "crea le proprie segnalazioni" on public.reports;
drop policy if exists "legge le proprie segnalazioni o tutta la coda da admin" on public.reports;
drop policy if exists "gli admin gestiscono le segnalazioni" on public.reports;
drop policy if exists "leggi la propria moderazione" on public.user_moderation;
drop policy if exists "gli admin gestiscono la moderazione" on public.user_moderation;
drop policy if exists "leggi la propria riga admin" on public.admin_users;
drop policy if exists "foto annunci: upload nella propria cartella" on storage.objects;
drop policy if exists "foto annunci: modifica le proprie" on storage.objects;
drop policy if exists "foto annunci: elimina le proprie" on storage.objects;

-- ------------------------------------------------------------ uid Firebase (testo)
alter table public.listings drop constraint if exists listings_owner_id_fkey;
alter table public.reports drop constraint if exists reports_reporter_id_fkey;
alter table public.reports drop constraint if exists reports_handled_by_fkey;
alter table public.profiles drop constraint if exists profiles_id_fkey;
alter table public.admin_users drop constraint if exists admin_users_user_id_fkey;
alter table public.user_moderation drop constraint if exists user_moderation_user_id_fkey;
alter table public.user_moderation drop constraint if exists user_moderation_updated_by_fkey;

alter table public.profiles alter column id type text using id::text;
alter table public.listings alter column owner_id type text using owner_id::text;
alter table public.reports alter column reporter_id type text using reporter_id::text;
alter table public.reports alter column handled_by type text using handled_by::text;
alter table public.admin_users alter column user_id type text using user_id::text;
alter table public.user_moderation alter column user_id type text using user_id::text;
alter table public.user_moderation alter column updated_by type text using updated_by::text;

alter table public.profiles
  add constraint profiles_id_format check (id ~ '^[A-Za-z0-9_-]{1,128}$');
alter table public.listings
  add constraint listings_owner_id_fkey foreign key (owner_id)
  references public.profiles (id) on delete cascade;
alter table public.reports
  add constraint reports_reporter_id_fkey foreign key (reporter_id)
  references public.profiles (id) on delete cascade;
alter table public.user_moderation
  add constraint user_moderation_user_id_fkey foreign key (user_id)
  references public.profiles (id) on delete cascade;

-- ------------------------------------------------------------ dati privati separati
create or replace function public.short_public_name(p_full_name text)
returns text
language sql
immutable
as $$
  select case
    when position(' ' in btrim(p_full_name)) = 0 then btrim(p_full_name)
    else split_part(btrim(p_full_name), ' ', 1) || ' ' ||
         upper(left(split_part(btrim(p_full_name), ' ', 2), 1)) || '.'
  end;
$$;

create table public.profile_private (
  id text primary key references public.profiles (id) on delete cascade,
  full_name text not null check (char_length(btrim(full_name)) between 2 and 80),
  -- Decisioni D1 e M1: privata, serve solo al controllo dell'età e alle protezioni.
  birth_date date check (birth_date is null or birth_date >= date '1900-01-01'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.profile_private (id, full_name)
select p.id, p.full_name from public.profiles p;

alter table public.profiles drop column public_name;
alter table public.profiles drop column full_name;
alter table public.profiles add column public_name text;
update public.profiles p
set public_name = public.short_public_name(pp.full_name)
from public.profile_private pp
where pp.id = p.id;

create trigger profile_private_touch_updated_at
  before update on public.profile_private
  for each row execute function public.touch_updated_at();

-- Il nome pubblico abbreviato lo calcola solo il server dal nome completo privato.
create or replace function public.sync_public_name()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('nexus.internal', 'on', true);
  update public.profiles
  set public_name = public.short_public_name(new.full_name)
  where id = new.id;
  perform set_config('nexus.internal', 'off', true);
  return new;
end;
$$;

create trigger profile_private_sync_public_name
  after insert or update of full_name on public.profile_private
  for each row execute function public.sync_public_name();

-- ------------------------------------------------------------ amministrazione
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users where user_id = public.current_uid()
  );
$$;

drop trigger if exists profiles_protect_write on public.profiles;

create or replace function public.protect_profile_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('nexus.internal', true) = 'on' or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    -- Valori gestiti dal server: il client non può impostarli alla creazione.
    new.public_name := null;
    new.rating_avg := 0;
    new.rating_count := 0;
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;
  if new.id is distinct from old.id
     or new.public_name is distinct from old.public_name
     or new.rating_avg is distinct from old.rating_avg
     or new.rating_count is distinct from old.rating_count
     or new.created_at is distinct from old.created_at
     or new.account_type is distinct from old.account_type then
    raise exception 'Campi gestiti dal server' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger profiles_protect_write
  before insert or update on public.profiles
  for each row execute function public.protect_profile_write();

create or replace function public.protect_profile_private_write()
returns trigger
language plpgsql
as $$
begin
  if new.id is distinct from old.id or new.created_at is distinct from old.created_at then
    raise exception 'Campi non modificabili' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger profile_private_protect_write
  before update on public.profile_private
  for each row execute function public.protect_profile_private_write();

-- ------------------------------------------------------------ posizione (P9)
create type public.location_mode as enum ('approximate', 'precise');

alter table public.listings
  add column location_mode public.location_mode not null default 'approximate';

comment on column public.listings.approx_location is
  'Punto visibile agli altri utenti: zona approssimata (griglia ~550 m) oppure, in '
  'modalità precise, il punto scelto dall''autore per quell''annuncio.';

create or replace function public.public_point(
  p_exact extensions.geography,
  p_mode public.location_mode
)
returns extensions.geography
language sql
immutable
set search_path = public, extensions
as $$
  select case p_mode
    when 'precise' then p_exact
    else st_snapToGrid(p_exact::geometry, 0.005, 0.005)::extensions.geography
  end;
$$;

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
     or new.created_at is distinct from old.created_at then
    raise exception 'Campi non modificabili' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop function if exists public.create_listing(
  public.listing_kind, text, text, double precision, double precision, text,
  integer, text[], boolean, timestamptz
);

-- Unico modo per creare un annuncio. La posizione esatta resta privata; quella visibile
-- dipende dalla modalità scelta dall'autore (predefinita: approssimata).
create or replace function public.create_listing(
  p_kind public.listing_kind,
  p_title text,
  p_description text,
  p_lat double precision,
  p_lon double precision,
  p_category text default null,
  p_price_cents integer default null,
  p_photos text[] default '{}',
  p_available_now boolean default false,
  p_expires_at timestamptz default now() + interval '7 days',
  p_location_mode public.location_mode default 'approximate'
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := public.current_uid();
  v_exact extensions.geography;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;

  if p_lat is null or p_lon is null
     or p_lat not between -90 and 90
     or p_lon not between -180 and 180 then
    raise exception 'Posizione non valida' using errcode = '22023';
  end if;

  if p_expires_at > now() + interval '30 days' then
    raise exception 'Scadenza troppo lontana (massimo 30 giorni)' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.user_moderation m
    where m.user_id = v_uid and m.banned_until is not null and m.banned_until > now()
  ) then
    raise exception 'Account sospeso' using errcode = '42501';
  end if;

  v_exact := st_setsrid(st_makepoint(p_lon, p_lat), 4326)::extensions.geography;

  insert into public.listings (
    owner_id, kind, title, description, category, price_cents, photos,
    approx_location, location_mode, available_now, expires_at
  )
  values (
    v_uid, p_kind, btrim(p_title), coalesce(p_description, ''), p_category,
    p_price_cents, coalesce(p_photos, '{}'),
    public.public_point(v_exact, coalesce(p_location_mode, 'approximate')),
    coalesce(p_location_mode, 'approximate'), p_available_now, p_expires_at
  )
  returning id into v_id;

  insert into public.listing_locations (listing_id, exact_location)
  values (v_id, v_exact);

  return v_id;
end;
$$;

revoke all on function public.create_listing(
  public.listing_kind, text, text, double precision, double precision, text,
  integer, text[], boolean, timestamptz, public.location_mode
) from public, anon;
grant execute on function public.create_listing(
  public.listing_kind, text, text, double precision, double precision, text,
  integer, text[], boolean, timestamptz, public.location_mode
) to authenticated, service_role;

-- Cambio di modalità: solo l'autore (o un admin). Il punto visibile si ricalcola dal
-- punto esatto privato.
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
  v_exact extensions.geography;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select l.owner_id, ll.exact_location into v_owner, v_exact
  from public.listings l
  join public.listing_locations ll on ll.listing_id = l.id
  where l.id = p_listing_id;
  if v_owner is null or (v_owner <> v_uid and not public.is_admin()) then
    raise exception 'Annuncio non trovato o non tuo' using errcode = '42501';
  end if;
  perform set_config('nexus.internal', 'on', true);
  update public.listings
  set location_mode = p_mode,
      approx_location = public.public_point(v_exact, p_mode)
  where id = p_listing_id;
  perform set_config('nexus.internal', 'off', true);
end;
$$;

revoke all on function public.set_listing_location_mode(uuid, public.location_mode)
  from public, anon;
grant execute on function public.set_listing_location_mode(uuid, public.location_mode)
  to authenticated, service_role;

drop function if exists public.nearby_listings(
  double precision, double precision, integer, public.listing_kind, integer
);

-- Ricerca per distanza: filtra sulla posizione esatta, restituisce solo il punto visibile
-- (approssimato o preciso secondo la modalità dell'annuncio) e una fascia di distanza.
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
    and st_dwithin(ll.exact_location, o.g, least(greatest(p_radius_m, 1000), 30000))
    and (p_kind is null or l.kind = p_kind)
  order by ll.exact_location <-> o.g
  limit least(greatest(p_limit, 1), 200);
$$;

revoke all on function public.nearby_listings(
  double precision, double precision, integer, public.listing_kind, integer
) from public, anon;
grant execute on function public.nearby_listings(
  double precision, double precision, integer, public.listing_kind, integer
) to authenticated, service_role;

-- ------------------------------------------------------------ sicurezza a livello di riga
alter table public.profile_private enable row level security;

-- Policy restrittive: senza un token valido del progetto Firebase configurato,
-- nessuna tabella è accessibile, qualunque altra policy ci sia.
create policy "solo token del progetto Firebase" on public.profiles
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "solo token del progetto Firebase" on public.profile_private
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "solo token del progetto Firebase" on public.listings
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "solo token del progetto Firebase" on public.listing_locations
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "solo token del progetto Firebase" on public.reports
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "solo token del progetto Firebase" on public.user_moderation
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "solo token del progetto Firebase" on public.admin_users
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);

-- Profili pubblici: visibili agli utenti autenticati, modificabili solo dal proprietario.
create policy "profili pubblici visibili agli utenti"
  on public.profiles for select to authenticated using (true);
create policy "crea il proprio profilo"
  on public.profiles for insert to authenticated
  with check (id = public.current_uid());
create policy "aggiorna il proprio profilo"
  on public.profiles for update to authenticated
  using (id = public.current_uid()) with check (id = public.current_uid());

-- Dati privati: solo il proprietario (e gli admin in lettura).
create policy "legge i propri dati privati"
  on public.profile_private for select to authenticated
  using (id = public.current_uid() or public.is_admin());
create policy "crea i propri dati privati"
  on public.profile_private for insert to authenticated
  with check (id = public.current_uid());
create policy "aggiorna i propri dati privati"
  on public.profile_private for update to authenticated
  using (id = public.current_uid()) with check (id = public.current_uid());

-- Annunci.
create policy "annunci attivi visibili"
  on public.listings for select to authenticated
  using ((status = 'active' and expires_at > now()) or owner_id = public.current_uid());
create policy "aggiorna i propri annunci"
  on public.listings for update to authenticated
  using (owner_id = public.current_uid()) with check (owner_id = public.current_uid());
create policy "elimina i propri annunci"
  on public.listings for delete to authenticated
  using (owner_id = public.current_uid());

create policy "posizione esatta del proprietario"
  on public.listing_locations for select to authenticated
  using (
    exists (
      select 1 from public.listings l
      where l.id = listing_id and l.owner_id = public.current_uid()
    )
    or public.is_admin()
  );

-- Segnalazioni.
create policy "crea le proprie segnalazioni"
  on public.reports for insert to authenticated
  with check (reporter_id = public.current_uid());
create policy "legge le proprie segnalazioni o tutta la coda da admin"
  on public.reports for select to authenticated
  using (reporter_id = public.current_uid() or public.is_admin());
create policy "gli admin gestiscono le segnalazioni"
  on public.reports for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Moderazione.
create policy "leggi la propria moderazione"
  on public.user_moderation for select to authenticated
  using (user_id = public.current_uid() or public.is_admin());
create policy "gli admin gestiscono la moderazione"
  on public.user_moderation for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Elenco admin: ognuno vede solo la propria riga; si gestisce da SQL Editor.
create policy "leggi la propria riga admin"
  on public.admin_users for select to authenticated
  using (user_id = public.current_uid());

-- ------------------------------------------------------------ foto degli annunci
create policy "foto annunci: upload nella propria cartella"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = public.current_uid()
  );
create policy "foto annunci: modifica le proprie"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = public.current_uid()
  );
create policy "foto annunci: elimina le proprie"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = public.current_uid()
  );

-- Fase 6 · Blocco 1: Aziende (piano, Fase 6 «Aziende, promozioni e abbonamento").
--
-- - Registrazione Azienda: ragione sociale e partita IVA (già in business_private dalla 0003),
--   anche per chi ha creato l'account come Privato (diventa Azienda, solo se maggiorenne).
--   Documento facoltativo in un bucket privato: lo vedono solo l'azienda e gli amministratori.
-- - Profilo attività pubblico: insegna, categoria, descrizione, foto, indirizzo ufficiale completo
--   (via, civico, città, CAP, provincia), orari, telefono dell'attività, link per prenotare.
-- - Sede fissa: il punto sulla mappa si sceglie dall'indirizzo e cambia solo modificando la sede.
--   Non dipende mai dal GPS privato del titolare (che resta solo sul suo telefono).
-- - Verifica: la decide un amministratore (approva o rifiuta, con nota). Il badge «Verificato»
--   richiederà anche l'abbonamento attivo (Blocco 2): qui c'è solo la decisione.
-- Ragione sociale e partita IVA restano private (P4): in pubblico solo insegna e sede.

alter table public.business_private
  add column if not exists document_path text,
  add column if not exists review_note text check (review_note is null or char_length(review_note) <= 300),
  add column if not exists reviewed_at timestamptz,
  add column if not exists submitted_at timestamptz not null default now();

alter table public.business_private
  add constraint business_private_document_own check (
    document_path is null or document_path ~ ('^' || id || '/documento-[A-Za-z0-9]{8,40}\.(jpg|pdf)$')
  );

create or replace function private.valid_business_hours(p jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  k text;
  slots jsonb;
  s jsonb;
  v_prev integer;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    return false;
  end if;
  for k, slots in select * from jsonb_each(p) loop
    if k not in ('1', '2', '3', '4', '5', '6', '7') or jsonb_typeof(slots) <> 'array'
       or jsonb_array_length(slots) > 3 then
      return false;
    end if;
    v_prev := -1;
    for s in select * from jsonb_array_elements(slots) loop
      -- [apertura, chiusura] in minuti dalla mezzanotte; la chiusura può andare oltre la
      -- mezzanotte fino alle 6 (bar e locali serali).
      if jsonb_typeof(s) <> 'array' or jsonb_array_length(s) <> 2
         or jsonb_typeof(s -> 0) <> 'number' or jsonb_typeof(s -> 1) <> 'number'
         or (s ->> 0)::numeric <> floor((s ->> 0)::numeric)
         or (s ->> 1)::numeric <> floor((s ->> 1)::numeric)
         or (s ->> 0)::integer < 0 or (s ->> 0)::integer >= 1440
         or (s ->> 1)::integer <= (s ->> 0)::integer or (s ->> 1)::integer > 1800
         or (s ->> 0)::integer <= v_prev then
        return false;
      end if;
      v_prev := (s ->> 1)::integer;
    end loop;
  end loop;
  return true;
end;
$$;

-- Foto della pagina: solo file nella cartella dell'azienda.
create or replace function private.valid_business_photos(p_id text, p_photos text[])
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(bool_and(x ~ ('^' || p_id || '/foto-[A-Za-z0-9]{8,40}\.jpg$')), true)
  from unnest(p_photos) x;
$$;

create table public.business_pages (
  id text primary key references public.profiles (id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 2 and 80),
  category text not null check (category in (
    'ristorante', 'bar', 'alimentari', 'negozio', 'bellezza', 'salute', 'sport', 'casa',
    'auto', 'servizi', 'hotel', 'svago', 'altro')),
  description text check (description is null or char_length(description) <= 600),
  street text not null check (char_length(btrim(street)) between 2 and 100),
  civic text not null check (civic ~ '^[0-9]{1,5}( ?[A-Za-z]{1,3})?(/[0-9A-Za-z]{1,4})?$|^(snc|SNC|s\.n\.c\.)$'),
  city text not null check (char_length(btrim(city)) between 2 and 80),
  cap text not null check (cap ~ '^[0-9]{5}$'),
  province text not null check (province ~ '^[A-Z]{2}$'),
  -- Sede fissa in Italia (si cambia solo modificando la sede).
  lat double precision not null check (lat between 35.4 and 47.2),
  lng double precision not null check (lng between 6.6 and 18.6),
  phone text check (phone is null or phone ~ '^\+?[0-9 ]{6,20}$'),
  booking_url text check (booking_url is null or (booking_url ~ '^https://[^\s<>"]{3,300}$')),
  hours jsonb not null default '{}'::jsonb check (private.valid_business_hours(hours)),
  photos text[] not null default '{}' check (cardinality(photos) <= 6),
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint business_pages_photos_own check (private.valid_business_photos(id, photos))
);

create index business_pages_geo_idx on public.business_pages (lat, lng) where published;

create trigger business_pages_touch_updated_at
  before update on public.business_pages
  for each row execute function public.touch_updated_at();

alter table public.business_pages enable row level security;

create policy "solo token del progetto Firebase" on public.business_pages
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "pagine pubblicate, la mia e per gli admin"
  on public.business_pages for select to authenticated
  using (id = public.current_uid() or public.is_admin()
         or (published and not public.is_blocked_between(id, public.current_uid())));

revoke all on public.business_pages from anon, authenticated;
grant select on public.business_pages to authenticated;

-- ------------------------------------------------------------ registrazione
-- Chi è già Azienda può correggere ragione sociale e partita IVA: se cambiano dopo la
-- verifica, la verifica ricomincia.
create or replace function public.business_register(p_business_name text, p_vat_number text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_birth date;
  v_name text := btrim(coalesce(p_business_name, ''));
  v_vat text := replace(btrim(coalesce(p_vat_number, '')), ' ', '');
  v_old public.business_private;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select birth_date into v_birth from public.profile_private where id = v_uid;
  if v_birth is null then
    raise exception 'Profilo non trovato' using errcode = '42501';
  end if;
  if public.age_years(v_birth) < 18 then
    raise exception 'Account Azienda solo per maggiorenni' using errcode = '22023';
  end if;
  if char_length(v_name) not between 2 and 100 then
    raise exception 'Ragione sociale non valida' using errcode = '22023';
  end if;
  if not public.valid_partita_iva(v_vat) then
    raise exception 'Partita IVA non valida' using errcode = '22023';
  end if;
  if exists (select 1 from public.business_private b where b.vat_number = v_vat and b.id <> v_uid) then
    raise exception 'Questa partita IVA è già registrata su Piazly' using errcode = '23505';
  end if;
  select * into v_old from public.business_private where id = v_uid;
  perform set_config('nexus.internal', 'on', true);
  update public.profiles set account_type = 'business' where id = v_uid and account_type <> 'business';
  if v_old.id is null then
    insert into public.business_private (id, business_name, vat_number, status, submitted_at)
    values (v_uid, v_name, v_vat, 'pending', now());
  elsif v_old.business_name is distinct from v_name or v_old.vat_number is distinct from v_vat then
    update public.business_private
       set business_name = v_name, vat_number = v_vat, status = 'pending',
           review_note = null, reviewed_at = null, submitted_at = now()
     where id = v_uid;
  end if;
  perform set_config('nexus.internal', 'off', true);
end;
$$;

create or replace function public.business_set_document(p_path text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_path is not null and p_path !~ ('^' || v_uid || '/documento-[A-Za-z0-9]{8,40}\.(jpg|pdf)$') then
    raise exception 'Documento non valido' using errcode = '22023';
  end if;
  update public.business_private set document_path = p_path where id = v_uid;
  if not found then
    raise exception 'Registra prima l''azienda' using errcode = '22023';
  end if;
end;
$$;

-- I miei dati Azienda (privati) e la mia pagina, per la schermata «La mia attività».
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
    'page', (select to_jsonb(pg) - 'created_at' from public.business_pages pg where pg.id = b.id)
  ) end
  from (select public.current_uid() as uid) me
  left join public.business_private b on b.id = me.uid
  where me.uid is not null;
$$;

-- ------------------------------------------------------------ profilo attività
create or replace function public.business_page_save(
  p_display_name text,
  p_category text,
  p_description text,
  p_street text,
  p_civic text,
  p_city text,
  p_cap text,
  p_province text,
  p_lat double precision,
  p_lng double precision,
  p_phone text,
  p_booking_url text,
  p_hours jsonb,
  p_photos text[],
  p_published boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if not exists (select 1 from public.business_private where id = v_uid) then
    raise exception 'Registra prima l''azienda' using errcode = '22023';
  end if;
  if p_lat is null or p_lng is null or p_lat not between 35.4 and 47.2 or p_lng not between 6.6 and 18.6 then
    raise exception 'La sede deve essere in Italia' using errcode = '22023';
  end if;
  if p_hours is not null and not private.valid_business_hours(p_hours) then
    raise exception 'Orari non validi' using errcode = '22023';
  end if;
  insert into public.business_pages as bp (
    id, display_name, category, description, street, civic, city, cap, province, lat, lng,
    phone, booking_url, hours, photos, published)
  values (
    v_uid, btrim(p_display_name), p_category, nullif(btrim(coalesce(p_description, '')), ''),
    btrim(p_street), btrim(p_civic), btrim(p_city), btrim(p_cap), upper(btrim(p_province)),
    round(p_lat::numeric, 6)::double precision, round(p_lng::numeric, 6)::double precision,
    nullif(btrim(coalesce(p_phone, '')), ''), nullif(btrim(coalesce(p_booking_url, '')), ''),
    coalesce(p_hours, '{}'::jsonb), coalesce(p_photos, '{}'), coalesce(p_published, true))
  on conflict (id) do update set
    display_name = excluded.display_name, category = excluded.category,
    description = excluded.description, street = excluded.street, civic = excluded.civic,
    city = excluded.city, cap = excluded.cap, province = excluded.province,
    lat = excluded.lat, lng = excluded.lng, phone = excluded.phone,
    booking_url = excluded.booking_url, hours = excluded.hours, photos = excluded.photos,
    published = excluded.published;
end;
$$;

-- Scheda pubblica di un'attività (con la verifica decisa dall'admin).
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
    'mine', pg.id = public.current_uid())
  from public.business_pages pg
  join public.profiles p on p.id = pg.id
  join public.business_private b on b.id = pg.id
  where public.current_uid() is not null
    and pg.id = p_id
    and (pg.id = public.current_uid() or public.is_admin()
         or (pg.published and not public.is_blocked_between(pg.id, public.current_uid())));
$$;

-- Attività intorno a un punto (segnaposti fissi sulla Mappa), al massimo 50 km e 200 risultati.
create or replace function public.businesses_nearby(p_lat double precision, p_lng double precision, p_radius_km integer)
returns table (id text, display_name text, category text, lat double precision, lng double precision, verified boolean)
language sql
stable
security definer
set search_path = public
as $$
  select pg.id, pg.display_name, pg.category, pg.lat, pg.lng, b.status = 'verified'
  from public.business_pages pg
  join public.business_private b on b.id = pg.id
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

-- ------------------------------------------------------------ verifica (amministratori)
create or replace function public.business_review_queue()
returns table (
  id text, username text, business_name text, vat_number text, status public.business_status,
  has_document boolean, document_path text, display_name text, city text, province text,
  submitted_at timestamptz
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
         b.submitted_at
  from public.business_private b
  join public.profiles p on p.id = b.id
  left join public.business_pages pg on pg.id = b.id
  order by (b.status = 'pending') desc, b.submitted_at desc
  limit 200;
end;
$$;

create or replace function public.business_review(p_id text, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo per gli amministratori' using errcode = '42501';
  end if;
  if p_note is not null and char_length(p_note) > 300 then
    raise exception 'Nota troppo lunga' using errcode = '22023';
  end if;
  update public.business_private
     set status = case when p_approve then 'verified'::public.business_status else 'rejected' end,
         review_note = nullif(btrim(coalesce(p_note, '')), ''),
         reviewed_at = now()
   where id = p_id;
  if not found then
    raise exception 'Azienda non trovata' using errcode = '22023';
  end if;
end;
$$;

revoke all on function private.valid_business_hours(jsonb) from public, anon, authenticated;
revoke all on function private.valid_business_photos(text, text[]) from public, anon, authenticated;
revoke all on function public.business_register(text, text) from public, anon;
revoke all on function public.business_set_document(text) from public, anon;
revoke all on function public.business_mine() from public, anon;
revoke all on function public.business_page_save(text, text, text, text, text, text, text, text,
  double precision, double precision, text, text, jsonb, text[], boolean) from public, anon;
revoke all on function public.business_page_get(text) from public, anon;
revoke all on function public.businesses_nearby(double precision, double precision, integer) from public, anon;
revoke all on function public.business_review_queue() from public, anon;
revoke all on function public.business_review(text, boolean, text) from public, anon;
grant execute on function public.business_register(text, text) to authenticated;
grant execute on function public.business_set_document(text) to authenticated;
grant execute on function public.business_mine() to authenticated;
grant execute on function public.business_page_save(text, text, text, text, text, text, text, text,
  double precision, double precision, text, text, jsonb, text[], boolean) to authenticated;
grant execute on function public.business_page_get(text) to authenticated;
grant execute on function public.businesses_nearby(double precision, double precision, integer) to authenticated;
grant execute on function public.business_review_queue() to authenticated;
grant execute on function public.business_review(text, boolean, text) to authenticated;

-- ------------------------------------------------------------ foto e documenti
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('aziende', 'aziende', false, 5242880, array['image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('aziende_documenti', 'aziende_documenti', false, 10485760, array['image/jpeg', 'application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy "aziende: carico solo nella mia cartella"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'aziende' and public.current_uid() is not null
              and (storage.foldername(name))[1] = public.current_uid());
create policy "aziende: foto visibili a chi è collegato"
  on storage.objects for select to authenticated
  using (bucket_id = 'aziende' and public.current_uid() is not null);
create policy "aziende: cancello solo le mie"
  on storage.objects for delete to authenticated
  using (bucket_id = 'aziende' and (storage.foldername(name))[1] = public.current_uid());

create policy "documenti aziende: carico solo nella mia cartella"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'aziende_documenti' and public.current_uid() is not null
              and (storage.foldername(name))[1] = public.current_uid());
create policy "documenti aziende: solo io e gli amministratori"
  on storage.objects for select to authenticated
  using (bucket_id = 'aziende_documenti'
         and ((storage.foldername(name))[1] = public.current_uid() or public.is_admin()));
create policy "documenti aziende: cancello solo i miei"
  on storage.objects for delete to authenticated
  using (bucket_id = 'aziende_documenti' and (storage.foldername(name))[1] = public.current_uid());

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

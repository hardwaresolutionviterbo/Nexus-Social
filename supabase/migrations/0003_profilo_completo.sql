-- Piazly (ex Nexus Social) · Migrazione 0003 · Fase 2, Blocco 2: profilo completo
--
-- Come applicarla: SOLO con autorizzazione del titolare, dopo i test sul database temporaneo.
-- Supabase → SQL Editor → incolla tutto il file → Run. Presuppone 0001 e 0002 già applicate.
--
-- Cosa aggiunge:
--  1. Creazione del profilo solo tramite funzione: età minima 14 anni controllata dal server
--     (D1, M2), account Azienda solo per maggiorenni (M6, S4), @username normalizzato.
--  2. Bio e social con interruttori «Mostra nel profilo pubblico», accesi di partenza (P3);
--     il server nasconde ciò che l'utente ha spento (P2). Social solo come nome utente.
--  3. Foto profilo su Supabase Storage (S5): foto e miniatura nella cartella dell'utente,
--     leggibili solo dagli utenti autenticati (R2.10).
--  4. Dati Azienda (S4): ragione sociale e partita IVA private (P4: protette fino alla
--     decisione della Fase 6), stato «in verifica».
--  5. Scritture dirette sulle tabelle del profilo chiuse: si passa dalle funzioni.

-- ------------------------------------------------------------ controlli comuni
create or replace function public.age_years(p_birth date)
returns integer
language sql
stable
as $$
  select extract(year from age(current_date, p_birth))::integer;
$$;

-- Partita IVA italiana: 11 cifre con cifra di controllo.
create or replace function public.valid_partita_iva(p_vat text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_sum integer := 0;
  v_d integer;
begin
  if p_vat is null or p_vat !~ '^[0-9]{11}$' or p_vat = '00000000000' then
    return false;
  end if;
  for i in 1..10 loop
    v_d := substr(p_vat, i, 1)::integer;
    if i % 2 = 0 then
      v_d := v_d * 2;
      if v_d > 9 then
        v_d := v_d - 9;
      end if;
    end if;
    v_sum := v_sum + v_d;
  end loop;
  return (10 - v_sum % 10) % 10 = substr(p_vat, 11, 1)::integer;
end;
$$;

-- Social: solo reti note e solo il nome utente (niente link liberi).
create or replace function public.valid_social_links(p_links jsonb)
returns boolean
language sql
immutable
as $$
  select jsonb_typeof(p_links) = 'object'
    and not exists (
      select 1
      from jsonb_each(p_links) e
      where e.key not in ('instagram', 'tiktok', 'facebook', 'x', 'youtube', 'linkedin')
         or jsonb_typeof(e.value) <> 'string'
         or (e.value #>> '{}') !~ '^[A-Za-z0-9._-]{1,50}$'
    );
$$;

-- Nomi utente riservati, per evitare che qualcuno si spacci per l'app o per lo staff.
create or replace function public.username_reserved(p_username text)
returns boolean
language sql
immutable
as $$
  select lower(p_username) in (
    'admin', 'administrator', 'amministratore', 'piazly', 'nexus', 'nexussocial',
    'support', 'supporto', 'assistenza', 'help', 'aiuto', 'staff', 'moderatore',
    'moderator', 'official', 'ufficiale', 'root', 'system', 'sistema'
  ) or lower(p_username) like 'piazly%';
$$;

create or replace function public.normalize_username(p_username text)
returns text
language plpgsql
immutable
as $$
declare
  v text := lower(btrim(coalesce(p_username, '')));
begin
  if v ~ '^@' then
    v := substr(v, 2);
  end if;
  if v !~ '^[a-z0-9._]{3,24}$' or v ~ '^[.]' or v ~ '[.]$' or v ~ '[.][.]' then
    raise exception 'Nome utente non valido' using errcode = '22023';
  end if;
  if public.username_reserved(v) then
    raise exception 'Nome utente riservato' using errcode = '22023';
  end if;
  return v;
end;
$$;

-- ------------------------------------------------------------ nuove colonne del profilo
alter table public.profiles drop column if exists avatar_url;
alter table public.profiles
  add column avatar_path text,
  add column avatar_thumb_path text,
  add column show_bio boolean not null default true,
  add column show_social boolean not null default true;

alter table public.profiles
  add constraint profiles_social_links_valid check (public.valid_social_links(social_links)),
  add constraint profiles_avatar_path_own check (
    avatar_path is null
    or avatar_path ~ ('^' || id || '/avatar-[A-Za-z0-9]{8,40}\.jpg$')
  ),
  add constraint profiles_avatar_thumb_path_own check (
    avatar_thumb_path is null
    or avatar_thumb_path ~ ('^' || id || '/thumb-[A-Za-z0-9]{8,40}\.jpg$')
  );

-- Dati Azienda privati (S4, P4): ragione sociale e partita IVA visibili solo all'azienda e
-- all'admin fino alla decisione della Fase 6. Il badge lo assegna solo l'admin (Fase 7).
create type public.business_status as enum ('pending', 'verified', 'rejected');

create table public.business_private (
  id text primary key references public.profiles (id) on delete cascade,
  business_name text not null check (char_length(btrim(business_name)) between 2 and 100),
  vat_number text not null check (public.valid_partita_iva(vat_number)),
  status public.business_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger business_private_touch_updated_at
  before update on public.business_private
  for each row execute function public.touch_updated_at();

alter table public.business_private enable row level security;

create policy "solo token del progetto Firebase" on public.business_private
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "legge i propri dati azienda"
  on public.business_private for select to authenticated
  using (id = public.current_uid() or public.is_admin());

-- La data di nascita non si cambia dopo la creazione (eviterebbe il controllo dell'età).
create or replace function public.protect_profile_private_write()
returns trigger
language plpgsql
as $$
begin
  if current_setting('nexus.internal', true) = 'on' or public.is_admin() then
    return new;
  end if;
  if new.id is distinct from old.id
     or new.created_at is distinct from old.created_at
     or new.birth_date is distinct from old.birth_date then
    raise exception 'Campi non modificabili' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ------------------------------------------------------------ permessi sulle tabelle
-- Lettura diretta dei profili: solo colonne sempre pubbliche. Bio e social passano da
-- get_public_profile, che rispetta gli interruttori (P3).
revoke all on public.profiles from anon, authenticated;
grant select (id) on public.profiles to anon;
grant select (
  id, account_type, username, public_name, avatar_path, avatar_thumb_path,
  rating_avg, rating_count, created_at, updated_at
) on public.profiles to authenticated;

revoke insert, update, delete on public.profile_private from anon, authenticated;
revoke all on public.business_private from anon, authenticated;
grant select on public.business_private to authenticated;

-- ------------------------------------------------------------ funzioni del profilo
create or replace function public.username_available(p_username text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_name text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  begin
    v_name := public.normalize_username(p_username);
  exception when others then
    return false;
  end;
  return not exists (
    select 1 from public.profiles p where p.username = v_name and p.id <> v_uid
  );
end;
$$;

create or replace function public.create_my_profile(
  p_username text,
  p_full_name text,
  p_birth_date date,
  p_account_type public.account_type default 'private',
  p_business_name text default null,
  p_vat_number text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_name text;
  v_age integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'Profilo già creato' using errcode = '23505';
  end if;
  if p_birth_date is null or p_birth_date < date '1900-01-01' or p_birth_date > current_date then
    raise exception 'Data di nascita non valida' using errcode = '22023';
  end if;
  v_age := public.age_years(p_birth_date);
  if v_age < 14 then
    raise exception 'Età minima 14 anni' using errcode = '22023';
  end if;
  if coalesce(p_account_type, 'private') = 'business' then
    if v_age < 18 then
      raise exception 'Account Azienda solo per maggiorenni' using errcode = '22023';
    end if;
    if p_business_name is null or char_length(btrim(p_business_name)) not between 2 and 100 then
      raise exception 'Ragione sociale non valida' using errcode = '22023';
    end if;
    if not public.valid_partita_iva(btrim(coalesce(p_vat_number, ''))) then
      raise exception 'Partita IVA non valida' using errcode = '22023';
    end if;
  elsif p_business_name is not null or p_vat_number is not null then
    raise exception 'Dati Azienda solo per account Azienda' using errcode = '22023';
  end if;
  if p_full_name is null or char_length(btrim(p_full_name)) not between 2 and 80 then
    raise exception 'Nome e cognome non validi' using errcode = '22023';
  end if;
  v_name := public.normalize_username(p_username);

  perform set_config('nexus.internal', 'on', true);
  insert into public.profiles (id, username, account_type)
  values (v_uid, v_name, coalesce(p_account_type, 'private'));
  insert into public.profile_private (id, full_name, birth_date)
  values (v_uid, regexp_replace(btrim(p_full_name), '\s+', ' ', 'g'), p_birth_date);
  if p_account_type = 'business' then
    insert into public.business_private (id, business_name, vat_number)
    values (v_uid, btrim(p_business_name), btrim(p_vat_number));
  end if;
  perform set_config('nexus.internal', 'off', true);
end;
$$;

create or replace function public.update_my_profile(
  p_username text,
  p_full_name text,
  p_bio text,
  p_social_links jsonb,
  p_show_bio boolean,
  p_show_social boolean,
  p_business_name text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_type public.account_type;
  v_old_business text;
  v_bio text := nullif(btrim(coalesce(p_bio, '')), '');
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select p.account_type, bp.business_name into v_type, v_old_business
  from public.profiles p
  left join public.business_private bp on bp.id = p.id
  where p.id = v_uid;
  if v_type is null then
    raise exception 'Profilo non trovato' using errcode = '42501';
  end if;
  if v_bio is not null and char_length(v_bio) > 300 then
    raise exception 'Bio troppo lunga (massimo 300 caratteri)' using errcode = '22023';
  end if;
  if not public.valid_social_links(coalesce(p_social_links, '{}'::jsonb)) then
    raise exception 'Social non validi' using errcode = '22023';
  end if;
  if p_full_name is null or char_length(btrim(p_full_name)) not between 2 and 80 then
    raise exception 'Nome e cognome non validi' using errcode = '22023';
  end if;
  if v_type = 'business' then
    if p_business_name is null or char_length(btrim(p_business_name)) not between 2 and 100 then
      raise exception 'Ragione sociale non valida' using errcode = '22023';
    end if;
  elsif p_business_name is not null then
    raise exception 'Dati Azienda solo per account Azienda' using errcode = '22023';
  end if;

  update public.profiles
  set username = public.normalize_username(p_username),
      bio = v_bio,
      social_links = coalesce(p_social_links, '{}'::jsonb),
      show_bio = coalesce(p_show_bio, true),
      show_social = coalesce(p_show_social, true)
  where id = v_uid;

  update public.profile_private
  set full_name = regexp_replace(btrim(p_full_name), '\s+', ' ', 'g')
  where id = v_uid
    and full_name is distinct from regexp_replace(btrim(p_full_name), '\s+', ' ', 'g');

  -- Cambiare la ragione sociale rimette l'Azienda «in verifica».
  if v_type = 'business' and btrim(p_business_name) is distinct from v_old_business then
    update public.business_private
    set business_name = btrim(p_business_name), status = 'pending'
    where id = v_uid;
  end if;
end;
$$;

-- Collega foto e miniatura già caricate nella propria cartella (o le toglie con null).
create or replace function public.set_my_avatar(p_avatar_path text, p_thumb_path text)
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
  if (p_avatar_path is null) <> (p_thumb_path is null) then
    raise exception 'Servono sia la foto sia la miniatura' using errcode = '22023';
  end if;
  if p_avatar_path is not null then
    if p_avatar_path !~ ('^' || v_uid || '/avatar-[A-Za-z0-9]{8,40}\.jpg$')
       or p_thumb_path !~ ('^' || v_uid || '/thumb-[A-Za-z0-9]{8,40}\.jpg$') then
      raise exception 'Percorso della foto non valido' using errcode = '42501';
    end if;
    if (select count(*) from storage.objects o
        where o.bucket_id = 'avatars' and o.name in (p_avatar_path, p_thumb_path)) <> 2 then
      raise exception 'Foto non trovata' using errcode = '22023';
    end if;
  end if;
  update public.profiles
  set avatar_path = p_avatar_path, avatar_thumb_path = p_thumb_path
  where id = v_uid;
  if not found then
    raise exception 'Profilo non trovato' using errcode = '42501';
  end if;
end;
$$;

-- Profilo pubblico (R2.10): solo utenti autenticati; bio e social secondo gli interruttori.
-- Nessun dato aziendale (P4).
create or replace function public.get_public_profile(p_id text)
returns table (
  id text,
  account_type public.account_type,
  username text,
  public_name text,
  avatar_path text,
  avatar_thumb_path text,
  bio text,
  social_links jsonb,
  rating_avg numeric,
  rating_count integer,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.account_type,
    p.username::text,
    p.public_name,
    p.avatar_path,
    p.avatar_thumb_path,
    case when p.show_bio then p.bio end,
    case when p.show_social then p.social_links else '{}'::jsonb end,
    p.rating_avg,
    p.rating_count,
    p.created_at
  from public.profiles p
  where public.current_uid() is not null and p.id = p_id;
$$;

-- Il proprio profilo completo, dati privati compresi.
create or replace function public.get_my_profile()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'account_type', p.account_type,
    'username', p.username::text,
    'public_name', p.public_name,
    'business_name', bp.business_name,
    'avatar_path', p.avatar_path,
    'avatar_thumb_path', p.avatar_thumb_path,
    'bio', p.bio,
    'social_links', p.social_links,
    'show_bio', p.show_bio,
    'show_social', p.show_social,
    'full_name', pp.full_name,
    'birth_date', pp.birth_date,
    'vat_number', bp.vat_number,
    'business_status', bp.status
  )
  from public.profiles p
  join public.profile_private pp on pp.id = p.id
  left join public.business_private bp on bp.id = p.id
  where p.id = public.current_uid();
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.username_available(text)',
    'public.create_my_profile(text, text, date, public.account_type, text, text)',
    'public.update_my_profile(text, text, text, jsonb, boolean, boolean, text)',
    'public.set_my_avatar(text, text)',
    'public.get_public_profile(text)',
    'public.get_my_profile()'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

-- ------------------------------------------------------------ foto profilo (S5)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 1048576, array['image/jpeg'])
on conflict (id) do nothing;

create policy "foto profilo: lettura per utenti autenticati"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and public.current_uid() is not null);
create policy "foto profilo: upload nella propria cartella"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.current_uid()
  );
create policy "foto profilo: modifica le proprie"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.current_uid()
  );
create policy "foto profilo: elimina le proprie"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.current_uid()
  );

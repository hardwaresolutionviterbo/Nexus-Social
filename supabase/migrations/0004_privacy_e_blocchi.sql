-- Piazly · Migrazione 0004 · Fase 2, Blocco 3: impostazioni privacy e blocco degli utenti
--
-- Come applicarla: SOLO con autorizzazione del titolare, dopo i test sul database temporaneo.
-- Supabase → SQL Editor → incolla tutto il file → Run. Presuppone 0001-0003 già applicate.
--
-- Cosa aggiunge:
--  1. Impostazioni privacy dell'utente (pagina Privacy, R2.8): chi vede il numero (P5, P6:
--     di partenza «contatti riconosciuti dalla rubrica», oppure «nessuno»; agli sconosciuti
--     mai), «Permetti di trovarmi» (P8: spento finché non si attiva la rubrica, Blocco 5).
--  2. Blocco degli utenti (R2.7, P12), applicato dal server: chi è bloccato non vede più il
--     profilo né la foto di chi lo ha bloccato, e non viene avvisato. Gli altri effetti (chat,
--     chiamate, commenti, reazioni) usano public.is_blocked_between nelle fasi 4 e 5.

-- ------------------------------------------------------------ impostazioni privacy
create type public.phone_visibility as enum ('contacts', 'nobody');

create table public.privacy_settings (
  id text primary key references public.profiles (id) on delete cascade,
  phone_visibility public.phone_visibility not null default 'contacts',
  discoverable boolean not null default false,
  updated_at timestamptz not null default now()
);

create trigger privacy_settings_touch_updated_at
  before update on public.privacy_settings
  for each row execute function public.touch_updated_at();

alter table public.privacy_settings enable row level security;
create policy "solo token del progetto Firebase" on public.privacy_settings
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "legge le proprie impostazioni privacy"
  on public.privacy_settings for select to authenticated
  using (id = public.current_uid() or public.is_admin());

revoke all on public.privacy_settings from anon, authenticated;
grant select on public.privacy_settings to authenticated;

-- Righe di partenza per i profili già esistenti e per quelli nuovi.
insert into public.privacy_settings (id) select id from public.profiles
on conflict (id) do nothing;

create or replace function public.create_privacy_settings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.privacy_settings (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

create trigger profiles_create_privacy_settings
  after insert on public.profiles
  for each row execute function public.create_privacy_settings();

-- ------------------------------------------------------------ blocchi
create table public.user_blocks (
  blocker_id text not null references public.profiles (id) on delete cascade,
  blocked_id text not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

create index user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;
create policy "solo token del progetto Firebase" on public.user_blocks
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
-- Ognuno vede solo chi ha bloccato: chi è bloccato non lo scopre (P12).
create policy "legge i propri blocchi"
  on public.user_blocks for select to authenticated
  using (blocker_id = public.current_uid() or public.is_admin());

revoke all on public.user_blocks from anon, authenticated;
grant select on public.user_blocks to authenticated;

-- Vero se uno dei due ha bloccato l'altro. Serve alle fasi successive (chat, commenti).
create or replace function public.is_blocked_between(p_a text, p_b text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = p_a and b.blocked_id = p_b)
       or (b.blocker_id = p_b and b.blocked_id = p_a)
  );
$$;

-- Vero se il proprietario del profilo ha bloccato l'utente collegato.
create or replace function public.blocked_by(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_blocks b
    where b.blocker_id = p_owner and b.blocked_id = public.current_uid()
  );
$$;

revoke all on function public.is_blocked_between(text, text) from public, anon, authenticated;
grant execute on function public.is_blocked_between(text, text) to service_role;
revoke all on function public.blocked_by(text) from public, anon;
grant execute on function public.blocked_by(text) to authenticated, service_role;

-- Il profilo di chi ti ha bloccato non è più leggibile, nemmeno con letture dirette.
drop policy if exists "profili pubblici visibili agli utenti" on public.profiles;
create policy "profili pubblici visibili agli utenti"
  on public.profiles for select to authenticated
  using (id = public.current_uid() or not public.blocked_by(id));

-- Lo stesso per la foto profilo.
drop policy if exists "foto profilo: lettura per utenti autenticati" on storage.objects;
create policy "foto profilo: lettura per utenti autenticati"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and public.current_uid() is not null
    and not public.blocked_by((storage.foldername(name))[1])
  );

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
  where public.current_uid() is not null
    and p.id = p_id
    and not public.blocked_by(p.id);
$$;

-- ------------------------------------------------------------ funzioni della pagina Privacy
create or replace function public.get_my_privacy()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'phone_visibility', coalesce(s.phone_visibility, 'contacts'),
    'discoverable', coalesce(s.discoverable, false),
    'show_bio', p.show_bio,
    'show_social', p.show_social,
    'blocked_count', (select count(*) from public.user_blocks b where b.blocker_id = p.id)
  )
  from public.profiles p
  left join public.privacy_settings s on s.id = p.id
  where p.id = public.current_uid();
$$;

create or replace function public.set_phone_visibility(p_value public.phone_visibility)
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
  if p_value is null then
    raise exception 'Scelta non valida' using errcode = '22023';
  end if;
  insert into public.privacy_settings (id, phone_visibility)
  values (v_uid, p_value)
  on conflict (id) do update set phone_visibility = excluded.phone_visibility;
end;
$$;

-- Interruttori del profilo pubblico (P3), salvati uno per volta (P15).
create or replace function public.set_profile_visibility(p_show_bio boolean, p_show_social boolean)
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
  if p_show_bio is null or p_show_social is null then
    raise exception 'Scelta non valida' using errcode = '22023';
  end if;
  update public.profiles
  set show_bio = p_show_bio, show_social = p_show_social
  where id = v_uid;
  if not found then
    raise exception 'Profilo non trovato' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.block_user(p_user_id text)
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
  if p_user_id is null or p_user_id = v_uid then
    raise exception 'Non puoi bloccare te stesso' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Utente non trovato' using errcode = '22023';
  end if;
  if (select count(*) from public.user_blocks where blocker_id = v_uid) >= 5000 then
    raise exception 'Hai raggiunto il numero massimo di blocchi' using errcode = '22023';
  end if;
  insert into public.user_blocks (blocker_id, blocked_id)
  values (v_uid, p_user_id)
  on conflict do nothing;
end;
$$;

create or replace function public.unblock_user(p_user_id text)
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
  delete from public.user_blocks where blocker_id = v_uid and blocked_id = p_user_id;
end;
$$;

-- Elenco dei propri bloccati, con i soli dati pubblici.
create or replace function public.my_blocked_users()
returns table (
  id text,
  username text,
  public_name text,
  avatar_thumb_path text,
  blocked_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.username::text, p.public_name, p.avatar_thumb_path, b.created_at
  from public.user_blocks b
  join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = public.current_uid()
  order by b.created_at desc;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.get_public_profile(text)',
    'public.get_my_privacy()',
    'public.set_phone_visibility(public.phone_visibility)',
    'public.set_profile_visibility(boolean, boolean)',
    'public.block_user(text)',
    'public.unblock_user(text)',
    'public.my_blocked_users()'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

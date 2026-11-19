-- Fase 4 · Blocco 15: GPS in tempo reale (piano, Fase 3 «Mappa»), richiesta del titolare del 19/11/2026.
--
-- Spento di partenza. Chi lo accende sceglie le persone (tra quelle che ha in rubrica) e per quanto:
-- 15 minuti, 1 ora o 8 ore. Revocabile in ogni momento, anche per una sola persona. La posizione la
-- vedono solo le persone scelte, mai chi è bloccato. Quando la condivisione finisce l'ultima posizione
-- si cancella. Non è cifrata end-to-end: la proteggono le regole del server (lo dice l'app).

create table private.live_shares (
  owner_id text not null references public.profiles (id) on delete cascade,
  viewer_id text not null references public.profiles (id) on delete cascade,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (owner_id, viewer_id),
  check (owner_id <> viewer_id),
  check (expires_at <= started_at + interval '8 hours 1 minute')
);
create index live_shares_viewer_idx on private.live_shares (viewer_id, expires_at);

create table private.live_positions (
  user_id text primary key references public.profiles (id) on delete cascade,
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  accuracy real check (accuracy is null or accuracy between 0 and 100000),
  updated_at timestamptz not null default now()
);

revoke all on private.live_shares, private.live_positions from public, anon, authenticated;

-- Toglie condivisioni scadute e posizioni di chi non condivide più con nessuno.
create or replace function private.live_cleanup()
returns void
language sql
security definer
set search_path = public
as $$
  delete from private.live_shares where expires_at <= now();
  delete from private.live_positions p
  where not exists (select 1 from private.live_shares s where s.owner_id = p.user_id and s.expires_at > now());
$$;

revoke all on function private.live_cleanup() from public, anon, authenticated;

-- Accende (o rinnova) la condivisione per queste persone; le altre condivisioni attive restano.
create or replace function public.live_share_start(p_viewers text[], p_minutes integer)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_until timestamptz;
  v_bad integer;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_minutes is null or p_minutes not in (15, 60, 480) then
    raise exception 'Durata non valida' using errcode = '22023';
  end if;
  if coalesce(array_length(p_viewers, 1), 0) = 0 then
    raise exception 'Scegli almeno una persona' using errcode = '22023';
  end if;
  if array_length(p_viewers, 1) > 50 then
    raise exception 'Al massimo 50 persone' using errcode = '22023';
  end if;
  -- Solo persone che ho in rubrica e che non sono bloccate.
  select count(*) into v_bad
  from unnest(p_viewers) v
  where v is null or v = v_uid
     or not exists (select 1 from private.contact_links l
                    where l.owner_id = v_uid and l.contact_id = v and l.expires_at > now())
     or public.is_blocked_between(v_uid, v);
  if v_bad > 0 then
    raise exception 'Puoi condividere la posizione solo con chi hai in rubrica' using errcode = '22023';
  end if;
  perform private.live_cleanup();
  v_until := now() + make_interval(mins => p_minutes);
  insert into private.live_shares (owner_id, viewer_id, started_at, expires_at)
  select distinct v_uid, v, now(), v_until from unnest(p_viewers) v
  on conflict (owner_id, viewer_id) do update set started_at = excluded.started_at, expires_at = excluded.expires_at;
  return v_until;
end;
$$;

-- Smette di condividere con una persona (p_viewer) o con tutti (null). Se non resta nessuno,
-- l'ultima posizione si cancella subito.
create or replace function public.live_share_stop(p_viewer text default null)
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
  delete from private.live_shares s where s.owner_id = v_uid and (p_viewer is null or s.viewer_id = p_viewer);
  perform private.live_cleanup();
end;
$$;

-- Nuova posizione: accettata solo se sto condividendo con qualcuno; al massimo una ogni 5 secondi.
create or replace function public.live_update(p_lat double precision, p_lng double precision, p_accuracy real)
returns boolean
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
  if not exists (select 1 from private.live_shares s where s.owner_id = v_uid and s.expires_at > now()) then
    delete from private.live_positions where user_id = v_uid;
    return false;
  end if;
  insert into private.live_positions as p (user_id, lat, lng, accuracy, updated_at)
  values (v_uid, p_lat, p_lng, p_accuracy, now())
  on conflict (user_id) do update
    set lat = excluded.lat, lng = excluded.lng, accuracy = excluded.accuracy, updated_at = now()
    where p.updated_at < now() - interval '5 seconds';
  return true;
end;
$$;

-- Con chi sto condividendo, e fino a quando.
create or replace function public.live_my_shares()
returns table (viewer_id text, username text, public_name text, avatar_thumb_path text,
               started_at timestamptz, expires_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select s.viewer_id, p.username::text, p.public_name, p.avatar_thumb_path, s.started_at, s.expires_at
  from private.live_shares s
  join public.profiles p on p.id = s.viewer_id
  where s.owner_id = public.current_uid() and s.expires_at > now()
  order by p.public_name;
$$;

-- Chi sta condividendo la posizione con me: solo condivisioni attive, mai tra persone bloccate.
-- Prima toglie le condivisioni scadute e le loro ultime posizioni (di tutti).
create or replace function public.live_visible()
returns table (user_id text, username text, public_name text, avatar_thumb_path text,
               lat double precision, lng double precision, accuracy real,
               updated_at timestamptz, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.live_cleanup();
  return query
  select s.owner_id, p.username::text, p.public_name, p.avatar_thumb_path,
         l.lat, l.lng, l.accuracy, l.updated_at, s.expires_at
  from private.live_shares s
  join private.live_positions l on l.user_id = s.owner_id
  join public.profiles p on p.id = s.owner_id
  where s.viewer_id = public.current_uid()
    and s.expires_at > now()
    and not public.is_blocked_between(s.owner_id, s.viewer_id);
end;
$$;

-- Chi blocca qualcuno smette subito di condividere con lui (e viceversa).
create or replace function private.live_on_block()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from private.live_shares s
  where (s.owner_id = new.blocker_id and s.viewer_id = new.blocked_id)
     or (s.owner_id = new.blocked_id and s.viewer_id = new.blocker_id);
  perform private.live_cleanup();
  return new;
end;
$$;

revoke all on function private.live_on_block() from public, anon, authenticated;

create trigger live_on_block after insert on public.user_blocks
  for each row execute function private.live_on_block();

revoke all on function public.live_share_start(text[], integer) from public, anon;
revoke all on function public.live_share_stop(text) from public, anon;
revoke all on function public.live_update(double precision, double precision, real) from public, anon;
revoke all on function public.live_my_shares() from public, anon;
revoke all on function public.live_visible() from public, anon;
grant execute on function public.live_share_start(text[], integer) to authenticated;
grant execute on function public.live_share_stop(text) to authenticated;
grant execute on function public.live_update(double precision, double precision, real) to authenticated;
grant execute on function public.live_my_shares() to authenticated;
grant execute on function public.live_visible() to authenticated;

select private.align_anon_with_authenticated();

-- Fase 4 · Blocco 13: Stati (aggiornamenti di 24 ore), come su WhatsApp.
--
-- Testo su sfondo colorato, foto o video breve. Chi pubblica sceglie chi lo vede:
--   «contatti»: le persone che ha in rubrica;
--   «tranne»:   le persone in rubrica tranne alcune;
--   «solo»:     solo alcune persone scelte.
-- Le regole le applica il server: nessuno può leggere uno stato che non è per lui, nemmeno
-- chiedendo il file direttamente. Uno stato dura 24 ore. Chi l'ha pubblicato vede chi l'ha
-- visto. Gli stati non sono cifrati end-to-end come le chat: lo dice anche l'app.

create table public.statuses (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('testo', 'foto', 'video')),
  body text not null default '' check (char_length(body) <= 700),
  color smallint not null default 0 check (color between 0 and 7),
  media_path text,
  audience text not null default 'contatti' check (audience in ('contatti', 'tranne', 'solo')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  check ((kind = 'testo' and media_path is null and char_length(btrim(body)) > 0)
         or (kind <> 'testo' and media_path is not null))
);
create index statuses_user_idx on public.statuses (user_id, expires_at);

create table public.status_audience (
  status_id uuid not null references public.statuses (id) on delete cascade,
  user_id text not null,
  primary key (status_id, user_id)
);

create table public.status_views (
  status_id uuid not null references public.statuses (id) on delete cascade,
  viewer_id text not null,
  seen_at timestamptz not null default now(),
  primary key (status_id, viewer_id)
);

alter table public.statuses enable row level security;
alter table public.status_audience enable row level security;
alter table public.status_views enable row level security;
revoke all on public.statuses, public.status_audience, public.status_views from public, anon, authenticated;

-- Lo stato è per questa persona?
create or replace function private.status_visible(p_status public.statuses, p_viewer text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_viewer is not null and (
    p_status.user_id = p_viewer
    or (
      p_status.expires_at > now()
      and exists (select 1 from private.contact_links l
                  where l.owner_id = p_status.user_id and l.contact_id = p_viewer and l.expires_at > now())
      and not public.is_blocked_between(p_status.user_id, p_viewer)
      and case p_status.audience
            when 'contatti' then true
            when 'tranne' then not exists (select 1 from public.status_audience a
                                           where a.status_id = p_status.id and a.user_id = p_viewer)
            else exists (select 1 from public.status_audience a
                         where a.status_id = p_status.id and a.user_id = p_viewer)
          end
    )
  );
$$;

revoke all on function private.status_visible(public.statuses, text) from public, anon, authenticated;

create or replace function public.status_create(
  p_kind text,
  p_body text,
  p_color integer,
  p_media_path text,
  p_audience text,
  p_people text[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_media_path is not null and (p_media_path not like v_uid || '/%' or p_media_path like '%..%'
                                   or char_length(p_media_path) > 200) then
    raise exception 'File non valido' using errcode = '22023';
  end if;
  if coalesce(array_length(p_people, 1), 0) > 500 then
    raise exception 'Al massimo 500 persone' using errcode = '22023';
  end if;
  if p_audience is null or p_audience not in ('contatti', 'tranne', 'solo') then
    raise exception 'Scelta non valida' using errcode = '22023';
  end if;
  if p_audience = 'solo' and coalesce(array_length(p_people, 1), 0) = 0 then
    raise exception 'Scegli almeno una persona' using errcode = '22023';
  end if;
  if (select count(*) from public.statuses s where s.user_id = v_uid and s.created_at > now() - interval '1 day') >= 30 then
    raise exception 'Al massimo 30 stati al giorno' using errcode = '54000';
  end if;
  insert into public.statuses (user_id, kind, body, color, media_path, audience)
  values (v_uid, p_kind, coalesce(p_body, ''), coalesce(p_color, 0), p_media_path, p_audience)
  returning id into v_id;
  if p_audience <> 'contatti' then
    insert into public.status_audience (status_id, user_id)
    select distinct v_id, u from unnest(p_people) u where u is not null and u <> v_uid;
  end if;
  return v_id;
end;
$$;

-- Stati da vedere (dei contatti, non scaduti) e i miei, con «già visto».
create or replace function public.status_feed()
returns table (id uuid, user_id text, username text, public_name text, avatar_thumb_path text,
               kind text, body text, color smallint, media_path text, created_at timestamptz,
               expires_at timestamptz, seen boolean, mine boolean, views integer)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.user_id, p.username::text, p.public_name, p.avatar_thumb_path, s.kind, s.body, s.color,
         s.media_path, s.created_at, s.expires_at,
         exists (select 1 from public.status_views v where v.status_id = s.id and v.viewer_id = public.current_uid()),
         s.user_id = public.current_uid(),
         case when s.user_id = public.current_uid()
              then (select count(*) from public.status_views v where v.status_id = s.id)::integer else 0 end
  from public.statuses s
  join public.profiles p on p.id = s.user_id
  where s.expires_at > now() and private.status_visible(s, public.current_uid())
  order by s.user_id, s.created_at;
$$;

create or replace function public.status_seen(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_status public.statuses;
begin
  select * into v_status from public.statuses where id = p_id;
  if v_status.id is null or not private.status_visible(v_status, v_uid) then
    raise exception 'Stato non trovato' using errcode = '42501';
  end if;
  if v_status.user_id <> v_uid then
    insert into public.status_views (status_id, viewer_id) values (p_id, v_uid) on conflict do nothing;
  end if;
end;
$$;

-- Chi ha visto il mio stato.
create or replace function public.status_viewers(p_id uuid)
returns table (user_id text, username text, public_name text, avatar_thumb_path text, seen_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select v.viewer_id, p.username::text, p.public_name, p.avatar_thumb_path, v.seen_at
  from public.status_views v
  join public.statuses s on s.id = v.status_id and s.user_id = public.current_uid()
  join public.profiles p on p.id = v.viewer_id
  where v.status_id = p_id
  order by v.seen_at desc;
$$;

-- Cancella un mio stato; restituisce il file da togliere.
create or replace function public.status_delete(p_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_path text;
begin
  delete from public.statuses s where s.id = p_id and s.user_id = public.current_uid()
  returning s.media_path into v_path;
  return v_path;
end;
$$;

-- Miei stati scaduti: si cancellano e si restituiscono i file da togliere (lo fa l'app).
create or replace function public.status_cleanup()
returns table (media_path text)
language sql
security definer
set search_path = public
as $$
  delete from public.statuses s
  where s.user_id = public.current_uid() and s.expires_at <= now()
  returning s.media_path;
$$;

revoke all on function public.status_create(text, text, integer, text, text, text[]) from public, anon;
revoke all on function public.status_feed() from public, anon;
revoke all on function public.status_seen(uuid) from public, anon;
revoke all on function public.status_viewers(uuid) from public, anon;
revoke all on function public.status_delete(uuid) from public, anon;
revoke all on function public.status_cleanup() from public, anon;
grant execute on function public.status_create(text, text, integer, text, text, text[]) to authenticated;
grant execute on function public.status_feed() to authenticated;
grant execute on function public.status_seen(uuid) to authenticated;
grant execute on function public.status_viewers(uuid) to authenticated;
grant execute on function public.status_delete(uuid) to authenticated;
grant execute on function public.status_cleanup() to authenticated;

-- File degli stati: si caricano solo nella propria cartella; li apre chi può vedere lo stato.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('stati', 'stati', false, 16777216, array['image/jpeg', 'video/mp4'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.status_media_visible(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.statuses s
                 where s.media_path = p_name and private.status_visible(s, public.current_uid()));
$$;

revoke all on function public.status_media_visible(text) from public, anon;
grant execute on function public.status_media_visible(text) to authenticated;

create policy "stati: carico solo nella mia cartella"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'stati' and public.current_uid() is not null
              and (storage.foldername(name))[1] = public.current_uid());

create policy "stati: li apre chi può vedere lo stato"
  on storage.objects for select to authenticated
  using (bucket_id = 'stati' and ((storage.foldername(name))[1] = public.current_uid()
                                  or public.status_media_visible(name)));

create policy "stati: cancello solo i miei"
  on storage.objects for delete to authenticated
  using (bucket_id = 'stati' and (storage.foldername(name))[1] = public.current_uid());

select private.align_anon_with_authenticated();

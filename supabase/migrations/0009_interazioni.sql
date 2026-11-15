-- Piazly · Fase 3, Blocco 4: eventi di gruppo e interazioni come Facebook.
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Decisioni del titolare (docs/fase3/PIANO_OPERATIVO.md, sezione 3.1):
--  • eventi: «Partecipo» con conteggio e «mancano N persone» (R3.12);
--  • Mi piace / Non mi piace sotto ogni annuncio, una reazione per persona, elenchi di chi ha
--    reagito; commenti con risposte (un livello, come Facebook); Mi piace sui commenti;
--  • notifiche: all'autore per i Mi piace (mai per i Non mi piace) e per i commenti; a chi
--    commenta il post (che da quel momento lo segue) per i commenti e le risposte successive;
--    all'autore di un commento per le risposte e per i Mi piace al suo commento;
--    «Disattiva notifiche per questo post»; Mi piace ravvicinati raggruppati; mai notifiche
--    per le proprie azioni né tra persone bloccate;
--  • P12: chi è bloccato non commenta, non reagisce, non partecipa e non vede reazioni,
--    commenti e partecipanti dell'altro.
--
-- Tabelle senza accesso diretto: tutto passa dalle funzioni qui sotto.

-- ------------------------------------------------------------ eventi di gruppo
alter table public.listings
  add column group_spots integer
  check (group_spots is null or group_spots between 1 and 50);

comment on column public.listings.group_spots is
  'Evento di gruppo: persone cercate oltre all''autore. Null = annuncio semplice.';

create table public.listing_participants (
  listing_id uuid not null references public.listings (id) on delete cascade,
  user_id text not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (listing_id, user_id)
);

-- ------------------------------------------------------------ reazioni e commenti
create table public.listing_reactions (
  listing_id uuid not null references public.listings (id) on delete cascade,
  user_id text not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('like', 'dislike')),
  created_at timestamptz not null default now(),
  primary key (listing_id, user_id)
);

create table public.listing_comments (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  author_id text not null references public.profiles (id) on delete cascade,
  parent_id uuid references public.listing_comments (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index listing_comments_listing_idx on public.listing_comments (listing_id, created_at);

create table public.comment_likes (
  comment_id uuid not null references public.listing_comments (id) on delete cascade,
  user_id text not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

-- Chi segue un post (chi ha commentato) e chi ha disattivato le notifiche di quel post.
create table public.listing_follows (
  listing_id uuid not null references public.listings (id) on delete cascade,
  user_id text not null references public.profiles (id) on delete cascade,
  following boolean not null default true,
  muted boolean not null default false,
  primary key (listing_id, user_id)
);

-- ------------------------------------------------------------ notifiche
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id text not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in (
    'listing_like', 'listing_comment', 'comment_reply', 'followed_comment', 'comment_like'
  )),
  listing_id uuid not null references public.listings (id) on delete cascade,
  comment_id uuid references public.listing_comments (id) on delete cascade,
  actor_id text not null references public.profiles (id) on delete cascade,
  -- Mi piace raggruppati: quante persone in tutto per questa notifica.
  actor_count integer not null default 1 check (actor_count >= 1),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);

do $$
declare
  t text;
begin
  foreach t in array array[
    'listing_participants', 'listing_reactions', 'listing_comments', 'comment_likes',
    'listing_follows', 'notifications'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end;
$$;

-- ------------------------------------------------------------ aiuti interni
-- Annuncio attivo e visibile a chi chiama (non bloccato); restituisce l'autore.
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
    and l.kind = 'social'
    and l.status = 'active'
    and l.expires_at > now()
    and not public.hidden_by_block(l.owner_id);
  if v_owner is null then
    raise exception 'Annuncio non trovato' using errcode = '42501';
  end if;
  return v_owner;
end;
$$;

-- Avvisa [p_recipient] se non è chi agisce, non ha disattivato il post e non c'è un blocco.
-- I Mi piace non letti dello stesso tipo sullo stesso oggetto si raggruppano.
create or replace function private.notify(
  p_recipient text,
  p_kind text,
  p_listing uuid,
  p_comment uuid,
  p_actor text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_recipient is null or p_recipient = p_actor
     or public.is_blocked_between(p_recipient, p_actor)
     or exists (
       select 1 from public.listing_follows f
       where f.listing_id = p_listing and f.user_id = p_recipient and f.muted
     ) then
    return;
  end if;
  if p_kind in ('listing_like', 'comment_like') then
    select n.id into v_id
    from public.notifications n
    where n.recipient_id = p_recipient and n.kind = p_kind and n.listing_id = p_listing
      and n.comment_id is not distinct from p_comment and n.read_at is null
    limit 1;
    if v_id is not null then
      update public.notifications
      set actor_id = p_actor, actor_count = actor_count + 1, created_at = now()
      where id = v_id;
      return;
    end if;
  end if;
  insert into public.notifications (recipient_id, kind, listing_id, comment_id, actor_id)
  values (p_recipient, p_kind, p_listing, p_comment, p_actor);
end;
$$;

revoke all on function private.visible_listing_owner(uuid) from public, anon, authenticated;
revoke all on function private.notify(text, text, uuid, uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------ pubblicazione con eventi
drop function if exists public.publish_map_listing(
  text, text, double precision, double precision, public.location_mode, timestamptz, text[]
);

create function public.publish_map_listing(
  p_title text,
  p_details text,
  p_lat double precision,
  p_lon double precision,
  p_location_mode public.location_mode,
  p_expires_at timestamptz,
  p_photos text[] default '{}',
  p_group_spots integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
begin
  if public.current_uid() is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_location_mode is null then
    raise exception 'Scegli dove mostrare l''annuncio' using errcode = '22023';
  end if;
  if p_group_spots is not null and p_group_spots not between 1 and 50 then
    raise exception 'Persone cercate: da 1 a 50' using errcode = '22023';
  end if;
  perform private.check_map_listing(p_title, p_details, p_expires_at, p_photos);
  v_id := public.create_listing(
    'social', p_title, coalesce(p_details, ''), p_lat, p_lon, 'libera', null,
    coalesce(p_photos, '{}'), false, p_expires_at, p_location_mode
  );
  update public.listings set group_spots = p_group_spots where id = v_id;
  return v_id;
end;
$$;

drop function if exists public.update_my_listing(uuid, text, text, timestamptz, text[]);

create function public.update_my_listing(
  p_id uuid,
  p_title text,
  p_details text,
  p_expires_at timestamptz,
  p_photos text[] default '{}',
  p_group_spots integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_taken integer;
begin
  perform private.my_active_listing(p_id);
  perform private.check_map_listing(p_title, p_details, p_expires_at, p_photos);
  select count(*) into v_taken from public.listing_participants where listing_id = p_id;
  if p_group_spots is not null and (p_group_spots not between 1 and 50 or p_group_spots < v_taken) then
    raise exception 'Persone cercate: da 1 a 50 e non meno di chi partecipa già' using errcode = '22023';
  end if;
  if p_group_spots is null and v_taken > 0 then
    raise exception 'Ci sono già partecipanti: l''evento non si può togliere' using errcode = '22023';
  end if;
  update public.listings
  set title = btrim(p_title),
      description = coalesce(p_details, ''),
      expires_at = p_expires_at,
      photos = coalesce(p_photos, '{}'),
      group_spots = p_group_spots
  where id = p_id;
end;
$$;

-- ------------------------------------------------------------ partecipare
create or replace function public.join_listing(p_listing uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_owner text := private.visible_listing_owner(p_listing);
  v_spots integer;
  v_taken integer;
begin
  if v_owner = v_uid then
    raise exception 'È il tuo annuncio' using errcode = '22023';
  end if;
  select group_spots into v_spots from public.listings where id = p_listing for update;
  if v_spots is null then
    raise exception 'Non è un evento di gruppo' using errcode = '22023';
  end if;
  if exists (select 1 from public.listing_participants where listing_id = p_listing and user_id = v_uid) then
    return;
  end if;
  select count(*) into v_taken from public.listing_participants where listing_id = p_listing;
  if v_taken >= v_spots then
    raise exception 'Evento al completo' using errcode = '22023';
  end if;
  insert into public.listing_participants (listing_id, user_id) values (p_listing, v_uid);
end;
$$;

create or replace function public.leave_listing(p_listing uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_uid() is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  delete from public.listing_participants
  where listing_id = p_listing and user_id = public.current_uid();
end;
$$;

-- ------------------------------------------------------------ reazioni
create or replace function public.set_listing_reaction(p_listing uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_owner text := private.visible_listing_owner(p_listing);
  v_before text;
begin
  if p_kind is not null and p_kind not in ('like', 'dislike') then
    raise exception 'Reazione non valida' using errcode = '22023';
  end if;
  select kind into v_before from public.listing_reactions
  where listing_id = p_listing and user_id = v_uid;
  if p_kind is null then
    delete from public.listing_reactions where listing_id = p_listing and user_id = v_uid;
    return;
  end if;
  insert into public.listing_reactions (listing_id, user_id, kind)
  values (p_listing, v_uid, p_kind)
  on conflict (listing_id, user_id) do update set kind = excluded.kind, created_at = now();
  -- Solo i Mi piace avvisano l'autore (mai i Non mi piace), una volta per persona.
  if p_kind = 'like' and v_before is distinct from 'like' then
    perform private.notify(v_owner, 'listing_like', p_listing, null, v_uid);
  end if;
end;
$$;

-- ------------------------------------------------------------ commenti
create or replace function public.add_listing_comment(
  p_listing uuid,
  p_body text,
  p_parent uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_owner text := private.visible_listing_owner(p_listing);
  v_parent_author text;
  v_parent_parent uuid;
  v_id uuid;
  r record;
begin
  if char_length(btrim(coalesce(p_body, ''))) not between 1 and 1000 then
    raise exception 'Il commento deve avere da 1 a 1000 caratteri' using errcode = '22023';
  end if;
  if p_parent is not null then
    select c.author_id, c.parent_id into v_parent_author, v_parent_parent
    from public.listing_comments c
    where c.id = p_parent and c.listing_id = p_listing;
    if v_parent_author is null or public.is_blocked_between(v_parent_author, v_uid) then
      raise exception 'Commento non trovato' using errcode = '42501';
    end if;
    -- Un solo livello di risposte, come Facebook: si risponde al commento principale.
    if v_parent_parent is not null then
      p_parent := v_parent_parent;
    end if;
  end if;

  insert into public.listing_comments (listing_id, author_id, parent_id, body)
  values (p_listing, v_uid, p_parent, btrim(p_body))
  returning id into v_id;

  -- Chi commenta segue il post (senza cambiare un'eventuale disattivazione).
  insert into public.listing_follows (listing_id, user_id) values (p_listing, v_uid)
  on conflict (listing_id, user_id) do update set following = true;

  -- Autore dell'annuncio.
  perform private.notify(v_owner, 'listing_comment', p_listing, v_id, v_uid);
  -- Autore del commento a cui si risponde.
  if p_parent is not null and v_parent_author is distinct from v_owner then
    perform private.notify(v_parent_author, 'comment_reply', p_listing, v_id, v_uid);
  end if;
  -- Chi segue il post, esclusi quelli già avvisati qui sopra.
  for r in
    select f.user_id from public.listing_follows f
    where f.listing_id = p_listing and f.following and not f.muted
      and f.user_id <> v_uid and f.user_id <> v_owner
      and f.user_id is distinct from v_parent_author
  loop
    perform private.notify(r.user_id, 'followed_comment', p_listing, v_id, v_uid);
  end loop;
  return v_id;
end;
$$;

create or replace function public.delete_my_comment(p_comment uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  -- L'autore del commento o l'autore dell'annuncio.
  delete from public.listing_comments c
  using public.listings l
  where c.id = p_comment and l.id = c.listing_id
    and (c.author_id = v_uid or l.owner_id = v_uid);
  if not found then
    raise exception 'Commento non trovato o non tuo' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.set_comment_like(p_comment uuid, p_like boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_listing uuid;
  v_author text;
  v_new integer;
begin
  select c.listing_id, c.author_id into v_listing, v_author
  from public.listing_comments c where c.id = p_comment;
  if v_listing is null or public.is_blocked_between(v_author, coalesce(v_uid, '')) then
    raise exception 'Commento non trovato' using errcode = '42501';
  end if;
  perform private.visible_listing_owner(v_listing);
  if coalesce(p_like, false) then
    insert into public.comment_likes (comment_id, user_id) values (p_comment, v_uid)
    on conflict do nothing;
    get diagnostics v_new = row_count;
    if v_new > 0 then
      perform private.notify(v_author, 'comment_like', v_listing, p_comment, v_uid);
    end if;
  else
    delete from public.comment_likes where comment_id = p_comment and user_id = v_uid;
  end if;
end;
$$;

-- ------------------------------------------------------------ notifiche di un post
create or replace function public.set_listing_muted(p_listing uuid, p_muted boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_owner text := private.visible_listing_owner(p_listing);
begin
  insert into public.listing_follows (listing_id, user_id, following, muted)
  values (p_listing, v_uid, v_owner = v_uid, coalesce(p_muted, false))
  on conflict (listing_id, user_id) do update set muted = excluded.muted;
end;
$$;

-- ------------------------------------------------------------ letture
create or replace function public.listing_social(p_listing uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_owner text := private.visible_listing_owner(p_listing);
begin
  return (
    select jsonb_build_object(
      'likes', (select count(*) from public.listing_reactions r
                where r.listing_id = p_listing and r.kind = 'like'
                  and not public.is_blocked_between(r.user_id, v_uid)),
      'dislikes', (select count(*) from public.listing_reactions r
                   where r.listing_id = p_listing and r.kind = 'dislike'
                     and not public.is_blocked_between(r.user_id, v_uid)),
      'comments', (select count(*) from public.listing_comments c
                   where c.listing_id = p_listing
                     and not public.is_blocked_between(c.author_id, v_uid)),
      'participants', (select count(*) from public.listing_participants p
                       where p.listing_id = p_listing),
      'group_spots', l.group_spots,
      'my_reaction', (select r.kind from public.listing_reactions r
                      where r.listing_id = p_listing and r.user_id = v_uid),
      'i_participate', exists (select 1 from public.listing_participants p
                               where p.listing_id = p_listing and p.user_id = v_uid),
      'following', v_owner = v_uid or exists (
        select 1 from public.listing_follows f
        where f.listing_id = p_listing and f.user_id = v_uid and f.following),
      'muted', exists (select 1 from public.listing_follows f
                       where f.listing_id = p_listing and f.user_id = v_uid and f.muted)
    )
    from public.listings l where l.id = p_listing
  );
end;
$$;

-- Chi ha reagito ('like' o 'dislike') o chi partecipa ('participant'): profilo essenziale.
create or replace function public.listing_people(p_listing uuid, p_what text)
returns table (
  user_id text,
  username text,
  public_name text,
  avatar_thumb_path text,
  reacted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  perform private.visible_listing_owner(p_listing);
  if p_what not in ('like', 'dislike', 'participant') then
    raise exception 'Elenco non valido' using errcode = '22023';
  end if;
  return query
    select p.id, p.username::text, p.public_name, p.avatar_thumb_path, x.ts
    from (
      select r.user_id as uid, r.created_at as ts from public.listing_reactions r
      where p_what in ('like', 'dislike') and r.listing_id = p_listing and r.kind = p_what
      union all
      select pp.user_id, pp.created_at from public.listing_participants pp
      where p_what = 'participant' and pp.listing_id = p_listing
    ) x
    join public.profiles p on p.id = x.uid
    where not public.is_blocked_between(p.id, v_uid)
    order by x.ts desc
    limit 500;
end;
$$;

create or replace function public.listing_comments_list(p_listing uuid)
returns table (
  id uuid,
  parent_id uuid,
  body text,
  created_at timestamptz,
  author_id text,
  author_username text,
  author_public_name text,
  author_avatar_thumb_path text,
  likes integer,
  liked_by_me boolean,
  is_mine boolean,
  can_delete boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_owner text := private.visible_listing_owner(p_listing);
begin
  return query
    select
      c.id, c.parent_id, c.body, c.created_at,
      p.id, p.username::text, p.public_name, p.avatar_thumb_path,
      (select count(*)::integer from public.comment_likes k
       where k.comment_id = c.id and not public.is_blocked_between(k.user_id, v_uid)),
      exists (select 1 from public.comment_likes k where k.comment_id = c.id and k.user_id = v_uid),
      c.author_id = v_uid,
      c.author_id = v_uid or v_owner = v_uid
    from public.listing_comments c
    join public.profiles p on p.id = c.author_id
    where c.listing_id = p_listing
      and not public.is_blocked_between(c.author_id, v_uid)
      -- Le risposte a un commento nascosto restano nascoste con lui.
      and (c.parent_id is null or exists (
        select 1 from public.listing_comments pc
        where pc.id = c.parent_id and not public.is_blocked_between(pc.author_id, v_uid)))
    order by c.created_at
    limit 1000;
end;
$$;

create or replace function public.my_notifications(p_limit integer default 50)
returns table (
  id uuid,
  kind text,
  listing_id uuid,
  listing_title text,
  comment_id uuid,
  comment_excerpt text,
  actor_id text,
  actor_username text,
  actor_public_name text,
  actor_avatar_thumb_path text,
  actor_count integer,
  created_at timestamptz,
  read boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    n.id, n.kind, n.listing_id, l.title, n.comment_id,
    left(c.body, 120),
    p.id, p.username::text, p.public_name, p.avatar_thumb_path,
    n.actor_count, n.created_at, n.read_at is not null
  from public.notifications n
  join public.listings l on l.id = n.listing_id
  join public.profiles p on p.id = n.actor_id
  left join public.listing_comments c on c.id = n.comment_id
  where n.recipient_id = public.current_uid()
    and not public.is_blocked_between(n.actor_id, public.current_uid())
  order by n.created_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

create or replace function public.unread_notifications_count()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer from public.notifications n
  where n.recipient_id = public.current_uid() and n.read_at is null
    and not public.is_blocked_between(n.actor_id, public.current_uid());
$$;

create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns void
language sql
security definer
set search_path = public
as $$
  update public.notifications
  set read_at = now()
  where recipient_id = public.current_uid() and read_at is null
    and (p_ids is null or id = any (p_ids));
$$;

-- ------------------------------------------------------------ annunci vicini con eventi
drop function if exists public.map_listings_nearby(
  double precision, double precision, integer, text, integer, boolean, integer
);

create function public.map_listings_nearby(
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
  owner_is_business boolean,
  group_spots integer,
  participants integer
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
    (floor(st_distance(l.approx_location, o.g) / 250.0) * 250)::integer,
    l.available_now,
    l.expires_at,
    l.created_at,
    l.owner_id = public.current_uid(),
    p.id,
    p.username::text,
    p.public_name,
    p.avatar_thumb_path,
    p.account_type = 'business',
    l.group_spots,
    (select count(*)::integer from public.listing_participants pp where pp.listing_id = l.id)
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

-- I miei annunci con l'evento di gruppo.
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
  created_at timestamptz,
  group_spots integer,
  participants integer
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
    l.created_at,
    l.group_spots,
    (select count(*)::integer from public.listing_participants pp where pp.listing_id = l.id)
  from public.listings l
  join public.listing_locations ll on ll.listing_id = l.id
  where l.owner_id = public.current_uid() and l.kind = 'social'
  order by l.created_at desc
  limit 100;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.publish_map_listing(text, text, double precision, double precision, public.location_mode, timestamptz, text[], integer)',
    'public.update_my_listing(uuid, text, text, timestamptz, text[], integer)',
    'public.join_listing(uuid)',
    'public.leave_listing(uuid)',
    'public.set_listing_reaction(uuid, text)',
    'public.add_listing_comment(uuid, text, uuid)',
    'public.delete_my_comment(uuid)',
    'public.set_comment_like(uuid, boolean)',
    'public.set_listing_muted(uuid, boolean)',
    'public.listing_social(uuid)',
    'public.listing_people(uuid, text)',
    'public.listing_comments_list(uuid)',
    'public.my_notifications(integer)',
    'public.unread_notifications_count()',
    'public.mark_notifications_read(uuid[])',
    'public.map_listings_nearby(double precision, double precision, integer, text, integer, boolean, integer)',
    'public.my_map_listings()'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

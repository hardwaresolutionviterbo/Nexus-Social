-- Piazly · Fase 4, Blocco 5: notifiche con l'app chiusa, «Silenzia» e «Non disturbare».
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Come funziona (docs/fase4/BLOCCO5_ESITO.md):
--  • ogni telefono registra il suo identificativo per le notifiche (Firebase Installation ID);
--  • quando arriva un messaggio di chat, o un commento / una proposta di scambio, il server
--    mette una notifica in coda e chiama la funzione «notifiche», che la manda con FCM;
--  • le notifiche NON contengono mai il testo dei messaggi (sono cifrati: il server non lo
--    conosce): solo chi scrive (o il nome del gruppo) e «Nuovo messaggio»; con «anteprima»
--    spenta nemmeno quello; mai il numero di telefono;
--  • niente notifiche per i Mi piace / Non mi piace (regola del piano);
--  • «Silenzia» per singola chat (8 ore, 1 settimana, sempre) e «Non disturbare» con orari;
--  • più messaggi della stessa chat si raggruppano in una sola notifica («3 nuovi messaggi»).

create extension if not exists pg_net with schema extensions;

-- ------------------------------------------------------------ tabelle
create table public.push_devices (
  fid text primary key check (fid ~ '^[A-Za-z0-9_:-]{10,300}$'),
  user_id text not null,
  platform text not null check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);
create index push_devices_user_idx on public.push_devices (user_id);

create table public.push_settings (
  user_id text primary key,
  messages boolean not null default true,
  comments boolean not null default true,
  market boolean not null default true,
  preview boolean not null default true,
  dnd_enabled boolean not null default false,
  dnd_from time not null default '22:00',
  dnd_to time not null default '07:00',
  time_zone text not null default 'Europe/Rome'
);

alter table public.chat_members add column muted_until timestamptz;

create table private.push_queue (
  id bigint generated always as identity primary key,
  user_id text not null,
  kind text not null check (kind in ('chat', 'comment', 'market')),
  conversation_id uuid,
  collapse_key text not null,
  title text not null,
  body text not null,
  count integer not null default 1,
  created_at timestamptz not null default now()
);
create index push_queue_user_idx on private.push_queue (user_id, collapse_key);

alter table public.push_devices enable row level security;
alter table public.push_settings enable row level security;
revoke all on public.push_devices, public.push_settings from public, anon, authenticated;
revoke all on private.push_queue from public, anon, authenticated;

-- Segreto condiviso tra il database e la funzione «notifiche».
do $$
begin
  if not exists (select 1 from private.settings where key = 'push_secret') then
    insert into private.settings (key, value)
    values ('push_secret', encode(extensions.gen_random_bytes(32), 'hex'));
  end if;
end;
$$;

-- ------------------------------------------------------------ preferenze e silenzio
create or replace function private.push_prefs(p_user text)
returns public.push_settings
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select s from public.push_settings s where s.user_id = p_user),
    row(p_user, true, true, true, true, false, '22:00'::time, '07:00'::time, 'Europe/Rome')::public.push_settings
  );
$$;

-- «Non disturbare» attivo adesso (gli orari possono scavalcare la mezzanotte).
create or replace function private.push_quiet(p_prefs public.push_settings)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_now time;
begin
  if not p_prefs.dnd_enabled then
    return false;
  end if;
  v_now := (now() at time zone p_prefs.time_zone)::time;
  if p_prefs.dnd_from <= p_prefs.dnd_to then
    return v_now >= p_prefs.dnd_from and v_now < p_prefs.dnd_to;
  end if;
  return v_now >= p_prefs.dnd_from or v_now < p_prefs.dnd_to;
end;
$$;

-- Avvia l'invio (asincrono): solo se l'indirizzo della funzione è configurato.
create or replace function private.push_kick()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := (select value from private.settings where key = 'push_functions_url');
  v_secret text := (select value from private.settings where key = 'push_secret');
begin
  if v_url is null or v_secret is null then
    return;
  end if;
  perform net.http_post(
    url := v_url || '/notifiche',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    timeout_milliseconds := 5000
  );
exception when others then
  -- Le notifiche non devono mai bloccare un messaggio.
  null;
end;
$$;

-- Mette in coda una notifica (raggruppando quelle della stessa chat non ancora partite).
create or replace function private.push_enqueue(
  p_user text,
  p_kind text,
  p_conversation uuid,
  p_collapse text,
  p_title text,
  p_body text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefs public.push_settings := private.push_prefs(p_user);
  v_row private.push_queue;
begin
  if not exists (select 1 from public.push_devices where user_id = p_user) then
    return;
  end if;
  if (p_kind = 'chat' and not v_prefs.messages)
     or (p_kind = 'comment' and not v_prefs.comments)
     or (p_kind = 'market' and not v_prefs.market)
     or private.push_quiet(v_prefs) then
    return;
  end if;
  select * into v_row from private.push_queue
  where user_id = p_user and collapse_key = p_collapse
  for update;
  if v_row.id is not null then
    update private.push_queue
    set count = count + 1, title = p_title,
        body = case when p_kind = 'chat' and v_prefs.preview
                    then (count + 1)::text || ' nuovi messaggi' else p_body end,
        created_at = now()
    where id = v_row.id;
  else
    insert into private.push_queue (user_id, kind, conversation_id, collapse_key, title, body)
    values (p_user, p_kind, p_conversation, p_collapse, p_title, p_body);
  end if;
  perform private.push_kick();
end;
$$;

revoke all on function private.push_prefs(text) from public, anon, authenticated;
revoke all on function private.push_quiet(public.push_settings) from public, anon, authenticated;
revoke all on function private.push_kick() from public, anon, authenticated;
revoke all on function private.push_enqueue(text, text, uuid, text, text, text) from public, anon, authenticated;

-- ------------------------------------------------------------ chat: nuovi messaggi
create or replace function private.push_on_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conv public.chat_conversations;
  v_sender text;
  v_member record;
  v_prefs public.push_settings;
  v_title text;
  v_body text;
begin
  select * into v_conv from public.chat_conversations where id = new.conversation_id;
  select coalesce(nullif(public_name, ''), '@' || username::text) into v_sender
  from public.profiles where id = new.sender_id;
  for v_member in
    select m.user_id, m.status
    from public.chat_members m
    where m.conversation_id = new.conversation_id
      and m.user_id <> new.sender_id
      and (m.muted_until is null or m.muted_until <= now())
      and (
        (v_conv.kind = 'direct' and m.status in ('active', 'request')
          and not public.is_blocked_between(m.user_id, new.sender_id))
        or (v_conv.kind = 'group' and m.status = 'active' and m.mls_state = 'in')
      )
  loop
    v_prefs := private.push_prefs(v_member.user_id);
    if not v_prefs.preview then
      v_title := 'Piazly';
      v_body := 'Hai un nuovo messaggio';
    elsif v_conv.kind = 'group' then
      v_title := v_conv.title;
      v_body := coalesce(v_sender, 'Un membro') || ': nuovo messaggio';
    else
      v_title := coalesce(v_sender, 'Piazly');
      v_body := case when v_member.status = 'request'
                     then 'Ti ha scritto (richiesta di messaggio)' else 'Nuovo messaggio' end;
    end if;
    perform private.push_enqueue(v_member.user_id, 'chat', new.conversation_id,
                                 'chat:' || new.conversation_id::text, v_title, v_body);
  end loop;
  return null;
exception when others then
  return null;
end;
$$;

create trigger chat_messages_push
after insert on public.chat_messages
for each row when (new.kind = 'app')
execute function private.push_on_chat_message();

-- ------------------------------------------------------------ commenti e scambi
create or replace function private.push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor text;
  v_kind text;
  v_body text;
begin
  -- Mai per i Mi piace / Non mi piace.
  if new.kind in ('listing_like', 'comment_like') or new.actor_id = new.recipient_id then
    return null;
  end if;
  select coalesce(nullif(public_name, ''), '@' || username::text) into v_actor
  from public.profiles where id = new.actor_id;
  v_actor := coalesce(v_actor, 'Qualcuno');
  v_kind := case when new.kind in ('listing_comment', 'comment_reply', 'followed_comment')
                 then 'comment' else 'market' end;
  v_body := case new.kind
    when 'listing_comment' then v_actor || ' ha commentato il tuo annuncio'
    when 'comment_reply' then v_actor || ' ha risposto al tuo commento'
    when 'followed_comment' then v_actor || ' ha commentato un annuncio che segui'
    when 'swap_proposal' then v_actor || ' ti ha proposto uno scambio'
    when 'swap_counter' then v_actor || ' ha fatto una controproposta'
    when 'swap_accepted' then v_actor || ' ha accettato lo scambio'
    when 'deal_confirm' then v_actor || ' chiede di confermare lo scambio concluso'
    when 'deal_completed' then 'Scambio concluso con ' || v_actor
    when 'feedback_received' then v_actor || ' ti ha lasciato un feedback'
    else null end;
  if v_body is null then
    return null;
  end if;
  perform private.push_enqueue(new.recipient_id, v_kind, null, 'n:' || new.id::text, 'Piazly', v_body);
  return null;
exception when others then
  return null;
end;
$$;

create trigger notifications_push
after insert on public.notifications
for each row execute function private.push_on_notification();

revoke all on function private.push_on_chat_message() from public, anon, authenticated;
revoke all on function private.push_on_notification() from public, anon, authenticated;

-- ------------------------------------------------------------ funzioni per l'app
create or replace function public.push_register(p_fid text, p_platform text)
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
  if p_fid is null or p_fid !~ '^[A-Za-z0-9_:-]{10,300}$' or p_platform not in ('android', 'ios') then
    raise exception 'Dispositivo non valido' using errcode = '22023';
  end if;
  -- Un telefono appartiene a un solo account: l'ultimo che ci entra.
  insert into public.push_devices (fid, user_id, platform, updated_at)
  values (p_fid, v_uid, p_platform, now())
  on conflict (fid) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
  -- Al massimo 10 telefoni per account: i più vecchi escono.
  delete from public.push_devices d
  where d.user_id = v_uid and d.fid in (
    select fid from public.push_devices where user_id = v_uid order by updated_at desc offset 10
  );
end;
$$;

create or replace function public.push_unregister(p_fid text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.push_devices where fid = p_fid and user_id = public.current_uid();
end;
$$;

create or replace function public.push_get_settings()
returns setof public.push_settings
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  return next private.push_prefs(v_uid);
end;
$$;

create or replace function public.push_set_settings(
  p_messages boolean,
  p_comments boolean,
  p_market boolean,
  p_preview boolean,
  p_dnd_enabled boolean,
  p_dnd_from time,
  p_dnd_to time,
  p_time_zone text
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
  if p_time_zone is null or not exists (select 1 from pg_timezone_names where name = p_time_zone) then
    raise exception 'Fuso orario non valido' using errcode = '22023';
  end if;
  insert into public.push_settings
    (user_id, messages, comments, market, preview, dnd_enabled, dnd_from, dnd_to, time_zone)
  values (v_uid, coalesce(p_messages, true), coalesce(p_comments, true), coalesce(p_market, true),
          coalesce(p_preview, true), coalesce(p_dnd_enabled, false), coalesce(p_dnd_from, '22:00'),
          coalesce(p_dnd_to, '07:00'), p_time_zone)
  on conflict (user_id) do update set
    messages = excluded.messages, comments = excluded.comments, market = excluded.market,
    preview = excluded.preview, dnd_enabled = excluded.dnd_enabled, dnd_from = excluded.dnd_from,
    dnd_to = excluded.dnd_to, time_zone = excluded.time_zone;
end;
$$;

-- «Silenzia» una chat fino a [p_until] (null = riattiva, 'infinity' = sempre).
create or replace function public.chat_set_mute(p_conversation uuid, p_until timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_me(p_conversation, v_uid);
begin
  if p_until is not null and p_until <= now() then
    raise exception 'Scegli un momento futuro' using errcode = '22023';
  end if;
  update public.chat_members set muted_until = p_until
  where conversation_id = p_conversation and user_id = v_uid;
end;
$$;

revoke all on function public.push_register(text, text) from public, anon;
revoke all on function public.push_unregister(text) from public, anon;
revoke all on function public.push_get_settings() from public, anon;
revoke all on function public.push_set_settings(boolean, boolean, boolean, boolean, boolean, time, time, text) from public, anon;
revoke all on function public.chat_set_mute(uuid, timestamptz) from public, anon;
grant execute on function public.push_register(text, text) to authenticated;
grant execute on function public.push_unregister(text) to authenticated;
grant execute on function public.push_get_settings() to authenticated;
grant execute on function public.push_set_settings(boolean, boolean, boolean, boolean, boolean, time, time, text) to authenticated;
grant execute on function public.chat_set_mute(uuid, timestamptz) to authenticated;

-- ------------------------------------------------------------ funzioni per il server
-- Solo per la funzione «notifiche» (ruolo di servizio): prende e toglie dalla coda.
create or replace function public.push_claim(p_limit integer default 100)
returns table (queue_id bigint, fid text, platform text, kind text, conversation_id uuid,
               collapse_key text, title text, body text)
language sql
security definer
set search_path = public
as $$
  with taken as (
    delete from private.push_queue q
    where q.id in (select id from private.push_queue order by id limit greatest(1, least(p_limit, 500)))
    returning q.*
  )
  select t.id, d.fid, d.platform, t.kind, t.conversation_id, t.collapse_key, t.title, t.body
  from taken t join public.push_devices d on d.user_id = t.user_id;
$$;

create or replace function public.push_drop_device(p_fid text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_devices where fid = p_fid;
$$;

create or replace function public.push_server_config()
returns table (push_secret text, firebase_project_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select value from private.settings where key = 'push_secret'),
    (select value from private.settings where key = 'firebase_project_id');
$$;

revoke all on function public.push_claim(integer) from public, anon, authenticated;
revoke all on function public.push_drop_device(text) from public, anon, authenticated;
revoke all on function public.push_server_config() from public, anon, authenticated;
grant execute on function public.push_claim(integer) to service_role;
grant execute on function public.push_drop_device(text) to service_role;
grant execute on function public.push_server_config() to service_role;

-- ------------------------------------------------------------ chat: anche lo stato «silenziata»
drop function public.chat_conversations();
create function public.chat_conversations()
returns table (
  id uuid,
  kind text,
  status text,
  generation integer,
  mls_group_id text,
  peer_id text,
  peer_username text,
  peer_public_name text,
  peer_avatar_thumb_path text,
  peer_signature_key text,
  peer_joined_key text,
  my_joined_key text,
  peer_delivered_upto bigint,
  peer_read_upto bigint,
  my_read_upto bigint,
  last_message_id bigint,
  last_message_at timestamptz,
  unread integer,
  created_at timestamptz,
  title text,
  description text,
  photo_version integer,
  my_role text,
  my_mls_state text,
  members integer,
  pending integer,
  invited_by text,
  muted_until timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  -- Chat a due (come nella migrazione 0019).
  select c.id, c.kind, me.status, c.generation, c.mls_group_id,
         p.id, p.username::text, p.public_name, p.avatar_thumb_path,
         i.signature_key, other.joined_key, me.joined_key,
         case when other.status = 'active' then other.delivered_upto else 0 end,
         case when other.status = 'active' then other.read_upto else 0 end,
         me.read_upto,
         c.last_message_id, c.last_message_at,
         (select count(*)::integer from public.chat_messages m
          where m.conversation_id = c.id and m.kind = 'app'
            and m.sender_id = other.user_id and m.id > me.read_upto),
         c.created_at,
         null::text, ''::text, 0, me.role, me.mls_state, 2, 0, null::text,
         me.muted_until
  from public.chat_members me
  join public.chat_conversations c on c.id = me.conversation_id and c.kind = 'direct'
  join public.chat_members other
    on other.conversation_id = c.id and other.user_id <> me.user_id
  join public.profiles p on p.id = other.user_id
  left join public.chat_identities i on i.user_id = other.user_id
  where me.user_id = private.chat_uid()
    and me.status <> 'declined'
    and not public.is_blocked_between(me.user_id, other.user_id)
  union all
  -- Gruppi: «consegnato»/«letto» quando tutti gli altri membri l'hanno ricevuto/letto.
  select c.id, c.kind, me.status, c.generation, c.mls_group_id,
         null::text, null::text, null::text, null::text, null::text, null::text, me.joined_key,
         coalesce((select min(o.delivered_upto) from public.chat_members o
                   where o.conversation_id = c.id and o.user_id <> me.user_id
                     and o.status = 'active' and o.mls_state = 'in'), 0),
         coalesce((select min(o.read_upto) from public.chat_members o
                   where o.conversation_id = c.id and o.user_id <> me.user_id
                     and o.status = 'active' and o.mls_state = 'in'), 0),
         me.read_upto,
         c.last_message_id, c.last_message_at,
         0,
         c.created_at,
         c.title, c.description, c.photo_version, me.role, me.mls_state,
         (select count(*)::integer from public.chat_members o
          where o.conversation_id = c.id and o.status = 'active'),
         (select count(*)::integer from public.chat_members o
          where o.conversation_id = c.id
            and ((o.status = 'active' and o.mls_state in ('to_add', 'to_readd'))
                 or o.mls_state = 'to_remove')),
         me.invited_by,
         me.muted_until
  from public.chat_members me
  join public.chat_conversations c on c.id = me.conversation_id and c.kind = 'group'
  where me.user_id = private.chat_uid()
    and me.status in ('active', 'request')
  order by 17 desc nulls last, 19 desc;
$$;
revoke all on function public.chat_conversations() from public, anon;
grant execute on function public.chat_conversations() to authenticated;


-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

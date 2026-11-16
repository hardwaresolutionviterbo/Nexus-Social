-- Piazly · Fase 4, Blocco 1: chat a due cifrata end-to-end (MLS, RFC 9420).
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Cosa conserva il server (docs/fase4/BLOCCO1_ESITO.md):
--  • per ogni persona la chiave pubblica di firma della chat (un telefono alla volta, come
--    WhatsApp) e i «pacchetti chiave» pubblici con cui gli altri aprono una chat;
--  • le conversazioni a due, chi ne fa parte e fin dove ha ricevuto e letto;
--  • i messaggi SOLO cifrati sul telefono (testo in base64 illeggibile per il server),
--    finché il destinatario non li ha ricevuti: poi vengono cancellati; in ogni caso dopo
--    30 giorni;
--  • nessun numero di telefono: in chat si vedono nome pubblico, @nome utente e foto.
--
-- Regole:
--  • chi non ti ha in rubrica ti scrive come «richiesta»: la accetti o la rifiuti; finché è
--    una richiesta chi scrive non vede né «consegnato» né «letto»; chi ha rifiutato non
--    riceve più nulla e chi scrive non lo sa;
--  • con un blocco (in un verso o nell'altro) la chat non si apre e non si scrive;
--  • anti-spam: 20 nuove richieste al giorno, 10 messaggi finché la richiesta è in attesa,
--    60 messaggi al minuto e 3.000 al giorno;
--  • «generazione»: ogni volta che la chat cifrata viene (ri)aperta, per esempio perché una
--    delle due persone ha cambiato telefono, la generazione sale di uno; il server accetta
--    solo messaggi della generazione corrente;
--  • nessun accesso diretto alle tabelle: solo funzioni, e solo per chi fa parte della chat.

-- ------------------------------------------------------------ tabelle
create table public.chat_identities (
  user_id text primary key references public.profiles (id) on delete cascade,
  -- Chiave pubblica di firma MLS (Ed25519), base64.
  signature_key text not null check (signature_key ~ '^[A-Za-z0-9+/]{40,88}={0,2}$'),
  created_at timestamptz not null default now()
);

create table public.chat_key_packages (
  id bigint generated always as identity primary key,
  user_id text not null references public.chat_identities (user_id) on delete cascade,
  package text not null check (
    char_length(package) between 100 and 8000 and package ~ '^[A-Za-z0-9+/]+={0,2}$'
  ),
  created_at timestamptz not null default now()
);
create index chat_key_packages_user_idx on public.chat_key_packages (user_id, id);

create table public.chat_conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'direct' check (kind = 'direct'),
  -- Coppia ordinata: una sola chat tra le stesse due persone.
  user_low text not null references public.profiles (id) on delete cascade,
  user_high text not null references public.profiles (id) on delete cascade,
  created_by text not null references public.profiles (id) on delete cascade,
  generation integer not null default 0 check (generation >= 0),
  mls_group_id text check (mls_group_id is null or mls_group_id ~ '^[A-Za-z0-9+/]{4,200}={0,2}$'),
  last_message_id bigint,
  last_message_at timestamptz,
  claims_day date,
  claims_used integer not null default 0,
  created_at timestamptz not null default now(),
  constraint chat_pair check (user_low < user_high),
  constraint chat_pair_unique unique (user_low, user_high)
);

create table public.chat_members (
  conversation_id uuid not null references public.chat_conversations (id) on delete cascade,
  user_id text not null references public.profiles (id) on delete cascade,
  -- active: la chat è nella lista; request: richiesta da accettare; declined: rifiutata.
  status text not null check (status in ('active', 'request', 'declined')),
  -- Chiave di firma con cui questa persona è entrata nella generazione corrente.
  joined_key text,
  delivered_upto bigint not null default 0,
  read_upto bigint not null default 0,
  primary key (conversation_id, user_id)
);
create index chat_members_user_idx on public.chat_members (user_id);

create table public.chat_messages (
  id bigint generated always as identity primary key,
  conversation_id uuid not null references public.chat_conversations (id) on delete cascade,
  generation integer not null,
  sender_id text not null references public.profiles (id) on delete cascade,
  -- welcome: invito cifrato alla nuova generazione, solo per recipient_id; app: messaggio.
  kind text not null check (kind in ('welcome', 'app')),
  recipient_id text references public.profiles (id) on delete cascade,
  payload text not null check (
    char_length(payload) between 4 and 90000 and payload ~ '^[A-Za-z0-9+/]+={0,2}$'
  ),
  created_at timestamptz not null default now(),
  constraint chat_welcome_recipient check ((kind = 'welcome') = (recipient_id is not null))
);
create index chat_messages_conv_idx on public.chat_messages (conversation_id, id);
create index chat_messages_sender_time_idx on public.chat_messages (sender_id, created_at);

-- Contatori anti-spam (i messaggi vengono cancellati appena consegnati).
create table private.chat_limits (
  user_id text not null,
  bucket text not null,
  used integer not null default 0,
  primary key (user_id, bucket)
);

alter table public.chat_identities enable row level security;
alter table public.chat_key_packages enable row level security;
alter table public.chat_conversations enable row level security;
alter table public.chat_members enable row level security;
alter table public.chat_messages enable row level security;
revoke all on public.chat_identities, public.chat_key_packages, public.chat_conversations,
  public.chat_members, public.chat_messages from public, anon, authenticated;
revoke all on private.chat_limits from public, anon, authenticated;

-- ------------------------------------------------------------ controlli comuni
create or replace function private.chat_uid()
returns text
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
  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'Completa prima il profilo' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

-- Conta un uso nel secchio (minuto, giorno...); false se il limite è raggiunto.
create or replace function private.chat_take(p_uid text, p_bucket text, p_max integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_used integer;
begin
  insert into private.chat_limits (user_id, bucket, used) values (p_uid, p_bucket, 1)
  on conflict (user_id, bucket) do update set used = private.chat_limits.used + 1
    where private.chat_limits.used < p_max
  returning used into v_used;
  return v_used is not null;
end;
$$;

create or replace function private.chat_check_not_banned(p_uid text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.user_moderation m
    where m.user_id = p_uid and m.banned_until is not null and m.banned_until > now()
  ) then
    raise exception 'Account sospeso' using errcode = '42501';
  end if;
end;
$$;

-- La riga di chi chiama in una chat, bloccata per l'aggiornamento.
create or replace function private.chat_me(p_conversation uuid, p_uid text)
returns public.chat_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.chat_members;
begin
  select * into v_row from public.chat_members
  where conversation_id = p_conversation and user_id = p_uid
  for update;
  if v_row.user_id is null then
    raise exception 'Chat non trovata' using errcode = '42501';
  end if;
  return v_row;
end;
$$;

create or replace function private.chat_other(p_conversation uuid, p_uid text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select m.user_id from public.chat_members m
  where m.conversation_id = p_conversation and m.user_id <> p_uid
  limit 1;
$$;

revoke all on function private.chat_uid() from public, anon, authenticated;
revoke all on function private.chat_take(text, text, integer) from public, anon, authenticated;
revoke all on function private.chat_check_not_banned(text) from public, anon, authenticated;
revoke all on function private.chat_me(uuid, text) from public, anon, authenticated;
revoke all on function private.chat_other(uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------ identità e pacchetti chiave
-- Registra la chiave di firma di questo telefono. Se cambia (telefono nuovo) i vecchi
-- pacchetti spariscono e le chat si riaprono con una nuova generazione.
create or replace function public.chat_register_identity(p_signature_key text, p_packages text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_old text;
begin
  if p_signature_key is null or p_signature_key !~ '^[A-Za-z0-9+/]{40,88}={0,2}$' then
    raise exception 'Chiave non valida' using errcode = '22023';
  end if;
  select signature_key into v_old from public.chat_identities where user_id = v_uid for update;
  if v_old is distinct from p_signature_key then
    if not private.chat_take(v_uid, 'identita:' || current_date::text, 5) then
      raise exception 'Troppi cambi di telefono oggi' using errcode = '22023';
    end if;
    delete from public.chat_key_packages where user_id = v_uid;
    insert into public.chat_identities (user_id, signature_key) values (v_uid, p_signature_key)
    on conflict (user_id) do update set signature_key = excluded.signature_key, created_at = now();
  end if;
  perform public.chat_add_key_packages(p_packages);
end;
$$;

create or replace function public.chat_add_key_packages(p_packages text[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_n integer := coalesce(array_length(p_packages, 1), 0);
  v_have integer;
begin
  if not exists (select 1 from public.chat_identities where user_id = v_uid) then
    raise exception 'Chat non ancora attivata su questo telefono' using errcode = '22023';
  end if;
  if v_n > 50 then
    raise exception 'Al massimo 50 pacchetti per volta' using errcode = '22023';
  end if;
  select count(*) into v_have from public.chat_key_packages where user_id = v_uid;
  if v_have + v_n > 100 then
    raise exception 'Troppi pacchetti chiave' using errcode = '22023';
  end if;
  if v_n > 0 then
    insert into public.chat_key_packages (user_id, package)
    select v_uid, x from unnest(p_packages) x;
  end if;
  return v_have + v_n;
end;
$$;

-- La chiave registrata per la chat di chi chiama (null se non ancora attivata).
create or replace function public.chat_my_identity()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select signature_key from public.chat_identities where user_id = private.chat_uid();
$$;

create or replace function public.chat_key_package_count()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer from public.chat_key_packages
  where user_id = private.chat_uid();
$$;

-- ------------------------------------------------------------ aprire una chat
create or replace function public.chat_open_direct(p_user text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_low text := least(v_uid, p_user);
  v_high text := greatest(v_uid, p_user);
  v_id uuid;
  v_known boolean;
begin
  if p_user is null or p_user = v_uid then
    raise exception 'Scegli un''altra persona' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_user)
     or public.is_blocked_between(v_uid, p_user) then
    raise exception 'Persona non trovata' using errcode = '42501';
  end if;
  perform private.chat_check_not_banned(v_uid);
  select id into v_id from public.chat_conversations where user_low = v_low and user_high = v_high;
  if v_id is not null then
    -- Chi riapre una chat che aveva rifiutato la riporta tra le sue.
    update public.chat_members set status = 'active'
    where conversation_id = v_id and user_id = v_uid and status <> 'active';
    return v_id;
  end if;
  if not exists (select 1 from public.chat_identities where user_id = p_user) then
    raise exception 'Questa persona non ha ancora attivato la chat: chiedile di aggiornare l''app'
      using errcode = '22023';
  end if;
  -- L'altra persona ti ha in rubrica? Allora la chat è subito attiva, altrimenti è una richiesta.
  select exists (
    select 1 from private.contact_links l
    where l.owner_id = p_user and l.contact_id = v_uid and l.expires_at > now()
  ) into v_known;
  if not v_known and not private.chat_take(v_uid, 'richieste:' || current_date::text, 20) then
    raise exception 'Hai raggiunto il limite di 20 nuove richieste al giorno' using errcode = '22023';
  end if;
  insert into public.chat_conversations (user_low, user_high, created_by)
  values (v_low, v_high, v_uid)
  returning id into v_id;
  insert into public.chat_members (conversation_id, user_id, status) values
    (v_id, v_uid, 'active'),
    (v_id, p_user, case when v_known then 'active' else 'request' end);
  return v_id;
end;
$$;

-- Un pacchetto chiave dell'altra persona, consumato (serve per aprire la chat cifrata).
create or replace function public.chat_claim_key_package(p_conversation uuid)
returns table (package text, signature_key text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_me(p_conversation, v_uid);
  v_other text := private.chat_other(p_conversation, v_uid);
  v_conv public.chat_conversations;
  v_kp public.chat_key_packages;
begin
  if public.is_blocked_between(v_uid, v_other) then
    raise exception 'Chat non disponibile' using errcode = '42501';
  end if;
  select * into v_conv from public.chat_conversations where id = p_conversation for update;
  -- Al massimo 10 pacchetti al giorno per chat: nessuno può svuotare quelli degli altri.
  if v_conv.claims_day is distinct from current_date then
    update public.chat_conversations set claims_day = current_date, claims_used = 0
    where id = p_conversation;
    v_conv.claims_used := 0;
  end if;
  if v_conv.claims_used >= 10 then
    raise exception 'Riprova più tardi' using errcode = '22023';
  end if;
  update public.chat_conversations set claims_used = claims_used + 1 where id = p_conversation;
  select * into v_kp from public.chat_key_packages k
  where k.user_id = v_other
  order by k.id
  limit 1
  for update skip locked;
  if v_kp.id is null then
    raise exception 'L''altra persona deve aprire l''app per attivare la chat' using errcode = '22023';
  end if;
  delete from public.chat_key_packages where id = v_kp.id;
  return query
    select v_kp.package, i.signature_key from public.chat_identities i where i.user_id = v_other;
end;
$$;

-- Apre (o riapre) la chat cifrata: nuova generazione con il suo invito per l'altra persona.
-- p_generation è quella che chi chiama ha visto: se nel frattempo è cambiata, errore 40001.
create or replace function public.chat_start(
  p_conversation uuid,
  p_generation integer,
  p_group_id text,
  p_welcome text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_me(p_conversation, v_uid);
  v_other text := private.chat_other(p_conversation, v_uid);
  v_conv public.chat_conversations;
  v_next integer;
  v_msg bigint;
begin
  if public.is_blocked_between(v_uid, v_other) then
    raise exception 'Chat non disponibile' using errcode = '42501';
  end if;
  if p_group_id is null or p_group_id !~ '^[A-Za-z0-9+/]{4,200}={0,2}$' then
    raise exception 'Chat cifrata non valida' using errcode = '22023';
  end if;
  select * into v_conv from public.chat_conversations where id = p_conversation for update;
  if v_conv.generation <> p_generation then
    raise exception 'La chat è appena cambiata: riprova' using errcode = '40001';
  end if;
  if not private.chat_take(v_uid, 'aperture:' || current_date::text, 200) then
    raise exception 'Troppe chat aperte oggi' using errcode = '22023';
  end if;
  v_next := v_conv.generation + 1;
  insert into public.chat_messages (conversation_id, generation, sender_id, kind, recipient_id, payload)
  values (p_conversation, v_next, v_uid, 'welcome', v_other, p_welcome)
  returning id into v_msg;
  update public.chat_conversations
  set generation = v_next, mls_group_id = p_group_id
  where id = p_conversation;
  update public.chat_members m set joined_key = i.signature_key
  from public.chat_identities i
  where m.conversation_id = p_conversation and i.user_id = m.user_id;
  -- I messaggi della generazione precedente non si possono più leggere: via dal server.
  delete from public.chat_messages
  where conversation_id = p_conversation and generation < v_next;
  return v_next;
end;
$$;

-- ------------------------------------------------------------ scrivere
create or replace function public.chat_send(p_conversation uuid, p_generation integer, p_payload text)
returns table (id bigint, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_me(p_conversation, v_uid);
  v_other text := private.chat_other(p_conversation, v_uid);
  v_other_status text;
  v_conv public.chat_conversations;
  v_id bigint;
  v_at timestamptz;
begin
  if public.is_blocked_between(v_uid, v_other) then
    raise exception 'Non puoi scrivere in questa chat' using errcode = '42501';
  end if;
  perform private.chat_check_not_banned(v_uid);
  select * into v_conv from public.chat_conversations where chat_conversations.id = p_conversation;
  if v_conv.generation = 0 or v_conv.generation <> p_generation then
    raise exception 'La chat è appena cambiata: riprova' using errcode = '40001';
  end if;
  if p_payload is null or char_length(p_payload) > 90000 then
    raise exception 'Messaggio troppo lungo' using errcode = '22023';
  end if;
  -- Rispondere a una richiesta vuol dire accettarla.
  if v_me.status <> 'active' then
    update public.chat_members set status = 'active'
    where conversation_id = p_conversation and user_id = v_uid;
  end if;
  select status into v_other_status from public.chat_members
  where conversation_id = p_conversation and user_id = v_other;
  if v_other_status = 'request'
     and not private.chat_take(v_uid, 'attesa:' || p_conversation::text, 10) then
    raise exception 'Aspetta che la richiesta venga accettata' using errcode = '22023';
  end if;
  if not private.chat_take(v_uid, 'minuto:' || to_char(now(), 'YYYYMMDDHH24MI'), 60)
     or not private.chat_take(v_uid, 'giorno:' || current_date::text, 3000) then
    raise exception 'Stai scrivendo troppo in fretta: aspetta un momento' using errcode = '22023';
  end if;
  insert into public.chat_messages (conversation_id, generation, sender_id, kind, payload)
  values (p_conversation, p_generation, v_uid, 'app', p_payload)
  returning chat_messages.id, chat_messages.created_at into v_id, v_at;
  update public.chat_conversations set last_message_id = v_id, last_message_at = v_at
  where chat_conversations.id = p_conversation;
  -- Pulizia: messaggi rimasti sul server da più di 30 giorni e contatori vecchi.
  delete from public.chat_messages m
  where m.conversation_id = p_conversation and m.created_at < now() - interval '30 days';
  delete from private.chat_limits l
  where l.user_id = v_uid and l.bucket like 'minuto:%'
    and l.bucket < 'minuto:' || to_char(now() - interval '2 minutes', 'YYYYMMDDHH24MI');
  return query select v_id, v_at;
end;
$$;

-- ------------------------------------------------------------ ricevere
-- Messaggi e inviti arrivati per chi chiama dopo p_after, in ordine. Le chat rifiutate no.
create or replace function public.chat_sync(p_after bigint default 0, p_limit integer default 200)
returns table (
  id bigint,
  conversation_id uuid,
  generation integer,
  sender_id text,
  kind text,
  payload text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, m.conversation_id, m.generation, m.sender_id, m.kind, m.payload, m.created_at
  from public.chat_messages m
  join public.chat_members me
    on me.conversation_id = m.conversation_id and me.user_id = private.chat_uid()
  where m.id > coalesce(p_after, 0)
    and me.status <> 'declined'
    and m.sender_id <> me.user_id
    and (m.kind = 'app' or m.recipient_id = me.user_id)
    and not public.is_blocked_between(me.user_id, m.sender_id)
  order by m.id
  limit least(greatest(coalesce(p_limit, 200), 1), 500);
$$;

-- Le chat di chi chiama, con l'altra persona (mai il numero) e le spunte.
create or replace function public.chat_conversations()
returns table (
  id uuid,
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
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, me.status, c.generation, c.mls_group_id,
         p.id, p.username::text, p.public_name, p.avatar_thumb_path,
         i.signature_key, other.joined_key, me.joined_key,
         -- Finché l'altra persona non ha accettato, niente «consegnato» né «letto».
         case when other.status = 'active' then other.delivered_upto else 0 end,
         case when other.status = 'active' then other.read_upto else 0 end,
         me.read_upto,
         c.last_message_id, c.last_message_at,
         (select count(*)::integer from public.chat_messages m
          where m.conversation_id = c.id and m.kind = 'app'
            and m.sender_id = other.user_id and m.id > me.read_upto),
         c.created_at
  from public.chat_members me
  join public.chat_conversations c on c.id = me.conversation_id
  join public.chat_members other
    on other.conversation_id = c.id and other.user_id <> me.user_id
  join public.profiles p on p.id = other.user_id
  left join public.chat_identities i on i.user_id = other.user_id
  where me.user_id = private.chat_uid()
    and me.status <> 'declined'
    and not public.is_blocked_between(me.user_id, other.user_id)
  order by coalesce(c.last_message_at, c.created_at) desc;
$$;

-- «Ricevuto fin qui» e «letto fin qui». I messaggi ricevuti spariscono dal server.
create or replace function public.chat_mark(p_conversation uuid, p_delivered bigint, p_read bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_me(p_conversation, v_uid);
  v_last bigint;
  v_delivered bigint;
  v_read bigint;
begin
  -- Ultimo messaggio esistente per chi chiama (inviti compresi).
  select greatest(
    (select c.last_message_id from public.chat_conversations c where c.id = p_conversation),
    (select max(m.id) from public.chat_messages m
     where m.conversation_id = p_conversation and (m.kind = 'app' or m.recipient_id = v_uid))
  ) into v_last;
  v_delivered := greatest(v_me.delivered_upto, least(coalesce(p_delivered, 0), coalesce(v_last, 0)));
  v_read := greatest(v_me.read_upto, least(coalesce(p_read, 0), coalesce(v_last, 0)));
  if v_read > v_delivered then
    v_delivered := v_read;
  end if;
  update public.chat_members
  set delivered_upto = v_delivered, read_upto = v_read
  where conversation_id = p_conversation and user_id = v_uid;
  delete from public.chat_messages m
  where m.conversation_id = p_conversation
    and m.sender_id <> v_uid
    and m.id <= v_delivered
    and (m.kind = 'app' or m.recipient_id = v_uid);
end;
$$;

-- Richiesta: accettare la sposta tra le chat, rifiutarla la nasconde per sempre.
create or replace function public.chat_respond_request(p_conversation uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_me(p_conversation, v_uid);
begin
  if v_me.status <> 'request' then
    raise exception 'Non è una richiesta in attesa' using errcode = '22023';
  end if;
  update public.chat_members
  set status = case when p_accept then 'active' else 'declined' end
  where conversation_id = p_conversation and user_id = v_uid;
  if not p_accept then
    delete from public.chat_messages m
    where m.conversation_id = p_conversation and m.sender_id <> v_uid;
  end if;
end;
$$;

revoke all on function public.chat_register_identity(text, text[]) from public, anon;
revoke all on function public.chat_add_key_packages(text[]) from public, anon;
revoke all on function public.chat_key_package_count() from public, anon;
revoke all on function public.chat_my_identity() from public, anon;
revoke all on function public.chat_open_direct(text) from public, anon;
revoke all on function public.chat_claim_key_package(uuid) from public, anon;
revoke all on function public.chat_start(uuid, integer, text, text) from public, anon;
revoke all on function public.chat_send(uuid, integer, text) from public, anon;
revoke all on function public.chat_sync(bigint, integer) from public, anon;
revoke all on function public.chat_conversations() from public, anon;
revoke all on function public.chat_mark(uuid, bigint, bigint) from public, anon;
revoke all on function public.chat_respond_request(uuid, boolean) from public, anon;
grant execute on function public.chat_register_identity(text, text[]) to authenticated;
grant execute on function public.chat_add_key_packages(text[]) to authenticated;
grant execute on function public.chat_key_package_count() to authenticated;
grant execute on function public.chat_my_identity() to authenticated;
grant execute on function public.chat_open_direct(text) to authenticated;
grant execute on function public.chat_claim_key_package(uuid) to authenticated;
grant execute on function public.chat_start(uuid, integer, text, text) to authenticated;
grant execute on function public.chat_send(uuid, integer, text) to authenticated;
grant execute on function public.chat_sync(bigint, integer) to authenticated;
grant execute on function public.chat_conversations() to authenticated;
grant execute on function public.chat_mark(uuid, bigint, bigint) to authenticated;
grant execute on function public.chat_respond_request(uuid, boolean) to authenticated;

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

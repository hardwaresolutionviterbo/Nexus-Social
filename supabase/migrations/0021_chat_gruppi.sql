-- Piazly · Fase 4, Blocco 4: gruppi cifrati (MLS) con amministratori, foto e codice d'invito.
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Come funziona (docs/fase4/BLOCCO4_ESITO.md):
--  • il server decide CHI fa parte del gruppo (membri, amministratori, inviti, codice);
--    i telefoni tengono allineato il gruppo cifrato MLS: un amministratore aggiunge al
--    gruppo cifrato chi è entrato e toglie chi è uscito;
--  • stato cifrato di ogni membro (mls_state): in (dentro), to_add (da aggiungere),
--    to_remove (uscito, da togliere), to_readd (telefono nuovo: da togliere e riaggiungere);
--  • «generazione» = epoca MLS: ogni modifica cifrata (commit) la fa salire di uno; il
--    server accetta solo commit e messaggi della generazione corrente (niente doppioni);
--  • chi ti aggiunge senza essere nella tua rubrica ti manda un invito (richiesta): entri
--    solo se accetti; nessun numero di telefono, mai;
--  • messaggi, commit e inviti cifrati restano sul server solo finché tutti li hanno
--    ricevuti (al massimo 30 giorni); gli avvisi del gruppo («X ha aggiunto Y») sono
--    generati dal server e contengono solo identificativi;
--  • massimo 256 membri; nome fino a 60 caratteri, descrizione fino a 500.

-- ------------------------------------------------------------ schema
alter table public.chat_conversations drop constraint chat_pair;
alter table public.chat_conversations drop constraint chat_conversations_kind_check;
alter table public.chat_conversations alter column user_low drop not null;
alter table public.chat_conversations alter column user_high drop not null;
alter table public.chat_conversations
  add constraint chat_conversations_kind_check check (kind in ('direct', 'group')),
  add constraint chat_pair check (
    (kind = 'direct' and user_low is not null and user_high is not null and user_low < user_high)
    or (kind = 'group' and user_low is null and user_high is null)
  ),
  add column title text check (title is null or char_length(title) between 1 and 60),
  add column description text not null default '' check (char_length(description) <= 500),
  add column photo_version integer not null default 0,
  add constraint chat_group_title check ((kind = 'group') = (title is not null));

alter table public.chat_members
  add column role text not null default 'member' check (role in ('admin', 'member')),
  add column mls_state text not null default 'in'
    check (mls_state in ('in', 'to_add', 'to_remove', 'to_readd')),
  add column invited_by text references public.profiles (id) on delete set null,
  -- Nei gruppi si ricevono solo i messaggi arrivati dopo l'ingresso.
  add column from_id bigint not null default 0,
  add column joined_at timestamptz not null default now();
alter table public.chat_members drop constraint chat_members_status_check;
alter table public.chat_members add constraint chat_members_status_check
  check (status in ('active', 'request', 'declined', 'left'));

alter table public.chat_messages drop constraint chat_messages_kind_check;
alter table public.chat_messages add constraint chat_messages_kind_check
  check (kind in ('welcome', 'app', 'commit', 'event'));

create table public.chat_group_invites (
  code text primary key check (code ~ '^[A-Z0-9]{10}$'),
  conversation_id uuid not null references public.chat_conversations (id) on delete cascade,
  created_by text references public.profiles (id) on delete set null,
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);
create index chat_group_invites_conv_idx on public.chat_group_invites (conversation_id);
alter table public.chat_group_invites enable row level security;
revoke all on public.chat_group_invites from public, anon, authenticated;

-- ------------------------------------------------------------ controlli comuni
-- «L'altra persona» esiste solo nelle chat a due: le funzioni della chat a due (pacchetto
-- chiave, apertura cifrata) non funzionano sui gruppi.
create or replace function private.chat_other(p_conversation uuid, p_uid text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select m.user_id from public.chat_members m
  join public.chat_conversations c on c.id = m.conversation_id and c.kind = 'direct'
  where m.conversation_id = p_conversation and m.user_id <> p_uid
  limit 1;
$$;

create or replace function private.chat_group_me(p_conversation uuid, p_uid text, p_admin boolean)
returns public.chat_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.chat_members;
begin
  select m.* into v_row
  from public.chat_members m
  join public.chat_conversations c on c.id = m.conversation_id and c.kind = 'group'
  where m.conversation_id = p_conversation and m.user_id = p_uid and m.status = 'active'
  for update of m;
  if v_row.user_id is null then
    raise exception 'Gruppo non trovato' using errcode = '42501';
  end if;
  if p_admin and v_row.role <> 'admin' then
    raise exception 'Solo gli amministratori possono farlo' using errcode = '42501';
  end if;
  return v_row;
end;
$$;

-- Avviso del gruppo, visibile a tutti i membri (solo identificativi, nessun testo libero).
create or replace function private.chat_group_event(p_conversation uuid, p_actor text, p_event jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gen integer;
begin
  select generation into v_gen from public.chat_conversations where id = p_conversation;
  insert into public.chat_messages (conversation_id, generation, sender_id, kind, payload)
  -- encode(…, 'base64') va a capo ogni 76 caratteri: si tolgono gli a capo.
  values (p_conversation, v_gen, p_actor, 'event',
          translate(encode(convert_to(p_event::text, 'UTF8'), 'base64'), E'\n\r', ''));
end;
$$;

create or replace function private.chat_group_size(p_conversation uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer from public.chat_members
  where conversation_id = p_conversation and status in ('active', 'request');
$$;

-- Aggiunge una persona: membro (da aggiungere al gruppo cifrato) se ti ha in rubrica,
-- altrimenti invito da accettare. Restituisce lo stato.
create or replace function private.chat_group_put(p_conversation uuid, p_actor text, p_user text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_known boolean;
  v_status text;
begin
  if p_user is null or p_user = p_actor
     or not exists (select 1 from public.profiles where id = p_user)
     or public.is_blocked_between(p_actor, p_user) then
    return null;
  end if;
  if exists (
    select 1 from public.chat_members
    where conversation_id = p_conversation and user_id = p_user and status in ('active', 'request')
  ) then
    return null;
  end if;
  if not exists (select 1 from public.chat_identities where user_id = p_user) then
    return null;
  end if;
  select exists (
    select 1 from private.contact_links l
    where l.owner_id = p_user and l.contact_id = p_actor and l.expires_at > now()
  ) into v_known;
  v_status := case when v_known then 'active' else 'request' end;
  insert into public.chat_members
    (conversation_id, user_id, status, role, mls_state, invited_by, joined_at)
  values (p_conversation, p_user, v_status, 'member', 'to_add', p_actor, now())
  on conflict (conversation_id, user_id) do update
    set status = excluded.status, role = 'member',
        -- Era uscito ma il vecchio telefono è ancora nel gruppo cifrato: va tolto e riaggiunto.
        mls_state = case when chat_members.mls_state in ('to_remove', 'to_readd') then 'to_readd'
                         else 'to_add' end,
        invited_by = excluded.invited_by, joined_at = now(), delivered_upto = 0, read_upto = 0,
        joined_key = null;
  return v_status;
end;
$$;

revoke all on function private.chat_group_me(uuid, text, boolean) from public, anon, authenticated;
revoke all on function private.chat_group_event(uuid, text, jsonb) from public, anon, authenticated;
revoke all on function private.chat_group_size(uuid) from public, anon, authenticated;
revoke all on function private.chat_group_put(uuid, text, text) from public, anon, authenticated;

-- ------------------------------------------------------------ creare e gestire il gruppo
create or replace function public.chat_create_group(p_title text, p_members text[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_id uuid;
  v_user text;
  v_added text[] := '{}';
  v_invited text[] := '{}';
  v_status text;
begin
  perform private.chat_check_not_banned(v_uid);
  if p_title is null or char_length(btrim(p_title)) not between 1 and 60 then
    raise exception 'Il nome del gruppo deve avere da 1 a 60 caratteri' using errcode = '22023';
  end if;
  if coalesce(array_length(p_members, 1), 0) > 255 then
    raise exception 'Al massimo 256 persone in un gruppo' using errcode = '22023';
  end if;
  if not exists (select 1 from public.chat_identities where user_id = v_uid) then
    raise exception 'Apri prima la scheda Chat per attivarla' using errcode = '22023';
  end if;
  if not private.chat_take(v_uid, 'gruppi:' || current_date::text, 20) then
    raise exception 'Hai creato troppi gruppi oggi' using errcode = '22023';
  end if;
  insert into public.chat_conversations (kind, title, created_by)
  values ('group', btrim(p_title), v_uid)
  returning id into v_id;
  insert into public.chat_members (conversation_id, user_id, status, role, mls_state)
  values (v_id, v_uid, 'active', 'admin', 'in');
  foreach v_user in array coalesce(p_members, '{}') loop
    v_status := private.chat_group_put(v_id, v_uid, v_user);
    if v_status = 'active' then
      v_added := v_added || v_user;
    elsif v_status = 'request' then
      v_invited := v_invited || v_user;
    end if;
  end loop;
  perform private.chat_group_event(v_id, v_uid,
    jsonb_build_object('t', 'created', 'by', v_uid, 'added', to_jsonb(v_added), 'invited', to_jsonb(v_invited)));
  return v_id;
end;
$$;

create or replace function public.chat_group_add(p_conversation uuid, p_members text[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_group_me(p_conversation, v_uid, true);
  v_user text;
  v_added text[] := '{}';
  v_invited text[] := '{}';
  v_status text;
begin
  if private.chat_group_size(p_conversation) + coalesce(array_length(p_members, 1), 0) > 256 then
    raise exception 'Al massimo 256 persone in un gruppo' using errcode = '22023';
  end if;
  foreach v_user in array coalesce(p_members, '{}') loop
    v_status := private.chat_group_put(p_conversation, v_uid, v_user);
    if v_status = 'active' then
      v_added := v_added || v_user;
    elsif v_status = 'request' then
      v_invited := v_invited || v_user;
    end if;
  end loop;
  if cardinality(v_added) + cardinality(v_invited) > 0 then
    perform private.chat_group_event(p_conversation, v_uid,
      jsonb_build_object('t', 'added', 'by', v_uid, 'added', to_jsonb(v_added), 'invited', to_jsonb(v_invited)));
  end if;
  return cardinality(v_added) + cardinality(v_invited);
end;
$$;

-- Toglie un membro (amministratori) o esce dal gruppo (p_user = sé stessi).
create or replace function public.chat_group_remove(p_conversation uuid, p_user text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_self boolean := p_user = v_uid;
  v_me public.chat_members := private.chat_group_me(p_conversation, v_uid, not v_self);
  v_target public.chat_members;
  v_next text;
begin
  select * into v_target from public.chat_members
  where conversation_id = p_conversation and user_id = p_user and status in ('active', 'request')
  for update;
  if v_target.user_id is null then
    raise exception 'Non fa parte del gruppo' using errcode = '22023';
  end if;
  update public.chat_members
  set status = 'left', role = 'member',
      mls_state = case when v_target.mls_state = 'to_add' then 'in' else 'to_remove' end
  where conversation_id = p_conversation and user_id = p_user;
  -- Chi non era ancora nel gruppo cifrato non va tolto: si cancella e basta.
  if v_target.mls_state = 'to_add' then
    delete from public.chat_members where conversation_id = p_conversation and user_id = p_user;
  end if;
  -- Il gruppo non resta mai senza amministratori.
  if v_target.role = 'admin' and not exists (
    select 1 from public.chat_members
    where conversation_id = p_conversation and status = 'active' and role = 'admin'
  ) then
    select user_id into v_next from public.chat_members
    where conversation_id = p_conversation and status = 'active'
    order by joined_at, user_id limit 1;
    if v_next is not null then
      update public.chat_members set role = 'admin'
      where conversation_id = p_conversation and user_id = v_next;
    end if;
  end if;
  if v_target.status = 'active' then
    perform private.chat_group_event(p_conversation, v_uid,
      jsonb_build_object('t', case when v_self then 'left' else 'removed' end, 'by', v_uid, 'who', p_user));
  end if;
end;
$$;

create or replace function public.chat_group_set_admin(p_conversation uuid, p_user text, p_admin boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_group_me(p_conversation, v_uid, true);
begin
  if not exists (
    select 1 from public.chat_members
    where conversation_id = p_conversation and user_id = p_user and status = 'active'
  ) then
    raise exception 'Non fa parte del gruppo' using errcode = '22023';
  end if;
  if not p_admin and (
    select count(*) from public.chat_members
    where conversation_id = p_conversation and status = 'active' and role = 'admin'
  ) <= 1 and exists (
    select 1 from public.chat_members
    where conversation_id = p_conversation and user_id = p_user and role = 'admin'
  ) then
    raise exception 'Il gruppo deve avere almeno un amministratore' using errcode = '22023';
  end if;
  update public.chat_members set role = case when p_admin then 'admin' else 'member' end
  where conversation_id = p_conversation and user_id = p_user;
  perform private.chat_group_event(p_conversation, v_uid,
    jsonb_build_object('t', case when p_admin then 'admin' else 'not_admin' end, 'by', v_uid, 'who', p_user));
end;
$$;

create or replace function public.chat_group_update(
  p_conversation uuid,
  p_title text,
  p_description text,
  p_photo_changed boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_group_me(p_conversation, v_uid, true);
  v_old public.chat_conversations;
begin
  if p_title is null or char_length(btrim(p_title)) not between 1 and 60 then
    raise exception 'Il nome del gruppo deve avere da 1 a 60 caratteri' using errcode = '22023';
  end if;
  if char_length(coalesce(p_description, '')) > 500 then
    raise exception 'Descrizione troppo lunga (massimo 500 caratteri)' using errcode = '22023';
  end if;
  select * into v_old from public.chat_conversations where id = p_conversation for update;
  update public.chat_conversations
  set title = btrim(p_title), description = coalesce(p_description, ''),
      photo_version = photo_version + case when p_photo_changed then 1 else 0 end
  where id = p_conversation;
  if v_old.title is distinct from btrim(p_title) then
    perform private.chat_group_event(p_conversation, v_uid,
      jsonb_build_object('t', 'title', 'by', v_uid, 'title', btrim(p_title)));
  end if;
  if p_photo_changed then
    perform private.chat_group_event(p_conversation, v_uid, jsonb_build_object('t', 'photo', 'by', v_uid));
  end if;
end;
$$;

-- ------------------------------------------------------------ codice d'invito
create or replace function public.chat_group_invite_code(p_conversation uuid, p_renew boolean default false)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_group_me(p_conversation, v_uid, true);
  v_code text;
begin
  if p_renew then
    update public.chat_group_invites set revoked = true
    where conversation_id = p_conversation and not revoked;
  end if;
  select code into v_code from public.chat_group_invites
  where conversation_id = p_conversation and not revoked
  order by created_at desc limit 1;
  if v_code is null then
    loop
      v_code := upper(substr(translate(encode(extensions.gen_random_bytes(12), 'base64'), '+/=0O1IL', ''), 1, 10));
      exit when char_length(v_code) = 10
        and not exists (select 1 from public.chat_group_invites where code = v_code);
    end loop;
    insert into public.chat_group_invites (code, conversation_id, created_by)
    values (v_code, p_conversation, v_uid);
  end if;
  return v_code;
end;
$$;

create or replace function public.chat_group_invite_revoke(p_conversation uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_group_me(p_conversation, v_uid, true);
begin
  update public.chat_group_invites set revoked = true
  where conversation_id = p_conversation and not revoked;
end;
$$;

-- Anteprima del gruppo dal codice (nome e numero di membri), prima di entrare.
create or replace function public.chat_group_invite_info(p_code text)
returns table (conversation_id uuid, title text, members integer, already_member boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_conv uuid;
begin
  if not private.chat_take(v_uid, 'codici:' || current_date::text, 50) then
    raise exception 'Troppi codici provati oggi' using errcode = '22023';
  end if;
  select i.conversation_id into v_conv from public.chat_group_invites i
  where i.code = upper(btrim(coalesce(p_code, ''))) and not i.revoked;
  if v_conv is null then
    raise exception 'Codice non valido o scaduto' using errcode = '22023';
  end if;
  return query
    select c.id, c.title, private.chat_group_size(c.id),
           exists (select 1 from public.chat_members m
                   where m.conversation_id = c.id and m.user_id = v_uid and m.status = 'active')
    from public.chat_conversations c where c.id = v_conv;
end;
$$;

create or replace function public.chat_group_join(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_conv uuid;
  v_by text;
begin
  perform private.chat_check_not_banned(v_uid);
  if not private.chat_take(v_uid, 'codici:' || current_date::text, 50) then
    raise exception 'Troppi codici provati oggi' using errcode = '22023';
  end if;
  select i.conversation_id, i.created_by into v_conv, v_by from public.chat_group_invites i
  where i.code = upper(btrim(coalesce(p_code, ''))) and not i.revoked;
  if v_conv is null then
    raise exception 'Codice non valido o scaduto' using errcode = '22023';
  end if;
  if exists (select 1 from public.chat_members
             where conversation_id = v_conv and user_id = v_uid and status = 'active') then
    return v_conv;
  end if;
  if private.chat_group_size(v_conv) >= 256 then
    raise exception 'Il gruppo è pieno (256 persone)' using errcode = '22023';
  end if;
  if not exists (select 1 from public.chat_identities where user_id = v_uid) then
    raise exception 'Apri prima la scheda Chat per attivarla' using errcode = '22023';
  end if;
  insert into public.chat_members (conversation_id, user_id, status, role, mls_state, invited_by, joined_at)
  values (v_conv, v_uid, 'active', 'member', 'to_add', v_by, now())
  on conflict (conversation_id, user_id) do update
    set status = 'active', role = 'member',
        mls_state = case when chat_members.mls_state in ('to_remove', 'to_readd') then 'to_readd'
                         else 'to_add' end,
        invited_by = excluded.invited_by, joined_at = now(), delivered_upto = 0, read_upto = 0,
        joined_key = null;
  perform private.chat_group_event(v_conv, v_uid, jsonb_build_object('t', 'joined', 'by', v_uid));
  return v_conv;
end;
$$;

-- ------------------------------------------------------------ gruppo cifrato (MLS)
-- Membri del gruppo con lo stato cifrato: serve ai telefoni per allinearsi.
create or replace function public.chat_group_members(p_conversation uuid)
returns table (
  user_id text,
  username text,
  public_name text,
  avatar_thumb_path text,
  role text,
  status text,
  mls_state text,
  signature_key text,
  joined_key text,
  invited_by text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
begin
  if not exists (
    select 1 from public.chat_members m join public.chat_conversations c on c.id = m.conversation_id
    where m.conversation_id = p_conversation and m.user_id = v_uid and c.kind = 'group'
      and m.status in ('active', 'request')
  ) then
    raise exception 'Gruppo non trovato' using errcode = '42501';
  end if;
  return query
    select m.user_id, p.username::text, p.public_name, p.avatar_thumb_path, m.role, m.status,
           m.mls_state, i.signature_key, m.joined_key, m.invited_by
    from public.chat_members m
    join public.profiles p on p.id = m.user_id
    left join public.chat_identities i on i.user_id = m.user_id
    where m.conversation_id = p_conversation
      and (m.status in ('active', 'request') or m.mls_state = 'to_remove')
    order by (m.role = 'admin') desc, p.public_name;
end;
$$;

-- Pacchetto chiave di un membro da aggiungere al gruppo cifrato (solo amministratori).
create or replace function public.chat_group_claim_key_package(p_conversation uuid, p_user text)
returns table (package text, signature_key text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_group_me(p_conversation, v_uid, true);
  v_kp public.chat_key_packages;
begin
  if not exists (
    select 1 from public.chat_members
    where conversation_id = p_conversation and user_id = p_user and status = 'active'
      and mls_state in ('to_add', 'to_readd')
  ) then
    raise exception 'Questa persona non va aggiunta' using errcode = '22023';
  end if;
  if not private.chat_take(v_uid, 'pacchetti:' || current_date::text, 600) then
    raise exception 'Riprova più tardi' using errcode = '22023';
  end if;
  select * into v_kp from public.chat_key_packages k
  where k.user_id = p_user order by k.id limit 1 for update skip locked;
  if v_kp.id is null then
    raise exception 'Un membro deve aprire l''app per attivare la chat' using errcode = '22023';
  end if;
  delete from public.chat_key_packages where id = v_kp.id;
  return query
    select v_kp.package, i.signature_key from public.chat_identities i where i.user_id = p_user;
end;
$$;

-- Modifica del gruppo cifrato fatta da un amministratore (o la sua nascita, con
-- p_commit null e generazione 0): commit per tutti, inviti cifrati per chi entra.
create or replace function public.chat_group_commit(
  p_conversation uuid,
  p_generation integer,
  p_group_id text,
  p_commit text,
  p_welcome text,
  p_added text[],
  p_removed text[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_group_me(p_conversation, v_uid, true);
  v_conv public.chat_conversations;
  v_next integer;
  v_commit_id bigint := 0;
  v_user text;
begin
  select * into v_conv from public.chat_conversations where id = p_conversation for update;
  if v_conv.generation <> p_generation then
    raise exception 'Il gruppo è appena cambiato: riprova' using errcode = '40001';
  end if;
  if (p_generation = 0) <> (p_commit is null) or (p_generation = 0 and v_me.mls_state <> 'in') then
    raise exception 'Modifica del gruppo non valida' using errcode = '22023';
  end if;
  if p_group_id is null or p_group_id !~ '^[A-Za-z0-9+/]{4,200}={0,2}$'
     or (v_conv.mls_group_id is not null and v_conv.mls_group_id <> p_group_id) then
    raise exception 'Gruppo cifrato non valido' using errcode = '22023';
  end if;
  if (coalesce(cardinality(p_added), 0) > 0) <> (p_welcome is not null) then
    raise exception 'Invito cifrato mancante' using errcode = '22023';
  end if;
  foreach v_user in array coalesce(p_added, '{}') loop
    if not exists (select 1 from public.chat_members where conversation_id = p_conversation
                   and user_id = v_user and status = 'active' and mls_state in ('to_add', 'to_readd')) then
      raise exception 'Persona da aggiungere non valida' using errcode = '22023';
    end if;
  end loop;
  foreach v_user in array coalesce(p_removed, '{}') loop
    if not exists (select 1 from public.chat_members where conversation_id = p_conversation
                   and user_id = v_user and mls_state in ('to_remove', 'to_readd')) then
      raise exception 'Persona da togliere non valida' using errcode = '22023';
    end if;
  end loop;
  v_next := p_generation + 1;
  if p_commit is not null then
    insert into public.chat_messages (conversation_id, generation, sender_id, kind, payload)
    values (p_conversation, p_generation, v_uid, 'commit', p_commit)
    returning id into v_commit_id;
  end if;
  if p_welcome is not null then
    foreach v_user in array p_added loop
      insert into public.chat_messages (conversation_id, generation, sender_id, kind, recipient_id, payload)
      values (p_conversation, v_next, v_uid, 'welcome', v_user, p_welcome);
    end loop;
  end if;
  update public.chat_conversations
  set generation = v_next, mls_group_id = p_group_id
  where id = p_conversation;
  -- Chi entra riceve solo da qui in avanti.
  update public.chat_members m
  set mls_state = 'in', from_id = v_commit_id, delivered_upto = v_commit_id, read_upto = v_commit_id,
      joined_key = (select i.signature_key from public.chat_identities i where i.user_id = m.user_id)
  where m.conversation_id = p_conversation and m.user_id = any (coalesce(p_added, '{}'));
  -- Chi è uscito sparisce; chi ha cambiato telefono senza essere riaggiunto resta da aggiungere.
  delete from public.chat_members m
  where m.conversation_id = p_conversation and m.user_id = any (coalesce(p_removed, '{}'))
    and m.mls_state = 'to_remove';
  update public.chat_members m set mls_state = 'to_add'
  where m.conversation_id = p_conversation and m.user_id = any (coalesce(p_removed, '{}'))
    and m.mls_state = 'to_readd' and not (m.user_id = any (coalesce(p_added, '{}')));
  if p_generation = 0 then
    update public.chat_members m
    set joined_key = (select i.signature_key from public.chat_identities i where i.user_id = m.user_id)
    where m.conversation_id = p_conversation and m.user_id = v_uid;
  end if;
  return v_next;
end;
$$;

-- Il mio telefono non ha più il gruppo cifrato (telefono nuovo, troppo tempo offline):
-- chiedo a un amministratore di riaggiungermi.
create or replace function public.chat_group_rejoin(p_conversation uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_group_me(p_conversation, v_uid, false);
begin
  if v_me.mls_state = 'in' then
    update public.chat_members set mls_state = 'to_readd'
    where conversation_id = p_conversation and user_id = v_uid;
  end if;
end;
$$;

revoke all on function public.chat_create_group(text, text[]) from public, anon;
revoke all on function public.chat_group_add(uuid, text[]) from public, anon;
revoke all on function public.chat_group_remove(uuid, text) from public, anon;
revoke all on function public.chat_group_set_admin(uuid, text, boolean) from public, anon;
revoke all on function public.chat_group_update(uuid, text, text, boolean) from public, anon;
revoke all on function public.chat_group_invite_code(uuid, boolean) from public, anon;
revoke all on function public.chat_group_invite_revoke(uuid) from public, anon;
revoke all on function public.chat_group_invite_info(text) from public, anon;
revoke all on function public.chat_group_join(text) from public, anon;
revoke all on function public.chat_group_members(uuid) from public, anon;
revoke all on function public.chat_group_claim_key_package(uuid, text) from public, anon;
revoke all on function public.chat_group_commit(uuid, integer, text, text, text, text[], text[]) from public, anon;
revoke all on function public.chat_group_rejoin(uuid) from public, anon;
grant execute on function public.chat_create_group(text, text[]) to authenticated;
grant execute on function public.chat_group_add(uuid, text[]) to authenticated;
grant execute on function public.chat_group_remove(uuid, text) to authenticated;
grant execute on function public.chat_group_set_admin(uuid, text, boolean) to authenticated;
grant execute on function public.chat_group_update(uuid, text, text, boolean) to authenticated;
grant execute on function public.chat_group_invite_code(uuid, boolean) to authenticated;
grant execute on function public.chat_group_invite_revoke(uuid) to authenticated;
grant execute on function public.chat_group_invite_info(text) to authenticated;
grant execute on function public.chat_group_join(text) to authenticated;
grant execute on function public.chat_group_members(uuid) to authenticated;
grant execute on function public.chat_group_claim_key_package(uuid, text) to authenticated;
grant execute on function public.chat_group_commit(uuid, integer, text, text, text, text[], text[]) to authenticated;
grant execute on function public.chat_group_rejoin(uuid) to authenticated;

-- ------------------------------------------------------------ funzioni della chat estese ai gruppi
-- Telefono nuovo: nei gruppi va tolto il vecchio telefono e aggiunto quello nuovo.
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
    update public.chat_members m set mls_state = 'to_readd'
    from public.chat_conversations c
    where c.id = m.conversation_id and c.kind = 'group' and m.user_id = v_uid
      and m.status = 'active' and m.mls_state = 'in';
  end if;
  perform public.chat_add_key_packages(p_packages);
end;
$$;

-- Scrivere: nei gruppi solo i membri dentro il gruppo cifrato.
create or replace function public.chat_send(p_conversation uuid, p_generation integer, p_payload text)
returns table (id bigint, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_me(p_conversation, v_uid);
  v_conv public.chat_conversations;
  v_other text;
  v_other_status text;
  v_id bigint;
  v_at timestamptz;
begin
  perform private.chat_check_not_banned(v_uid);
  select * into v_conv from public.chat_conversations where chat_conversations.id = p_conversation;
  if v_conv.kind = 'group' then
    if v_me.status <> 'active' or v_me.mls_state <> 'in' then
      raise exception 'Non fai più parte di questo gruppo' using errcode = '42501';
    end if;
  else
    v_other := private.chat_other(p_conversation, v_uid);
    if public.is_blocked_between(v_uid, v_other) then
      raise exception 'Non puoi scrivere in questa chat' using errcode = '42501';
    end if;
  end if;
  if v_conv.generation = 0 or v_conv.generation <> p_generation then
    raise exception 'La chat è appena cambiata: riprova' using errcode = '40001';
  end if;
  if p_payload is null or char_length(p_payload) > 90000 then
    raise exception 'Messaggio troppo lungo' using errcode = '22023';
  end if;
  if v_conv.kind = 'direct' then
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
  delete from public.chat_messages m
  where m.conversation_id = p_conversation and m.created_at < now() - interval '30 days';
  delete from private.chat_limits l
  where l.user_id = v_uid and l.bucket like 'minuto:%'
    and l.bucket < 'minuto:' || to_char(now() - interval '2 minutes', 'YYYYMMDDHH24MI');
  return query select v_id, v_at;
end;
$$;

-- Ricevere: chat a due come prima; nei gruppi messaggi, commit e avvisi per chi è dentro
-- (dal suo ingresso in poi) e gli inviti cifrati per chi entra.
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
  join public.chat_conversations c on c.id = m.conversation_id
  where m.id > coalesce(p_after, 0)
    and (
      (c.kind = 'direct'
        and me.status <> 'declined'
        and m.sender_id <> me.user_id
        and (m.kind = 'app' or m.recipient_id = me.user_id)
        and not public.is_blocked_between(me.user_id, m.sender_id))
      or
      (c.kind = 'group'
        and me.status = 'active'
        and (
          m.recipient_id = me.user_id
          or (me.mls_state = 'in' and m.id > me.from_id
              and (m.kind = 'event' or (m.kind in ('app', 'commit') and m.sender_id <> me.user_id)))
        ))
    )
  order by m.id
  limit least(greatest(coalesce(p_limit, 200), 1), 500);
$$;

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
  invited_by text
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
         null::text, ''::text, 0, me.role, me.mls_state, 2, 0, null::text
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
         me.invited_by
  from public.chat_members me
  join public.chat_conversations c on c.id = me.conversation_id and c.kind = 'group'
  where me.user_id = private.chat_uid()
    and me.status in ('active', 'request')
  order by 17 desc nulls last, 19 desc;
$$;
revoke all on function public.chat_conversations() from public, anon;
grant execute on function public.chat_conversations() to authenticated;

-- Spunte e pulizia: nei gruppi un messaggio sparisce quando tutti l'hanno ricevuto.
create or replace function public.chat_mark(p_conversation uuid, p_delivered bigint, p_read bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_me(p_conversation, v_uid);
  v_kind text;
  v_last bigint;
  v_delivered bigint;
  v_read bigint;
begin
  select c.kind into v_kind from public.chat_conversations c where c.id = p_conversation;
  select greatest(
    (select c.last_message_id from public.chat_conversations c where c.id = p_conversation),
    (select max(m.id) from public.chat_messages m
     where m.conversation_id = p_conversation
       and (m.kind in ('app', 'commit', 'event') or m.recipient_id = v_uid))
  ) into v_last;
  v_delivered := greatest(v_me.delivered_upto, least(coalesce(p_delivered, 0), coalesce(v_last, 0)));
  v_read := greatest(v_me.read_upto, least(coalesce(p_read, 0), coalesce(v_last, 0)));
  if v_read > v_delivered then
    v_delivered := v_read;
  end if;
  update public.chat_members
  set delivered_upto = v_delivered, read_upto = v_read
  where conversation_id = p_conversation and user_id = v_uid;
  if v_kind = 'direct' then
    delete from public.chat_messages m
    where m.conversation_id = p_conversation
      and m.sender_id <> v_uid
      and m.id <= v_delivered
      and (m.kind = 'app' or m.recipient_id = v_uid);
  else
    delete from public.chat_messages m
    where m.conversation_id = p_conversation and m.recipient_id = v_uid and m.id <= v_delivered;
    delete from public.chat_messages m
    where m.conversation_id = p_conversation
      and m.recipient_id is null
      and m.id <= v_delivered
      and not exists (
        select 1 from public.chat_members o
        where o.conversation_id = p_conversation
          and o.status = 'active' and o.mls_state = 'in'
          -- Gli avvisi servono anche a chi li ha causati.
          and (o.user_id <> m.sender_id or m.kind = 'event')
          and o.from_id < m.id
          and o.delivered_upto < m.id
      );
  end if;
end;
$$;

-- Richieste: per i gruppi «accetta» vuol dire entrare (un amministratore ti aggiunge al
-- gruppo cifrato), «rifiuta» vuol dire uscire dall'elenco.
create or replace function public.chat_respond_request(p_conversation uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := private.chat_uid();
  v_me public.chat_members := private.chat_me(p_conversation, v_uid);
  v_kind text;
begin
  if v_me.status <> 'request' then
    raise exception 'Non è una richiesta in attesa' using errcode = '22023';
  end if;
  select kind into v_kind from public.chat_conversations where id = p_conversation;
  if v_kind = 'group' then
    if p_accept then
      update public.chat_members set status = 'active', mls_state = 'to_add', joined_at = now()
      where conversation_id = p_conversation and user_id = v_uid;
      perform private.chat_group_event(p_conversation, v_uid, jsonb_build_object('t', 'joined', 'by', v_uid));
    else
      delete from public.chat_members where conversation_id = p_conversation and user_id = v_uid;
    end if;
    return;
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

-- ------------------------------------------------------------ foto del gruppo
-- Contenitore privato: la leggono i membri, la cambiano gli amministratori.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-group-photos', 'chat-group-photos', false, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.chat_group_role(p_conversation text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null or p_conversation is null
     or p_conversation !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  return (
    select m.role from public.chat_members m
    join public.chat_conversations c on c.id = m.conversation_id and c.kind = 'group'
    where m.conversation_id = p_conversation::uuid and m.user_id = v_uid
      and m.status in ('active', 'request')
  );
end;
$$;
revoke all on function public.chat_group_role(text) from public, anon;
grant execute on function public.chat_group_role(text) to authenticated;

create policy "foto gruppo: lettura per i membri"
  on storage.objects for select to authenticated
  using (bucket_id = 'chat-group-photos' and public.chat_group_role((storage.foldername(name))[1]) is not null);

create policy "foto gruppo: caricamento per gli amministratori"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-group-photos'
    and name ~ '^[0-9a-f-]{36}/foto\.jpg$'
    and public.chat_group_role((storage.foldername(name))[1]) = 'admin'
  );

create policy "foto gruppo: sostituzione per gli amministratori"
  on storage.objects for update to authenticated
  using (bucket_id = 'chat-group-photos' and public.chat_group_role((storage.foldername(name))[1]) = 'admin')
  with check (
    bucket_id = 'chat-group-photos'
    and name ~ '^[0-9a-f-]{36}/foto\.jpg$'
    and public.chat_group_role((storage.foldername(name))[1]) = 'admin'
  );

create policy "foto gruppo: cancellazione per gli amministratori"
  on storage.objects for delete to authenticated
  using (bucket_id = 'chat-group-photos' and public.chat_group_role((storage.foldername(name))[1]) = 'admin');

-- Gli allegati della chat valgono anche nei gruppi (solo per chi è dentro il gruppo cifrato).
create or replace function public.chat_media_member(p_conversation text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_conv uuid;
  v_kind text;
begin
  if v_uid is null or p_conversation is null
     or p_conversation !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  v_conv := p_conversation::uuid;
  select kind into v_kind from public.chat_conversations where id = v_conv;
  if v_kind = 'group' then
    return exists (
      select 1 from public.chat_members me
      where me.conversation_id = v_conv and me.user_id = v_uid
        and me.status = 'active' and me.mls_state = 'in'
    );
  end if;
  return exists (
    select 1
    from public.chat_members me
    join public.chat_members other
      on other.conversation_id = me.conversation_id and other.user_id <> me.user_id
    where me.conversation_id = v_conv
      and me.user_id = v_uid
      and me.status <> 'declined'
      and not public.is_blocked_between(me.user_id, other.user_id)
  );
end;
$$;

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

-- Fase 4 · Blocco 8: chiamate vocali e videochiamate (chat a due).
--
-- La chiamata viaggia come i messaggi: offerta, risposta e chiusura sono messaggi cifrati MLS
-- (il server non legge nulla). `call_signal` li consegna con chat_send e dice alle notifiche
-- se far squillare il telefono («Chiamata in arrivo») o restare in silenzio (risposta, chiusura).
-- L'audio e il video passano da telefono a telefono (DTLS-SRTP), al massimo tramite il ponte
-- TURN di Cloudflare, che non può leggerli. Le credenziali del ponte le dà la funzione `chiamate`.

-- Limiti: credenziali del ponte (funzione `chiamate`) e squilli.
alter table private.contacts_limits drop constraint if exists contacts_limits_kind_check;
alter table private.contacts_limits
  add constraint contacts_limits_kind_check check (kind in ('sincronizzazioni', 'mio_numero', 'turn'));

alter table private.push_queue drop constraint if exists push_queue_kind_check;
alter table private.push_queue
  add constraint push_queue_kind_check check (kind in ('chat', 'comment', 'market', 'call'));

create table private.call_rings (
  user_id text not null,
  at timestamptz not null default now()
);
create index call_rings_user_idx on private.call_rings (user_id, at);

-- Le chiamate rispettano «Messaggi», «Non disturbare» e «Silenzia» come i messaggi.
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
  if (p_kind in ('chat', 'call') and not v_prefs.messages)
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

revoke all on function private.push_enqueue(text, text, uuid, text, text, text) from public, anon, authenticated;

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
  v_call text := coalesce(current_setting('piazly.call', true), '');
begin
  -- Risposta, chiusura o rifiuto di una chiamata: nessuna notifica.
  if v_call = 'quiet' then
    return null;
  end if;
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
    if v_call in ('voice', 'video') then
      v_title := case when v_prefs.preview then coalesce(v_sender, 'Piazly') else 'Piazly' end;
      v_body := case when v_call = 'video' then 'Videochiamata in arrivo' else 'Chiamata in arrivo' end;
      perform private.push_enqueue(v_member.user_id, 'call', new.conversation_id,
                                   'call:' || new.conversation_id::text, v_title, v_body);
      continue;
    end if;
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

revoke all on function private.push_on_chat_message() from public, anon, authenticated;

-- Messaggio di una chiamata. [p_ring]: è l'offerta (fa squillare); altrimenti silenzioso.
-- Solo nelle chat a due già accettate da entrambi e senza blocchi; al massimo 30 squilli l'ora.
create or replace function public.call_signal(
  p_conversation uuid,
  p_generation integer,
  p_payload text,
  p_ring boolean,
  p_video boolean
)
returns table (id bigint, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_other text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select o.user_id into v_other
  from public.chat_conversations c
  join public.chat_members me on me.conversation_id = c.id and me.user_id = v_uid and me.status = 'active'
  join public.chat_members o on o.conversation_id = c.id and o.user_id <> v_uid and o.status = 'active'
  where c.id = p_conversation and c.kind = 'direct';
  if v_other is null or public.is_blocked_between(v_uid, v_other) then
    raise exception 'Chiamata non possibile in questa chat' using errcode = '42501';
  end if;
  if coalesce(p_ring, false) then
    if (select count(*) from private.call_rings r where r.user_id = v_uid and r.at > now() - interval '1 hour') >= 30 then
      raise exception 'Troppe chiamate: riprova più tardi' using errcode = '54000';
    end if;
    insert into private.call_rings (user_id) values (v_uid);
    delete from private.call_rings r where r.at < now() - interval '1 day';
  end if;
  perform set_config('piazly.call',
    case when coalesce(p_ring, false) then (case when coalesce(p_video, false) then 'video' else 'voice' end)
         else 'quiet' end,
    true);
  return query select s.id, s.created_at from public.chat_send(p_conversation, p_generation, p_payload) s;
  perform set_config('piazly.call', '', true);
end;
$$;

revoke all on function public.call_signal(uuid, integer, text, boolean, boolean) from public, anon;
grant execute on function public.call_signal(uuid, integer, text, boolean, boolean) to authenticated;

select private.align_anon_with_authenticated();

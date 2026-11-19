-- Fase 4 · Blocco 10: chiamate e videochiamate di gruppo.
--
-- Come per le chiamate a due, ogni passaggio è un messaggio cifrato MLS del gruppo: il server
-- non legge nulla. Si collegano fino a 4 persone, ognuna direttamente con le altre (o tramite
-- il ponte TURN). Possono chiamare i membri del gruppo che sono dentro anche alla cifratura,
-- in gruppi fino a 8 membri. Lo squillo arriva ai membri come «Chiamata di gruppo».

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
  v_kind text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select c.kind into v_kind from public.chat_conversations c where c.id = p_conversation;
  if v_kind = 'group' then
    -- Gruppo: chi chiama deve essere dentro (anche cifratura), e il gruppo al massimo di 8.
    if not exists (select 1 from public.chat_members me where me.conversation_id = p_conversation
                   and me.user_id = v_uid and me.status = 'active' and me.mls_state = 'in') then
      raise exception 'Chiamata non possibile in questa chat' using errcode = '42501';
    end if;
    if (select count(*) from public.chat_members m where m.conversation_id = p_conversation
        and m.status = 'active') > 8 then
      raise exception 'Chiamate di gruppo fino a 8 membri' using errcode = '22023';
    end if;
  else
    select o.user_id into v_other
    from public.chat_conversations c
    join public.chat_members me on me.conversation_id = c.id and me.user_id = v_uid and me.status = 'active'
    join public.chat_members o on o.conversation_id = c.id and o.user_id <> v_uid and o.status = 'active'
    where c.id = p_conversation and c.kind = 'direct';
    if v_other is null or public.is_blocked_between(v_uid, v_other) then
      raise exception 'Chiamata non possibile in questa chat' using errcode = '42501';
    end if;
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
      if v_conv.kind = 'group' then
        v_title := case when v_prefs.preview then v_conv.title else 'Piazly' end;
        v_body := case when v_prefs.preview then coalesce(v_sender, 'Un membro') || ' · ' else '' end
                  || case when v_call = 'video' then 'Videochiamata di gruppo' else 'Chiamata di gruppo' end;
      else
        v_title := case when v_prefs.preview then coalesce(v_sender, 'Piazly') else 'Piazly' end;
        v_body := case when v_call = 'video' then 'Videochiamata in arrivo' else 'Chiamata in arrivo' end;
      end if;
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

select private.align_anon_with_authenticated();

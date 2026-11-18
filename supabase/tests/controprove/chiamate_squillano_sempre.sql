-- Difetto introdotto apposta: ogni passaggio della chiamata fa squillare. Deve far fallire X1.
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
  perform set_config('piazly.call', case when coalesce(p_video, false) then 'video' else 'voice' end, true);
  return query select s.id, s.created_at from public.chat_send(p_conversation, p_generation, p_payload) s;
  perform set_config('piazly.call', '', true);
end;
$$;

select private.align_anon_with_authenticated();

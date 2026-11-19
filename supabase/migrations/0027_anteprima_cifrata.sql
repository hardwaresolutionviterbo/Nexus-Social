-- Fase 4 · Blocco 10: testo del messaggio nella notifica, senza che il server lo legga.
--
-- Chi scrive cifra una breve anteprima (al massimo 100 caratteri) con una chiave sua, che ha
-- già mandato ai membri della chat dentro la chat cifrata (MLS). Il server passa l'anteprima
-- cifrata alla notifica così com'è: la decifra solo il telefono di chi riceve. Se «Mostra chi
-- scrive» è spento, l'anteprima non parte. Senza anteprima resta «Nuovo messaggio».

alter table private.push_queue add column if not exists preview text;
alter table private.push_queue add column if not exists sender_id text;

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
  v_preview text := nullif(current_setting('piazly.preview', true), '');
  v_sender text := nullif(current_setting('piazly.sender', true), '');
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
  -- L'anteprima solo per i messaggi e solo con «Mostra chi scrive» acceso.
  if p_kind <> 'chat' or not v_prefs.preview then
    v_preview := null;
    v_sender := null;
  end if;
  select * into v_row from private.push_queue
  where user_id = p_user and collapse_key = p_collapse
  for update;
  if v_row.id is not null then
    update private.push_queue
    set count = count + 1, title = p_title,
        body = case when p_kind = 'chat' and v_prefs.preview
                    then (count + 1)::text || ' nuovi messaggi' else p_body end,
        preview = v_preview, sender_id = v_sender,
        created_at = now()
    where id = v_row.id;
  else
    insert into private.push_queue (user_id, kind, conversation_id, collapse_key, title, body, preview, sender_id)
    values (p_user, p_kind, p_conversation, p_collapse, p_title, p_body, v_preview, v_sender);
  end if;
  perform private.push_kick();
end;
$$;

revoke all on function private.push_enqueue(text, text, uuid, text, text, text) from public, anon, authenticated;

-- Messaggio con anteprima cifrata: stesse regole di chat_send.
create or replace function public.chat_send_preview(
  p_conversation uuid,
  p_generation integer,
  p_payload text,
  p_preview text
)
returns table (id bigint, created_at timestamptz)
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
  if p_preview is not null and (char_length(p_preview) > 600 or p_preview !~ '^[A-Za-z0-9+/=]+$') then
    raise exception 'Anteprima non valida' using errcode = '22023';
  end if;
  perform set_config('piazly.preview', coalesce(p_preview, ''), true);
  perform set_config('piazly.sender', v_uid, true);
  return query select s.id, s.created_at from public.chat_send(p_conversation, p_generation, p_payload) s;
  perform set_config('piazly.preview', '', true);
  perform set_config('piazly.sender', '', true);
end;
$$;

revoke all on function public.chat_send_preview(uuid, integer, text, text) from public, anon;
grant execute on function public.chat_send_preview(uuid, integer, text, text) to authenticated;

-- La funzione «notifiche» riceve anche anteprima cifrata, autore e numero di messaggi.
drop function if exists public.push_claim(integer);
create function public.push_claim(p_limit integer default 100)
returns table (queue_id bigint, fid text, platform text, kind text, conversation_id uuid,
               collapse_key text, title text, body text, preview text, sender_id text, count integer)
language sql
security definer
set search_path = public
as $$
  with taken as (
    delete from private.push_queue q
    where q.id in (select id from private.push_queue order by id limit greatest(1, least(p_limit, 500)))
    returning q.*
  )
  select t.id, d.fid, d.platform, t.kind, t.conversation_id, t.collapse_key, t.title, t.body,
         t.preview, t.sender_id, t.count
  from taken t join public.push_devices d on d.user_id = t.user_id;
$$;

revoke all on function public.push_claim(integer) from public, anon, authenticated;
grant execute on function public.push_claim(integer) to service_role;

select private.align_anon_with_authenticated();

-- Difetto introdotto apposta: l'anteprima parte anche con «Mostra chi scrive» spento. Deve far fallire AP2.
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
  if p_kind <> 'chat' then
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

select private.align_anon_with_authenticated();

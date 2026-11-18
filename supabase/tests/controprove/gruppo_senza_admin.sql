-- Difetto introdotto apposta: qualunque membro gestisce il gruppo. Deve far fallire T2.
create or replace function private.chat_group_me(p_conversation uuid, p_uid text, p_admin boolean)
returns public.chat_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.chat_members;
begin
  select m.* into v_row from public.chat_members m
  where m.conversation_id = p_conversation and m.user_id = p_uid and m.status = 'active';
  if v_row.user_id is null then
    raise exception 'Gruppo non trovato' using errcode = '42501';
  end if;
  return v_row;
end;
$$;

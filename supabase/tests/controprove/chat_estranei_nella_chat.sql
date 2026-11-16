-- Difetto introdotto apposta: chiunque passa per membro di qualsiasi chat. Deve far fallire R3.
create or replace function private.chat_me(p_conversation uuid, p_uid text)
returns public.chat_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.chat_members;
begin
  select * into v_row from public.chat_members where conversation_id = p_conversation limit 1;
  if v_row.user_id is null then
    raise exception 'Chat non trovata' using errcode = '42501';
  end if;
  return v_row;
end;
$$;

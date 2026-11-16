-- Difetto introdotto apposta: nessun limite anti-spam nella chat. Deve far fallire R7.
create or replace function private.chat_take(p_uid text, p_bucket text, p_max integer)
returns boolean
language sql
as $$ select true; $$;

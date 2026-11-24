-- Difetto introdotto apposta: il gestionale si apre senza la verifica in due passaggi.
-- Deve far fallire GS1.
create or replace function private.require_admin_2fa()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null or not public.is_admin() then
    raise exception 'Solo gli amministratori' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

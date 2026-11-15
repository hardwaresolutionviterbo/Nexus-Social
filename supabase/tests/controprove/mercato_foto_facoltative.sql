-- Difetto introdotto apposta: le foto non sono più obbligatorie. Deve far fallire M3.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'check_market_listing';
  execute replace(v_def, 'if p_type <> ''wanted'' and v_n < 1 then', 'if false then');
end;
$$;

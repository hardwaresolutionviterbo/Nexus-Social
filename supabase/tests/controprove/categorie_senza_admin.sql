-- Difetto introdotto apposta: chiunque gestisce le categorie. Deve far fallire Q7.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('private.require_admin()'::regprocedure) into v_def;
  execute replace(v_def, 'if not public.is_admin() then', 'if false then');
end;
$$;

-- Difetto introdotto apposta: anche i Non mi piace avvisano l'autore. Deve far fallire L2.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'set_listing_reaction';
  execute replace(v_def, 'if p_kind = ''like'' and v_before is distinct from ''like'' then',
                  'if v_before is distinct from p_kind then');
end;
$$;

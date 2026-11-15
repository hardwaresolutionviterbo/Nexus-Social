-- Difetto introdotto apposta: l'elenco dei commenti ignora i blocchi. Deve far fallire L7.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'listing_comments_list';
  execute replace(v_def, 'and not public.is_blocked_between(c.author_id, v_uid)', '');
end;
$$;

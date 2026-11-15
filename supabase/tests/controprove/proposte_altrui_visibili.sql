-- Difetto introdotto apposta: l'elenco delle proposte mostra anche quelle altrui. Deve far fallire O2.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.my_swap_proposals()'::regprocedure) into v_def;
  execute replace(v_def, 'where public.current_uid() in (p.owner_id, p.requester_id)', 'where true');
end;
$$;

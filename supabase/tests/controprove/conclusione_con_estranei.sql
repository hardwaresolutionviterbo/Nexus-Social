-- Difetto introdotto apposta: si può indicare come controparte chiunque. Deve far fallire P1.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.mark_listing_concluded(uuid, text)'::regprocedure) into v_def;
  execute replace(
    v_def,
    'if not exists (select 1 from public.deal_candidates(p_listing) c where c.id = p_other) then',
    'if false then'
  );
end;
$$;

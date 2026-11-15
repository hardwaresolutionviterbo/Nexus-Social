-- Difetto introdotto apposta: la ricerca mostra anche gli annunci in revisione. Deve far fallire N8.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('private.market_rows(double precision, double precision)'::regprocedure)
  into v_def;
  execute replace(
    v_def,
    'and (l.review_status = ''published'' or l.owner_id = public.current_uid())',
    ''
  );
end;
$$;

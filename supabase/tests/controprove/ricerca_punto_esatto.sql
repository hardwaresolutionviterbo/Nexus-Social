-- Difetto introdotto apposta: la ricerca restituisce il punto salvato al posto di quello
-- pubblico. Deve far fallire N4.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('private.market_rows(double precision, double precision)'::regprocedure)
  into v_def;
  execute replace(
    v_def,
    'st_y(l.approx_location::geometry), st_x(l.approx_location::geometry),',
    '(select st_y(ll.exact_location::geometry) from public.listing_locations ll where ll.listing_id = l.id), '
      || '(select st_x(ll.exact_location::geometry) from public.listing_locations ll where ll.listing_id = l.id),'
  );
end;
$$;

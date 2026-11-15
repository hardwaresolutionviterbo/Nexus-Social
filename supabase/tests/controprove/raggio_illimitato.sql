-- Difetto introdotto apposta: il raggio richiesto non viene più limitato a 30 km.
-- Deve far fallire K2 (Milano vedrebbe Torino).
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'map_listings_nearby';
  execute replace(v_def, 'least(greatest(coalesce(p_radius_m, 10000), 1000), 30000)',
                  'greatest(coalesce(p_radius_m, 10000), 1000)');
end;
$$;

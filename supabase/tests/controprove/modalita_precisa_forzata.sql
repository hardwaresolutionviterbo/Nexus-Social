-- Difetto introdotto apposta: si torna a permettere «approssimata → precisa» sul punto
-- salvato, che mostrerebbe la posizione reale del telefono. Deve far fallire J4.
create or replace function public.set_listing_location_mode(
  p_listing_id uuid,
  p_mode public.location_mode
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_exact extensions.geography;
begin
  select ll.exact_location into v_exact
  from public.listings l
  join public.listing_locations ll on ll.listing_id = l.id
  where l.id = p_listing_id and l.owner_id = public.current_uid();
  if v_exact is null then
    raise exception 'Annuncio non trovato o non tuo' using errcode = '42501';
  end if;
  perform set_config('nexus.internal', 'on', true);
  update public.listings
  set location_mode = p_mode,
      approx_location = public.public_point(v_exact, p_mode)
  where id = p_listing_id;
  perform set_config('nexus.internal', 'off', true);
end;
$$;

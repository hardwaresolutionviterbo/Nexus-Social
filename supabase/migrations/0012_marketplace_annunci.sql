-- Piazly · Fase 5, Blocco 1: annunci di Scambia & Vendi (un solo sistema, 4 tipologie).
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Decisioni (docs/fase5/PIANO_OPERATIVO.md e CATALOGO_TITOLARE.md):
--  • tipologie: sell (Vendita), swap (Scambio), free (Regalo), wanted (Cerco);
--  • prezzo obbligatorio per la Vendita, facoltativo per Scambio e Cerco, assente per il Regalo;
--    in centesimi di euro, fino a 999.999.999 € (immobili);
--  • condizioni dell'oggetto: new, like_new, excellent, good, fair, to_repair;
--  • foto obbligatorie (1-10) per Vendita, Scambio e Regalo (D11), facoltative per Cerco;
--  • campi specifici (D3): motori anno e km (anno obbligatorio per Auto), immobili metri
--    quadri (obbligatori) e locali, abbigliamento e scarpe taglia/numero, elettronica memoria;
--  • durata 30 giorni, rinnovabile (D5); 20 annunci nuovi al giorno per persona (D9);
--  • prodotti vietati: conferma obbligatoria; parole a rischio → annuncio in revisione, non
--    visibile agli altri finché un amministratore non lo approva; niente animali vivi;
--  • questi annunci non compaiono sulla Mappa (D10).

-- ------------------------------------------------------------ colonne
alter table public.listings
  add column market_type text check (market_type in ('sell', 'swap', 'free', 'wanted')),
  add column market_category_id uuid references public.marketplace_categories (id) on delete restrict,
  add column market_price_cents bigint
    check (market_price_cents is null or market_price_cents between 0 and 99999999900),
  add column item_condition text
    check (item_condition in ('new', 'like_new', 'excellent', 'good', 'fair', 'to_repair')),
  add column ships boolean not null default false,
  add column pickup boolean not null default false,
  add column attributes jsonb not null default '{}'::jsonb,
  add column wanted_in_exchange text
    check (wanted_in_exchange is null or char_length(wanted_in_exchange) <= 300),
  add column review_status text not null default 'published'
    check (review_status in ('published', 'pending_review', 'rejected')),
  add column renewed_at timestamptz;

alter table public.listings
  add constraint market_fields check (
    (kind = 'market') = (market_type is not null and market_category_id is not null)
  );

-- Fino a 10 foto (la Mappa resta a 4, controllato dalle sue funzioni).
do $$
declare
  c text;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.listings'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%array_length(photos%'
  loop
    execute format('alter table public.listings drop constraint %I', c);
  end loop;
end;
$$;

alter table public.listings
  add constraint listings_photos_max check (coalesce(array_length(photos, 1), 0) <= 10);

-- Gli annunci di Scambia & Vendi si rinnovano: la scadenza non è legata alla creazione.
alter table public.listings drop constraint expires_in_range;
alter table public.listings
  add constraint expires_in_range
  check (kind = 'market' or expires_at <= created_at + interval '30 days');

create index listings_market_idx
  on public.listings (market_category_id, market_type, created_at desc)
  where kind = 'market';

-- Annunci in revisione o rifiutati: li vede solo l'autore (e gli amministratori).
create policy "annunci in revisione nascosti"
  on public.listings as restrictive for select to authenticated
  using (review_status = 'published' or owner_id = public.current_uid() or public.is_admin());

-- ------------------------------------------------------------ parole a rischio
create table public.marketplace_flag_terms (
  term text primary key check (term = lower(btrim(term)) and char_length(term) between 3 and 40),
  reason text not null
);

alter table public.marketplace_flag_terms enable row level security;
revoke all on public.marketplace_flag_terms from public, anon, authenticated;

insert into public.marketplace_flag_terms (term, reason) values
  ('pistola', 'armi'), ('pistole', 'armi'), ('fucile', 'armi'), ('fucili', 'armi'),
  ('munizioni', 'armi'), ('proiettili', 'armi'), ('cartucce calibro', 'armi'),
  ('silenziatore', 'armi'), ('tirapugni', 'armi'), ('coltello a scatto', 'armi'),
  ('cocaina', 'droghe'), ('eroina', 'droghe'), ('hashish', 'droghe'), ('marijuana', 'droghe'),
  ('ecstasy', 'droghe'), ('mdma', 'droghe'), ('anfetamine', 'droghe'), ('ketamina', 'droghe'),
  ('ricetta medica', 'farmaci'), ('senza ricetta', 'farmaci'), ('antibiotici', 'farmaci'),
  ('psicofarmaci', 'farmaci'), ('steroidi', 'farmaci'), ('anabolizzanti', 'farmaci'),
  ('replica', 'contraffazione'), ('contraffatto', 'contraffazione'), ('falso d''autore', 'contraffazione'),
  ('rubato', 'beni rubati'), ('rubata', 'beni rubati'), ('refurtiva', 'beni rubati'),
  ('cucciolo', 'animali vivi'), ('cuccioli', 'animali vivi'), ('gattino', 'animali vivi'),
  ('gattini', 'animali vivi'), ('pedigree', 'animali vivi'),
  ('documenti falsi', 'documenti'), ('patente falsa', 'documenti')
on conflict do nothing;

-- Parola a rischio presente nel testo (confronto senza maiuscole e accenti).
create or replace function private.market_flag_reason(p_text text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select t.reason
  from public.marketplace_flag_terms t
  where translate(lower(coalesce(p_text, '')), 'àèéìòù', 'aeeiou')
        ~ ('(^|[^a-z0-9])' || regexp_replace(t.term, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '($|[^a-z0-9])')
  limit 1;
$$;

revoke all on function private.market_flag_reason(text) from public, anon, authenticated;

-- ------------------------------------------------------------ controlli comuni
create or replace function private.check_market_listing(
  p_type text,
  p_category uuid,
  p_title text,
  p_description text,
  p_price_cents bigint,
  p_condition text,
  p_ships boolean,
  p_pickup boolean,
  p_attributes jsonb,
  p_photos text[],
  p_wanted_in_exchange text
)
returns void
language plpgsql
stable
security definer
set search_path = public, storage
as $$
declare
  v_uid text := public.current_uid();
  v_cat public.marketplace_categories;
  v_parent text;
  v_photo text;
  v_n integer := coalesce(array_length(p_photos, 1), 0);
  v_key text;
  v_year integer;
  v_no_condition boolean;
  v_no_delivery boolean;
begin
  if p_type is null or p_type not in ('sell', 'swap', 'free', 'wanted') then
    raise exception 'Tipologia non valida' using errcode = '22023';
  end if;

  select * into v_cat from public.marketplace_categories where id = p_category;
  if v_cat.id is null or v_cat.parent_id is null or not v_cat.is_active or v_cat.archived_at is not null then
    raise exception 'Scegli una sottocategoria valida' using errcode = '22023';
  end if;
  select slug into v_parent from public.marketplace_categories
  where id = v_cat.parent_id and is_active and archived_at is null;
  if v_parent is null then
    raise exception 'Scegli una sottocategoria valida' using errcode = '22023';
  end if;

  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'Il titolo deve avere da 3 a 120 caratteri' using errcode = '22023';
  end if;
  if char_length(coalesce(p_description, '')) > 2000 then
    raise exception 'Descrizione troppo lunga (massimo 2000 caratteri)' using errcode = '22023';
  end if;

  -- Prezzo secondo la tipologia.
  if p_type = 'sell' and p_price_cents is null then
    raise exception 'Per la vendita il prezzo è obbligatorio' using errcode = '22023';
  end if;
  if p_type = 'free' and p_price_cents is not null then
    raise exception 'Un regalo non ha prezzo' using errcode = '22023';
  end if;
  if p_price_cents is not null and p_price_cents not between 0 and 99999999900 then
    raise exception 'Prezzo non valido' using errcode = '22023';
  end if;

  -- Condizioni e consegna: non si applicano a servizi e immobili, né a chi cerca.
  v_no_condition := v_parent in ('servizi', 'immobili') or p_type = 'wanted';
  v_no_delivery := v_parent in ('servizi', 'immobili') or p_type = 'wanted';
  if not v_no_condition and p_condition is null then
    raise exception 'Indica le condizioni dell''oggetto' using errcode = '22023';
  end if;
  if p_condition is not null
     and p_condition not in ('new', 'like_new', 'excellent', 'good', 'fair', 'to_repair') then
    raise exception 'Condizioni non valide' using errcode = '22023';
  end if;
  if not v_no_delivery and not (coalesce(p_ships, false) or coalesce(p_pickup, false)) then
    raise exception 'Scegli ritiro a mano, spedizione o entrambi' using errcode = '22023';
  end if;

  if p_type <> 'swap' and p_wanted_in_exchange is not null then
    raise exception '«Cosa cerchi in cambio» vale solo per lo scambio' using errcode = '22023';
  end if;

  -- Foto: obbligatorie (D11) tranne per «Cerco»; massimo 10; solo foto proprie caricate.
  if p_type <> 'wanted' and v_n < 1 then
    raise exception 'Aggiungi almeno una foto' using errcode = '22023';
  end if;
  if v_n > 10 then
    raise exception 'Al massimo 10 foto' using errcode = '22023';
  end if;
  foreach v_photo in array coalesce(p_photos, '{}') loop
    if split_part(v_photo, '/', 1) <> v_uid or v_photo !~ '^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+\.jpg$'
       or not exists (
         select 1 from storage.objects o
         where o.bucket_id = 'listing-photos' and o.name = v_photo
       ) then
      raise exception 'Foto non valida' using errcode = '22023';
    end if;
  end loop;

  -- Campi specifici (D3): solo quelli previsti per la categoria, con valori sensati.
  if jsonb_typeof(coalesce(p_attributes, '{}'::jsonb)) <> 'object' then
    raise exception 'Campi specifici non validi' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(coalesce(p_attributes, '{}'::jsonb)) loop
    if not (
      (v_parent = 'motori' and v_key in ('anno', 'km'))
      or (v_parent = 'immobili' and v_key in ('mq', 'locali'))
      or (v_parent in ('abbigliamento-accessori', 'bambini-neonati') and v_key = 'taglia')
      or (v_parent = 'elettronica' and v_key = 'memoria')
    ) then
      raise exception 'Campo «%» non previsto per questa categoria', v_key using errcode = '22023';
    end if;
  end loop;
  if p_attributes ? 'anno' then
    v_year := (p_attributes ->> 'anno')::integer;
    if v_year not between 1900 and extract(year from now())::integer + 1 then
      raise exception 'Anno non valido' using errcode = '22023';
    end if;
  end if;
  if p_attributes ? 'km' and (p_attributes ->> 'km')::integer not between 0 and 2000000 then
    raise exception 'Chilometri non validi' using errcode = '22023';
  end if;
  if p_attributes ? 'mq' and (p_attributes ->> 'mq')::integer not between 1 and 100000 then
    raise exception 'Metri quadri non validi' using errcode = '22023';
  end if;
  if p_attributes ? 'locali' and (p_attributes ->> 'locali')::integer not between 1 and 50 then
    raise exception 'Numero di locali non valido' using errcode = '22023';
  end if;
  if p_attributes ? 'taglia' and char_length(p_attributes ->> 'taglia') not between 1 and 12 then
    raise exception 'Taglia non valida' using errcode = '22023';
  end if;
  if p_attributes ? 'memoria' and char_length(p_attributes ->> 'memoria') not between 1 and 20 then
    raise exception 'Memoria non valida' using errcode = '22023';
  end if;
  if v_cat.slug = 'motori-auto' and p_type <> 'wanted' and not (p_attributes ? 'anno') then
    raise exception 'Per un''auto indica l''anno' using errcode = '22023';
  end if;
  if v_parent = 'immobili' and p_type <> 'wanted' and not (p_attributes ? 'mq') then
    raise exception 'Per un immobile indica i metri quadri' using errcode = '22023';
  end if;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Valore numerico non valido' using errcode = '22023';
end;
$$;

revoke all on function private.check_market_listing(
  text, uuid, text, text, bigint, text, boolean, boolean, jsonb, text[], text
) from public, anon, authenticated;

-- ------------------------------------------------------------ pubblicare
create or replace function public.publish_market_listing(
  p_type text,
  p_category uuid,
  p_title text,
  p_description text,
  p_price_cents bigint,
  p_condition text,
  p_ships boolean,
  p_pickup boolean,
  p_attributes jsonb,
  p_lat double precision,
  p_lon double precision,
  p_location_mode public.location_mode,
  p_photos text[],
  p_wanted_in_exchange text default null,
  p_no_prohibited_items boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := public.current_uid();
  v_id uuid;
  v_reason text;
  v_slug text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if not coalesce(p_no_prohibited_items, false) then
    raise exception 'Conferma che non pubblichi prodotti vietati' using errcode = '22023';
  end if;
  if p_location_mode is null then
    raise exception 'Scegli dove mostrare l''annuncio' using errcode = '22023';
  end if;
  perform private.check_market_listing(
    p_type, p_category, p_title, p_description, p_price_cents, p_condition, p_ships, p_pickup,
    p_attributes, p_photos, p_wanted_in_exchange
  );
  -- Anti-spam (D9): 20 annunci nuovi al giorno.
  if (select count(*) from public.listings
      where owner_id = v_uid and kind = 'market' and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Hai raggiunto il limite di 20 annunci al giorno' using errcode = '22023';
  end if;

  select slug into v_slug from public.marketplace_categories where id = p_category;
  v_id := public.create_listing(
    'market', p_title, coalesce(p_description, ''), p_lat, p_lon, v_slug, null,
    coalesce(p_photos, '{}'), false, now() + interval '30 days', p_location_mode
  );
  v_reason := private.market_flag_reason(
    coalesce(p_title, '') || ' ' || coalesce(p_description, '') || ' ' || coalesce(p_wanted_in_exchange, '')
  );
  perform set_config('nexus.internal', 'on', true);
  update public.listings
  set market_type = p_type,
      market_category_id = p_category,
      market_price_cents = p_price_cents,
      item_condition = p_condition,
      ships = coalesce(p_ships, false),
      pickup = coalesce(p_pickup, false),
      attributes = coalesce(p_attributes, '{}'::jsonb),
      wanted_in_exchange = nullif(btrim(coalesce(p_wanted_in_exchange, '')), ''),
      review_status = case when v_reason is null then 'published' else 'pending_review' end
  where id = v_id;
  perform set_config('nexus.internal', 'off', true);
  return jsonb_build_object(
    'id', v_id,
    'review_status', case when v_reason is null then 'published' else 'pending_review' end
  );
end;
$$;

-- ------------------------------------------------------------ modificare, rinnovare, chiudere
create or replace function private.my_market_listing(p_id uuid)
returns public.listings
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.listings;
begin
  select * into v_row from public.listings
  where id = p_id and owner_id = public.current_uid() and kind = 'market';
  if v_row.id is null then
    raise exception 'Annuncio non trovato o non tuo' using errcode = '42501';
  end if;
  if v_row.status <> 'active' then
    raise exception 'Annuncio chiuso o rimosso' using errcode = '42501';
  end if;
  return v_row;
end;
$$;

revoke all on function private.my_market_listing(uuid) from public, anon, authenticated;

create or replace function public.update_market_listing(
  p_id uuid,
  p_category uuid,
  p_title text,
  p_description text,
  p_price_cents bigint,
  p_condition text,
  p_ships boolean,
  p_pickup boolean,
  p_attributes jsonb,
  p_photos text[],
  p_wanted_in_exchange text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.listings := private.my_market_listing(p_id);
  v_reason text;
  v_status text;
begin
  -- La tipologia non cambia: per cambiarla si pubblica un annuncio nuovo.
  perform private.check_market_listing(
    v_row.market_type, p_category, p_title, p_description, p_price_cents, p_condition, p_ships,
    p_pickup, p_attributes, p_photos, p_wanted_in_exchange
  );
  v_reason := private.market_flag_reason(
    coalesce(p_title, '') || ' ' || coalesce(p_description, '') || ' ' || coalesce(p_wanted_in_exchange, '')
  );
  -- Un annuncio rifiutato resta rifiutato; uno pubblicato torna in revisione se serve.
  v_status := case
    when v_row.review_status = 'rejected' then 'rejected'
    when v_reason is not null then 'pending_review'
    else v_row.review_status
  end;
  perform set_config('nexus.internal', 'on', true);
  update public.listings
  set title = btrim(p_title),
      description = coalesce(p_description, ''),
      category = (select slug from public.marketplace_categories where id = p_category),
      market_category_id = p_category,
      market_price_cents = p_price_cents,
      item_condition = p_condition,
      ships = coalesce(p_ships, false),
      pickup = coalesce(p_pickup, false),
      attributes = coalesce(p_attributes, '{}'::jsonb),
      photos = coalesce(p_photos, '{}'),
      wanted_in_exchange = nullif(btrim(coalesce(p_wanted_in_exchange, '')), ''),
      review_status = v_status
  where id = p_id;
  perform set_config('nexus.internal', 'off', true);
  return jsonb_build_object('id', p_id, 'review_status', v_status);
end;
$$;

create or replace function public.renew_market_listing(p_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_until timestamptz := now() + interval '30 days';
begin
  perform private.my_market_listing(p_id);
  update public.listings set expires_at = v_until, renewed_at = now() where id = p_id;
  return v_until;
end;
$$;

create or replace function public.close_market_listing(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.my_market_listing(p_id);
  update public.listings set status = 'completed', completed_at = now() where id = p_id;
end;
$$;

-- ------------------------------------------------------------ letture
create or replace function public.marketplace_categories_list()
returns table (
  id uuid,
  parent_id uuid,
  name text,
  slug text,
  sort_order integer
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.parent_id, c.name, c.slug, c.sort_order
  from public.marketplace_categories c
  left join public.marketplace_categories p on p.id = c.parent_id
  where public.current_uid() is not null
    and c.is_active and c.archived_at is null
    and (c.parent_id is null or (p.is_active and p.archived_at is null))
  order by coalesce(p.sort_order, c.sort_order), c.parent_id nulls first, c.sort_order;
$$;

create or replace function public.my_market_listings()
returns table (
  id uuid,
  market_type text,
  category_id uuid,
  title text,
  description text,
  price_cents bigint,
  item_condition text,
  ships boolean,
  pickup boolean,
  attributes jsonb,
  photos text[],
  wanted_in_exchange text,
  location_mode public.location_mode,
  exact_lat double precision,
  exact_lon double precision,
  status text,
  review_status text,
  expires_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    l.id, l.market_type, l.market_category_id, l.title, l.description, l.market_price_cents,
    l.item_condition, l.ships, l.pickup, l.attributes, l.photos, l.wanted_in_exchange,
    l.location_mode,
    st_y(ll.exact_location::geometry), st_x(ll.exact_location::geometry),
    case when l.status = 'active' and l.expires_at <= now() then 'expired' else l.status::text end,
    l.review_status, l.expires_at, l.created_at
  from public.listings l
  join public.listing_locations ll on ll.listing_id = l.id
  where l.owner_id = public.current_uid() and l.kind = 'market'
  order by l.created_at desc
  limit 200;
$$;

-- La vecchia ricerca generica (0002/0007) non restituisce gli annunci di Scambia & Vendi:
-- hanno la loro ricerca (Blocco 2) che rispetta revisione e filtri.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'nearby_listings';
  execute replace(v_def, 'and l.status = ''active''', 'and l.status = ''active'' and l.kind <> ''market''');
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.publish_market_listing(text, uuid, text, text, bigint, text, boolean, boolean, jsonb, double precision, double precision, public.location_mode, text[], text, boolean)',
    'public.update_market_listing(uuid, uuid, text, text, bigint, text, boolean, boolean, jsonb, text[], text)',
    'public.renew_market_listing(uuid)',
    'public.close_market_listing(uuid)',
    'public.marketplace_categories_list()',
    'public.my_market_listings()'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

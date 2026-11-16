-- Piazly · Fase 5, Blocco 3: proposte di scambio.
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Decisioni (docs/fase5/CATALOGO_TITOLARE.md sezione 6; PIANO_OPERATIVO.md D2, D9):
--  • si propone uno scambio su un annuncio di Scambio o su una Vendita che «valuta scambi»;
--  • chi propone allega da 1 a 5 annunci propri (pubblicati, attivi) e, se l'annuncio lo
--    accetta, un conguaglio da 1 a 999.999 € con la direzione (lo aggiungo io / lo chiedo io);
--  • chi riceve accetta, rifiuta o fa una controproposta (che chiude la precedente come
--    «Controproposta» e ne apre una nuova verso l'altra parte); chi l'ha fatta la annulla
--    finché è in attesa;
--  • stati: pending (In attesa), accepted (Accettata), rejected (Rifiutata), countered
--    (Controproposta), cancelled (Annullata), completed (Completata, con il Blocco 4);
--  • notifiche: nuova proposta, controproposta, accettazione;
--  • anti-spam (D9): 30 proposte al giorno per persona (controproposte comprese), una sola
--    proposta in attesa per persona e annuncio;
--  • chat tra le parti con la Fase 4 (D2): intanto ci si scrive nei commenti;
--  • nessun accesso diretto alle tabelle: solo funzioni, e solo per le due parti.

-- ------------------------------------------------------------ tabelle
create table public.swap_proposals (
  id uuid primary key default gen_random_uuid(),
  -- Annuncio richiesto e i due ruoli fissi.
  target_listing_id uuid not null references public.listings (id) on delete cascade,
  owner_id text not null references public.profiles (id) on delete cascade,
  requester_id text not null references public.profiles (id) on delete cascade,
  -- Chi ha fatto questa versione e chi deve rispondere (si alternano con le controproposte).
  from_id text not null references public.profiles (id) on delete cascade,
  to_id text not null references public.profiles (id) on delete cascade,
  parent_id uuid references public.swap_proposals (id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'countered', 'cancelled', 'completed')),
  cash_cents bigint check (cash_cents is null or cash_cents between 100 and 99999900),
  -- requester_pays: aggiunge chi chiede l'annuncio; owner_pays: aggiunge l'autore.
  cash_direction text check (cash_direction in ('requester_pays', 'owner_pays')),
  message text not null default '' check (char_length(message) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint swap_parties check (
    owner_id <> requester_id
    and ((from_id = requester_id and to_id = owner_id) or (from_id = owner_id and to_id = requester_id))
  ),
  constraint swap_cash check ((cash_cents is null) = (cash_direction is null))
);

create index swap_proposals_owner_idx on public.swap_proposals (owner_id, updated_at desc);
create index swap_proposals_requester_idx on public.swap_proposals (requester_id, updated_at desc);
create index swap_proposals_target_idx on public.swap_proposals (target_listing_id);
create unique index swap_proposals_one_pending
  on public.swap_proposals (target_listing_id, requester_id) where status = 'pending';

create table public.swap_proposal_items (
  proposal_id uuid not null references public.swap_proposals (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  primary key (proposal_id, listing_id)
);

alter table public.swap_proposals enable row level security;
alter table public.swap_proposal_items enable row level security;
revoke all on public.swap_proposals, public.swap_proposal_items from public, anon, authenticated;

-- ------------------------------------------------------------ notifiche
alter table public.notifications add column proposal_id uuid
  references public.swap_proposals (id) on delete cascade;

do $$
declare
  c text;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.notifications'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%listing_like%'
  loop
    execute format('alter table public.notifications drop constraint %I', c);
  end loop;
end;
$$;

alter table public.notifications add constraint notifications_kind_check check (kind in (
  'listing_like', 'listing_comment', 'comment_reply', 'followed_comment', 'comment_like',
  'swap_proposal', 'swap_counter', 'swap_accepted'
));

-- Le proposte avvisano sempre (anche se il post è silenziato), tranne con un blocco.
create or replace function private.notify_swap(p_proposal uuid, p_kind text, p_recipient text, p_actor text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_recipient = p_actor or public.is_blocked_between(p_recipient, p_actor) then
    return;
  end if;
  insert into public.notifications (recipient_id, kind, listing_id, proposal_id, actor_id)
  select p_recipient, p_kind, p.target_listing_id, p.id, p_actor
  from public.swap_proposals p where p.id = p_proposal;
end;
$$;

revoke all on function private.notify_swap(uuid, text, text, text) from public, anon, authenticated;

-- ------------------------------------------------------------ controlli comuni
-- Annuncio di Scambia & Vendi pubblicato, attivo e visibile.
create or replace function private.swap_listing_ok(p_listing uuid)
returns public.listings
language sql
stable
security definer
set search_path = public
as $$
  select l.* from public.listings l
  where l.id = p_listing and l.kind = 'market' and l.status = 'active'
    and l.expires_at > now() and l.review_status = 'published';
$$;

revoke all on function private.swap_listing_ok(uuid) from public, anon, authenticated;

-- Condizioni dell'offerta: annunci del richiedente, conguaglio, messaggio.
create or replace function private.check_swap_offer(
  p_target public.listings,
  p_requester text,
  p_items uuid[],
  p_cash_cents bigint,
  p_cash_direction text,
  p_message text
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_n integer := coalesce(array_length(p_items, 1), 0);
  v_item uuid;
  v_row public.listings;
begin
  if v_n < 1 then
    raise exception 'Scegli almeno un tuo annuncio da offrire' using errcode = '22023';
  end if;
  if v_n > 5 then
    raise exception 'Al massimo 5 annunci per proposta' using errcode = '22023';
  end if;
  if (select count(distinct x) from unnest(p_items) x) <> v_n then
    raise exception 'Annuncio ripetuto' using errcode = '22023';
  end if;
  foreach v_item in array p_items loop
    v_row := private.swap_listing_ok(v_item);
    if v_row.id is null or v_row.owner_id <> p_requester or v_row.id = p_target.id then
      raise exception 'Puoi offrire solo annunci attivi di chi chiede lo scambio' using errcode = '22023';
    end if;
  end loop;
  if (p_cash_cents is null) <> (p_cash_direction is null) then
    raise exception 'Indica importo e direzione del conguaglio' using errcode = '22023';
  end if;
  if p_cash_cents is not null then
    if not p_target.cash_adjustment then
      raise exception 'Questo annuncio non accetta conguagli' using errcode = '22023';
    end if;
    if p_cash_cents not between 100 and 99999900 then
      raise exception 'Conguaglio da 1 a 999.999 €' using errcode = '22023';
    end if;
    if p_cash_direction not in ('requester_pays', 'owner_pays') then
      raise exception 'Direzione del conguaglio non valida' using errcode = '22023';
    end if;
  end if;
  if char_length(coalesce(p_message, '')) > 500 then
    raise exception 'Messaggio troppo lungo (massimo 500 caratteri)' using errcode = '22023';
  end if;
end;
$$;

revoke all on function private.check_swap_offer(public.listings, text, uuid[], bigint, text, text)
  from public, anon, authenticated;

create or replace function private.check_swap_limit(p_uid text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.swap_proposals
      where from_id = p_uid and created_at > now() - interval '1 day') >= 30 then
    raise exception 'Hai raggiunto il limite di 30 proposte al giorno' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.user_moderation m
    where m.user_id = p_uid and m.banned_until is not null and m.banned_until > now()
  ) then
    raise exception 'Account sospeso' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.check_swap_limit(text) from public, anon, authenticated;

-- La proposta in attesa a cui risponde chi chiama.
create or replace function private.swap_to_answer(p_proposal uuid)
returns public.swap_proposals
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.swap_proposals;
begin
  select * into v_row from public.swap_proposals
  where id = p_proposal and to_id = public.current_uid()
  for update;
  if v_row.id is null then
    raise exception 'Proposta non trovata' using errcode = '42501';
  end if;
  if v_row.status <> 'pending' then
    raise exception 'La proposta non è più in attesa' using errcode = '22023';
  end if;
  if public.is_blocked_between(v_row.owner_id, v_row.requester_id) then
    raise exception 'Proposta non trovata' using errcode = '42501';
  end if;
  return v_row;
end;
$$;

revoke all on function private.swap_to_answer(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------ proporre
create or replace function public.propose_swap(
  p_listing uuid,
  p_items uuid[],
  p_cash_cents bigint default null,
  p_cash_direction text default null,
  p_message text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_target public.listings;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  v_target := private.swap_listing_ok(p_listing);
  if v_target.id is null or public.hidden_by_block(v_target.owner_id) then
    raise exception 'Annuncio non trovato' using errcode = '42501';
  end if;
  if v_target.owner_id = v_uid then
    raise exception 'È un tuo annuncio' using errcode = '22023';
  end if;
  if not (v_target.market_type = 'swap' or v_target.open_to_swap) then
    raise exception 'Questo annuncio non accetta scambi' using errcode = '22023';
  end if;
  perform private.check_swap_offer(v_target, v_uid, p_items, p_cash_cents, p_cash_direction, p_message);
  perform private.check_swap_limit(v_uid);
  if exists (select 1 from public.swap_proposals
             where target_listing_id = p_listing and requester_id = v_uid and status = 'pending') then
    raise exception 'Hai già una proposta in attesa per questo annuncio' using errcode = '22023';
  end if;
  insert into public.swap_proposals (
    target_listing_id, owner_id, requester_id, from_id, to_id, cash_cents, cash_direction, message
  )
  values (
    p_listing, v_target.owner_id, v_uid, v_uid, v_target.owner_id, p_cash_cents, p_cash_direction,
    btrim(coalesce(p_message, ''))
  )
  returning id into v_id;
  insert into public.swap_proposal_items (proposal_id, listing_id)
  select v_id, x from unnest(p_items) x;
  perform private.notify_swap(v_id, 'swap_proposal', v_target.owner_id, v_uid);
  return v_id;
end;
$$;

-- ------------------------------------------------------------ controproposta
create or replace function public.counter_swap(
  p_proposal uuid,
  p_items uuid[],
  p_cash_cents bigint default null,
  p_cash_direction text default null,
  p_message text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_old public.swap_proposals := private.swap_to_answer(p_proposal);
  v_target public.listings;
  v_id uuid;
begin
  v_target := private.swap_listing_ok(v_old.target_listing_id);
  if v_target.id is null then
    raise exception 'L''annuncio non è più disponibile' using errcode = '22023';
  end if;
  -- Gli annunci offerti restano sempre quelli di chi chiede lo scambio.
  perform private.check_swap_offer(
    v_target, v_old.requester_id, p_items, p_cash_cents, p_cash_direction, p_message
  );
  perform private.check_swap_limit(v_uid);
  update public.swap_proposals set status = 'countered', updated_at = now() where id = v_old.id;
  insert into public.swap_proposals (
    target_listing_id, owner_id, requester_id, from_id, to_id, parent_id, cash_cents,
    cash_direction, message
  )
  values (
    v_old.target_listing_id, v_old.owner_id, v_old.requester_id, v_uid, v_old.from_id, v_old.id,
    p_cash_cents, p_cash_direction, btrim(coalesce(p_message, ''))
  )
  returning id into v_id;
  insert into public.swap_proposal_items (proposal_id, listing_id)
  select v_id, x from unnest(p_items) x;
  perform private.notify_swap(v_id, 'swap_counter', v_old.from_id, v_uid);
  return v_id;
end;
$$;

-- ------------------------------------------------------------ accettare, rifiutare, annullare
create or replace function public.respond_swap(p_proposal uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_row public.swap_proposals := private.swap_to_answer(p_proposal);
  v_item uuid;
begin
  if p_accept is null then
    raise exception 'Risposta non valida' using errcode = '22023';
  end if;
  if p_accept then
    -- Si accetta solo se l'annuncio e quelli offerti sono ancora disponibili.
    if (private.swap_listing_ok(v_row.target_listing_id)).id is null then
      raise exception 'L''annuncio non è più disponibile' using errcode = '22023';
    end if;
    for v_item in select listing_id from public.swap_proposal_items where proposal_id = v_row.id loop
      if (private.swap_listing_ok(v_item)).id is null then
        raise exception 'Uno degli annunci offerti non è più disponibile' using errcode = '22023';
      end if;
    end loop;
    update public.swap_proposals set status = 'accepted', updated_at = now() where id = v_row.id;
    perform private.notify_swap(v_row.id, 'swap_accepted', v_row.from_id, v_uid);
    return 'accepted';
  end if;
  update public.swap_proposals set status = 'rejected', updated_at = now() where id = v_row.id;
  return 'rejected';
end;
$$;

create or replace function public.cancel_swap(p_proposal uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.swap_proposals;
begin
  select * into v_row from public.swap_proposals
  where id = p_proposal and from_id = public.current_uid()
  for update;
  if v_row.id is null then
    raise exception 'Proposta non trovata' using errcode = '42501';
  end if;
  if v_row.status <> 'pending' then
    raise exception 'Si annulla solo una proposta in attesa' using errcode = '22023';
  end if;
  update public.swap_proposals set status = 'cancelled', updated_at = now() where id = v_row.id;
end;
$$;

-- ------------------------------------------------------------ letture
-- Annunci che si possono offrire: i propri, oppure (in una controproposta) quelli di chi
-- chiede lo scambio.
create or replace function public.swap_offer_candidates(p_proposal uuid default null)
returns table (
  id uuid,
  market_type text,
  title text,
  price_cents bigint,
  photos text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_requester text := v_uid;
  v_target uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_proposal is not null then
    select p.requester_id, p.target_listing_id into v_requester, v_target
    from public.swap_proposals p
    where p.id = p_proposal and v_uid in (p.owner_id, p.requester_id)
      and not public.is_blocked_between(p.owner_id, p.requester_id);
    if v_requester is null then
      raise exception 'Proposta non trovata' using errcode = '42501';
    end if;
  end if;
  return query
  select l.id, l.market_type, l.title, l.market_price_cents, l.photos
  from public.listings l
  where l.owner_id = v_requester and l.kind = 'market' and l.status = 'active'
    and l.expires_at > now() and l.review_status = 'published'
    and l.id is distinct from v_target
  order by l.created_at desc
  limit 100;
end;
$$;

-- Le proposte in cui si è parte: ricevute, inviate e storico.
create or replace function public.my_swap_proposals()
returns table (
  id uuid,
  status text,
  parent_id uuid,
  from_me boolean,
  i_am_owner boolean,
  target_id uuid,
  target_title text,
  target_type text,
  target_photo text,
  target_available boolean,
  target_cash_adjustment boolean,
  other_id text,
  other_username text,
  other_public_name text,
  other_is_business boolean,
  items jsonb,
  cash_cents bigint,
  cash_direction text,
  message text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id, p.status, p.parent_id,
    p.from_id = public.current_uid(),
    p.owner_id = public.current_uid(),
    t.id, t.title, t.market_type, t.photos[1],
    t.status = 'active' and t.expires_at > now() and t.review_status = 'published',
    t.cash_adjustment,
    o.id, o.username::text, o.public_name, o.account_type = 'business',
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', l.id, 'title', l.title, 'price_cents', l.market_price_cents,
        'photo', l.photos[1], 'market_type', l.market_type,
        'available', l.status = 'active' and l.expires_at > now() and l.review_status = 'published'
      ) order by l.title)
      from public.swap_proposal_items i join public.listings l on l.id = i.listing_id
      where i.proposal_id = p.id
    ), '[]'::jsonb),
    p.cash_cents, p.cash_direction, p.message, p.created_at, p.updated_at
  from public.swap_proposals p
  join public.listings t on t.id = p.target_listing_id
  join public.profiles o on o.id = case
    when p.owner_id = public.current_uid() then p.requester_id else p.owner_id end
  where public.current_uid() in (p.owner_id, p.requester_id)
    and not public.is_blocked_between(p.owner_id, p.requester_id)
  order by p.updated_at desc
  limit 200;
$$;

-- ------------------------------------------------------------ notifiche con la proposta
drop function public.my_notifications(integer);

create function public.my_notifications(p_limit integer default 50)
returns table (
  id uuid,
  kind text,
  listing_id uuid,
  listing_title text,
  comment_id uuid,
  comment_excerpt text,
  actor_id text,
  actor_username text,
  actor_public_name text,
  actor_avatar_thumb_path text,
  actor_count integer,
  created_at timestamptz,
  read boolean,
  proposal_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select
    n.id, n.kind, n.listing_id, l.title, n.comment_id,
    left(c.body, 120),
    p.id, p.username::text, p.public_name, p.avatar_thumb_path,
    n.actor_count, n.created_at, n.read_at is not null, n.proposal_id
  from public.notifications n
  join public.listings l on l.id = n.listing_id
  join public.profiles p on p.id = n.actor_id
  left join public.listing_comments c on c.id = n.comment_id
  where n.recipient_id = public.current_uid()
    and not public.is_blocked_between(n.actor_id, public.current_uid())
  order by n.created_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.propose_swap(uuid, uuid[], bigint, text, text)',
    'public.counter_swap(uuid, uuid[], bigint, text, text)',
    'public.respond_swap(uuid, boolean)',
    'public.cancel_swap(uuid)',
    'public.swap_offer_candidates(uuid)',
    'public.my_swap_proposals()',
    'public.my_notifications(integer)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

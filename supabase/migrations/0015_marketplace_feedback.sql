-- Piazly · Fase 5, Blocco 4: conclusione e feedback.
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Decisioni (PDF: «Segna come concluso: solo dopo si può lasciare un feedback»; «Feedback a
-- stelle con commento, stile eBay e Subito; media stelle sul profilo dei privati»;
-- docs/fase5/PIANO_OPERATIVO.md D6):
--  • Vendo, Regalo, Cerco: l'autore segna l'annuncio come concluso indicando la persona (tra chi
--    ha commentato l'annuncio o gli ha fatto una proposta); l'altra conferma o dice che non è
--    avvenuto; l'autore può annullare finché l'altra non ha risposto;
--  • Scambio: la proposta accettata si conclude quando la confermano entrambe le parti;
--  • a conclusione avvenuta l'annuncio (e, negli scambi, gli annunci offerti) si chiude e la
--    proposta diventa «Completata»;
--  • poi un feedback a testa: da 1 a 5 stelle, commento facoltativo fino a 500 caratteri,
--    non modificabile e non cancellabile dall'autore;
--  • media e numero di feedback per ogni persona; elenco dei feedback a pagine da 20;
--  • i feedback delle persone bloccate non si vedono;
--  • notifiche: richiesta di conferma, conclusione, feedback ricevuto;
--  • nessun accesso diretto alle tabelle: solo funzioni.

-- ------------------------------------------------------------ tabelle
create table public.market_deals (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  owner_id text not null references public.profiles (id) on delete cascade,
  other_id text not null references public.profiles (id) on delete cascade,
  proposal_id uuid unique references public.swap_proposals (id) on delete cascade,
  owner_confirmed_at timestamptz,
  other_confirmed_at timestamptz,
  declined_at timestamptz,
  cancelled_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint deal_parties check (owner_id <> other_id)
);

-- Un annuncio si conclude una volta sola; finché una conclusione è aperta non se ne apre un'altra.
create unique index market_deals_open_listing on public.market_deals (listing_id)
  where declined_at is null and cancelled_at is null;
create index market_deals_owner_idx on public.market_deals (owner_id, created_at desc);
create index market_deals_other_idx on public.market_deals (other_id, created_at desc);

create table public.market_feedback (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.market_deals (id) on delete cascade,
  author_id text not null references public.profiles (id) on delete cascade,
  subject_id text not null references public.profiles (id) on delete cascade,
  stars smallint not null check (stars between 1 and 5),
  comment text not null default '' check (char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  unique (deal_id, author_id),
  constraint feedback_parties check (author_id <> subject_id)
);

create index market_feedback_subject_idx on public.market_feedback (subject_id, created_at desc);

alter table public.market_deals enable row level security;
alter table public.market_feedback enable row level security;
revoke all on public.market_deals, public.market_feedback from public, anon, authenticated;

-- ------------------------------------------------------------ notifiche
alter table public.notifications add column deal_id uuid
  references public.market_deals (id) on delete cascade;

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in (
  'listing_like', 'listing_comment', 'comment_reply', 'followed_comment', 'comment_like',
  'swap_proposal', 'swap_counter', 'swap_accepted',
  'deal_confirm', 'deal_completed', 'feedback_received'
));

create or replace function private.notify_deal(p_deal uuid, p_kind text, p_recipient text, p_actor text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_recipient = p_actor or public.is_blocked_between(p_recipient, p_actor) then
    return;
  end if;
  insert into public.notifications (recipient_id, kind, listing_id, deal_id, proposal_id, actor_id)
  select p_recipient, p_kind, d.listing_id, d.id, d.proposal_id, p_actor
  from public.market_deals d where d.id = p_deal;
end;
$$;

revoke all on function private.notify_deal(uuid, text, text, text) from public, anon, authenticated;

-- ------------------------------------------------------------ chiusura
-- Entrambi hanno confermato: si chiude tutto.
create or replace function private.complete_deal(p_deal uuid, p_actor text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal public.market_deals;
begin
  update public.market_deals set completed_at = now()
  where id = p_deal and owner_confirmed_at is not null and other_confirmed_at is not null
    and completed_at is null
  returning * into v_deal;
  if v_deal.id is null then
    return;
  end if;
  perform set_config('nexus.internal', 'on', true);
  update public.listings set status = 'completed', completed_at = now()
  where id = v_deal.listing_id and status = 'active';
  if v_deal.proposal_id is not null then
    update public.swap_proposals set status = 'completed', updated_at = now()
    where id = v_deal.proposal_id;
    update public.listings l set status = 'completed', completed_at = now()
    from public.swap_proposal_items i
    where i.proposal_id = v_deal.proposal_id and l.id = i.listing_id and l.status = 'active';
    -- Le altre proposte in attesa sull'annuncio non hanno più oggetto.
    update public.swap_proposals set status = 'cancelled', updated_at = now()
    where target_listing_id = v_deal.listing_id and status = 'pending';
  end if;
  perform set_config('nexus.internal', 'off', true);
  perform private.notify_deal(v_deal.id, 'deal_completed', v_deal.owner_id, p_actor);
  perform private.notify_deal(v_deal.id, 'deal_completed', v_deal.other_id, p_actor);
end;
$$;

revoke all on function private.complete_deal(uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------ Vendo, Regalo, Cerco
-- Persone che si possono indicare: chi ha commentato l'annuncio o gli ha fatto una proposta.
create or replace function public.deal_candidates(p_listing uuid)
returns table (id text, username text, public_name text, avatar_thumb_path text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  if not exists (
    select 1 from public.listings l
    where l.id = p_listing and l.owner_id = v_uid and l.kind = 'market'
  ) then
    raise exception 'Annuncio non trovato' using errcode = '42501';
  end if;
  return query
  select p.id, p.username::text, p.public_name, p.avatar_thumb_path
  from public.profiles p
  where p.id <> v_uid
    and not public.is_blocked_between(p.id, v_uid)
    and (
      exists (select 1 from public.listing_comments c
              where c.listing_id = p_listing and c.author_id = p.id)
      or exists (select 1 from public.swap_proposals s
                 where s.target_listing_id = p_listing and s.requester_id = p.id)
    )
  order by p.public_name
  limit 100;
end;
$$;

create or replace function public.mark_listing_concluded(p_listing uuid, p_other text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_listing public.listings;
  v_id uuid;
begin
  select * into v_listing from public.listings
  where id = p_listing and owner_id = v_uid and kind = 'market'
  for update;
  if v_listing.id is null then
    raise exception 'Annuncio non trovato' using errcode = '42501';
  end if;
  if v_listing.status <> 'active' or v_listing.review_status <> 'published' then
    raise exception 'Si conclude solo un annuncio pubblicato e attivo' using errcode = '22023';
  end if;
  if v_listing.market_type = 'swap' then
    raise exception 'Uno scambio si conclude dalla proposta accettata' using errcode = '22023';
  end if;
  if not exists (select 1 from public.deal_candidates(p_listing) c where c.id = p_other) then
    raise exception 'Scegli una persona che ha commentato o proposto' using errcode = '22023';
  end if;
  if exists (select 1 from public.market_deals d
             where d.listing_id = p_listing and d.declined_at is null and d.cancelled_at is null) then
    raise exception 'C''è già una conclusione in corso per questo annuncio' using errcode = '22023';
  end if;
  insert into public.market_deals (listing_id, owner_id, other_id, owner_confirmed_at)
  values (p_listing, v_uid, p_other, now())
  returning id into v_id;
  perform private.notify_deal(v_id, 'deal_confirm', p_other, v_uid);
  return v_id;
end;
$$;

-- ------------------------------------------------------------ Scambio
create or replace function public.confirm_swap_concluded(p_proposal uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_prop public.swap_proposals;
  v_deal public.market_deals;
begin
  select * into v_prop from public.swap_proposals
  where id = p_proposal and v_uid in (owner_id, requester_id)
  for update;
  if v_prop.id is null or public.is_blocked_between(v_prop.owner_id, v_prop.requester_id) then
    raise exception 'Proposta non trovata' using errcode = '42501';
  end if;
  if v_prop.status <> 'accepted' then
    raise exception 'Si conclude solo una proposta accettata' using errcode = '22023';
  end if;
  select * into v_deal from public.market_deals where proposal_id = p_proposal for update;
  if v_deal.id is null then
    if exists (select 1 from public.market_deals d
               where d.listing_id = v_prop.target_listing_id
                 and d.declined_at is null and d.cancelled_at is null) then
      raise exception 'C''è già una conclusione in corso per questo annuncio' using errcode = '22023';
    end if;
    insert into public.market_deals (listing_id, owner_id, other_id, proposal_id)
    values (v_prop.target_listing_id, v_prop.owner_id, v_prop.requester_id, v_prop.id)
    returning * into v_deal;
  end if;
  if v_uid = v_deal.owner_id then
    if v_deal.owner_confirmed_at is not null then
      raise exception 'Hai già confermato' using errcode = '22023';
    end if;
    update public.market_deals set owner_confirmed_at = now() where id = v_deal.id;
  else
    if v_deal.other_confirmed_at is not null then
      raise exception 'Hai già confermato' using errcode = '22023';
    end if;
    update public.market_deals set other_confirmed_at = now() where id = v_deal.id;
  end if;
  perform private.complete_deal(v_deal.id, v_uid);
  if (select completed_at from public.market_deals where id = v_deal.id) is not null then
    return 'completed';
  end if;
  perform private.notify_deal(
    v_deal.id, 'deal_confirm',
    case when v_uid = v_deal.owner_id then v_deal.other_id else v_deal.owner_id end, v_uid
  );
  return 'waiting';
end;
$$;

-- ------------------------------------------------------------ rispondere e annullare
create or replace function public.answer_deal(p_deal uuid, p_confirm boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_deal public.market_deals;
begin
  select * into v_deal from public.market_deals
  where id = p_deal and other_id = v_uid and proposal_id is null
  for update;
  if v_deal.id is null or public.is_blocked_between(v_deal.owner_id, v_deal.other_id) then
    raise exception 'Conclusione non trovata' using errcode = '42501';
  end if;
  if v_deal.other_confirmed_at is not null or v_deal.declined_at is not null
     or v_deal.cancelled_at is not null then
    raise exception 'Hai già risposto' using errcode = '22023';
  end if;
  if p_confirm is null then
    raise exception 'Risposta non valida' using errcode = '22023';
  end if;
  if not p_confirm then
    update public.market_deals set declined_at = now() where id = v_deal.id;
    return 'declined';
  end if;
  update public.market_deals set other_confirmed_at = now() where id = v_deal.id;
  perform private.complete_deal(v_deal.id, v_uid);
  return 'completed';
end;
$$;

create or replace function public.cancel_deal(p_deal uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal public.market_deals;
begin
  select * into v_deal from public.market_deals
  where id = p_deal and owner_id = public.current_uid() and proposal_id is null
  for update;
  if v_deal.id is null then
    raise exception 'Conclusione non trovata' using errcode = '42501';
  end if;
  if v_deal.completed_at is not null or v_deal.declined_at is not null
     or v_deal.cancelled_at is not null then
    raise exception 'Non è più in attesa' using errcode = '22023';
  end if;
  update public.market_deals set cancelled_at = now() where id = v_deal.id;
end;
$$;

-- ------------------------------------------------------------ feedback
create or replace function public.leave_feedback(p_deal uuid, p_stars integer, p_comment text default '')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_deal public.market_deals;
  v_subject text;
  v_id uuid;
begin
  select * into v_deal from public.market_deals
  where id = p_deal and v_uid in (owner_id, other_id);
  if v_deal.id is null or public.is_blocked_between(v_deal.owner_id, v_deal.other_id) then
    raise exception 'Conclusione non trovata' using errcode = '42501';
  end if;
  if v_deal.completed_at is null then
    raise exception 'Il feedback si lascia dopo la conclusione' using errcode = '22023';
  end if;
  if p_stars is null or p_stars not between 1 and 5 then
    raise exception 'Da 1 a 5 stelle' using errcode = '22023';
  end if;
  if char_length(coalesce(p_comment, '')) > 500 then
    raise exception 'Commento troppo lungo (massimo 500 caratteri)' using errcode = '22023';
  end if;
  if exists (select 1 from public.market_feedback where deal_id = p_deal and author_id = v_uid) then
    raise exception 'Hai già lasciato il feedback: non si può modificare' using errcode = '22023';
  end if;
  v_subject := case when v_uid = v_deal.owner_id then v_deal.other_id else v_deal.owner_id end;
  insert into public.market_feedback (deal_id, author_id, subject_id, stars, comment)
  values (p_deal, v_uid, v_subject, p_stars, btrim(coalesce(p_comment, '')))
  returning id into v_id;
  perform private.notify_deal(p_deal, 'feedback_received', v_subject, v_uid);
  return v_id;
end;
$$;

-- Media e numero dei feedback di una persona (visibili a chi non è bloccato).
create or replace function public.feedback_summary(p_user text)
returns table (average numeric, count integer, completed_deals integer)
language sql
stable
security definer
set search_path = public
as $$
  select
    round(avg(f.stars)::numeric, 1),
    count(f.id)::integer,
    (select count(*)::integer from public.market_deals d
     where d.completed_at is not null and p_user in (d.owner_id, d.other_id))
  from public.market_feedback f
  where public.current_uid() is not null
    and f.subject_id = p_user
    and not public.hidden_by_block(p_user)
    and not public.hidden_by_block(f.author_id);
$$;

create or replace function public.feedback_list(p_user text, p_offset integer default 0)
returns table (
  id uuid,
  stars smallint,
  comment text,
  created_at timestamptz,
  author_id text,
  author_username text,
  author_public_name text,
  listing_title text,
  role text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    f.id, f.stars, f.comment, f.created_at, a.id, a.username::text, a.public_name, l.title,
    case
      when d.proposal_id is not null then 'swap'
      when f.author_id = d.owner_id then 'from_owner'
      else 'from_other'
    end
  from public.market_feedback f
  join public.market_deals d on d.id = f.deal_id
  join public.listings l on l.id = d.listing_id
  join public.profiles a on a.id = f.author_id
  where public.current_uid() is not null
    and f.subject_id = p_user
    and not public.hidden_by_block(p_user)
    and not public.hidden_by_block(f.author_id)
  order by f.created_at desc
  offset least(greatest(coalesce(p_offset, 0), 0), 10000)
  limit 20;
$$;

-- ------------------------------------------------------------ le mie conclusioni
create or replace function public.my_deals()
returns table (
  id uuid,
  listing_id uuid,
  listing_title text,
  listing_photo text,
  listing_type text,
  proposal_id uuid,
  i_am_owner boolean,
  other_id text,
  other_username text,
  other_public_name text,
  i_confirmed boolean,
  other_confirmed boolean,
  declined boolean,
  cancelled boolean,
  completed boolean,
  my_feedback_stars smallint,
  their_feedback_stars smallint,
  created_at timestamptz,
  completed_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    d.id, l.id, l.title, l.photos[1], l.market_type, d.proposal_id,
    d.owner_id = public.current_uid(),
    o.id, o.username::text, o.public_name,
    case when d.owner_id = public.current_uid()
      then d.owner_confirmed_at is not null else d.other_confirmed_at is not null end,
    case when d.owner_id = public.current_uid()
      then d.other_confirmed_at is not null else d.owner_confirmed_at is not null end,
    d.declined_at is not null, d.cancelled_at is not null, d.completed_at is not null,
    (select f.stars from public.market_feedback f
     where f.deal_id = d.id and f.author_id = public.current_uid()),
    (select f.stars from public.market_feedback f
     where f.deal_id = d.id and f.author_id <> public.current_uid()),
    d.created_at, d.completed_at
  from public.market_deals d
  join public.listings l on l.id = d.listing_id
  join public.profiles o on o.id = case
    when d.owner_id = public.current_uid() then d.other_id else d.owner_id end
  where public.current_uid() in (d.owner_id, d.other_id)
    and not public.is_blocked_between(d.owner_id, d.other_id)
  order by coalesce(d.completed_at, d.created_at) desc
  limit 200;
$$;

-- ------------------------------------------------------------ notifiche con la conclusione
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
  proposal_id uuid,
  deal_id uuid
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
    n.actor_count, n.created_at, n.read_at is not null, n.proposal_id, n.deal_id
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
    'public.deal_candidates(uuid)',
    'public.mark_listing_concluded(uuid, text)',
    'public.confirm_swap_concluded(uuid)',
    'public.answer_deal(uuid, boolean)',
    'public.cancel_deal(uuid)',
    'public.leave_feedback(uuid, integer, text)',
    'public.feedback_summary(text)',
    'public.feedback_list(text, integer)',
    'public.my_deals()',
    'public.my_notifications(integer)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

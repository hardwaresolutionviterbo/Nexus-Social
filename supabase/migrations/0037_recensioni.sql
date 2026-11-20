-- Fase 6 · Blocco 4: recensioni verificate delle attività.
--
-- «Verificate» vuol dire: le scrive solo chi è stato davvero cliente, cioè chi ha usato in cassa
-- (convalidato) almeno un coupon di quell'attività. Una recensione per persona e attività, che si
-- può correggere o cancellare; il titolare può rispondere una volta (e correggere la risposta);
-- gli amministratori possono togliere una recensione. Chi ha bloccato (o è bloccato) non vede le
-- recensioni dell'altro. In pubblico compare il nome pubblico dell'autore, mai altri dati.

create table public.business_reviews (
  id uuid primary key default gen_random_uuid(),
  business_id text not null references public.business_pages (id) on delete cascade,
  author_id text not null references public.profiles (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  body text check (body is null or char_length(body) <= 500),
  reply text check (reply is null or char_length(reply) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  replied_at timestamptz,
  unique (business_id, author_id)
);

create index business_reviews_business_idx on public.business_reviews (business_id, created_at desc);

create trigger business_reviews_touch_updated_at
  before update on public.business_reviews
  for each row execute function public.touch_updated_at();

alter table public.business_reviews enable row level security;
create policy "solo token del progetto Firebase" on public.business_reviews
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
revoke all on public.business_reviews from anon, authenticated;

-- Cliente verificato: almeno un coupon di questa attività convalidato in cassa.
create or replace function private.verified_customer(p_business_id text, p_user text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.coupons c
    join public.promotions p on p.id = c.promotion_id
    where p.business_id = p_business_id and c.user_id = p_user and c.redeemed_at is not null
  );
$$;
revoke all on function private.verified_customer(text, text) from public, anon, authenticated;

-- Recensioni di un'attività: media, numero, se posso scriverne una, la mia, le ultime 100.
create or replace function public.reviews_of(p_business_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select public.current_uid() as uid),
  visible as (
    select r.* from public.business_reviews r, me
    where r.business_id = p_business_id
      and (r.author_id = me.uid or not public.is_blocked_between(r.author_id, me.uid))
  )
  select case when (select uid from me) is null
              or not exists (select 1 from public.business_pages pg, me where pg.id = p_business_id
                             and (pg.published or pg.id = me.uid or public.is_admin())
                             and (pg.id = me.uid or not public.is_blocked_between(pg.id, me.uid)))
    then null
    else jsonb_build_object(
      'average', (select round(avg(rating)::numeric, 1) from visible),
      'count', (select count(*) from visible),
      'can_review', (select p_business_id <> me.uid and private.verified_customer(p_business_id, me.uid) from me),
      'mine_owner', (select p_business_id = me.uid from me),
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', v.id, 'author', pr.public_name, 'rating', v.rating, 'body', v.body,
          'reply', v.reply, 'created_at', v.created_at, 'updated_at', v.updated_at,
          'mine', v.author_id = (select uid from me)) order by v.created_at desc)
        from (select * from visible order by created_at desc limit 100) v
        join public.profiles pr on pr.id = v.author_id
      ), '[]'::jsonb))
  end;
$$;

create or replace function public.review_save(p_business_id text, p_rating integer, p_body text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_business_id = v_uid then
    raise exception 'Non puoi recensire la tua attività' using errcode = '22023';
  end if;
  if not private.verified_customer(p_business_id, v_uid) then
    raise exception 'Puoi recensire solo dopo aver usato un suo coupon in cassa' using errcode = '22023';
  end if;
  if public.is_blocked_between(p_business_id, v_uid) then
    raise exception 'Non disponibile' using errcode = '22023';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Scegli da 1 a 5 stelle' using errcode = '22023';
  end if;
  insert into public.business_reviews as r (business_id, author_id, rating, body)
  values (p_business_id, v_uid, p_rating, nullif(btrim(coalesce(p_body, '')), ''))
  on conflict (business_id, author_id) do update
    set rating = excluded.rating, body = excluded.body;
end;
$$;

create or replace function public.review_delete_mine(p_business_id text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.business_reviews where business_id = p_business_id and author_id = public.current_uid();
$$;

create or replace function public.review_reply(p_review_id uuid, p_reply text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.business_reviews
     set reply = nullif(btrim(coalesce(p_reply, '')), ''),
         replied_at = case when nullif(btrim(coalesce(p_reply, '')), '') is null then null else now() end
   where id = p_review_id and business_id = public.current_uid();
  if not found then
    raise exception 'Recensione non trovata' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.review_admin_delete(p_review_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo per gli amministratori' using errcode = '42501';
  end if;
  delete from public.business_reviews where id = p_review_id;
end;
$$;

revoke all on function public.reviews_of(text) from public, anon;
revoke all on function public.review_save(text, integer, text) from public, anon;
revoke all on function public.review_delete_mine(text) from public, anon;
revoke all on function public.review_reply(uuid, text) from public, anon;
revoke all on function public.review_admin_delete(uuid) from public, anon;
grant execute on function public.reviews_of(text) to authenticated;
grant execute on function public.review_save(text, integer, text) to authenticated;
grant execute on function public.review_delete_mine(text) to authenticated;
grant execute on function public.review_reply(uuid, text) to authenticated;
grant execute on function public.review_admin_delete(uuid) to authenticated;

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

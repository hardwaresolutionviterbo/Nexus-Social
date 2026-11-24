-- Fase 7 · Blocco 1: gestionale degli amministratori. Accesso riservato, coda delle
-- segnalazioni, utenti, avvisi e ban.
--
-- Regole:
-- - ogni funzione del gestionale richiede un amministratore (public.admin_users) che abbia la
--   verifica in due passaggi (PIN, migrazione 0005) attiva; dal telefono non attendibile
--   public.current_uid() è già vuoto, quindi serve anche il PIN su quel telefono;
-- - le segnalazioni delle chat mostrano solo i messaggi che chi segnala ha scelto (0024);
-- - chi è bannato non può pubblicare annunci, commenti, stati, promozioni o recensioni: il
--   controllo è sulle tabelle (trigger), quindi vale per ogni funzione che scrive;
-- - ogni azione resta nello storico (private.moderation_log), visibile solo agli amministratori;
-- - la persona vede gli avvisi e il ban con il motivo, mai chi li ha decisi.

-- ------------------------------------------------------------------ tabelle
create table public.moderation_notices (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('warning', 'ban', 'unban', 'removed')),
  message text not null check (char_length(btrim(message)) between 3 and 500),
  until timestamptz,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index moderation_notices_user_idx on public.moderation_notices (user_id, created_at desc);

alter table public.moderation_notices enable row level security;
create policy "solo token del progetto Firebase" on public.moderation_notices
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
revoke all on public.moderation_notices from anon, authenticated;

create table private.moderation_log (
  id uuid primary key default gen_random_uuid(),
  admin_id text not null,
  user_id text,
  action text not null check (action in (
    'ignore', 'remove', 'warn', 'ban', 'unban', 'restore'
  )),
  target text check (target is null or target in ('listing', 'comment', 'chat', 'user')),
  target_id text,
  reason text check (reason is null or char_length(reason) <= 500),
  until timestamptz,
  created_at timestamptz not null default now()
);

create index moderation_log_user_idx on private.moderation_log (user_id, created_at desc);
revoke all on private.moderation_log from public, anon, authenticated;

-- ------------------------------------------------------------------ controlli
create or replace function private.user_banned(p_uid text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_moderation m
    where m.user_id = p_uid and m.banned_until is not null and m.banned_until > now()
  );
$$;
revoke all on function private.user_banned(text) from public, anon, authenticated;

-- Amministratore con PIN attivo. Restituisce il suo identificativo.
create or replace function private.require_admin_2fa()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null or not public.is_admin() then
    raise exception 'Solo gli amministratori' using errcode = '42501';
  end if;
  if not exists (
    select 1 from private.account_security s where s.id = v_uid and s.pin_hash is not null
  ) then
    raise exception 'Per il gestionale serve la verifica in due passaggi (PIN)' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;
revoke all on function private.require_admin_2fa() from public, anon, authenticated;

-- Chi è bannato non scrive contenuti nuovi, da qualunque funzione arrivi la scrittura.
create or replace function private.block_banned_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if private.user_banned(to_jsonb(new) ->> tg_argv[0]) then
    raise exception 'Account sospeso' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function private.block_banned_author() from public, anon, authenticated;

create trigger listings_block_banned before insert on public.listings
  for each row execute function private.block_banned_author('owner_id');
create trigger listing_comments_block_banned before insert on public.listing_comments
  for each row execute function private.block_banned_author('author_id');
create trigger statuses_block_banned before insert on public.statuses
  for each row execute function private.block_banned_author('user_id');
create trigger promotions_block_banned before insert on public.promotions
  for each row execute function private.block_banned_author('business_id');
create trigger business_reviews_block_banned before insert on public.business_reviews
  for each row execute function private.block_banned_author('author_id');

-- ------------------------------------------------------------------ azioni interne
create or replace function private.log_action(
  p_admin text, p_user text, p_action text, p_target text, p_target_id text,
  p_reason text, p_until timestamptz default null
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into private.moderation_log (admin_id, user_id, action, target, target_id, reason, until)
  values (p_admin, p_user, p_action, p_target, p_target_id, left(p_reason, 500), p_until);
$$;
revoke all on function private.log_action(text, text, text, text, text, text, timestamptz)
  from public, anon, authenticated;

create or replace function private.notify_user(p_user text, p_kind text, p_message text, p_until timestamptz default null)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.moderation_notices (user_id, kind, message, until)
  select p_user, p_kind, btrim(p_message), p_until
  where p_user is not null and exists (select 1 from public.profiles where id = p_user);
$$;
revoke all on function private.notify_user(text, text, text, timestamptz) from public, anon, authenticated;

-- Ban: [p_days] 1, 7 o 30; null = definitivo.
create or replace function private.apply_ban(p_admin text, p_user text, p_days integer, p_reason text)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_until timestamptz;
begin
  if p_user is null or not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'Utente non trovato' using errcode = '22023';
  end if;
  if p_user = p_admin or exists (select 1 from public.admin_users where user_id = p_user) then
    raise exception 'Non puoi bannare un amministratore' using errcode = '22023';
  end if;
  if p_days is not null and p_days not in (1, 7, 30) then
    raise exception 'Durata non valida (1, 7 o 30 giorni, oppure definitivo)' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 3 and 500 then
    raise exception 'Scrivi il motivo del ban (da 3 a 500 caratteri)' using errcode = '22023';
  end if;
  v_until := case when p_days is null then 'infinity'::timestamptz else now() + make_interval(days => p_days) end;
  insert into public.user_moderation (user_id, banned_until, ban_reason, updated_by, updated_at)
  values (p_user, v_until, btrim(p_reason), p_admin, now())
  on conflict (user_id) do update
    set banned_until = excluded.banned_until, ban_reason = excluded.ban_reason,
        updated_by = excluded.updated_by, updated_at = now();
  perform private.notify_user(p_user, 'ban', p_reason, v_until);
  return v_until;
end;
$$;
revoke all on function private.apply_ban(text, text, integer, text) from public, anon, authenticated;

-- Autore del contenuto segnalato (annuncio, commento o chat).
create or replace function private.report_author(p_kind text, p_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case p_kind
    when 'listing' then (select owner_id from public.listings where id = p_id)
    when 'comment' then (select author_id from public.listing_comments where id = p_id)
    when 'chat' then (select reported_user_id from public.chat_reports where id = p_id)
  end;
$$;
revoke all on function private.report_author(text, uuid) from public, anon, authenticated;

create or replace function private.person(p_uid text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when p.id is null then null else jsonb_build_object(
    'id', p.id, 'username', p.username, 'name', p.public_name,
    'account_type', p.account_type, 'banned_until', m.banned_until
  ) end
  from (select p_uid as uid) x
  left join public.profiles p on p.id = x.uid
  left join public.user_moderation m on m.user_id = x.uid;
$$;
revoke all on function private.person(text) from public, anon, authenticated;

-- ------------------------------------------------------------------ funzioni dell'app
-- Stato per aprire il gestionale: nessun dato per chi non è amministratore.
create or replace function public.admin_access()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when a.user_id is null then jsonb_build_object('admin', false)
  else jsonb_build_object(
    'admin', true,
    'role', a.role,
    'pin', exists (select 1 from private.account_security s where s.id = a.user_id and s.pin_hash is not null)
  ) end
  from (select public.current_uid() as uid) me
  left join public.admin_users a on a.user_id = me.uid;
$$;

-- Coda delle segnalazioni. [p_closed] false: da gestire; true: gestite negli ultimi 30 giorni.
create or replace function public.admin_reports(p_closed boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_items jsonb;
begin
  perform private.require_admin_2fa();
  with grouped as (
    select r.target::text as kind, r.target_id as id,
           count(*) as reports,
           jsonb_agg(distinct r.reason) as reasons,
           (jsonb_agg(r.details order by r.created_at desc) filter (where r.details is not null)) as details,
           min(r.created_at) as first_at, max(r.created_at) as last_at,
           max(r.handled_at) as handled_at,
           (array_agg(r.status::text order by r.handled_at desc nulls last))[1] as status
    from public.reports r
    where r.target in ('listing', 'comment')
      and case when p_closed then r.status in ('resolved', 'dismissed') and r.handled_at > now() - interval '30 days'
               else r.status in ('open', 'reviewing') end
    group by r.target, r.target_id
  ),
  content as (
    select g.kind, g.id, g.reports, g.reasons,
           coalesce((select jsonb_agg(d) from (select jsonb_array_elements(g.details) d limit 5) x), '[]'::jsonb) as details,
           g.first_at, g.last_at, g.handled_at, g.status,
           case g.kind
             when 'listing' then (
               select jsonb_build_object('title', l.title, 'text', left(l.description, 500),
                 'listing_kind', l.kind, 'state', l.status, 'created_at', l.created_at)
               from public.listings l where l.id = g.id)
             when 'comment' then (
               select jsonb_build_object('text', c.body, 'hidden', c.hidden_at is not null,
                 'listing_id', c.listing_id, 'listing_title', l.title, 'created_at', c.created_at)
               from public.listing_comments c join public.listings l on l.id = c.listing_id
               where c.id = g.id)
           end as preview,
           private.person(private.report_author(g.kind, g.id)) as author
    from grouped g
  ),
  chats as (
    select 'chat'::text as kind, r.id, 1::bigint as reports, jsonb_build_array(r.reason) as reasons,
           case when r.details is null then '[]'::jsonb else jsonb_build_array(r.details) end as details,
           r.created_at as first_at, r.created_at as last_at, null::timestamptz as handled_at, r.status,
           jsonb_build_object('group', r.is_group, 'messages', r.messages) as preview,
           private.person(r.reported_user_id) as author
    from public.chat_reports r
    where case when p_closed then r.status = 'closed' and r.created_at > now() - interval '30 days'
               else r.status = 'open' end
  )
  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_at desc), '[]'::jsonb) into v_items
  from (
    select * from content
    union all
    select * from chats
    order by last_at desc
    limit 200
  ) x;
  return v_items;
end;
$$;

-- Gestisce una segnalazione. [p_action]: ignore | remove | warn | ban.
-- [p_message]: testo per la persona (obbligatorio per avviso e ban).
-- [p_remove]: con avviso o ban, toglie anche il contenuto.
create or replace function public.admin_report_resolve(
  p_kind text,
  p_id uuid,
  p_action text,
  p_message text default null,
  p_ban_days integer default null,
  p_remove boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := private.require_admin_2fa();
  v_author text;
  v_remove boolean := p_action = 'remove' or (p_remove and p_action in ('warn', 'ban'));
  v_until timestamptz;
  v_msg text := nullif(btrim(coalesce(p_message, '')), '');
begin
  if p_kind not in ('listing', 'comment', 'chat') then
    raise exception 'Tipo non valido' using errcode = '22023';
  end if;
  if p_action not in ('ignore', 'remove', 'warn', 'ban') then
    raise exception 'Azione non valida' using errcode = '22023';
  end if;
  if p_kind = 'chat' and v_remove then
    raise exception 'I messaggi della chat sono cifrati: non si possono togliere' using errcode = '22023';
  end if;
  if p_kind = 'chat' then
    if not exists (select 1 from public.chat_reports where id = p_id) then
      raise exception 'Segnalazione non trovata' using errcode = '22023';
    end if;
  elsif not exists (select 1 from public.reports where target::text = p_kind and target_id = p_id) then
    raise exception 'Segnalazione non trovata' using errcode = '22023';
  end if;
  if p_action = 'warn' and char_length(coalesce(v_msg, '')) < 3 then
    raise exception 'Scrivi il testo dell''avviso' using errcode = '22023';
  end if;

  v_author := private.report_author(p_kind, p_id);
  if p_action in ('warn', 'ban') and v_author is null then
    raise exception 'Autore non più presente' using errcode = '22023';
  end if;

  if p_action = 'ban' then
    v_until := private.apply_ban(v_admin, v_author, p_ban_days, v_msg);
  elsif p_action = 'warn' then
    perform private.notify_user(v_author, 'warning', v_msg);
  end if;

  if v_remove then
    if p_kind = 'listing' then
      update public.listings set status = 'removed' where id = p_id;
    else
      update public.listing_comments
      set hidden_at = coalesce(hidden_at, now()), hidden_by = coalesce(hidden_by, v_admin)
      where id = p_id;
    end if;
    if p_action = 'remove' then
      perform private.notify_user(v_author, 'removed', coalesce(v_msg, case p_kind
        when 'listing' then 'Un tuo annuncio è stato tolto perché non rispetta le regole della community.'
        else 'Un tuo commento è stato nascosto perché non rispetta le regole della community.' end));
    end if;
  end if;

  if p_kind = 'chat' then
    update public.chat_reports set status = 'closed' where id = p_id;
  else
    update public.reports
    set status = case when p_action = 'ignore' then 'dismissed'::public.report_status
                      else 'resolved'::public.report_status end,
        handled_by = v_admin, handled_at = now()
    where target::text = p_kind and target_id = p_id and status in ('open', 'reviewing');
  end if;

  perform private.log_action(v_admin, v_author, p_action, p_kind, p_id::text, v_msg, v_until);
  if v_remove and p_action <> 'remove' then
    perform private.log_action(v_admin, v_author, 'remove', p_kind, p_id::text, v_msg);
  end if;
end;
$$;

-- Ricerca utenti per nome utente o nome pubblico (mai per numero di telefono).
create or replace function public.admin_users_search(p_query text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q text := btrim(coalesce(p_query, ''));
  v_items jsonb;
begin
  perform private.require_admin_2fa();
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  select coalesce(jsonb_agg(private.person(x.id) order by x.created_at desc), '[]'::jsonb) into v_items
  from (
    select p.id, p.created_at from public.profiles p
    where v_q = '' or p.username::text ilike '%' || v_q || '%' or p.public_name ilike '%' || v_q || '%'
    order by p.created_at desc
    limit 50
  ) x;
  return v_items;
end;
$$;

-- Scheda dell'utente: dati pubblici, ban, conteggi e storico.
create or replace function public.admin_user_detail(p_user text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_res jsonb;
begin
  perform private.require_admin_2fa();
  if not exists (select 1 from public.profiles where id = p_user) then
    return null;
  end if;
  select jsonb_build_object(
    'person', private.person(p.id),
    'created_at', p.created_at,
    'bio', p.bio,
    'is_admin', exists (select 1 from public.admin_users a where a.user_id = p.id),
    'ban_reason', case when m.banned_until > now() then m.ban_reason end,
    'listings', (select count(*) from public.listings l where l.owner_id = p.id and l.status = 'active'),
    'comments', (select count(*) from public.listing_comments c where c.author_id = p.id),
    'reports_open', (
      (select count(*) from public.reports r
       where r.status in ('open', 'reviewing') and (
         (r.target = 'listing' and exists (select 1 from public.listings l where l.id = r.target_id and l.owner_id = p.id))
         or (r.target = 'comment' and exists (select 1 from public.listing_comments c where c.id = r.target_id and c.author_id = p.id))))
      + (select count(*) from public.chat_reports cr where cr.status = 'open' and cr.reported_user_id = p.id)),
    'reports_total', (
      (select count(*) from public.reports r
       where (r.target = 'listing' and exists (select 1 from public.listings l where l.id = r.target_id and l.owner_id = p.id))
          or (r.target = 'comment' and exists (select 1 from public.listing_comments c where c.id = r.target_id and c.author_id = p.id)))
      + (select count(*) from public.chat_reports cr where cr.reported_user_id = p.id)),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action', h.action, 'target', h.target, 'reason', h.reason, 'until', h.until,
        'at', h.created_at, 'by', (select ap.username from public.profiles ap where ap.id = h.admin_id)
      ) order by h.created_at desc)
      from (select * from private.moderation_log where user_id = p.id order by created_at desc limit 50) h
    ), '[]'::jsonb)
  ) into v_res
  from public.profiles p
  left join public.user_moderation m on m.user_id = p.id
  where p.id = p_user;
  return v_res;
end;
$$;

create or replace function public.admin_ban_user(p_user text, p_days integer, p_reason text)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := private.require_admin_2fa();
  v_until timestamptz;
begin
  v_until := private.apply_ban(v_admin, p_user, p_days, p_reason);
  perform private.log_action(v_admin, p_user, 'ban', 'user', p_user, btrim(p_reason), v_until);
  return v_until;
end;
$$;

create or replace function public.admin_unban_user(p_user text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := private.require_admin_2fa();
begin
  if not private.user_banned(p_user) then
    raise exception 'L''utente non è bannato' using errcode = '22023';
  end if;
  update public.user_moderation
  set banned_until = null, ban_reason = null, updated_by = v_admin, updated_at = now()
  where user_id = p_user;
  perform private.notify_user(p_user, 'unban',
    coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Il tuo account è di nuovo attivo. Grazie per rispettare le regole della community.'));
  perform private.log_action(v_admin, p_user, 'unban', 'user', p_user, nullif(btrim(coalesce(p_reason, '')), ''));
end;
$$;

create or replace function public.admin_warn_user(p_user text, p_message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin text := private.require_admin_2fa();
begin
  if not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'Utente non trovato' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_message, ''))) not between 3 and 500 then
    raise exception 'Scrivi il testo dell''avviso (da 3 a 500 caratteri)' using errcode = '22023';
  end if;
  perform private.notify_user(p_user, 'warning', p_message);
  perform private.log_action(v_admin, p_user, 'warn', 'user', p_user, btrim(p_message));
end;
$$;

-- Per la persona: ban in corso (con il motivo) e avvisi non ancora letti.
create or replace function public.my_moderation()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'banned_until', (select m.banned_until from public.user_moderation m
                     where m.user_id = me.uid and m.banned_until > now()),
    'ban_reason', (select m.ban_reason from public.user_moderation m
                   where m.user_id = me.uid and m.banned_until > now()),
    'notices', coalesce((
      select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'message', n.message,
                                          'until', n.until, 'at', n.created_at) order by n.created_at)
      from public.moderation_notices n
      where n.user_id = me.uid and n.read_at is null
    ), '[]'::jsonb)
  )
  from (select public.current_uid() as uid) me
  where me.uid is not null;
$$;

create or replace function public.moderation_notices_read()
returns void
language sql
security definer
set search_path = public
as $$
  update public.moderation_notices set read_at = now()
  where user_id = public.current_uid() and read_at is null;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.admin_access()',
    'public.admin_reports(boolean)',
    'public.admin_report_resolve(text, uuid, text, text, integer, boolean)',
    'public.admin_users_search(text)',
    'public.admin_user_detail(text)',
    'public.admin_ban_user(text, integer, text)',
    'public.admin_unban_user(text, text)',
    'public.admin_warn_user(text, text)',
    'public.my_moderation()',
    'public.moderation_notices_read()'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

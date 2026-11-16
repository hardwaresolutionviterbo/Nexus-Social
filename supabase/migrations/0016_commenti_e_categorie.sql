-- Piazly · Fase 5, Blocco 5: commenti completi (Mappa e Scambia & Vendi) e amministrazione
-- delle categorie.
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Decisioni (docs/fase5/PIANO_OPERATIVO.md D8, D9; specifica R5.12):
--  • modifica del proprio commento, con l'indicazione «modificato»;
--  • l'autore dell'annuncio e gli amministratori nascondono (e rimostrano) un commento: resta
--    al suo posto con l'autore invariato, il testo lo vedono solo chi l'ha scritto, l'autore
--    dell'annuncio e gli amministratori; a un commento nascosto non si risponde e non si mette
--    Mi piace;
--  • segnalazione di un commento alla moderazione (una aperta per persona e commento);
--  • anti-spam: 10 commenti al minuto e 100 al giorno per persona (anche le risposte);
--  • categorie: solo gli amministratori creano, rinominano, descrivono, riordinano, attivano o
--    disattivano e archiviano; lo slug nasce dal nome con la stessa regola del catalogo e non
--    cambia più; gli annunci di una categoria archiviata restano integri.

-- ------------------------------------------------------------ commenti
alter table public.listing_comments
  add column edited_at timestamptz,
  add column hidden_at timestamptz,
  add column hidden_by text references public.profiles (id) on delete set null;

alter type public.report_target add value if not exists 'comment';

-- Anti-spam (D9): vale per ogni nuovo commento, comunque arrivi.
create or replace function private.comment_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('nexus.internal', true) = 'on' then
    return new;
  end if;
  if (select count(*) from public.listing_comments
      where author_id = new.author_id and created_at > now() - interval '1 minute') >= 10 then
    raise exception 'Stai commentando troppo in fretta: riprova tra un minuto' using errcode = '22023';
  end if;
  if (select count(*) from public.listing_comments
      where author_id = new.author_id and created_at > now() - interval '1 day') >= 100 then
    raise exception 'Hai raggiunto il limite di 100 commenti al giorno' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function private.comment_rate_limit() from public, anon, authenticated;

create trigger listing_comments_rate_limit
  before insert on public.listing_comments
  for each row execute function private.comment_rate_limit();

-- Risposte e Mi piace: non sui commenti nascosti.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.add_listing_comment(uuid, text, uuid)'::regprocedure) into v_def;
  if position('where c.id = p_parent and c.listing_id = p_listing;' in v_def) = 0 then
    raise exception 'add_listing_comment: testo atteso non trovato';
  end if;
  execute replace(
    v_def,
    'where c.id = p_parent and c.listing_id = p_listing;',
    'where c.id = p_parent and c.listing_id = p_listing and c.hidden_at is null;'
  );

  select pg_get_functiondef('public.set_comment_like(uuid, boolean)'::regprocedure) into v_def;
  if position('from public.listing_comments c where c.id = p_comment;' in v_def) = 0 then
    raise exception 'set_comment_like: testo atteso non trovato';
  end if;
  execute replace(
    v_def,
    'from public.listing_comments c where c.id = p_comment;',
    'from public.listing_comments c where c.id = p_comment and c.hidden_at is null;'
  );
end;
$$;

-- Il commento e chi può farci cosa.
create or replace function private.comment_for(p_comment uuid)
returns table (
  id uuid,
  listing_id uuid,
  author_id text,
  listing_owner text,
  hidden boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  return query
  select c.id, c.listing_id, c.author_id, l.owner_id, c.hidden_at is not null
  from public.listing_comments c
  join public.listings l on l.id = c.listing_id
  where c.id = p_comment
    and not public.is_blocked_between(c.author_id, v_uid)
    and (public.is_admin() or (
      l.status = 'active' and l.expires_at > now()
      and (l.kind = 'social' or (l.kind = 'market' and l.review_status = 'published'))
      and not public.hidden_by_block(l.owner_id)
    ));
end;
$$;

revoke all on function private.comment_for(uuid) from public, anon, authenticated;

create or replace function public.edit_my_comment(p_comment uuid, p_body text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_c record;
begin
  select * into v_c from private.comment_for(p_comment);
  if v_c.id is null or v_c.author_id <> v_uid then
    raise exception 'Commento non trovato o non tuo' using errcode = '42501';
  end if;
  if v_c.hidden then
    raise exception 'Un commento nascosto non si modifica' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_body, ''))) not between 1 and 1000 then
    raise exception 'Il commento deve avere da 1 a 1000 caratteri' using errcode = '22023';
  end if;
  update public.listing_comments
  set body = btrim(p_body), edited_at = now()
  where id = p_comment and body is distinct from btrim(p_body);
end;
$$;

create or replace function public.set_comment_hidden(p_comment uuid, p_hidden boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_c record;
begin
  select * into v_c from private.comment_for(p_comment);
  if v_c.id is null or not (v_c.listing_owner = v_uid or public.is_admin()) then
    raise exception 'Solo l''autore dell''annuncio o la moderazione' using errcode = '42501';
  end if;
  if p_hidden is null then
    raise exception 'Valore non valido' using errcode = '22023';
  end if;
  update public.listing_comments
  set hidden_at = case when p_hidden then coalesce(hidden_at, now()) end,
      hidden_by = case when p_hidden then coalesce(hidden_by, v_uid) end
  where id = p_comment;
end;
$$;

create or replace function public.report_comment(p_comment uuid, p_reason text, p_details text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_c record;
begin
  select * into v_c from private.comment_for(p_comment);
  if v_c.id is null then
    raise exception 'Commento non trovato' using errcode = '42501';
  end if;
  if v_c.author_id = v_uid then
    raise exception 'Non puoi segnalare un tuo commento' using errcode = '22023';
  end if;
  if p_reason is null or p_reason not in
     ('spam', 'truffa', 'contenuto_inappropriato', 'pericolo', 'falso', 'altro') then
    raise exception 'Motivo non valido' using errcode = '22023';
  end if;
  if char_length(coalesce(p_details, '')) > 1000 then
    raise exception 'Dettagli troppo lunghi (massimo 1000 caratteri)' using errcode = '22023';
  end if;
  insert into public.reports (reporter_id, target, target_id, reason, details)
  values (v_uid, 'comment', p_comment, p_reason, nullif(btrim(coalesce(p_details, '')), ''))
  on conflict (reporter_id, target, target_id) where status = 'open' do nothing;
end;
$$;

-- Elenco con «modificato», «nascosto» e i permessi di chi guarda.
drop function public.listing_comments_list(uuid);

create function public.listing_comments_list(p_listing uuid)
returns table (
  id uuid,
  parent_id uuid,
  body text,
  created_at timestamptz,
  author_id text,
  author_username text,
  author_public_name text,
  author_avatar_thumb_path text,
  likes integer,
  liked_by_me boolean,
  is_mine boolean,
  can_delete boolean,
  edited boolean,
  hidden boolean,
  can_hide boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_owner text := private.visible_listing_owner(p_listing);
  v_mod boolean := v_owner = v_uid or public.is_admin();
begin
  return query
    select
      c.id, c.parent_id,
      -- Il testo nascosto lo vedono solo chi l'ha scritto, l'autore dell'annuncio e la moderazione.
      case when c.hidden_at is null or c.author_id = v_uid or v_mod then c.body end,
      c.created_at,
      p.id, p.username::text, p.public_name, p.avatar_thumb_path,
      (select count(*)::integer from public.comment_likes k
       where k.comment_id = c.id and not public.is_blocked_between(k.user_id, v_uid)),
      exists (select 1 from public.comment_likes k where k.comment_id = c.id and k.user_id = v_uid),
      c.author_id = v_uid,
      c.author_id = v_uid or v_owner = v_uid,
      c.edited_at is not null,
      c.hidden_at is not null,
      v_mod
    from public.listing_comments c
    join public.profiles p on p.id = c.author_id
    where c.listing_id = p_listing
      and not public.is_blocked_between(c.author_id, v_uid)
      and (c.parent_id is null or exists (
        select 1 from public.listing_comments pc
        where pc.id = c.parent_id and not public.is_blocked_between(pc.author_id, v_uid)))
    order by c.created_at
    limit 1000;
end;
$$;

-- ------------------------------------------------------------ categorie (solo amministratori)
-- Stessa regola del catalogo (tool/marketplace/genera_catalogo.py): minuscole senza accenti,
-- parole senza articoli e preposizioni, unite da trattini.
create or replace function private.category_slug_part(p_name text)
returns text
language sql
immutable
as $$
  select coalesce(string_agg(w, '-' order by n), '')
  from regexp_split_to_table(
    translate(lower(btrim(p_name)), 'àáâäèéêëìíîïòóôöùúûüçñ''’', 'aaaaeeeeiiiioooouuuucn  '),
    '[^a-z0-9]+'
  ) with ordinality as t(w, n)
  where w <> '' and w not in ('e', 'di', 'per', 'da', 'd', 'la', 'il', 'lo', 'le', 'i', 'gli', 'a', 'con', 'in');
$$;

create or replace function private.require_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo gli amministratori' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.category_slug_part(text) from public, anon, authenticated;
revoke all on function private.require_admin() from public, anon, authenticated;

create or replace function public.admin_create_category(
  p_name text,
  p_parent uuid default null,
  p_description text default null,
  p_sort_order integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent public.marketplace_categories;
  v_base text;
  v_slug text;
  v_n integer := 1;
  v_id uuid := gen_random_uuid();
begin
  perform private.require_admin();
  if char_length(btrim(coalesce(p_name, ''))) not between 2 and 80 then
    raise exception 'Il nome deve avere da 2 a 80 caratteri' using errcode = '22023';
  end if;
  if p_parent is not null then
    select * into v_parent from public.marketplace_categories where id = p_parent;
    if v_parent.id is null or v_parent.parent_id is not null then
      raise exception 'La categoria principale non esiste' using errcode = '22023';
    end if;
  end if;
  v_base := private.category_slug_part(p_name);
  if v_base = '' then
    raise exception 'Il nome deve contenere lettere o numeri' using errcode = '22023';
  end if;
  if v_parent.id is not null then
    v_base := v_parent.slug || '-' || v_base;
  end if;
  v_slug := v_base;
  while exists (select 1 from public.marketplace_categories where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;
  insert into public.marketplace_categories (id, parent_id, name, description, slug, sort_order)
  values (
    v_id, p_parent, btrim(p_name), nullif(btrim(coalesce(p_description, '')), ''), v_slug,
    coalesce(p_sort_order, (select coalesce(max(sort_order), 0) + 10
                            from public.marketplace_categories
                            where parent_id is not distinct from p_parent))
  );
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$$;

create or replace function public.admin_update_category(
  p_id uuid,
  p_name text,
  p_description text default null,
  p_sort_order integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.require_admin();
  if char_length(btrim(coalesce(p_name, ''))) not between 2 and 80 then
    raise exception 'Il nome deve avere da 2 a 80 caratteri' using errcode = '22023';
  end if;
  -- Lo slug resta quello di nascita (trigger della migrazione 0010).
  update public.marketplace_categories
  set name = btrim(p_name),
      description = nullif(btrim(coalesce(p_description, '')), ''),
      sort_order = coalesce(p_sort_order, sort_order)
  where id = p_id;
  if not found then
    raise exception 'Categoria non trovata' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.admin_set_category_active(p_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.require_admin();
  update public.marketplace_categories
  set is_active = coalesce(p_active, is_active)
  where id = p_id and archived_at is null;
  if not found then
    raise exception 'Categoria non trovata o archiviata' using errcode = '22023';
  end if;
end;
$$;

-- Archiviare una principale archivia anche le sue sottocategorie.
create or replace function public.admin_archive_category(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.require_admin();
  update public.marketplace_categories
  set archived_at = coalesce(archived_at, now()), is_active = false
  where id = p_id or parent_id = p_id;
  if not found then
    raise exception 'Categoria non trovata' using errcode = '22023';
  end if;
end;
$$;

-- Tutte le categorie, anche disattivate e archiviate, con il numero di annunci attivi.
create or replace function public.admin_categories()
returns table (
  id uuid,
  parent_id uuid,
  name text,
  description text,
  slug text,
  sort_order integer,
  is_active boolean,
  archived_at timestamptz,
  active_listings integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_admin();
  return query
  select c.id, c.parent_id, c.name, c.description, c.slug, c.sort_order, c.is_active,
         c.archived_at,
         (select count(*)::integer from public.listings l
          where l.market_category_id = c.id and l.status = 'active')
  from public.marketplace_categories c
  order by c.parent_id nulls first, c.sort_order;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.edit_my_comment(uuid, text)',
    'public.set_comment_hidden(uuid, boolean)',
    'public.report_comment(uuid, text, text)',
    'public.listing_comments_list(uuid)',
    'public.admin_create_category(text, uuid, text, integer)',
    'public.admin_update_category(uuid, text, text, integer)',
    'public.admin_set_category_active(uuid, boolean)',
    'public.admin_archive_category(uuid)',
    'public.admin_categories()'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

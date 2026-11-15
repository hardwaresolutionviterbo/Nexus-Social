-- Piazly · Fase 5, Blocco 1: tipo di annuncio «market» e tabella delle categorie di
-- Scambia & Vendi (specifica del titolare, sezione 3).
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Il nuovo valore dell'enum si usa solo dalla migrazione successiva (regola di PostgreSQL).

alter type public.listing_kind add value if not exists 'market';

create table public.marketplace_categories (
  id uuid primary key,
  parent_id uuid references public.marketplace_categories (id) on delete restrict,
  name text not null check (char_length(btrim(name)) between 2 and 80),
  description text check (description is null or char_length(description) <= 300),
  -- Lo slug non cambia mai, anche se il nome visualizzato viene modificato.
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  -- Archiviata: non più proposta né mostrata nei filtri, ma gli annunci restano integri.
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index marketplace_categories_parent_idx
  on public.marketplace_categories (parent_id, sort_order);

-- Due soli livelli: categoria principale e sottocategoria.
create or replace function private.check_category_depth()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.parent_id is not null and exists (
    select 1 from public.marketplace_categories p
    where p.id = new.parent_id and p.parent_id is not null
  ) then
    raise exception 'Solo due livelli: categoria e sottocategoria' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger marketplace_categories_depth
  before insert or update on public.marketplace_categories
  for each row execute function private.check_category_depth();

-- Lo slug resta quello di nascita (specifica: «gli slug non devono cambiare»).
create or replace function private.keep_category_slug()
returns trigger
language plpgsql
as $$
begin
  if new.slug is distinct from old.slug or new.id is distinct from old.id then
    raise exception 'Lo slug e l''ID di una categoria non si cambiano' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger marketplace_categories_slug
  before update on public.marketplace_categories
  for each row execute function private.keep_category_slug();

alter table public.marketplace_categories enable row level security;
revoke all on public.marketplace_categories from public, anon, authenticated;
grant select on public.marketplace_categories to authenticated;

create policy "categorie attive leggibili"
  on public.marketplace_categories for select to authenticated
  using (is_active and archived_at is null or public.is_admin());

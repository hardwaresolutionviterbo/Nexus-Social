-- Piazly · Accesso al server senza il «timbro» `role: authenticated` (scelta C del titolare).
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Perché: Supabase dà il ruolo `authenticated` solo ai token Firebase con il claim
-- `role: authenticated`, che si aggiunge con una Cloud Function (piano Blaze) o con una chiave
-- di servizio. Senza quel claim la richiesta arriva come `anon`, ma Supabase ha già verificato
-- la firma del token Firebase e `public.current_uid()` (migrazioni 0002 e 0005) riconosce
-- l'utente da emittente, destinatario, soggetto e scadenza. Quindi:
--  • ogni richiesta all'API passa da un controllo iniziale (pre-request): senza un utente
--    Firebase valido è rifiutata, tranne `ping` (il controllo di raggiungibilità dell'app);
--    il controllo del telefono e del PIN (0005) resta quello di sempre, dentro le funzioni;
--    vale anche per chi usasse il ruolo `authenticated` con un token non di Firebase;
--  • `anon` riceve esattamente i permessi di `authenticated` (funzioni, tabelle, colonne,
--    policy delle tabelle e delle foto): le regole restano quelle di sempre, basate su
--    `current_uid()`, e restano chiuse senza un utente;
--  • le foto (Storage) non passano dal pre-request: lì valgono le policy, che senza utente
--    Firebase non danno nulla;
--  • il controllo automatico (supabase-rls.yml) verifica che i permessi di `anon` e
--    `authenticated` restino identici anche nelle migrazioni future.

-- ------------------------------------------------------------ raggiungibilità
create or replace function public.ping()
returns boolean
language sql
stable
as $$
  select true;
$$;

revoke all on function public.ping() from public;
grant execute on function public.ping() to anon, authenticated, service_role;

-- ------------------------------------------------------------ controllo iniziale
create or replace function public.require_firebase_identity()
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  -- Solo le richieste dell'app: il ruolo di servizio e gli strumenti interni passano.
  if current_user not in ('anon', 'authenticated') then
    return;
  end if;
  -- Identità Firebase valida (il controllo del telefono e del PIN resta nelle singole
  -- funzioni, che usano `current_uid()`).
  if public.current_uid_raw() is not null then
    return;
  end if;
  if coalesce(current_setting('request.path', true), '') in ('/rpc/ping', '/rest/v1/rpc/ping') then
    return;
  end if;
  raise exception 'Accesso richiesto' using errcode = '42501',
    hint = 'Serve un accesso con il numero di telefono.';
end;
$$;

revoke all on function public.require_firebase_identity() from public;
grant execute on function public.require_firebase_identity() to anon, authenticated, service_role;
grant execute on function public.current_uid() to anon, authenticated;
grant execute on function public.current_uid_raw() to anon, authenticated;

alter role authenticator set pgrst.db_pre_request = 'public.require_firebase_identity';
notify pgrst, 'reload config';

-- ------------------------------------------------------------ stessi permessi per anon
-- Funzione che allinea `anon` ad `authenticated`; si richiama alla fine di ogni migrazione
-- futura che concede qualcosa ad `authenticated`.
create or replace function private.align_anon_with_authenticated()
returns void
language plpgsql
set search_path = ''
as $$
declare
  r record;
  v_roles text;
begin
  -- Funzioni dello schema pubblico.
  for r in
    select p.oid::regprocedure as fn
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  loop
    execute format('grant execute on function %s to anon', r.fn);
  end loop;

  -- Tabelle e viste dello schema pubblico.
  for r in
    select table_schema, table_name, privilege_type
    from information_schema.role_table_grants
    where grantee = 'authenticated' and table_schema = 'public'
  loop
    execute format('grant %s on table %I.%I to anon', r.privilege_type, r.table_schema, r.table_name);
  end loop;

  -- Permessi sulle singole colonne (es. il profilo pubblico).
  for r in
    select table_schema, table_name, column_name, privilege_type
    from information_schema.column_privileges
    where grantee = 'authenticated' and table_schema = 'public'
  loop
    execute format('grant %s (%I) on table %I.%I to anon',
                   r.privilege_type, r.column_name, r.table_schema, r.table_name);
  end loop;

  -- Policy delle tabelle e delle foto: chi vale per `authenticated` vale anche per `anon`.
  for r in
    select schemaname, tablename, policyname, roles
    from pg_policies
    where schemaname in ('public', 'storage')
      and 'authenticated' = any (roles)
      and not ('anon' = any (roles))
  loop
    select string_agg(quote_ident(x), ', ') into v_roles
    from unnest(array_append(r.roles, 'anon'::name)) x;
    execute format('alter policy %I on %I.%I to %s', r.policyname, r.schemaname, r.tablename, v_roles);
  end loop;
end;
$$;

revoke all on function private.align_anon_with_authenticated() from public, anon, authenticated;

select private.align_anon_with_authenticated();

-- ------------------------------------------------------------ controllo per i test
-- Differenze di permessi tra `anon` e `authenticated` (deve restituire zero righe).
create or replace function private.anon_authenticated_differences()
returns table (kind text, object text)
language sql
stable
set search_path = ''
as $$
  select 'funzione', p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      <> has_function_privilege('anon', p.oid, 'EXECUTE')
    and p.proname not in ('ping', 'require_firebase_identity')
  union all
  select 'policy', schemaname || '.' || tablename || ': ' || policyname
  from pg_policies
  where schemaname in ('public', 'storage')
    and ('authenticated' = any (roles)) <> ('anon' = any (roles))
  union all
  select 'tabella', a.table_name || ' ' || a.privilege_type
  from information_schema.role_table_grants a
  where a.grantee = 'authenticated' and a.table_schema = 'public'
    and not exists (
      select 1 from information_schema.role_table_grants b
      where b.grantee = 'anon' and b.table_schema = 'public'
        and b.table_name = a.table_name and b.privilege_type = a.privilege_type);
$$;

revoke all on function private.anon_authenticated_differences() from public, anon, authenticated;

-- Piazly · La rubrica passa dalle Cloud Functions (piano Blaze) a una funzione di Supabase.
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Cosa cambia:
--  • le due chiavi della rubrica nascono qui, a caso, dentro il database (mai nel repository,
--    mai in chat): `oprf_key` (calcolo protetto dei numeri, RFC 9497) e `rubrica_attest_key`
--    (firma tra la funzione e il database); se esistono già restano quelle;
--  • la funzione `rubrica` (supabase/functions/rubrica) le legge con il ruolo di servizio,
--    insieme all'ID del progetto Firebase per controllare i token;
--  • i limiti (3 sincronizzazioni e 5 registrazioni del proprio numero al giorno) si contano
--    nel database invece che in Firestore;
--  • l'app e le altre regole della rubrica (migrazione 0006) non cambiano.

-- ------------------------------------------------------------ chiavi
-- Scalare valido per P-256: diverso da zero e minore dell'ordine del gruppo.
do $$
declare
  v_key text;
  n constant text := 'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551';
begin
  if not exists (select 1 from private.settings where key = 'oprf_key') then
    loop
      v_key := encode(extensions.gen_random_bytes(32), 'hex');
      exit when v_key < n and v_key <> repeat('0', 64);
    end loop;
    insert into private.settings (key, value) values ('oprf_key', v_key);
  end if;
  if not exists (select 1 from private.settings where key = 'rubrica_attest_key') then
    insert into private.settings (key, value)
    values ('rubrica_attest_key', encode(extensions.gen_random_bytes(32), 'hex'));
  end if;
end;
$$;

-- ------------------------------------------------------------ limiti giornalieri
create table private.contacts_limits (
  user_id text not null,
  day date not null,
  kind text not null check (kind in ('sincronizzazioni', 'mio_numero')),
  used integer not null default 0,
  primary key (user_id, day, kind)
);

-- ------------------------------------------------------------ solo per la funzione `rubrica`
create or replace function public.rubrica_server_config()
returns table (oprf_key text, attest_key text, firebase_project_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select value from private.settings where key = 'oprf_key'),
    (select value from private.settings where key = 'rubrica_attest_key'),
    (select value from private.settings where key = 'firebase_project_id');
$$;

-- true se l'uso è consentito (e lo conta), false se il limite del giorno è raggiunto.
create or replace function public.rubrica_consume_limit(p_uid text, p_kind text, p_max integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_used integer;
begin
  if p_uid is null or p_uid !~ '^[A-Za-z0-9_-]{1,128}$' then
    raise exception 'Utente non valido' using errcode = '22023';
  end if;
  insert into private.contacts_limits (user_id, day, kind, used)
  values (p_uid, (now() at time zone 'Europe/Rome')::date, p_kind, 1)
  on conflict (user_id, day, kind) do update
    set used = private.contacts_limits.used + 1
    where private.contacts_limits.used < p_max
  returning used into v_used;
  return v_used is not null;
end;
$$;

revoke all on function public.rubrica_server_config() from public, anon, authenticated;
revoke all on function public.rubrica_consume_limit(text, text, integer) from public, anon, authenticated;
grant execute on function public.rubrica_server_config() to service_role;
grant execute on function public.rubrica_consume_limit(text, text, integer) to service_role;

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

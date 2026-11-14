-- Piazly · Migrazione 0005 · Fase 2, Blocco 4: sicurezza dell'account
--
-- Come applicarla: SOLO con autorizzazione del titolare, dopo i test sul database temporaneo.
-- Supabase → SQL Editor → incolla tutto il file → Run. Presuppone 0001-0004 già applicate.
--
-- Verifica in due passaggi con PIN di 6 cifre, come WhatsApp (S2, R2.5):
--  - il PIN è salvato solo come hash bcrypt, mai in chiaro;
--  - chi entra da un telefono nuovo deve inserire il PIN: finché non lo fa, il server non lo
--    riconosce (public.current_uid restituisce null) e non vede né modifica alcun dato;
--  - il telefono diventa «attendibile» con un codice casuale che l'app conserva nella memoria
--    protetta e invia nell'intestazione x-device-id; il server ne conserva solo l'hash;
--  - 5 tentativi sbagliati bloccano i tentativi per 1 ora, poi 4, poi 24;
--  - PIN dimenticato: si chiede il ripristino e dopo 7 giorni il PIN si può togliere.
-- L'impronta o il volto (S3) restano sul telefono: non passano dal server.

create extension if not exists pgcrypto with schema extensions;

-- ------------------------------------------------------------ identità senza il controllo PIN
-- Stesso controllo del token di 0002. Serve solo alle funzioni del PIN.
create or replace function public.current_uid_raw()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_claims jsonb := auth.jwt();
  v_project text;
  v_now numeric := extract(epoch from now());
begin
  select s.value into v_project from private.settings s where s.key = 'firebase_project_id';
  if v_project is null or v_claims is null then
    return null;
  end if;
  if (v_claims ->> 'iss') is distinct from ('https://securetoken.google.com/' || v_project) then
    return null;
  end if;
  if not (
    v_claims -> 'aud' = to_jsonb(v_project)
    or (jsonb_typeof(v_claims -> 'aud') = 'array' and (v_claims -> 'aud') ? v_project)
  ) then
    return null;
  end if;
  if coalesce(v_claims ->> 'sub', '') !~ '^[A-Za-z0-9_-]{1,128}$' then
    return null;
  end if;
  if (v_claims ->> 'iat') is null or (v_claims ->> 'iat') !~ '^[0-9]+(\.[0-9]+)?$'
     or (v_claims ->> 'iat')::numeric > v_now + 60 then
    return null;
  end if;
  if (v_claims ->> 'exp') is null or (v_claims ->> 'exp') !~ '^[0-9]+(\.[0-9]+)?$'
     or (v_claims ->> 'exp')::numeric <= v_now then
    return null;
  end if;
  return v_claims ->> 'sub';
end;
$$;

-- ------------------------------------------------------------ tabelle (solo server)
create schema if not exists private;

create table private.account_security (
  id text primary key references public.profiles (id) on delete cascade,
  pin_hash text,
  pin_set_at timestamptz,
  failed_attempts integer not null default 0,
  lock_level integer not null default 0,
  locked_until timestamptz,
  reset_requested_at timestamptz
);

create table private.trusted_devices (
  user_id text not null,
  token_hash text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, token_hash)
);

revoke all on private.account_security from public, anon, authenticated;
revoke all on private.trusted_devices from public, anon, authenticated;

-- Hash del codice del telefono inviato dall'app (x-device-id), oppure null.
create or replace function public.request_device_hash()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_headers json;
  v_token text;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    return null;
  end;
  v_token := v_headers ->> 'x-device-id';
  if v_token is null or v_token !~ '^[A-Za-z0-9_-]{32,128}$' then
    return null;
  end if;
  return encode(extensions.digest(v_token, 'sha256'), 'hex');
end;
$$;

-- Vero se il telefono che fa la richiesta è attendibile per l'utente (o se non ha il PIN).
create or replace function public.device_trusted(p_uid text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
      select 1 from private.account_security s where s.id = p_uid and s.pin_hash is not null
    )
    or exists (
      select 1 from private.trusted_devices d
      where d.user_id = p_uid and d.token_hash = public.request_device_hash()
    );
$$;

-- Identità usata da TUTTE le regole e funzioni: con il PIN attivo, solo da un telefono
-- attendibile. Da un telefono nuovo l'utente non vede e non modifica nulla finché non
-- inserisce il PIN.
create or replace function public.current_uid()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid_raw();
begin
  if v_uid is null or not public.device_trusted(v_uid) then
    return null;
  end if;
  return v_uid;
end;
$$;

-- ------------------------------------------------------------ funzioni del PIN
create or replace function public.valid_pin(p_pin text)
returns boolean
language sql
immutable
as $$
  select p_pin ~ '^[0-9]{6}$';
$$;

-- Stato per l'app: PIN attivo, telefono attendibile, attesa dopo troppi tentativi.
create or replace function public.security_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid_raw();
  s private.account_security;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select * into s from private.account_security where id = v_uid;
  return jsonb_build_object(
    'pin_enabled', s.pin_hash is not null,
    'device_trusted', public.device_trusted(v_uid),
    'locked_until', case when s.locked_until > now() then s.locked_until end,
    'reset_requested_at', s.reset_requested_at,
    'reset_available_at', case when s.reset_requested_at is not null
                               then s.reset_requested_at + interval '7 days' end
  );
end;
$$;

-- Rende attendibile il telefono che fa la richiesta.
create or replace function public.trust_this_device(p_uid text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := public.request_device_hash();
begin
  if v_hash is null then
    raise exception 'Telefono non riconosciuto: riapri l''app e riprova' using errcode = '22023';
  end if;
  insert into private.trusted_devices (user_id, token_hash)
  values (p_uid, v_hash)
  on conflict do nothing;
  -- Al massimo 10 telefoni attendibili: si tolgono i più vecchi.
  delete from private.trusted_devices d
  where d.user_id = p_uid
    and d.token_hash not in (
      select t.token_hash from private.trusted_devices t
      where t.user_id = p_uid order by t.created_at desc limit 10
    );
end;
$$;

-- Attiva o cambia il PIN. Per cambiarlo serve quello attuale. Solo da un telefono attendibile.
create or replace function public.set_pin(p_new_pin text, p_current_pin text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid();
  s private.account_security;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if not public.valid_pin(coalesce(p_new_pin, '')) then
    raise exception 'Il PIN deve avere 6 cifre' using errcode = '22023';
  end if;
  select * into s from private.account_security where id = v_uid;
  if s.pin_hash is not null
     and (p_current_pin is null or extensions.crypt(p_current_pin, s.pin_hash) <> s.pin_hash) then
    raise exception 'PIN attuale errato' using errcode = '22023';
  end if;
  insert into private.account_security (id, pin_hash, pin_set_at)
  values (v_uid, extensions.crypt(p_new_pin, extensions.gen_salt('bf', 10)), now())
  on conflict (id) do update
    set pin_hash = excluded.pin_hash, pin_set_at = now(), failed_attempts = 0,
        lock_level = 0, locked_until = null, reset_requested_at = null;
  perform public.trust_this_device(v_uid);
end;
$$;

-- Disattiva il PIN (serve il PIN). Solo da un telefono attendibile.
create or replace function public.disable_pin(p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid();
  s private.account_security;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select * into s from private.account_security where id = v_uid;
  if s.pin_hash is null then
    return;
  end if;
  if p_pin is null or extensions.crypt(p_pin, s.pin_hash) <> s.pin_hash then
    raise exception 'PIN errato' using errcode = '22023';
  end if;
  update private.account_security
  set pin_hash = null, pin_set_at = null, failed_attempts = 0, lock_level = 0,
      locked_until = null, reset_requested_at = null
  where id = v_uid;
  delete from private.trusted_devices where user_id = v_uid;
end;
$$;

-- Verifica il PIN da un telefono nuovo. Restituisce true se corretto (e il telefono diventa
-- attendibile). Dopo 5 errori: attesa di 1 ora, poi 4, poi 24.
create or replace function public.verify_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid_raw();
  s private.account_security;
  v_wait interval;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select * into s from private.account_security where id = v_uid for update;
  if s.pin_hash is null then
    return true;
  end if;
  if s.locked_until is not null and s.locked_until > now() then
    raise exception 'Troppi tentativi: riprova più tardi' using errcode = '22023';
  end if;
  if p_pin is not null and public.valid_pin(p_pin)
     and extensions.crypt(p_pin, s.pin_hash) = s.pin_hash then
    update private.account_security
    set failed_attempts = 0, lock_level = 0, locked_until = null, reset_requested_at = null
    where id = v_uid;
    perform public.trust_this_device(v_uid);
    return true;
  end if;
  if s.failed_attempts + 1 >= 5 then
    v_wait := case s.lock_level when 0 then interval '1 hour' when 1 then interval '4 hours'
              else interval '24 hours' end;
    update private.account_security
    set failed_attempts = 0, lock_level = least(s.lock_level + 1, 2),
        locked_until = now() + v_wait
    where id = v_uid;
  else
    update private.account_security
    set failed_attempts = s.failed_attempts + 1
    where id = v_uid;
  end if;
  return false;
end;
$$;

-- PIN dimenticato: si chiede il ripristino; dopo 7 giorni il PIN si può togliere.
create or replace function public.request_pin_reset()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid_raw();
  v_at timestamptz;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  update private.account_security
  set reset_requested_at = coalesce(reset_requested_at, now())
  where id = v_uid and pin_hash is not null
  returning reset_requested_at + interval '7 days' into v_at;
  return v_at;
end;
$$;

create or replace function public.complete_pin_reset()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid_raw();
  s private.account_security;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select * into s from private.account_security where id = v_uid;
  if s.reset_requested_at is null or s.reset_requested_at + interval '7 days' > now() then
    raise exception 'Il ripristino non è ancora disponibile' using errcode = '22023';
  end if;
  update private.account_security
  set pin_hash = null, pin_set_at = null, failed_attempts = 0, lock_level = 0,
      locked_until = null, reset_requested_at = null
  where id = v_uid;
  delete from private.trusted_devices where user_id = v_uid;
  perform public.trust_this_device(v_uid);
end;
$$;

-- Uscita sicura: questo telefono non è più attendibile (al prossimo accesso serve il PIN).
create or replace function public.forget_this_device()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid_raw();
begin
  if v_uid is null then
    return;
  end if;
  delete from private.trusted_devices
  where user_id = v_uid and token_hash = public.request_device_hash();
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.security_status()',
    'public.set_pin(text, text)',
    'public.disable_pin(text)',
    'public.verify_pin(text)',
    'public.request_pin_reset()',
    'public.complete_pin_reset()',
    'public.forget_this_device()'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  foreach f in array array[
    'public.current_uid_raw()',
    'public.request_device_hash()',
    'public.device_trusted(text)',
    'public.trust_this_device(text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- Piazly · Migrazione 0006 · Fase 2, Blocco 5: rubrica
--
-- Come applicarla: SOLO con autorizzazione del titolare, dopo i test sul database temporaneo.
-- Supabase → SQL Editor → incolla tutto il file → Run. Presuppone 0001-0005 già applicate.
-- Dopo l'applicazione, quando la rubrica sarà attivata con Blaze, il titolare imposta la
-- chiave di firma condivisa con le Cloud Functions (mai nel repository):
--   insert into private.settings (key, value) values ('rubrica_attest_key', '<chiave>');
--
-- Regole (R2.6, R2.11, R2.12, S6, P5-P8, P13):
--  - la rubrica non arriva mai in chiaro: il telefono invia solo codici OPRF (RFC 9497)
--    calcolati con la chiave segreta delle Cloud Functions;
--  - consenso esplicito, registrato con la data e revocabile (P13);
--  - al massimo 3 sincronizzazioni al giorno e 2.000 numeri;
--  - «Revoca e cancella» elimina subito i dati derivati; senza nuova sincronizzazione
--    scadono dopo 30 giorni (P7);
--  - «Permetti a chi ha il mio numero di trovarmi» si accende con la propria
--    sincronizzazione e si può spegnere (P8); spento, il proprio codice non trova nessuno;
--  - il numero si vede solo a chi lo ha in rubrica ed è riconosciuto, se l'utente lo
--    consente (P5, P6); mai agli sconosciuti; i blocchi valgono anche qui (P12).

-- ------------------------------------------------------------ tabelle
create type public.consent_kind as enum ('contacts');

create table public.consents (
  user_id text not null references public.profiles (id) on delete cascade,
  kind public.consent_kind not null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (user_id, kind)
);

alter table public.consents enable row level security;
create policy "solo token del progetto Firebase" on public.consents
  as restrictive for all to authenticated
  using (public.current_uid() is not null) with check (public.current_uid() is not null);
create policy "legge i propri consensi"
  on public.consents for select to authenticated
  using (user_id = public.current_uid());
revoke all on public.consents from anon, authenticated;
grant select on public.consents to authenticated;

-- Numero e codice OPRF dell'utente: solo server.
create table private.phone_numbers (
  user_id text primary key references public.profiles (id) on delete cascade,
  phone_e164 text not null check (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  tag text not null unique check (tag ~ '^[0-9a-f]{64}$'),
  updated_at timestamptz not null default now()
);

-- Contatti riconosciuti: owner ha il numero di contact in rubrica.
create table private.contact_links (
  owner_id text not null references public.profiles (id) on delete cascade,
  contact_id text not null references public.profiles (id) on delete cascade,
  expires_at timestamptz not null,
  primary key (owner_id, contact_id),
  constraint contact_links_not_self check (owner_id <> contact_id)
);

create table private.contact_syncs (
  user_id text not null references public.profiles (id) on delete cascade,
  synced_at timestamptz not null default now()
);
create index contact_syncs_user_idx on private.contact_syncs (user_id, synced_at);

revoke all on private.phone_numbers, private.contact_links, private.contact_syncs
  from public, anon, authenticated;

alter table public.privacy_settings add column contacts_synced_at timestamptz;

-- ------------------------------------------------------------ funzioni
-- Consenso attivo alla rubrica.
create or replace function public.contacts_consent_active(p_uid text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.consents c
    where c.user_id = p_uid and c.kind = 'contacts' and c.revoked_at is null
  );
$$;

-- Registra il proprio numero con il codice firmato dalle Cloud Functions.
create or replace function public.register_my_phone(
  p_phone text,
  p_tag text,
  p_ts bigint,
  p_sig text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid();
  v_key text;
  v_claim text := auth.jwt() ->> 'phone_number';
  v_expected text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select s.value into v_key from private.settings s where s.key = 'rubrica_attest_key';
  if v_key is null then
    raise exception 'Rubrica non ancora disponibile' using errcode = '22023';
  end if;
  if p_phone is null or p_phone is distinct from v_claim then
    raise exception 'Numero non corrispondente all''accesso' using errcode = '42501';
  end if;
  if p_ts is null or abs(extract(epoch from now()) - p_ts) > 600 then
    raise exception 'Richiesta scaduta: riprova' using errcode = '22023';
  end if;
  v_expected := encode(
    extensions.hmac(v_uid || '|' || p_phone || '|' || p_tag || '|' || p_ts, v_key, 'sha256'),
    'hex'
  );
  if p_sig is null or p_sig <> v_expected then
    raise exception 'Firma non valida' using errcode = '42501';
  end if;
  insert into private.phone_numbers (user_id, phone_e164, tag)
  values (v_uid, p_phone, p_tag)
  on conflict (user_id) do update
    set phone_e164 = excluded.phone_e164, tag = excluded.tag, updated_at = now();
end;
$$;

-- Consenso alla rubrica: lo registra con la data e accende «trovarmi» (P8).
create or replace function public.enable_contacts()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  insert into public.consents (user_id, kind, granted_at, revoked_at)
  values (v_uid, 'contacts', now(), null)
  on conflict (user_id, kind) do update set granted_at = now(), revoked_at = null;
  insert into public.privacy_settings (id, discoverable)
  values (v_uid, true)
  on conflict (id) do update set discoverable = true;
end;
$$;

-- «Permetti a chi ha il mio numero di trovarmi»: acceso solo dopo aver attivato la rubrica.
create or replace function public.set_discoverable(p_value boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_value is true and not exists (
    select 1 from public.consents c where c.user_id = v_uid and c.kind = 'contacts'
  ) then
    raise exception 'Attiva prima la rubrica' using errcode = '22023';
  end if;
  insert into public.privacy_settings (id, discoverable)
  values (v_uid, coalesce(p_value, false))
  on conflict (id) do update set discoverable = coalesce(p_value, false);
end;
$$;

-- Sincronizzazione: i codici dei numeri in rubrica diventano contatti riconosciuti.
-- Sostituisce la sincronizzazione precedente; i dati scadono dopo 30 giorni.
create or replace function public.match_contacts(p_tags text[])
returns table (
  id text,
  username text,
  public_name text,
  avatar_thumb_path text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if not public.contacts_consent_active(v_uid) then
    raise exception 'Consenso alla rubrica non attivo' using errcode = '42501';
  end if;
  if p_tags is null or coalesce(array_length(p_tags, 1), 0) > 2000 then
    raise exception 'Al massimo 2.000 numeri per sincronizzazione' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_tags) t where t !~ '^[0-9a-f]{64}$') then
    raise exception 'Dati non validi' using errcode = '22023';
  end if;
  if (select count(*) from private.contact_syncs s
      where s.user_id = v_uid and s.synced_at > now() - interval '1 day') >= 3 then
    raise exception 'Limite giornaliero raggiunto. Riprova domani' using errcode = '22023';
  end if;

  insert into private.contact_syncs (user_id) values (v_uid);
  delete from private.contact_syncs where synced_at < now() - interval '2 days';
  delete from private.contact_links l where l.owner_id = v_uid or l.expires_at <= now();

  insert into private.contact_links (owner_id, contact_id, expires_at)
  select distinct v_uid, n.user_id, now() + interval '30 days'
  from private.phone_numbers n
  join public.privacy_settings ps on ps.id = n.user_id and ps.discoverable
  where n.tag = any (p_tags)
    and n.user_id <> v_uid
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = v_uid and b.blocked_id = n.user_id)
         or (b.blocker_id = n.user_id and b.blocked_id = v_uid)
    );

  update public.privacy_settings set contacts_synced_at = now() where privacy_settings.id = v_uid;

  return query
  select p.id, p.username::text, p.public_name, p.avatar_thumb_path
  from private.contact_links l
  join public.profiles p on p.id = l.contact_id
  where l.owner_id = v_uid and l.expires_at > now()
  order by p.public_name;
end;
$$;

-- Contatti riconosciuti ancora validi, con i soli dati pubblici e il numero se consentito.
create or replace function public.my_contacts()
returns table (
  id text,
  username text,
  public_name text,
  avatar_thumb_path text,
  phone text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username::text, p.public_name, p.avatar_thumb_path,
         case when coalesce(ps.phone_visibility, 'contacts') = 'contacts'
              then n.phone_e164 end
  from private.contact_links l
  join public.profiles p on p.id = l.contact_id
  left join public.privacy_settings ps on ps.id = l.contact_id
  left join private.phone_numbers n on n.user_id = l.contact_id
  where l.owner_id = public.current_uid()
    and l.expires_at > now()
    and public.contacts_consent_active(l.owner_id)
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = l.owner_id and b.blocked_id = l.contact_id)
         or (b.blocker_id = l.contact_id and b.blocked_id = l.owner_id)
    )
  order by p.public_name;
$$;

-- Numero di un utente: solo se chi chiede lo ha in rubrica ed è riconosciuto, e l'utente
-- lo consente. Agli sconosciuti mai (P5, P6).
create or replace function public.contact_phone(p_id text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select c.phone from public.my_contacts() c where c.id = p_id;
$$;

-- «Revoca e cancella»: stop alla sincronizzazione e cancellazione dei dati derivati.
create or replace function public.revoke_contacts()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := public.current_uid();
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  delete from private.contact_links where owner_id = v_uid;
  update public.consents set revoked_at = now()
  where user_id = v_uid and kind = 'contacts' and revoked_at is null;
  update public.privacy_settings set contacts_synced_at = null where id = v_uid;
end;
$$;

-- Stato della pagina Privacy: anche rubrica e consenso.
create or replace function public.get_my_privacy()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'phone_visibility', coalesce(s.phone_visibility, 'contacts'),
    'discoverable', coalesce(s.discoverable, false),
    'show_bio', p.show_bio,
    'show_social', p.show_social,
    'blocked_count', (select count(*) from public.user_blocks b where b.blocker_id = p.id),
    'contacts_enabled', public.contacts_consent_active(p.id),
    'contacts_consent_at', (select c.granted_at from public.consents c
                            where c.user_id = p.id and c.kind = 'contacts'
                              and c.revoked_at is null),
    'contacts_synced_at', s.contacts_synced_at,
    'contacts_expire_at', s.contacts_synced_at + interval '30 days',
    'contacts_count', (select count(*) from public.my_contacts())
  )
  from public.profiles p
  left join public.privacy_settings s on s.id = p.id
  where p.id = public.current_uid();
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.register_my_phone(text, text, bigint, text)',
    'public.enable_contacts()',
    'public.set_discoverable(boolean)',
    'public.match_contacts(text[])',
    'public.my_contacts()',
    'public.contact_phone(text)',
    'public.revoke_contacts()',
    'public.get_my_privacy()'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  execute 'revoke all on function public.contacts_consent_active(text) from public, anon, authenticated';
end;
$$;

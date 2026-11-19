-- Fase 4 · Blocco 12: «online» e «ultimo accesso», come su WhatsApp.
--
-- L'app dice al server quando è aperta (ogni 30 secondi) e quando si chiude. Chi può vederlo lo
-- decide ognuno in Privacy → «Ultimo accesso e online»: Tutti, I miei contatti (chi ho in
-- rubrica), Nessuno. Come su WhatsApp vale anche al contrario: chi lo nasconde non vede quello
-- degli altri. Con un blocco, in nessuna delle due direzioni.

alter table public.privacy_settings
  add column if not exists last_seen text not null default 'contatti'
  check (last_seen in ('tutti', 'contatti', 'nessuno'));

create table private.presence (
  user_id text primary key references public.profiles (id) on delete cascade,
  last_seen timestamptz not null default now(),
  online_until timestamptz not null default now()
);

-- App aperta (p_online) o appena chiusa.
create or replace function public.presence_ping(p_online boolean)
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
  insert into private.presence (user_id, last_seen, online_until)
  values (v_uid, now(), case when coalesce(p_online, false) then now() + interval '45 seconds' else now() end)
  on conflict (user_id) do update
    set last_seen = now(),
        online_until = case when coalesce(p_online, false) then now() + interval '45 seconds' else now() end;
end;
$$;

-- Stato di più persone: online, oppure da quando non lo sono. Nulla se non si può vedere.
create or replace function public.presence_of(p_users text[])
returns table (id text, online boolean, last_seen timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_mine text;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if p_users is null or coalesce(array_length(p_users, 1), 0) > 200 then
    raise exception 'Al massimo 200 persone' using errcode = '22023';
  end if;
  select coalesce(s.last_seen, 'contatti') into v_mine from public.privacy_settings s where s.id = v_uid;
  v_mine := coalesce(v_mine, 'contatti');
  return query
  select u.uid,
         visible and coalesce(p.online_until > now(), false),
         case when visible then p.last_seen end
  from (
    select t.uid,
      v_mine <> 'nessuno'
      and t.uid <> v_uid
      and not public.is_blocked_between(v_uid, t.uid)
      and (
        coalesce(s.last_seen, 'contatti') = 'tutti'
        or (coalesce(s.last_seen, 'contatti') = 'contatti' and exists (
              select 1 from private.contact_links l
              where l.owner_id = t.uid and l.contact_id = v_uid and l.expires_at > now()))
      ) as visible
    from unnest(p_users) as t(uid)
    left join public.privacy_settings s on s.id = t.uid
  ) u
  left join private.presence p on p.user_id = u.uid;
end;
$$;

create or replace function public.set_last_seen(p_value text)
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
  if p_value is null or p_value not in ('tutti', 'contatti', 'nessuno') then
    raise exception 'Valore non valido' using errcode = '22023';
  end if;
  insert into public.privacy_settings (id, last_seen) values (v_uid, p_value)
  on conflict (id) do update set last_seen = excluded.last_seen;
end;
$$;

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
    'contacts_count', (select count(*) from public.my_contacts()),
    'last_seen', coalesce(s.last_seen, 'contatti')
  )
  from public.profiles p
  left join public.privacy_settings s on s.id = p.id
  where p.id = public.current_uid();
$$;

revoke all on function public.presence_ping(boolean) from public, anon;
revoke all on function public.presence_of(text[]) from public, anon;
revoke all on function public.set_last_seen(text) from public, anon;
revoke all on function public.get_my_privacy() from public, anon;
grant execute on function public.presence_ping(boolean) to authenticated;
grant execute on function public.presence_of(text[]) to authenticated;
grant execute on function public.set_last_seen(text) to authenticated;
grant execute on function public.get_my_privacy() to authenticated;

select private.align_anon_with_authenticated();

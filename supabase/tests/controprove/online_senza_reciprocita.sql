-- Difetto introdotto apposta: chi nasconde il proprio vede quello degli altri. Deve far fallire OL2.
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
      t.uid <> v_uid
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

select private.align_anon_with_authenticated();

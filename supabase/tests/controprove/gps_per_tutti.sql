-- Difetto introdotto apposta: la posizione la vede chiunque. Deve far fallire GP2.
create or replace function public.live_visible()
returns table (user_id text, username text, public_name text, avatar_thumb_path text,
               lat double precision, lng double precision, accuracy real,
               updated_at timestamptz, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.live_cleanup();
  return query
  select s.owner_id, p.username::text, p.public_name, p.avatar_thumb_path,
         l.lat, l.lng, l.accuracy, l.updated_at, s.expires_at
  from private.live_shares s
  join private.live_positions l on l.user_id = s.owner_id
  join public.profiles p on p.id = s.owner_id
  where s.expires_at > now()
    and not public.is_blocked_between(s.owner_id, s.viewer_id);
end;
$$;

select private.align_anon_with_authenticated();

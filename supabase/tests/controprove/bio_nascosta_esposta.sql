-- Difetto introdotto apposta: il profilo pubblico ignora l'interruttore della bio.
-- Deve far fallire F3.
create or replace function public.get_public_profile(p_id text)
returns table (
  id text, account_type public.account_type, username text, public_name text,
  business_name text, avatar_path text, avatar_thumb_path text, bio text,
  social_links jsonb, rating_avg numeric, rating_count integer, created_at timestamptz
)
language sql stable security definer set search_path = public
as $$
  select p.id, p.account_type, p.username::text, p.public_name, p.business_name,
         p.avatar_path, p.avatar_thumb_path, p.bio, p.social_links, p.rating_avg,
         p.rating_count, p.created_at
  from public.profiles p
  where public.current_uid() is not null and p.id = p_id;
$$;

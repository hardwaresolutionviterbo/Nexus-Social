-- Difetto introdotto apposta: gli stati li vede anche chi non è in rubrica. Deve far fallire ST1.
create or replace function private.status_visible(p_status public.statuses, p_viewer text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_viewer is not null and (
    p_status.user_id = p_viewer
    or (
      p_status.expires_at > now()
      and not public.is_blocked_between(p_status.user_id, p_viewer)
      and case p_status.audience
            when 'contatti' then true
            when 'tranne' then not exists (select 1 from public.status_audience a
                                           where a.status_id = p_status.id and a.user_id = p_viewer)
            else exists (select 1 from public.status_audience a
                         where a.status_id = p_status.id and a.user_id = p_viewer)
          end
    )
  );
$$;

select private.align_anon_with_authenticated();

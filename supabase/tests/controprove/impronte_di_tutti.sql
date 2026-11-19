-- Difetto introdotto apposta: dice di chi è qualsiasi impronta, non solo dei contatti. Deve far fallire CN1.
create or replace function public.match_contact_tags(p_tags text[])
returns table (id text, tag text)
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
    raise exception 'Al massimo 2.000 numeri' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_tags) t where t !~ '^[0-9a-f]{64}$') then
    raise exception 'Dati non validi' using errcode = '22023';
  end if;
  return query
  select n.user_id, n.tag
  from private.phone_numbers n
  where n.tag = any (p_tags);
end;
$$;

select private.align_anon_with_authenticated();

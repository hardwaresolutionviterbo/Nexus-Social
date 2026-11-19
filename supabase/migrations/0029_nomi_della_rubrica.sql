-- Fase 4 · Blocco 11: nelle chat i nomi come li hai scritti nella tua rubrica.
--
-- Dopo la sincronizzazione protetta della rubrica (Fase 2) il telefono sa quali impronte dei
-- suoi numeri corrispondono a persone su Piazly, ma non a quale persona. Questa funzione
-- risponde solo per le persone già riconosciute come contatti (contact_links): «l'impronta X è
-- di questa persona». Il telefono già conosce quel numero (è nella sua rubrica), quindi non
-- impara niente di nuovo; il nome resta sul telefono e non arriva mai al server.

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
  join private.contact_links l on l.contact_id = n.user_id and l.owner_id = v_uid and l.expires_at > now()
  where n.tag = any (p_tags);
end;
$$;

revoke all on function public.match_contact_tags(text[]) from public, anon;
grant execute on function public.match_contact_tags(text[]) to authenticated;

select private.align_anon_with_authenticated();

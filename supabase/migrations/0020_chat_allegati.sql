-- Piazly · Fase 4, Blocco 3: allegati della chat (foto, video, vocali, documenti).
--
-- NON applicare al database reale senza l'autorizzazione esplicita del titolare.
--
-- Gli allegati sono cifrati sul telefono (AES-256-GCM, una chiave nuova per ogni file) prima
-- di partire: nel contenitore «chat-media» ci sono solo byte illeggibili. La chiave viaggia
-- dentro il messaggio, cifrato a sua volta con MLS.
--
-- Regole:
--  • percorso: <id chat>/<chi invia>/<nome casuale>.bin;
--  • carica solo chi fa parte della chat, nella propria cartella, al massimo 50 MB per file
--    e 200 file al giorno;
--  • scarica solo chi fa parte della chat (mai con un blocco, mai dopo un rifiuto);
--  • chi riceve cancella il file dal server appena l'ha scaricato; può cancellarlo anche chi
--    l'ha inviato;
--  • nessuna modifica dei file caricati.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-media', 'chat-media', false, 52428800, array['application/octet-stream'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Chi chiama fa parte della chat [p_conversation] (attiva o richiesta, senza blocchi).
create or replace function public.chat_media_member(p_conversation text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_conv uuid;
begin
  if v_uid is null or p_conversation is null
     or p_conversation !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  v_conv := p_conversation::uuid;
  return exists (
    select 1
    from public.chat_members me
    join public.chat_members other
      on other.conversation_id = me.conversation_id and other.user_id <> me.user_id
    where me.conversation_id = v_conv
      and me.user_id = v_uid
      and me.status <> 'declined'
      and not public.is_blocked_between(me.user_id, other.user_id)
  );
end;
$$;

-- Al massimo 200 allegati al giorno per persona.
create or replace function public.chat_media_quota_ok()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select count(*) < 200
  from storage.objects o
  where o.bucket_id = 'chat-media'
    and (storage.foldername(o.name))[2] = public.current_uid()
    and o.created_at > now() - interval '1 day';
$$;

-- Servono alle regole del contenitore (che girano con il ruolo di chi chiama). Dicono solo
-- «sì/no» su chi chiama: nessun dato di altri.
revoke all on function public.chat_media_member(text) from public, anon;
revoke all on function public.chat_media_quota_ok() from public, anon;
grant execute on function public.chat_media_member(text) to authenticated;
grant execute on function public.chat_media_quota_ok() to authenticated;

create policy "allegati chat: lettura per chi è nella chat"
  on storage.objects for select to authenticated
  using (bucket_id = 'chat-media' and public.chat_media_member((storage.foldername(name))[1]));

create policy "allegati chat: caricamento nella propria cartella"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = public.current_uid()
    and name ~ '^[0-9a-f-]{36}/[^/]+/[A-Za-z0-9_-]{16,64}\.bin$'
    and public.chat_media_member((storage.foldername(name))[1])
    and public.chat_media_quota_ok()
  );

create policy "allegati chat: cancellazione per chi è nella chat"
  on storage.objects for delete to authenticated
  using (bucket_id = 'chat-media' and public.chat_media_member((storage.foldername(name))[1]));

-- Regola della migrazione 0017.
select private.align_anon_with_authenticated();

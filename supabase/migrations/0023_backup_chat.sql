-- Fase 4 · Blocco 6: backup della chat cifrato con una password.
--
-- Il telefono cifra la cronologia con una chiave ricavata dalla password (Argon2id + AES-256-GCM)
-- e la carica qui: il server conserva solo byte illeggibili e non conosce la password. Un solo
-- file per account, `{uid}/backup.bin`, visibile e modificabile solo dal proprietario.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-backups', 'chat-backups', false, 20971520, array['application/octet-stream'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Il file del backup appartiene a chi lo sta usando.
create or replace function public.chat_backup_own(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_uid() is not null
     and p_name = public.current_uid() || '/backup.bin';
$$;

-- Data e dimensione dell'ultimo backup (nessuna riga se non c'è).
create or replace function public.chat_backup_info()
returns table (updated_at timestamptz, size bigint)
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(o.updated_at, o.created_at), coalesce((o.metadata ->> 'size')::bigint, 0)
  from storage.objects o
  where o.bucket_id = 'chat-backups'
    and public.current_uid() is not null
    and o.name = public.current_uid() || '/backup.bin';
$$;

revoke all on function public.chat_backup_own(text) from public, anon;
revoke all on function public.chat_backup_info() from public, anon;
grant execute on function public.chat_backup_own(text) to authenticated;
grant execute on function public.chat_backup_info() to authenticated;

create policy "backup chat: lettura solo del proprio"
  on storage.objects for select to authenticated
  using (bucket_id = 'chat-backups' and public.chat_backup_own(name));

create policy "backup chat: caricamento solo del proprio"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-backups' and public.chat_backup_own(name));

create policy "backup chat: sostituzione solo del proprio"
  on storage.objects for update to authenticated
  using (bucket_id = 'chat-backups' and public.chat_backup_own(name))
  with check (bucket_id = 'chat-backups' and public.chat_backup_own(name));

create policy "backup chat: cancellazione solo del proprio"
  on storage.objects for delete to authenticated
  using (bucket_id = 'chat-backups' and public.chat_backup_own(name));

select private.align_anon_with_authenticated();

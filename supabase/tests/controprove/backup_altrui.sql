-- Difetto introdotto apposta: si legge il backup di chiunque. Deve far fallire V2.
drop policy if exists "backup chat: lettura solo del proprio" on storage.objects;
create policy "backup chat: lettura solo del proprio"
  on storage.objects for select to authenticated
  using (bucket_id = 'chat-backups');
select private.align_anon_with_authenticated();

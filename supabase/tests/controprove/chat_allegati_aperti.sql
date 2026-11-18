-- Difetto introdotto apposta: allegati della chat leggibili da chiunque abbia un accesso. Deve far fallire S2.
create policy "difetto: allegati a tutti" on storage.objects for select to authenticated
  using (bucket_id = 'chat-media');

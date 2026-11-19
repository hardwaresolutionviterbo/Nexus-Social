-- Difetto introdotto apposta: chiunque legge i tocchi di chiunque. Deve far fallire Z3.
drop policy if exists "tocchi della chat: solo il proprio canale" on realtime.messages;
create policy "tocchi della chat: solo il proprio canale"
  on realtime.messages for select to anon, authenticated
  using (true);
select private.align_anon_with_authenticated();

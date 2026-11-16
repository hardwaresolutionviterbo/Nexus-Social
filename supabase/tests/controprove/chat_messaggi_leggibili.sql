-- Difetto introdotto apposta: i messaggi cifrati leggibili direttamente da chiunque. Deve far fallire R5.
grant select on public.chat_messages to authenticated;
create policy "difetto: messaggi a tutti" on public.chat_messages for select to authenticated using (true);

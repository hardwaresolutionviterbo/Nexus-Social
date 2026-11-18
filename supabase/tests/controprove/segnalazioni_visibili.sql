-- Difetto introdotto apposta: le segnalazioni delle chat le legge chiunque. Deve far fallire W2.
drop policy if exists "segnalazioni chat: solo amministratori" on public.chat_reports;
create policy "segnalazioni chat: solo amministratori"
  on public.chat_reports for select to authenticated
  using (true);
select private.align_anon_with_authenticated();

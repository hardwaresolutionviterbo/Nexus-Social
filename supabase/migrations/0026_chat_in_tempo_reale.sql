-- Fase 4 · Blocco 9: chat e chiamate in tempo reale.
--
-- Quando c'è qualcosa di nuovo per una persona (messaggio, passaggio di una chiamata, spunte,
-- richiesta accettata) il database le manda un «tocco» sul suo canale privato di Supabase
-- Realtime, `u:<uid>`. Il tocco è vuoto: dice solo «controlla», mai chi scrive né cosa.
-- Il telefono allora si sincronizza subito invece di aspettare il controllo periodico.
-- Ognuno può ascoltare solo il proprio canale.

create or replace function private.realtime_poke(p_user text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform realtime.send('{}'::jsonb, 'nuovo', 'u:' || p_user, true);
exception when others then
  -- Senza tempo reale resta il controllo periodico.
  null;
end;
$$;

revoke all on function private.realtime_poke(text) from public, anon, authenticated;

create or replace function private.poke_on_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user text;
begin
  if new.recipient_id is not null then
    perform private.realtime_poke(new.recipient_id);
    return null;
  end if;
  for v_user in
    select m.user_id from public.chat_members m
    where m.conversation_id = new.conversation_id
      and (m.user_id <> new.sender_id or new.kind = 'event')
  loop
    perform private.realtime_poke(v_user);
  end loop;
  return null;
exception when others then
  return null;
end;
$$;

drop trigger if exists chat_messages_poke on public.chat_messages;
create trigger chat_messages_poke
after insert on public.chat_messages
for each row execute function private.poke_on_chat_message();

-- Spunte (consegnato, letto) e stato della chat (richiesta accettata, rifiutata, uscita).
create or replace function private.poke_on_chat_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user text;
begin
  if new.delivered_upto is not distinct from old.delivered_upto
     and new.read_upto is not distinct from old.read_upto
     and new.status is not distinct from old.status then
    return null;
  end if;
  for v_user in
    select m.user_id from public.chat_members m
    where m.conversation_id = new.conversation_id and m.user_id <> new.user_id
  loop
    perform private.realtime_poke(v_user);
  end loop;
  return null;
exception when others then
  return null;
end;
$$;

drop trigger if exists chat_members_poke on public.chat_members;
create trigger chat_members_poke
after update on public.chat_members
for each row execute function private.poke_on_chat_member();

revoke all on function private.poke_on_chat_message() from public, anon, authenticated;
revoke all on function private.poke_on_chat_member() from public, anon, authenticated;

-- Canale privato: lo ascolta solo il proprietario (token Firebase valido). Nessuno ci scrive
-- dall'app: i tocchi li manda solo il database. (La sicurezza a livello di riga su
-- realtime.messages è già attiva in Supabase.)

drop policy if exists "tocchi della chat: solo il proprio canale" on realtime.messages;
create policy "tocchi della chat: solo il proprio canale"
  on realtime.messages for select to anon, authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and public.current_uid_raw() is not null
    and (select realtime.topic()) = 'u:' || public.current_uid_raw()
  );

select private.align_anon_with_authenticated();

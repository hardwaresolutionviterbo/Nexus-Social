-- Fase 4 · Blocco 7: segnalazione di una chat.
--
-- Chi segnala sceglie quali messaggi allegare: sono messaggi che il suo telefono ha già decifrato
-- e che manda in chiaro di sua volontà. Solo quelli (e nient'altro della chat) arrivano agli
-- amministratori autorizzati (public.is_admin). Chi è segnalato non vede nulla.

create table public.chat_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id text not null,
  conversation_id uuid not null references public.chat_conversations (id) on delete cascade,
  reported_user_id text,
  is_group boolean not null default false,
  reason text not null check (reason in ('spam', 'truffa', 'molestie', 'contenuti', 'minore', 'altro')),
  details text check (details is null or char_length(details) <= 1000),
  messages jsonb not null default '[]'::jsonb check (jsonb_typeof(messages) = 'array'),
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now()
);

create index chat_reports_queue_idx on public.chat_reports (status, created_at);
create unique index chat_reports_one_open on public.chat_reports (reporter_id, conversation_id) where status = 'open';

alter table public.chat_reports enable row level security;
revoke all on public.chat_reports from public, anon, authenticated;
grant select on public.chat_reports to authenticated;

create policy "segnalazioni chat: solo amministratori"
  on public.chat_reports for select to authenticated
  using (public.is_admin());

-- Segnala la chat [p_conversation]. [p_messages]: elenco scelto da chi segnala, al massimo 50,
-- ognuno {"a": ora ISO, "da": "io" | id dell'autore, "t": testo ≤ 4000 caratteri}.
create or replace function public.chat_report(
  p_conversation uuid,
  p_reason text,
  p_details text,
  p_messages jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := public.current_uid();
  v_group boolean;
  v_other text;
  v_clean jsonb := '[]'::jsonb;
  v_item jsonb;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  select c.kind = 'group' into v_group
  from public.chat_conversations c
  join public.chat_members m on m.conversation_id = c.id and m.user_id = v_uid
  where c.id = p_conversation;
  if v_group is null then
    raise exception 'Chat non trovata' using errcode = '42501';
  end if;
  if p_reason is null or p_reason not in ('spam', 'truffa', 'molestie', 'contenuti', 'minore', 'altro') then
    raise exception 'Motivo non valido' using errcode = '22023';
  end if;
  if p_details is not null and char_length(p_details) > 1000 then
    raise exception 'Descrizione troppo lunga' using errcode = '22023';
  end if;
  if p_messages is null or jsonb_typeof(p_messages) <> 'array' or jsonb_array_length(p_messages) > 50 then
    raise exception 'Al massimo 50 messaggi' using errcode = '22023';
  end if;
  for v_item in select * from jsonb_array_elements(p_messages) loop
    if jsonb_typeof(v_item) <> 'object' or jsonb_typeof(v_item -> 't') <> 'string'
       or char_length(v_item ->> 't') > 4000 or jsonb_typeof(v_item -> 'da') <> 'string'
       or char_length(v_item ->> 'da') > 128 or (v_item ->> 'a') is null
       or char_length(v_item ->> 'a') > 40 then
      raise exception 'Messaggio allegato non valido' using errcode = '22023';
    end if;
    v_clean := v_clean || jsonb_build_array(jsonb_build_object(
      'a', v_item ->> 'a', 'da', v_item ->> 'da', 't', v_item ->> 't'));
  end loop;
  if (select count(*) from public.chat_reports where reporter_id = v_uid
      and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Troppe segnalazioni oggi: riprova domani' using errcode = '54000';
  end if;
  if not v_group then
    select m.user_id into v_other from public.chat_members m
    where m.conversation_id = p_conversation and m.user_id <> v_uid limit 1;
  end if;
  insert into public.chat_reports (reporter_id, conversation_id, reported_user_id, is_group, reason, details, messages)
  values (v_uid, p_conversation, v_other, v_group, p_reason, nullif(btrim(coalesce(p_details, '')), ''), v_clean)
  on conflict (reporter_id, conversation_id) where status = 'open' do update
    set reason = excluded.reason, details = excluded.details, messages = excluded.messages, created_at = now()
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.chat_report(uuid, text, text, jsonb) from public, anon;
grant execute on function public.chat_report(uuid, text, text, jsonb) to authenticated;

select private.align_anon_with_authenticated();

-- Difetto introdotto apposta: notifiche anche per i Mi piace. Deve far fallire U5.
create or replace function private.push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.push_enqueue(new.recipient_id, 'comment', null, 'n:' || new.id::text, 'Piazly',
                               'Qualcuno ha messo Mi piace');
  return null;
end;
$$;

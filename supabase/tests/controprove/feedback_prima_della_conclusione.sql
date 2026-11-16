-- Difetto introdotto apposta: il feedback si può lasciare prima della conclusione. Deve far fallire P2.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.leave_feedback(uuid, integer, text)'::regprocedure) into v_def;
  execute replace(v_def, 'if v_deal.completed_at is null then', 'if false then');
end;
$$;

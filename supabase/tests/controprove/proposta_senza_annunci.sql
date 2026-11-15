-- Difetto introdotto apposta: si può proporre uno scambio senza offrire annunci. Deve far fallire O2.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'private.check_swap_offer(public.listings, text, uuid[], bigint, text, text)'::regprocedure
  ) into v_def;
  execute replace(v_def, 'if v_n < 1 then', 'if false then');
end;
$$;

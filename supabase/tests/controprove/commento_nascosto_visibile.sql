-- Difetto introdotto apposta: il testo dei commenti nascosti arriva a tutti. Deve far fallire Q2.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.listing_comments_list(uuid)'::regprocedure) into v_def;
  execute replace(
    v_def,
    'case when c.hidden_at is null or c.author_id = v_uid or v_mod then c.body end',
    'c.body'
  );
end;
$$;

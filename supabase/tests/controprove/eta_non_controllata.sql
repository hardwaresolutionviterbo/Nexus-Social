-- Difetto introdotto apposta: il server non controlla più l'età minima.
-- Deve far fallire F1.
create or replace function public.age_years(p_birth date)
returns integer
language sql
stable
as $$
  select 99;
$$;

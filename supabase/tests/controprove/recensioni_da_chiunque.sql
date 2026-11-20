-- Difetto introdotto apposta: chiunque può recensire (non serve aver usato un coupon).
-- Deve far fallire RV1.
create or replace function private.verified_customer(p_business_id text, p_user text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select true;
$$;

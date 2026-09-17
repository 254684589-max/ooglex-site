-- Add Forbes/Billionaires as an Ooglex Pro product.
alter table public.plan_entitlements
  drop constraint if exists plan_entitlements_product_key_check;

alter table public.plan_entitlements
  add constraint plan_entitlements_product_key_check
  check (product_key in ('supply_chain','macro_risk','billionaires'));

insert into public.plan_entitlements(plan, product_key, access_level) values
  ('free','billionaires','preview'),
  ('pro','billionaires','full'),
  ('pro_plus','billionaires','full')
on conflict (plan, product_key) do update
set access_level = excluded.access_level, updated_at = now();

-- Add Finance Column as an Ooglex Pro product.
alter table public.plan_entitlements
  drop constraint if exists plan_entitlements_product_key_check;

alter table public.plan_entitlements
  add constraint plan_entitlements_product_key_check
  check (product_key in ('supply_chain','macro_risk','billionaires','finance_column'));

insert into public.plan_entitlements(plan, product_key, access_level) values
  ('free','finance_column','preview'),
  ('pro','finance_column','full'),
  ('pro_plus','finance_column','full')
on conflict (plan, product_key) do update
set access_level = excluded.access_level, updated_at = now();

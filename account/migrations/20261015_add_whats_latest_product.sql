-- Add What's Latest (最新消息) as an Ooglex Pro product.
-- OWNER accounts already get full access via my_product_access(); these rows
-- give PRO / PRO+ the full news set and keep FREE on the public 10% preview.
alter table public.plan_entitlements
  drop constraint if exists plan_entitlements_product_key_check;

alter table public.plan_entitlements
  add constraint plan_entitlements_product_key_check
  check (product_key in ('supply_chain','macro_risk','billionaires','finance_column','whats_latest'));

insert into public.plan_entitlements(plan, product_key, access_level) values
  ('free','whats_latest','preview'),
  ('pro','whats_latest','full'),
  ('pro_plus','whats_latest','full')
on conflict (plan, product_key) do update
set access_level = excluded.access_level, updated_at = now();

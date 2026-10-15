-- Add What's Latest (最新消息) as an Ooglex Pro product.
-- Any signed-in account gets the full news set. The PRO API Worker already
-- enforces this for whats_latest (signedInFull) without these rows; they keep
-- plan_entitlements consistent for any other consumer of my_product_access().
alter table public.plan_entitlements
  drop constraint if exists plan_entitlements_product_key_check;

alter table public.plan_entitlements
  add constraint plan_entitlements_product_key_check
  check (product_key in ('supply_chain','macro_risk','billionaires','finance_column','whats_latest'));

insert into public.plan_entitlements(plan, product_key, access_level) values
  ('free','whats_latest','full'),
  ('pro','whats_latest','full'),
  ('pro_plus','whats_latest','full')
on conflict (plan, product_key) do update
set access_level = excluded.access_level, updated_at = now();

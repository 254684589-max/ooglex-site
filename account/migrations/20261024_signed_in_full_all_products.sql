-- Site rule: visitors who are not signed in see a 10% preview; any signed-in
-- account sees 100%. The PRO API Worker enforces this for every product
-- (signedInFull) without these rows; they keep plan_entitlements consistent
-- with what the Worker actually serves. Applying it is optional.
update public.plan_entitlements
set access_level = 'full', updated_at = now()
where plan = 'free'
  and product_key in ('supply_chain','macro_risk','billionaires','finance_column');

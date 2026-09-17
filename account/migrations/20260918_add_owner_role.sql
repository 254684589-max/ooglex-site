-- Ooglex owner role
-- Keeps subscription tier (free/pro/pro_plus) separate from site ownership.

alter table public.profiles
  add column if not exists role text not null default 'user';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_role_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_role_check check (role in ('user','owner'));
  end if;
end $$;

comment on column public.profiles.role is
  'Server-managed site role. owner bypasses subscription tier for protected product access.';

create or replace function public.my_product_access(p_product_key text)
returns table(plan text, access_level text)
language sql
stable
security definer
set search_path = public
as $$
  select
    case when p.role = 'owner' then 'owner' else p.plan end as plan,
    case when p.role = 'owner' then 'full' else e.access_level end as access_level
  from public.profiles p
  left join public.plan_entitlements e
    on e.plan = p.plan and e.product_key = p_product_key
  where p.id = auth.uid()
    and p.status = 'active'
    and (p.role = 'owner' or e.product_key is not null)
  limit 1;
$$;

revoke all on function public.my_product_access(text) from public;
grant execute on function public.my_product_access(text) to authenticated;

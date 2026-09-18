create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  plan text not null default 'free' check (plan in ('free','pro','pro_plus')),
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
before update on public.profiles
for each row execute procedure public.set_updated_at();

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;

comment on column public.profiles.plan is 'Server-managed membership tier. Client users must not be able to modify this column.';
comment on column public.profiles.status is 'Server-managed account status. Client users cannot modify this column.';

-- Ooglex Pro V0.1 -----------------------------------------------------------
-- profiles.plan remains the effective access tier. The subscriptions table is
-- server-managed bookkeeping for future Paddle/Stripe webhooks.

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null default 'manual' check (provider in ('manual','paddle','stripe')),
  customer_id text,
  subscription_id text,
  plan text not null check (plan in ('pro','pro_plus')),
  status text not null default 'active' check (status in ('trialing','active','past_due','canceled','expired','paused','incomplete')),
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists subscriptions_provider_subscription_uidx
  on public.subscriptions(provider, subscription_id)
  where subscription_id is not null;
create index if not exists subscriptions_user_id_idx on public.subscriptions(user_id);
create index if not exists subscriptions_status_idx on public.subscriptions(status);

alter table public.subscriptions enable row level security;
drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own
on public.subscriptions
for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on table public.subscriptions from anon, authenticated;
grant select on table public.subscriptions to authenticated;

drop trigger if exists set_subscriptions_updated_at on public.subscriptions;
create trigger set_subscriptions_updated_at
before update on public.subscriptions
for each row execute procedure public.set_updated_at();

create table if not exists public.plan_entitlements (
  plan text not null check (plan in ('free','pro','pro_plus')),
  product_key text not null check (product_key in ('supply_chain','macro_risk','billionaires','finance_column')),
  access_level text not null check (access_level in ('preview','full')),
  updated_at timestamptz not null default now(),
  primary key (plan, product_key)
);

insert into public.plan_entitlements(plan, product_key, access_level) values
  ('free','supply_chain','preview'),
  ('pro','supply_chain','full'),
  ('pro_plus','supply_chain','full'),
  ('free','macro_risk','preview'),
  ('pro','macro_risk','full'),
  ('pro_plus','macro_risk','full'),
  ('free','billionaires','preview'),
  ('pro','billionaires','full'),
  ('pro_plus','billionaires','full'),
  ('free','finance_column','preview'),
  ('pro','finance_column','full'),
  ('pro_plus','finance_column','full')
on conflict (plan, product_key) do update
set access_level = excluded.access_level, updated_at = now();

alter table public.plan_entitlements enable row level security;
drop policy if exists plan_entitlements_read on public.plan_entitlements;
create policy plan_entitlements_read
on public.plan_entitlements
for select
to anon, authenticated
using (true);

grant select on table public.plan_entitlements to anon, authenticated;

create or replace function public.my_product_access(p_product_key text)
returns table(plan text, access_level text)
language sql
stable
security definer
set search_path = public
as $$
  select p.plan, e.access_level
  from public.profiles p
  join public.plan_entitlements e
    on e.plan = p.plan and e.product_key = p_product_key
  where p.id = auth.uid()
    and p.status = 'active'
  limit 1;
$$;

revoke all on function public.my_product_access(text) from public;
grant execute on function public.my_product_access(text) to authenticated;

-- Subscription rows are the future webhook input. This trigger is the only
-- automatic path that converts active/trialing subscription state into a
-- profile access tier; canceled/expired/paused subscriptions fall back to FREE.
create or replace function public.sync_profile_plan_from_subscriptions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user uuid;
  next_plan text;
begin
  target_user := coalesce(new.user_id, old.user_id);

  select s.plan
  into next_plan
  from public.subscriptions s
  where s.user_id = target_user
    and s.status in ('active','trialing')
    and (s.current_period_end is null or s.current_period_end > now())
  order by case s.plan when 'pro_plus' then 2 when 'pro' then 1 else 0 end desc,
           s.current_period_end desc nulls first,
           s.updated_at desc
  limit 1;

  update public.profiles
  set plan = coalesce(next_plan, 'free'), updated_at = now()
  where id = target_user;

  return coalesce(new, old);
end;
$$;

revoke all on function public.sync_profile_plan_from_subscriptions() from public, anon, authenticated;

drop trigger if exists sync_profile_plan_after_subscription on public.subscriptions;
create trigger sync_profile_plan_after_subscription
after insert or update or delete on public.subscriptions
for each row execute procedure public.sync_profile_plan_from_subscriptions();

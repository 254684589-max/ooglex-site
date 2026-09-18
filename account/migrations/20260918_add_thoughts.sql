-- Ooglex 想法流（public.thoughts）
-- 站内第一处用户生成内容（UGC）。口径：任何登录用户可发，发出即公开，未登录访客只读。
--
-- 这个文件的设计前提是「前端不可信」。浏览器里的 JS 随时可以被改，所以下面四件事
-- 一件都不放在前端：
--   1. 作者身份    —— author_id 由触发器写成 auth.uid()，客户端连这一列的 insert 权限都没有
--   2. 正文长度    —— check 约束，1..500 字
--   3. 发布频率    —— 触发器内计数限流，并挡住短时间内重复正文
--   4. 初始可见性  —— 触发器强制 'visible'，客户端不能自己塞一条 'hidden' 或 'removed'
--
-- 客户端只被授予 insert (body) 这一列。其余全部由服务端决定。

-- ---------------------------------------------------------------------------
-- owner 判定：策略里不能直接查 public.profiles
-- ---------------------------------------------------------------------------
-- public.profiles 自己开了 RLS，且只允许本人 select。如果在 thoughts 的策略里直接
-- 写 exists(select 1 from public.profiles ...)，owner 判定会被 profiles 自己的 RLS
-- 挡掉（owner 也只能看见自己那一行，判定恒假），所以这里用 security definer 函数
-- 绕过 RLS 只回一个布尔值，不暴露 profiles 的任何字段。
create or replace function public.is_site_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'owner'
      and p.status = 'active'
  );
$$;

revoke all on function public.is_site_owner() from public;
grant execute on function public.is_site_owner() to anon, authenticated;

comment on function public.is_site_owner() is
  'RLS 辅助函数。只回布尔值，不返回 profiles 字段；绕过 profiles 的 RLS 是为了让站主判定在策略里可用。';

-- ---------------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------------
create table if not exists public.thoughts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  -- 作者昵称在发布时落库（反范式）。原因：公开信息流要显示昵称，但 public.profiles
  -- 只允许本人读取，公开 join 不到。落库的代价是改昵称不会回溯旧帖 —— 这是刻意取舍，
  -- 换来的是公开读完全不碰 profiles 表，邮箱之类的字段没有任何泄露路径。
  author_name text not null default '',
  body text not null,
  status text not null default 'visible' check (status in ('visible', 'hidden', 'removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint thoughts_body_length check (char_length(btrim(body)) between 1 and 500)
);

comment on table public.thoughts is '站内公开想法流。任何登录用户可发，发出即公开。';
comment on column public.thoughts.author_name is '发布时落库的昵称快照；改昵称不回溯旧帖。';
comment on column public.thoughts.status is
  '服务端管理的可见性。visible 公开；hidden 被站主隐藏；removed 已撤下。客户端只能在 owner 身份下改这一列。';

-- 公开信息流只按 created_at 倒序翻页，部分索引把 hidden/removed 直接排除在索引之外
create index if not exists thoughts_public_feed_idx
  on public.thoughts (created_at desc)
  where status = 'visible';

create index if not exists thoughts_author_idx
  on public.thoughts (author_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 发帖流水：限流的唯一依据
-- ---------------------------------------------------------------------------
-- 为什么不直接数 public.thoughts：**作者可以删自己的帖**。如果从 thoughts 数，
-- 「发两条 → 删掉 → 再发两条」就能把每小时 20 条、每天 100 条的上限无限循环绕开，
-- 每次只留一两条可见，数据库照样被无限写。
--
-- 所以另立一张只增不删的流水表。它没有任何客户端角色的权限，只有 security definer
-- 的触发器能写；删帖不动它，限流因此拿不掉。
--
-- body_hash 只存 md5，不存正文，用于「删掉再发一模一样的」这种复读。
create table if not exists public.thought_post_log (
  id bigserial primary key,
  author_id uuid not null references auth.users(id) on delete cascade,
  body_hash text not null,
  created_at timestamptz not null default now()
);

comment on table public.thought_post_log is
  '只增不删的发帖流水，限流与复读检测的唯一依据。删帖不会删这里的记录，否则删帖即可重置限额。客户端无任何权限。';
comment on column public.thought_post_log.body_hash is '正文 md5，仅用于复读检测；不存正文本身。';

create index if not exists thought_post_log_author_idx
  on public.thought_post_log (author_id, created_at desc);

alter table public.thought_post_log enable row level security;
-- 不给 anon/authenticated 任何权限，也不建任何策略：RLS 开着 + 零授权 =
-- 客户端读不到、写不进；只有 security definer 触发器绕过 RLS 写入。
revoke all on table public.thought_post_log from anon, authenticated;
revoke all on sequence public.thought_post_log_id_seq from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 写入前：身份、可见性、限流
-- ---------------------------------------------------------------------------
-- 合成一个触发器而不是拆成两个：Postgres 同一时机的多个触发器按名字字母序执行，
-- 依赖这个顺序来保证「先填 author_id 再按 author_id 限流」太脆弱了。
create or replace function public.thoughts_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid;
  profile_name text;
  profile_status text;
  recent_minute int;
  recent_hour int;
  recent_day int;
  duplicate_count int;
begin
  uid := (select auth.uid());
  if uid is null then
    raise exception '请先登录再发布' using errcode = '42501';
  end if;

  select btrim(coalesce(p.display_name, '')), p.status
    into profile_name, profile_status
  from public.profiles p
  where p.id = uid;

  if profile_status is null then
    raise exception '未找到账户资料，无法发布' using errcode = '42501';
  end if;
  if profile_status <> 'active' then
    raise exception '账户已停用，无法发布' using errcode = '42501';
  end if;

  -- 限流一律数 thought_post_log，不数 thoughts —— 后者能被作者删掉，删完限额就重置了。
  -- 三个窗口都查一遍，因为单看一分钟挡不住「每分钟一条刷一整天」。
  select count(*) into recent_minute
  from public.thought_post_log l
  where l.author_id = uid and l.created_at > now() - interval '1 minute';
  if recent_minute >= 2 then
    raise exception '发得太快了，等一会儿再发' using errcode = '53400';
  end if;

  select count(*) into recent_hour
  from public.thought_post_log l
  where l.author_id = uid and l.created_at > now() - interval '1 hour';
  if recent_hour >= 20 then
    raise exception '一小时内最多发 20 条，已达上限' using errcode = '53400';
  end if;

  select count(*) into recent_day
  from public.thought_post_log l
  where l.author_id = uid and l.created_at > now() - interval '1 day';
  if recent_day >= 100 then
    raise exception '一天内最多发 100 条，已达上限' using errcode = '53400';
  end if;

  -- 复读同样数流水：否则「删掉再发一模一样的」也能绕过
  select count(*) into duplicate_count
  from public.thought_post_log l
  where l.author_id = uid
    and l.created_at > now() - interval '10 minutes'
    and l.body_hash = md5(btrim(new.body));
  if duplicate_count > 0 then
    raise exception '刚刚发过一模一样的内容' using errcode = '53400';
  end if;

  insert into public.thought_post_log (author_id, body_hash)
  values (uid, md5(btrim(new.body)));

  -- 以下几列一律由服务端决定，客户端送什么都不算
  new.author_id := uid;
  new.author_name := case when profile_name = '' then '匿名用户' else left(profile_name, 40) end;
  new.status := 'visible';
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.thoughts_before_insert() from public, anon, authenticated;

drop trigger if exists thoughts_before_insert on public.thoughts;
create trigger thoughts_before_insert
before insert on public.thoughts
for each row execute procedure public.thoughts_before_insert();

-- ---------------------------------------------------------------------------
-- 更新前：只允许改可见性
-- ---------------------------------------------------------------------------
-- 列级 grant 已经只给了 status，但 grant 是「能不能在 SET 子句里写这一列」，
-- 拦不住将来从后台或别的角色改正文。这里把「正文与作者一旦发布就不可变」钉死在表上。
create or replace function public.thoughts_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.body <> old.body
     or new.author_id <> old.author_id
     or new.author_name <> old.author_name
     or new.created_at <> old.created_at then
    raise exception '想法发布后只能改可见性，不能改正文、作者或时间' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.thoughts_before_update() from public, anon, authenticated;

drop trigger if exists thoughts_before_update on public.thoughts;
create trigger thoughts_before_update
before update on public.thoughts
for each row execute procedure public.thoughts_before_update();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.thoughts enable row level security;

-- 读：公开帖任何人可读；自己的帖无论什么状态自己都能看见（否则被隐藏后会以为凭空消失）；
-- 站主全部可见。
drop policy if exists thoughts_select_visible on public.thoughts;
create policy thoughts_select_visible
on public.thoughts
for select
to anon, authenticated
using (
  status = 'visible'
  or author_id = (select auth.uid())
  or public.is_site_owner()
);

-- 写：只能以自己的身份插入。
-- Postgres 的 with check 在 before insert 触发器改写完行之后才求值，所以这里
-- 比对的是触发器刚写进去的 author_id —— 客户端连这一列都没有 insert 权限，
-- 这条策略是第二道锁，不是唯一一道。
drop policy if exists thoughts_insert_own on public.thoughts;
create policy thoughts_insert_own
on public.thoughts
for insert
to authenticated
with check (author_id = (select auth.uid()));

-- 删：作者删自己的，站主删任何一条
drop policy if exists thoughts_delete_own_or_owner on public.thoughts;
create policy thoughts_delete_own_or_owner
on public.thoughts
for delete
to authenticated
using (author_id = (select auth.uid()) or public.is_site_owner());

-- 改：只有站主，且只用于改可见性（由 before update 触发器把范围锁死）
drop policy if exists thoughts_update_owner on public.thoughts;
create policy thoughts_update_owner
on public.thoughts
for update
to authenticated
using (public.is_site_owner())
with check (public.is_site_owner());

-- 列级权限。anon 拿不到 author_id：那是 auth.users 的主键，公开信息流不需要它。
revoke all on table public.thoughts from anon, authenticated;
grant select (id, author_name, body, created_at, status) on public.thoughts to anon;
grant select (id, author_id, author_name, body, created_at, status) on public.thoughts to authenticated;
grant insert (body) on public.thoughts to authenticated;
grant update (status) on public.thoughts to authenticated;
grant delete on public.thoughts to authenticated;

-- ---------------------------------------------------------------------------
-- 举报
-- ---------------------------------------------------------------------------
-- 公开可发即公开可见，就必须有一条给访客用的上报通道，否则站主只能靠自己刷。
create table if not exists public.thought_reports (
  id uuid primary key default gen_random_uuid(),
  thought_id uuid not null references public.thoughts(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null default '',
  created_at timestamptz not null default now(),
  constraint thought_reports_reason_length check (char_length(btrim(reason)) <= 200),
  constraint thought_reports_once unique (thought_id, reporter_id)
);

comment on table public.thought_reports is '想法举报。只有站主可读；同一人对同一条只能报一次。';

create index if not exists thought_reports_thought_idx
  on public.thought_reports (thought_id, created_at desc);

create or replace function public.thought_reports_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid;
  recent_hour int;
begin
  uid := (select auth.uid());
  if uid is null then
    raise exception '请先登录再举报' using errcode = '42501';
  end if;

  -- 举报本身也会被滥用，同样限流
  select count(*) into recent_hour
  from public.thought_reports r
  where r.reporter_id = uid and r.created_at > now() - interval '1 hour';
  if recent_hour >= 30 then
    raise exception '举报过于频繁，请稍后再试' using errcode = '53400';
  end if;

  new.reporter_id := uid;
  new.created_at := now();
  return new;
end;
$$;

revoke all on function public.thought_reports_before_insert() from public, anon, authenticated;

drop trigger if exists thought_reports_before_insert on public.thought_reports;
create trigger thought_reports_before_insert
before insert on public.thought_reports
for each row execute procedure public.thought_reports_before_insert();

alter table public.thought_reports enable row level security;

drop policy if exists thought_reports_insert_own on public.thought_reports;
create policy thought_reports_insert_own
on public.thought_reports
for insert
to authenticated
with check ((select auth.uid()) is not null);

-- 举报内容只给站主看。举报人自己也不回读，避免「谁报了谁」被推断出来。
drop policy if exists thought_reports_select_owner on public.thought_reports;
create policy thought_reports_select_owner
on public.thought_reports
for select
to authenticated
using (public.is_site_owner());

revoke all on table public.thought_reports from anon, authenticated;
grant select on table public.thought_reports to authenticated;
grant insert (thought_id, reason) on public.thought_reports to authenticated;

-- ---------------------------------------------------------------------------
-- 给站主用的待办视图：被举报过、且仍然公开的帖子
-- ---------------------------------------------------------------------------
create or replace function public.reported_thoughts()
returns table(
  id uuid,
  author_name text,
  body text,
  status text,
  created_at timestamptz,
  report_count bigint,
  last_reason text
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id,
         t.author_name,
         t.body,
         t.status,
         t.created_at,
         count(r.id) as report_count,
         (array_agg(r.reason order by r.created_at desc))[1] as last_reason
  from public.thoughts t
  join public.thought_reports r on r.thought_id = t.id
  where public.is_site_owner()
  group by t.id, t.author_name, t.body, t.status, t.created_at
  order by count(r.id) desc, max(r.created_at) desc
  limit 200;
$$;

revoke all on function public.reported_thoughts() from public, anon, authenticated;
grant execute on function public.reported_thoughts() to authenticated;

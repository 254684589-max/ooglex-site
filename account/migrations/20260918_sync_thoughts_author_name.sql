-- Ooglex 想法流：改昵称时同步已有帖子的作者名
--
-- 背景：public.thoughts.author_name 是发布时的昵称快照。之所以反范式，是因为
-- public.profiles 只允许本人读取，公开信息流 join 不到它 —— 换来的是公开读完全
-- 不碰 profiles，邮箱之类的字段没有任何泄露路径。这一点不改。
--
-- 但快照有个副作用：改了昵称，旧帖还挂着老名字。想法流的头像又是从 author_name
-- 推导出来的（首字母 + 按名字稳定取色，纯前端，不读数据库），所以名字不回溯的话
-- 头像也不回溯 —— 这个体验上不能接受。
--
-- 两种修法，这里选了后者：
--   ① 加一张公开可读的 profiles 投影表，信息流 join 它。
--      否决原因：join 需要给 anon 开 author_id 的读权限，白扩大暴露面；
--      改用视图则会在 Supabase Advisor 里留一条 security_definer_view 告警。
--   ② 改昵称时把该用户已有帖子的 author_name 一并改掉。
--      不加新表、不加新授权、不扩大任何隐私面，公开读依旧不碰 profiles。
--
-- 客户端拿不到这个能力：thoughts 的 author_name 列对 authenticated 没有 update
-- 授权（只有 status），所以只有下面这个 security definer 触发器能改它。

-- ---------------------------------------------------------------------------
-- 放开 author_name，正文/作者/时间照旧钉死
-- ---------------------------------------------------------------------------
-- 原守卫把 author_name 也列为不可变。那一条其实不是守卫的目的 —— 目的是
-- 「发布后正文与时间不可篡改」。author_name 的不可变性本来就由列级 grant 保证
-- （客户端根本没有这一列的 update 权限），所以放开它不丢任何防护。
create or replace function public.thoughts_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.body <> old.body
     or new.author_id <> old.author_id
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
-- 同步：profiles.display_name 改了，该用户的历史帖子跟着改
-- ---------------------------------------------------------------------------
create or replace function public.sync_thoughts_author_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_name text;
begin
  -- 与 thoughts_before_insert 里完全同一套归一化：去空白、空则「匿名用户」、截 40 字。
  -- 两处必须一致，否则改一次昵称就会让旧帖和新帖显示成两个不同的名字。
  next_name := btrim(coalesce(new.display_name, ''));
  if next_name = '' then
    next_name := '匿名用户';
  else
    next_name := left(next_name, 40);
  end if;

  update public.thoughts
  set author_name = next_name
  where author_id = new.id
    and author_name <> next_name;

  return new;
end;
$$;

revoke all on function public.sync_thoughts_author_name() from public, anon, authenticated;

comment on function public.sync_thoughts_author_name() is
  '改昵称时回填历史帖子的 author_name。归一化规则必须与 thoughts_before_insert 保持一致。';

-- 只在 display_name 真的变了的时候触发，避免每次 profiles 更新都扫一遍帖子
drop trigger if exists sync_thoughts_author_name on public.profiles;
create trigger sync_thoughts_author_name
after update of display_name on public.profiles
for each row
when (coalesce(old.display_name, '') is distinct from coalesce(new.display_name, ''))
execute procedure public.sync_thoughts_author_name();

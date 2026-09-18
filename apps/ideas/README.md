# 想法流（/apps/ideas/）

站内公开想法流，Ooglex 的第一处用户生成内容。

口径：**任何注册用户可发，发出即公开，未登录访客只读。**

## 上线前还差一步（必须由你操作）

代码已完整，但**数据表还没建**。这个会话没有、也不该有 Supabase 的写库凭据
（`service_role`、数据库密码都属于仓库规则 5/12 明令不得出现在这里的东西），
所以迁移只能由你在 Supabase 控制台跑一次：

1. 打开 Supabase → 项目 `nwthqkpkvbtilafqpjlf` → SQL Editor
2. 粘贴并执行 `account/migrations/20260918_add_thoughts.sql` 的全文
3. 刷新 `https://www.ooglex.com/apps/ideas/`

跑之前页面不会白屏也不会报一句看不懂的错，会明确显示
**「想法流的数据表还没建好，功能尚未启用。」** —— 这是刻意做的状态，
免得你以为是网络问题。

顺带确认一下自己的站主身份（隐藏违规内容要用）：

```sql
select id, email, role from public.profiles where email = '你的邮箱';
-- 如果 role 不是 owner：
update public.profiles set role = 'owner' where email = '你的邮箱';
```

## 权限模型：前端一行都不算

浏览器里的 `app.js` 只负责显示和少一次往返的提示。任何校验都可以被绕过——
用户按 F12 就能改。所以下面每一条都由数据库保证：

| 规则 | 落在哪里 |
|---|---|
| 作者身份不可伪造 | `thoughts_before_insert` 触发器把 `author_id` 写成 `auth.uid()`；客户端连这一列的 insert 权限都没有 |
| 正文 1–500 字 | `thoughts_body_length` check 约束 |
| 每分钟 2 条 / 每小时 20 条 / 每天 100 条 | `thoughts_before_insert` 触发器数 `thought_post_log`（只增不删）|
| 十分钟内不能复读同一正文 | 同上，按正文 md5 比对 |
| 删帖不能重置限额 | 流水表独立于 `thoughts`，删帖不动它；客户端对它零权限 |
| 新帖必定是 `visible` | 触发器强制，客户端无 `status` 的 insert 权限 |
| 停用账户不能发 | 触发器读 `profiles.status` |
| 未登录不能写 | 列级 grant 只给 `authenticated` |
| 未登录读不到 `author_id` | 列级 grant：`anon` 只有 `id, author_name, body, created_at, status` |
| 未登录读不到 `profiles` | 沿用 `profiles` 原有 RLS，公开信息流完全不 join 这张表 |
| 只有站主能隐藏 | `thoughts_update_owner` 策略 + `is_site_owner()` |
| 发布后正文与时间不可改 | `thoughts_before_update` 触发器（连表属主改都拦） |
| 作者可删自己的，站主可删任何人的 | `thoughts_delete_own_or_owner` 策略 |
| 同一人对同一条只能举报一次 | `thought_reports_once` 唯一约束 |
| 举报内容只有站主可读 | `thought_reports_select_owner` 策略 |

这些行为有可重跑的闸门：

```bash
python3 scripts/validate_thoughts_rls.py
```

它自己起一个临时 PostgreSQL、打桩 `auth` schema、按顺序应用 `account/schema.sql`
与 `account/migrations/*.sql`，跑 45 个用例后销毁实例。纯离线，不碰线上库。
找不到 PostgreSQL 服务端时退出码 2（跳过，不算失败）。

## XSS

用户正文和昵称一律走 `textContent`，**永不进 `innerHTML`**（仓库规则）。
页面测试里直接喂了 `<img src=x onerror=…>` 和 `<script>…</script>` 两种载荷，
确认都没有执行、都作为字面文本显示。改这个文件时别把 `textContent` 换成 `innerHTML`。

## 三个已知取舍

1. **改昵称不回溯旧帖。** `author_name` 是发布时的快照。原因是 `public.profiles`
   只允许本人读取，公开信息流 join 不到它；反范式换来的是公开读完全不碰
   `profiles`，邮箱之类的字段没有任何泄露路径。
2. **发布后不能编辑，只能删。** 少一套编辑历史，也少一类「改完再骗人」的问题。
3. **删帖不会删掉发帖流水。** `thought_post_log` 只留 `author_id`、正文 md5 和时间，不留正文。这是限流的唯一依据——如果删帖能清掉它，删帖就等于重置限额。

## 还没做的事

- **没有自动内容审核。** 违规内容靠访客举报 + 你手动隐藏。公开 UGC 在中文站点
  有实际的内容合规责任，量大起来之后建议再评估关键词过滤或先审后发
  （数据库已经预留 `status`，改成先审后发只需改策略，不用动表结构）。
- **没有图片、没有回复、没有点赞。** 只有纯文本时间线。
- **没有接入邮件通知。**

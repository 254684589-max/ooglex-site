# Ooglex Account MVP

状态：开发分支 `feature/auth-mvp`，未部署生产环境。

## 已接入

- Supabase Auth：邮箱 + 密码注册、登录、退出、找回密码、重设密码
- Supabase Database：`public.profiles`
- 会员字段：`free` / `pro` / `pro_plus`
- 账户状态：`active` / `suspended`
- RLS：登录用户只能读取自己的资料
- 列权限：前端用户只能修改 `display_name`，不能修改 `plan`、`status`、邮箱和系统时间字段
- 新用户触发器：Auth 创建用户后自动创建 `profiles` 记录

## 生产上线前必须完成

Supabase Dashboard → Authentication → URL Configuration：

1. Site URL 设置为 `https://www.ooglex.com`
2. Redirect URLs 增加 `https://www.ooglex.com/account/`

这是邮箱确认和密码重置正确返回 Ooglex 的必要配置。

## 邮件

当前先使用 Supabase 默认邮件能力进行开发验证。正式开放注册前再接 Resend SMTP，并完成发信域名验证、SPF/DKIM 等配置。

## 安全

- `account/config.js` 只包含 Supabase Project URL 和 Publishable Key；Publishable Key 是给浏览器客户端使用的公开标识。
- 禁止把 `service_role`、数据库密码、SMTP 密钥或其他私密凭据提交到 GitHub。
- `plan` 与 `status` 必须由服务端/后台管理，不允许浏览器用户自行升级会员或解除停用。

## 数据库

可复现的数据库定义保存在 `account/schema.sql`。实际 Supabase 项目已通过迁移创建并启用 RLS。

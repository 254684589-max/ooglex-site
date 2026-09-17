# Ooglex Pro V0.1

首批仅覆盖两个产品：

- `supply_chain`：全球产业链
- `macro_risk`：宏观风险监测

## 目标

先打通 FREE → 登录 → PRO 权限 → 私有数据 → 订阅状态整条链，再接真实支付。V0.1 不开启真实扣款。

## 权限模型

Supabase 是身份与会员状态唯一事实来源：

- `profiles.plan`: `free | pro | pro+`
- `profiles.status`: 只有 `active` 才能获得有效权限
- `plan_entitlements`: 决定每个套餐对产品是 `preview` 还是 `full`
- `subscriptions`: 为未来 Paddle / Stripe webhook 保存订阅状态；浏览器无写权限

浏览器不得通过隐藏 DOM、CSS 或截断数组来实现付费墙。

## 服务端链路

```text
Browser
  -> Supabase Auth JWT
  -> Cloudflare Worker (pro-api.ooglex.com)
  -> Supabase my_product_access(product)
  -> Worker checks preview/full
  -> private R2 bucket
  -> response
```

Worker 不使用 `service_role`。它用用户自己的 JWT 调用 Supabase Auth 与 `my_product_access` RPC；RLS 与数据库函数共同决定访问级别。

## 私有数据

R2 bucket binding: `PRO_DATA`

```text
supply-chain/preview.json
supply-chain/full.json
macro-risk/preview.json
macro-risk/full.json
```

`full.json` 不得进入：

- GitHub 公共仓库
- Cloudflare Pages 静态目录
- 浏览器 bundle
- public URL

当前仓库里的完整公开 JSON 是迁移前遗留数据。**在 R2 + Worker 上线并验证前不删除，避免生产站中断；但正式收费前必须完成迁移和删除公开全量副本。**

## API

- `GET /health`
- `GET /v1/access?product=supply_chain|macro_risk`
- `GET /v1/data/:product?mode=preview|full`

`full` 请求规则：

- 未登录：401 `sign_in_required`
- 已登录但 FREE：403 `pro_required`
- PRO / PRO+ 且 ACTIVE：返回 R2 私有对象

## 部署顺序

1. Supabase entitlement schema
2. Cloudflare Worker + private R2 bucket
3. 生成 preview/full 两套数据
4. 上传私有数据到 R2
5. 前端改为 Worker API
6. 验证 FREE 无法拿到 full
7. 验证 PRO 可以拿到 full
8. 将 `ooglex.com` 从 GitHub Pages 切到 Cloudflare Pages
9. 删除 GitHub / Pages 中公开的完整 PRO 数据副本
10. 完成条款、隐私、退款、数据来源说明
11. 接 Paddle/Stripe Sandbox
12. 最后才开启真实收费

## 安全验收

正式收费前必须全部通过：

- FREE 用户直接访问 API full 返回 403
- 未登录访问 full 返回 401
- 修改前端 JS / localStorage 不能获得 full
- GitHub 搜索不到完整 PRO 数据文件
- Cloudflare Pages 静态 URL 不存在完整 PRO 数据
- Worker 不包含 `service_role` 或支付 secret
- subscription 写入仅允许 service role / webhook 服务端
- 取消、到期、退款后权限会按状态回落

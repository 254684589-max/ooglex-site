# Ooglex Global Cams API

为 `/apps/global-cams/` 提供服务端摄像头查询。用途只有两个：

1. 隐藏 Windy Webcams API Key；
2. 把 Windy V3 返回结构归一化为 Ooglex 前端需要的最小字段。

## 数据与许可

- 上游：Windy Webcams API V3。
- 免费版允许在用户应用中使用，但必须遵守 Windy 的 Webcams API Terms。
- 前端必须显示 Windy attribution，并把图片链接回相应的 Windy webcam detail。
- 不把 Windy API 批量导出、复制或重新分发成 Ooglex 自有公开数据库。
- 本 Worker 只按用户当前视角查询最多 50 个摄像头，半径最多 250 km。
- 返回的图片 URL 有短期 token；Worker 只做 120 秒边缘缓存，不持久化。

## 密钥

密钥名称：

```
WINDY_WEBCAMS_API_KEY
```

只能用 Cloudflare Secret 设置，绝不能写入 GitHub：

```bash
cd workers/global-cams-api
npx wrangler secret put WINDY_WEBCAMS_API_KEY
```

## 部署

先在非生产环境验证：

```bash
cd workers/global-cams-api
npx wrangler deploy
```

建议生产自有域名：`https://cams-api.ooglex.com`。

部署并绑定域名后，再把 `apps/global-cams/config.js` 的 `apiBase` 改为该域名。

## 接口

`GET /health`

`GET /v1/webcams?lat=35.68&lng=139.76&radius=250&limit=50&lang=zh`

只允许 `https://www.ooglex.com` 与 `https://ooglex.com` 的浏览器 Origin。

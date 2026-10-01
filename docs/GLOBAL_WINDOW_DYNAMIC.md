# 环球实景 WINDOW V0.9 动态目录

## 目标

把 WINDOW 从“固定 100 条精选视频”升级为可持续更新的动态目录，同时保持以下原则：

- 质量优先，不为凑数量降低现有景观筛选标准。
- R2 只长期保存当前目录正在使用的视频，避免轮换后对象无限增长。
- 页面提供“精选 / 最新 / 热门”三种排序，并继续保留随机窗口。
- 热门只统计 Ooglex 内实际播放，不引入用户账号，不把 IP、邮箱或设备标识写入持久化存储。
- Cloudflare 统计不可用时，WINDOW 视频本身仍可正常播放。

## 目录策略

生产目标为 150 条，安全底线仍为 100 条。

每次自动刷新：

1. 读取当前生产 manifest。
2. 读取近 30 天播放统计。
3. 从现有目录中最多保留 140 条，排序优先考虑近 30 天播放、累计播放、质量分。
4. 剩余名额从 Wikimedia Commons 重新发现并经过既有版权、场景、地理、重复、大小和质量过滤。
5. 新清单必须先完成 100+ 条、质量分、来源、许可、地理分布和 Range 播放验证。
6. 只有新清单验证成功后，才删除上一版 manifest 中已经退出目录的 R2 视频。
7. 单次清理硬限制为最多 20 个旧对象；超过限制直接失败，不执行批量删除。

这样在达到 150 条后，正常情况下每天最多给约 10 条新素材留出轮换空间，而不是每天重新下载 150 条。

## “最新”口径

新入选视频写入：

- `catalog_added_at`：首次进入本轮 Ooglex 目录的 UTC 时间。
- `source_updated_at`：Wikimedia 文件修订时间（能获取时）。
- `source_published_at`：Wikimedia 元数据中的原始拍摄/发布时间（能可靠解析时）。

前端“最新”优先按 `catalog_added_at` 排序，再使用来源时间作为回退。旧目录中没有这些字段的素材显示为“较早收录”，不会伪造发布日期。

## “热门”口径

热门统计由 `ooglex-global-windows-cdn` Worker 的 SQLite-backed Durable Object 保存。

浏览器只有在一个视频实际播放约 8 秒后才尝试上报一次；同一浏览器同一视频同一天只上报一次。服务端还对同一临时客户端与同一视频做 5 分钟短时限流。

持久化内容仅包括：

- WINDOW `id`
- 每日播放计数
- 累计播放计数
- 最近一次播放时间

不会持久化 IP、User-Agent、邮箱、账号或设备 ID。Worker 只用 Cloudflare 提供的 IP 与 User-Agent 生成当天的临时哈希做内存限流，该值不写入 Durable Object 存储。

热门接口：

- `GET /stats/popular?days=7&limit=500`
- `POST /stats/play`
- `GET /stats/health`

写入端点只接受 Ooglex 允许来源的浏览器请求，限制 JSON 体积并校验 WINDOW ID。

## 自动更新

`.github/workflows/deploy-global-windows-cdn.yml` 在生产合并后按 UTC 19:25 每天执行一次（台湾/中国标准时间次日 03:25）。

手动 `workflow_dispatch` 仍可使用，默认目标为 150 条。

自动刷新失败时：

- 不覆盖当前有效 manifest；
- 不删除当前正在使用的视频；
- 前端继续读取上一份有效目录。

## Cloudflare 服务与成本风险

V0.9 新增一个 SQLite-backed Durable Object 类 `WindowStats`，用于少量聚合播放计数。R2 继续负责视频文件。

该服务会产生 Workers / Durable Objects 请求与存储用量。部署前应在 Cloudflare 账户中确认当前计划和免费额度；如果达到免费计划限制，请求可能失败，但页面会退回“精选”排序，视频播放不依赖热门统计。

## 回退与删除方法

如果要撤销热门功能：

1. 前端移除 `/stats/*` 调用和“热门”排序；
2. Worker 移除 `WINDOW_STATS` 绑定及 `WindowStats` 路由；
3. 按 Cloudflare Durable Objects 的迁移规则删除对应类/命名空间；
4. R2 manifest 与视频文件无需改动，WINDOW 可继续按精选/最新播放。

如果自动轮换本身出现问题，可移除 workflow 的 `schedule`，恢复仅手动发布；当前有效 R2 manifest 不受影响。

## 当前状态

V0.9 仅在功能分支 `window-v0.9-dynamic-catalog` 开发。未经所有者明确批准，不合并 `main`，不部署 Worker，不修改生产 R2/Durable Object。

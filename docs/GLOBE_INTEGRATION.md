# 全球态势地球（apps/globe）集成说明

> 站内入口：`/apps/globe/`（首页第 21 条）
> 上游项目：[bilawalsidhu/gods-eye-view](https://github.com/bilawalsidhu/gods-eye-view)
> 固定版本：`844c25212c06cfa26ff6c0f3cb82bc9c325f4a85`（2026-09-13）
> 部署形态：纯静态，无服务端，无密钥
> 用途定性：**个人学习，非商业使用**

## 1. 结构

```
apps/globe/index.html          中文包装页（原创）——顶栏、进入卡、数据来源面板
apps/globe/app/                上游构建产物（28MB / 417 文件），由脚本生成，勿手改
apps/globe/app/BUILD_INFO.json 本次构建的上游版本、基址、模式、时间
scripts/globe/build.sh         构建编排：拉取 → 许可裁剪 → 补丁 → 构建 → 自检 → 输出
scripts/globe/patch-base.mjs   子路径补丁：把写死的根路径改写为部署基址
```

包装页用同源 iframe 承载应用。这样做的原因：

- 应用的界面骨架由上游 `build/application-html.js` 生成，无法在不分叉的前提下注入中文外壳；
- iframe 隔离了应用自带的 CSS/JS，不影响站内其他页面；
- 包装页承载中文说明、数据来源与许可、移动端体积提示，满足仓库规则第 2、3、6 条；
- 包装页**不加载广告脚本**，与「非商业使用」的定性一致。

## 2. 重新构建

```sh
bash scripts/globe/build.sh                          # 非商业模式（默认）
GLOBE_UPSTREAM_REF=<sha> bash scripts/globe/build.sh # 升级上游版本
GLOBE_COMMERCIAL=1 bash scripts/globe/build.sh       # 商业模式：删除非商业数据集
GLOBE_BASE=/ bash scripts/globe/build.sh             # 改挂独立域名根目录
```

脚本不改动上游仓库，补丁只作用于 `$TMPDIR/ooglex-globe-build/`，且是幂等的
（复用检出时先 `git checkout -- .` 丢弃上一轮补丁）。

**升级上游后必须重跑第 5 节的四项验证，并在本文件记录版本与结果。**

### 为什么需要打补丁

上游假定应用位于站点根目录，源码里有三类写死 `/` 开头的路径：

| 类别 | 例子 | 不打补丁的后果 |
|---|---|---|
| `public/` 根级文件 | `/logo.svg`、`/pin.svg` | 图标 404（JS 与 HTML 模板都有引用） |
| 飞机 3D 模型 | `/models/airplane.glb` | 模型 404；这些字符串同时用作查表键（`src/data/modelVisualAnchor.js`），必须全局一致替换 |
| 接口前缀 | `/api/opensky` | 请求打到站点根 `www.ooglex.com/api/*`，污染主站 |

补丁**刻意不改上游入口 `index.html`**：其中的 `/src/main.js` 与 `/style.css` 由 Vite
按 `base` 自行重写，手工替换会破坏构建。

另有一个 `vite-plugin-cesium` 的行为需要修正：它把 Cesium 静态资源拷到
`<outDir>/<base>/cesium`，而 `index.html` 引用的是 `<base>cesium/`，
所以构建后要把该目录上移到产物根。脚本已处理并有断言。

## 3. 数据来源与许可

代码是 MIT，**但 MIT 不覆盖数据**。每个数据源各自独立授权。

### 本站启用（静态可用）

| 数据 | 许可 | 署名要求 |
|---|---|---|
| Esri World Imagery（默认卫星底图） | Esri 主协议下的公开 World Imagery 服务 | Powered by Esri — Source: Esri, Maxar, Earthstar Geographics 及 GIS 用户社区 |
| OpenStreetMap 底图（降级备选） | ODbL 1.0 | © OpenStreetMap contributors |
| USGS 全球地震目录 | 公有领域（美国地质调查局） | 建议署名 |
| 数据中心约 4300 处 · 大坝 704 座 | **ODbL 1.0** | © OpenStreetMap contributors；大坝另据 Open Infrastructure Map。**署名 + 相同方式共享** |
| Natural Earth 命名地理区域 | 公有领域 | Made with Natural Earth（礼节性） |
| TeleGeography 海底电缆 712 条 + 登陆点 1917 个 | **CC BY-NC-SA 3.0** | © TeleGeography — submarinecablemap.com |

以上署名全部呈现在包装页的「数据来源」面板中，且应用自身在地球左下角保留
Cesium/数据署名行。**不要移除任何一处。**

### ⚠️ 商业化红线

本站按**个人学习、非商业**用途部署。若将来转作商业用途（含在本页投放广告），
以下各条必须先处理：

1. **TeleGeography 海底电缆（CC BY-NC-SA 3.0）—— 必须删除。**
   执行 `GLOBE_COMMERCIAL=1 bash scripts/globe/build.sh` 即可；
   依据为上游 `DATA_SOURCES.md` 的「TeleGeography is bundled but NonCommercial」一节。
2. **OpenSky 航班** —— 非商业授权，且上游注明在 live product 中调用其 REST API
   可能需要事先书面协议（即使非营利）。第二阶段若接入航班，**用 adsb.lol（ODbL）
   而非 OpenSky**。
3. **Google News RSS（区域新闻）** —— 仅限个人非商业，商用须关闭或改用 GDELT。
4. **Cesium ion Community 免费版** —— 仅限符合条件的个人/非商业用途。
5. **ODbL 的相同方式共享义务** 对数据中心与大坝数据始终有效，与商业性无关。

注意：本仓库根目录的 `ads.txt` 与首页含 AdSense。**包装页与应用子树都不加载广告
脚本**，这是维持非商业定性的前提之一；`robots.txt` 另已 `Disallow: /apps/globe/app/`
（28MB 引擎产物无检索价值，也避免浪费抓取预算）。

## 4. 图层可用性（为什么不是全功能）

上游有约 20 个服务端代理（`server/providers/local.js`），以 Vite 中间件形式运行；
客户端写死同源 `/api/*` 调用共 84 处、跨 31 个文件。本站是纯静态托管，没有服务端，
因此这些图层不可用：

- 航班、船舶（AIS）、卫星、火箭发射、活跃火点（FIRMS）
- 交通流（TomTom）、公共自行车（GBFS）、交通摄像头（CCTV）、网络电台、区域新闻
- Google 真实感三维瓦片、地点搜索、语音控制（均需按量计费密钥）

**这些 404 是上游设计的生产路径，不是故障。** 上游 `src/keySetup.js` 的注释写明：
密钥设置入口在取不到 `/api/setup/status` 时会自我移除
（"a prod build (no endpoint) ... both the chip and the dialog are removed outright"）。
因此**不要**为这些接口加静态 JSON 桩——那会把一个写不了任何东西的设置面板复活。

包装页的「数据来源」面板把可用与不可用图层分两栏明确列出，并说明原因。

### 第二阶段（如需活数据）

需要一个与应用**同源**的后端。可行路径：把应用改挂 `globe.ooglex.com`
（Cloudflare Pages），用 Pages Functions 承接 `functions/api/[[path]].js` ——
同源，无需改动客户端那 84 处调用，密钥留在服务端环境变量里（比上游把
`GOOGLE_MAPS_API_KEY` / `CESIUM_ION_TOKEN` 打进浏览器包更符合本仓库规则第 5 条）。

注意：主站 `www.ooglex.com` 与 apex 当前都是 Cloudflare **灰云（仅 DNS）**，
解析到 GitHub Pages 的 `185.199.108-111.153`，流量不经过 Cloudflare。
所以**不能**用 Worker Routes 在 `www.ooglex.com/api/*` 上挂代理——路由不会触发。

移植成本最低且许可干净的五个（合计约 920 行上游参考代码，`node:fs`/`node:path`
仅用于磁盘缓存，换成 Cache API 即可）：

| 图层 | 数据源 | 上游参考 | 备注 |
|---|---|---|---|
| 航班（含军机、轨迹） | adsb.lol（ODbL） | 158 行 | 零 node 依赖 |
| 军事设施 | Overpass / OSM（ODbL） | 219 行 | 零 node 依赖 |
| 卫星 | CelesTrak TLE + 前端 satellite.js | 139 行 | 无密钥 |
| 火箭发射 | Launch Library 2 | 144 行 | 无密钥，15 次/小时，须加缓存 |
| 活跃火点 | NASA FIRMS | 261 行 | 需免费密钥，放服务端环境变量 |

不建议移植：AIS 船舶（常驻 WebSocket，需 Durable Objects）、CCTV（数十个源包 +
图片代理 + base64 解码）、语音 AI（按分钟计费）。

## 5. 验证口径

改动包装页或升级上游后，四项都要跑：

1. **构建自检** —— `bash scripts/globe/build.sh` 自带：补丁覆盖率、Cesium 目录、
   产物内无残留根路径、被引用资源真实存在、产物内无疑似密钥。任一失败即中止。
2. **本地起服务** —— `npx http-server -p 8899 .`，确认
   `/apps/globe/`、`/apps/globe/app/`、`.../cesium/Cesium.js`、`.../logo.svg`、
   `.../pin.svg`、`.../models/airplane.glb` 全部 200。
3. **三视口浏览器实测** —— 360 / 768 / 1280 宽下：iframe 内 Cesium 初始化成功、
   进入卡加载后**计算样式为 `display:none`**（只查 `hidden` 属性会漏——
   `.gate` 自带 `display:flex` 会覆盖 UA 样式表的 `[hidden]`，此坑已踩过）、
   无横向溢出、无 JS 异常、站内无非 `/api/` 的 404。
4. **交互可达性** —— 键盘可达且有可见焦点环、Esc 关闭数据来源面板、
   `prefers-reduced-motion` 下面板不做过渡动画。

### 已知的环境限制

本仓库的开发容器出网策略禁止访问 `api.adsb.lol`、`celestrak.org`、
`overpass-api.de`、`earthquake.usgs.gov`、`services.arcgisonline.com` 等数据源域名
（代理返回 `connect_rejected`）。因此**底图瓦片与地震数据无法在容器内实测**，
只能验证到「应用正常启动、图层按失败路径优雅降级」。这几项需要在真实浏览器里
打开线上页面确认。

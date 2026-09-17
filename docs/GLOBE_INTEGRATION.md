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
scripts/globe/build.sh         构建编排：拉取 → 许可裁剪 → 补丁 → 中文化 → 构建 → 自检 → 输出
scripts/globe/patch-base.mjs   子路径补丁：把写死的根路径改写为部署基址
scripts/globe/i18n-zh.js       界面中文化层（运行时 DOM 文案映射，构建时注入）
scripts/globe/fetch_space_data.py       生成卫星 TLE 与航天任务的静态快照
scripts/globe/test_fetch_space_data.py  上述脚本的校验逻辑自测（无网络依赖）
scripts/globe/verify.mjs       浏览器实测：中文化、署名、图标、响应式、无异常
apps/globe/status.json         静态快照的来源与更新时间台账（包装页读取显示）
apps/globe/app/api/            静态数据快照，由定时工作流生成（不属于构建产物）
scripts/globe/network-policy.js 同源启动策略与相机守卫（源；由 patch-network.mjs 复制进产物）
.github/workflows/globe_space_data.yml  每日刷新卫星与航天任务数据
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

## 3. 界面中文化

上游没有国际化层，文案散落在 `src/ui/templates/*.html` 与 JS 里。分叉源码逐处替换
会让每次同步上游都要重做，所以改为**运行时 DOM 文案映射**
（`scripts/globe/i18n-zh.js`，构建时注入产物的 `index.html`）。

三条安全约束，改动时不要破坏：

1. **白名单，绝不做自由子串替换。** 界面用 Material Icons 的**连字名**当图标内容
   （`arrow_forward`、`chevron_left`、`public`、`radar` 等），一旦被翻译图标会变成
   乱码文字；MGRS、经纬度、时刻、呼号、机型等读数同样不能动。只替换字典里逐条
   列出的完整文案。
2. **跳过署名子树。** `#cesium-credits`、`.cesium-credit-lightbox` 等内部的英文是
   许可要求的署名（Esri / Google / OSM / TeleGeography / NASA / OpenSky…），
   **翻译即违反许可**。见 `SKIP_SELECTORS`。
3. **保留数据源专名。** OpenSky、adsb.lol、AISStream、OpenStreetMap、CelesTrak、
   USGS、Launch Library 2 作为出处标识不翻译。

图层面板的副标题是 `${来源} · ${详情}` 拼出来的（上游 `src/ui/layerPanel.js` 的
`_statusLine`/`_timeAgo`），整串不可能进字典，因此另有一组**两端锚定**的正则
（`PATTERNS`）只翻译尾部时间/状态词，捕获组原样保留来源名。

无障碍标签（`aria-label`、`title`、`placeholder`、`alt`）同样覆盖。其中图层开关的
标签是 JS 动态拼的 `${图层名}: ON|OFF`，另有 `Collapse/Expand … panel`、`Close/Open …`
几类，都由函数型正则规则处理（查字典翻译嵌在里面的图层名/面板名）。

> **踩过的坑**：文本节点与属性必须走**同一条**查找路径（`translate()`）。第一版把
> 正则规则只接进了文本节点，属性仍留英文，实测才发现 —— 界面看着全中文，但屏幕
> 阅读器读到的还是 `Satellites: ON`。

aria-label 覆盖的是主要交互控件与常用独立标签，**不是全量**；上游 aria-label 有
几十条长尾。可见界面已全中文，键盘可达性与焦点环不受语言影响，所以按这个优先级
处理。补充时往 `DICT` 里加条目即可。

切回英文原版：包装页顶栏的「中 / EN」按钮，实现是给 iframe 带上 `?lang=en`
重载，中文化层自行短路。**刻意不做「撤销翻译」的簿记** —— 重载可靠得多。

## 3.2 页面结构：单栏 + 单层 iframe（刻意如此）

`apps/globe/index.html`（中文包装页，一条 44px 顶栏：返回 / 标题 / 中 EN / 数据来源）
→ 单个同源 iframe → `apps/globe/app/`。**不要再加第二条工具栏，也不要再套一层
iframe。**

曾经有过一版：包装页 → `apps/globe/lite/`（轻量地球，即时首屏）→ 内层 iframe
才是完整应用，顶栏下面还多一条「全球视角 / 返回基础地球 / 切换高清影像」的状态栏。
它换来首屏从约 1.6 秒提前到约 60 毫秒，但代价是：

- 用户明确不要那条多出来的工具栏；
- 两层 iframe 让所有验证脚本的「就绪判断」失效过两次（见下一节）；
- 包装页与 lite 页之间的 `ooglex:set-map` 转发出过一个「应用已就绪后消息永不转发」
  的死锁，表现为点切换高清影像永远停在「正在连接」。

现在回到单层：首屏约 1.6 秒（应用完全可用约 2 秒），底图默认是随 Cesium 自带的
Natural Earth 本地瓦片，所以不开 VPN 也能直接显示。切换高清影像走应用**自身**的
底图菜单，不再由包装页代理。

## 3.3 三条容易再犯的坑

### 缩放下限必须**跟着底图走**，不能全局硬夹

本地基础底图是 Cesium 自带的 NaturalEarthII，`maximumLevel` 只有 **2**，低空彻底
失去细节。实测（旧金山上方，画面中心 200×200 的唯一颜色数）：

| 高度 | 唯一颜色数 | 观感 |
|---|---|---|
| 1344 km | 180 | 有细节 |
| 668 km | 80 | 有细节（临界）|
| 263 km | 20 | 开始糊 |
| 32 km | 2 | 纯色 |
| **468 m** | **1** | **整屏一片纯绿** ← 用户报的就是这个 |

所以下限取 **500 公里**，并且**只在本地底图生效**；换上真实影像立刻放开，街景、
驾驶舱、CCTV 地面投影照旧。

两个必须同时处理的入口：

1. **用户输入** —— `screenSpaceCameraController.minimumZoomDistance`。
2. **程序化飞行** —— `minimumZoomDistance` 在 Cesium 里**不约束** `flyTo` / `setView`。
   应用自带的场景（例如「旧金山金门大桥」街景）会直接把相机飞到几百米高，
   这正是用户看到纯色球的由来。所以相机守卫里补了一道：本地底图下若相机落到
   下限以下，**抬回下限**（保留经纬度）并给出中文说明，同时**自动试一次高清影像**
   —— 能连上高清的网络就不该被限制。

> 这不是之前那个「弹回太空」的守卫。区别是：只抬到当前底图能显示的**最低有效
> 高度**（500 km），而不是无条件拉回 22000 公里；而且只在画面真的无法显示时才动。

`sourceState` 里原先「回退到本地底图就拉回全球视角」也一并改成只抬到下限 ——
否则「自动试高清、失败后退回」会表现成相机被凭空甩走。

`OoglexGlobeNetwork.setView(lon, lat, height)` 是为此加的测试钩子（与已有的
`viewState` 同性质）：程序化飞行这条路必须能被闸门覆盖。

### 相机守卫只该救「非有限值」，不该管「好不好看」

曾经为了掩盖「基础地球放大后发糊」，在 `installCameraGuard` 里设了三样东西，
把导航打残：

| 设置 | 后果 |
|---|---|
| `maximumMovementRatio = 0.12`（Cesium 默认 1.0） | 每次滚轮只走到地表距离的 12%，滚轮手感近乎死掉 —— 用户原话「滚轮不是前进或者后退，而是页面放大缩小」 |
| `minimumZoomDistance = 1200` | 最近只能到 1200 米，永远贴不到地面，而街景/驾驶舱/CCTV 地面投影正是这个应用的看点 |
| `height < 250` 就调用 `overview()` | 任何一次接近地面都被甩回 22000 公里全球视角 |

「基础地球放大后发糊」是**数据本身的性质**：本地底图是 Cesium 自带的
NaturalEarthII，`maximumLevel` 只有 2。**糊是诚实的，弹回不是。** 需要细节就切
高清影像。守卫现在只做一件事：把 NaN/Infinity 的相机状态救回来。

实测（`verify-network.mjs` 已把这条做成闸门）：持续前滚 22000 km → 165 km，
向后滚能拉远，不再弹回。

> **诊断备忘**：判断「滚轮坏没坏」要在**应用 frame 内**往画布派发 `wheel`。
> `page.mouse.wheel()` 的 CDP 合成滚轮虽然能到达画布（实测 canvas 确实收到了
> 事件），却驱动不了 Cesium 的相机控制器，会得出「滚轮完全无效」的假结论。

### 消息要转发给**已经就绪**的应用，不只是「就绪那一刻」

lite 页收到包装页的 `ooglex:set-map` 时只把 `pendingMap` 存下来，而**转发只写在
「完整应用上报 ready」那个分支里**。于是「加载完之后再点切换高清影像」——也就是
用户手动点击的**唯一**路径——消息只被存下、永不转发，状态永远停在
「正在连接高清影像…」，既不成功也不超时。

修法：`ooglex:set-map` 分支里若 `fullReady` 已为真，就立即转发并清空 `pendingMap`。

这个 bug 的诊断过程本身值得记：两次探针一次通过一次卡死，差别只在**点击时机**
（`!hd.disabled` 之后 vs `globeState==='ready'` 之后）。判据是**外部请求数为 0** ——
既然连请求都没发出，就不是网络慢，而是消息没送到。


### 产物里的文件不是源文件

`scripts/globe/` 下的 `network-policy.js`、`network.css`、`fonts/`、`icons/` 是**源**，
由 `patch-network.mjs` 复制进 `apps/globe/app/`。**只改源，不要改产物里的副本。**

曾经发生过：一次 119 行的 no-VPN 启动修复（含 mainland fast path、fetch 拦截、
远端主机白名单）**只写进了产物、没回写源文件**，源文件停在 209 行而产物是 264 行。
那份修复只活在构建产物里 —— 任何人跑一次 `build.sh` 都会静默把它还原掉。

`build.sh` 现在在动手前先比对产物与源文件，不一致就中止并说明该怎么办。确认源文件
才是最新的（例如刚刚回写过），用 `GLOBE_ACCEPT_DRIFT=1` 放行本次构建。

### 应用在**第二层** iframe 里

页面层级是：`apps/globe/index.html`（中文包装页）→ `apps/globe/lite/`（轻量地球，
即时首屏）→ `#full` 内层 iframe（完整三维应用）。

写验证脚本时**只穿一层会把 lite 页当成应用**，于是「图标数 0」「没有中文」这类断言
全部落空，看着像应用坏了，其实是测错了对象。两个验证脚本都已按两层取 document。

## 4. 数据来源与许可

代码是 MIT，**但 MIT 不覆盖数据**。每个数据源各自独立授权。

### 本站启用（静态可用）

| 数据 | 许可 | 署名要求 |
|---|---|---|
| Esri World Imagery（可选卫星底图） | Esri 主协议下的公开 World Imagery 服务 | Powered by Esri — Source: Esri, Maxar, Earthstar Geographics 及 GIS 用户社区 |
| OpenStreetMap 底图（可选） | ODbL 1.0 | © OpenStreetMap contributors |
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

## 5. 图层可用性

上游有约 20 个服务端代理（`server/providers/local.js`），以 Vite 中间件形式运行；
客户端写死同源 `/api/*` 调用共 84 处、跨 31 个文件。本站是纯静态托管，没有服务端。
因此图层分三类处理。

### 5.1 浏览器直连（无需任何后端）

- **地震**：`src/layers/earthquakes/source.js` 里就是浏览器直接 `fetch`
  `earthquake.usgs.gov`，USGS 发 CORS 头，**本来就能用**（默认关闭，需手动开启）。
- 底图 Esri / OSM、内置的数据中心 / 大坝 / Natural Earth 区域 / 海底电缆同理。

### 5.2 静态数据快照（用本仓库既有的 Actions 架构修好）

`/api/celestrak/<group>` 与 `/api/launches` 在上游都是**透传**（前者返回 TLE 纯文本，
后者返回 LL2 的 JSON 原样）。于是由 `.github/workflows/globe_space_data.yml`
每日抓好，**直接写到客户端已经在请求的那些路径上**，一行客户端代码都不用改：

| 图层 | 数据源 | 文件 | 说明 |
|---|---|---|---|
| 卫星（约 840 颗，六个分组） | CelesTrak | `api/celestrak/{stations,visual,gps-ops,glo-ops,galileo,geo}` | **位置由前端 satellite.js 按 SGP4 实时推算**，所以 TLE 每日刷新一次，星点在图上依然实时移动 |
| 航天任务（近 30 天） | Launch Library 2 | `api/launches` | 提供发射事件与时间，不含上升段遥测 |

为什么非得走静态快照而不是让浏览器直连：**CelesTrak 不发 CORS 头**，上游
`server/providers/space/celestrak.js` 的注释明确写了这一点。

刻意不取 CelesTrak 的 `active` 全集（约 1.2 万颗、数 MB）：它只是航天任务层的
**可选**在轨匹配增强（上游注释 "optional active-orbit catalog"，失败仅记警告），
不值得每天往仓库塞几 MB。

失败处理遵循仓库规则第 13 条：任何一项抓取失败都**保留上一份有效数据**，绝不用空
文件或部分数据覆盖；状态写入 `apps/globe/status.json`，包装页的「数据来源」面板
显示来源与更新时间（规则第 6 条）。这条路径有专门的自测：
`python3 scripts/globe/test_fetch_space_data.py`（14 项，无网络依赖）。

实测（2026-09-14 首次运行）：六个分组共 **833 颗**（去重后；文件里 836 条）——
`stations` 20、`gps-ops` 32、`glo-ops` 28、`galileo` 32、`geo` 567、`visual` 154，
TLE 合计约 140KB；航天任务 **25 条**记录。两个图层在浏览器里实测均正常点亮。

`/api/celestrak/active` 会 404，这是**刻意的**（见上），上游只记一条警告。

**落盘前把 launches 展开成多行**：LL2 的 detailed 响应是紧凑**单行** JSON（约 1MB），
单行文件每天换一次，git 做不了行级 delta，每次都得存一个全新的 1MB blob —— 相比
本仓库其他数据文件（多为 1 行级改动）重得多。展开后 1.31MB / 34762 行，每天真正
变化的只有少数记录对应的行，打包 delta 效果好得多。客户端走 `response.json()`，
空白与它无关；HTTP 层有 gzip，传输上基本抵消。**刻意不改用 `mode=normal` 省空间**
—— 那会丢掉载荷与箭体回收等细节，是拿功能换空间。

> 注意：`apps/globe/app/api/` 不是构建产物。`build.sh` 在重建时会先暂存再恢复它
> （实测：暂存 7 个文件 → 恢复）。

### 5.3 仍然不可用（需要一个与应用同源的后端）

- **实时航班、船舶（AIS）**：秒级实时位置，无法用定时静态快照替代。船舶还需常驻
  WebSocket 与私有密钥。
- **活跃火点（FIRMS）**：需要 NASA 密钥，且密钥不能进前端。
- **交通摄像头（CCTV）**：几十个源包 + 实时图片代理 + base64 解码。
- **交通流（TomTom）**：按量计费密钥 + 实时瓦片。
- **网络电台**：目录本身可以预生成（本仓库 `apps/radio/stations.json` 已在做类似的事），
  但上游 `/api/radio/stations` 的归一化结构与之不同，需要一层形状适配才能复用。
- **军事设施（Overpass）**：Overpass 上游实测 `CORS *`（见 `server/providers/overpass/constants.js`
  的注释），理论上可浏览器直连；但上游代理还做了几何简化与缓存，客户端解析的是
  **简化后**的结构，直接打原始上游未必能解析。**未验证，故未接入。**
- **Google 真实感三维瓦片、地点搜索、语音控制**：需要按量计费的第三方密钥。

**这些 404 是上游设计的生产路径，不是故障。** 上游 `src/keySetup.js` 注释写明：
取不到 `/api/setup/status` 时密钥设置入口会自我移除（"a prod build (no endpoint)
... both the chip and the dialog are removed outright"）。因此**不要**为这些接口加
静态 JSON 桩 —— 那会把一个写不了任何东西的设置面板复活。

包装页的「数据来源」面板把可用与不可用分两栏明确列出，逐条给原因。

### 5.4 如果要把 5.3 也修好

需要一个与应用**同源**的后端。可行路径：把应用改挂 `globe.ooglex.com`
（Cloudflare Pages），用 Pages Functions 承接 `functions/api/[[path]].js` —— 同源，
无需改动客户端那 84 处调用，密钥留在服务端环境变量里（比上游把
`GOOGLE_MAPS_API_KEY` / `CESIUM_ION_TOKEN` 打进浏览器包更符合本仓库规则第 5 条）。

注意：主站 `www.ooglex.com` 与 apex 当前都是 Cloudflare **灰云（仅 DNS）**，解析到
GitHub Pages 的 `185.199.108-111.153`，流量不经过 Cloudflare。所以**不能**用
Worker Routes 在 `www.ooglex.com/api/*` 上挂代理 —— 路由不会触发。

这一步需要一个 `CLOUDFLARE_API_TOKEN`（免费额度内，Pages Functions 10 万次/天），
只有仓库所有者能创建。仓库已有同类工作流可照抄：`.github/workflows/deploy-tv-proxy.yml`。

移植成本最低且许可干净的两个：军事设施（Overpass / OSM，ODbL，219 行，零 node 依赖）、
军用航班（adsb.lol，ODbL，158 行，零 node 依赖）。**航班明确用 adsb.lol 而非 OpenSky**
—— 后者非商业授权，且上游注明在 live product 中调用其 REST API 可能需要事先书面协议。

## 6. 验证口径

改动包装页、中文化层或升级上游后，五项都要跑：

1. **构建自检** —— `bash scripts/globe/build.sh` 自带：补丁覆盖率、Cesium 目录、
   产物内无残留根路径、被引用资源真实存在、中文化层已注入、产物内无疑似密钥。
   任一失败即中止。
2. **数据管线自测** —— `python3 scripts/globe/test_fetch_space_data.py`（20 项，
   无网络依赖）。重点是「坏响应被识别」、「失败保留上一份」、「重排不改语义且
   重排失败退回原始字节」。
3. **本地起服务** —— `npx http-server -p 8902 -s .`，确认 `/apps/globe/`、
   `/apps/globe/app/`、`.../cesium/Cesium.js`、`.../logo.svg`、`.../pin.svg`、
   `.../models/airplane.glb`、`/apps/globe/status.json` 全部 200。
4. **浏览器实测** —— `node scripts/globe/verify.mjs`，覆盖 1400 / 768 / 360 三视口：
   Cesium 初始化、进入卡已隐藏、图层名中文化、状态词无英文残留、数据源专名保留、
   图标连字完好、署名行保持英文、**开关 aria-label 中文化且无英文残留**、
   无横向溢出、站内无非 `/api/` 的 404、无 JS 异常。
5. **交互可达性** —— 键盘可达且有可见焦点环、Esc 关闭数据来源面板、
   `prefers-reduced-motion` 下面板不做过渡动画、「中 / EN」可来回切换。

### 三个踩过的坑，别改回去

- **断言计算样式，不是 `hidden` 属性。** 进入卡的 `.gate` 自带 `display:flex`，会
  覆盖 UA 样式表里 `[hidden]` 的 `display:none`；只读 `element.hidden` 返回 `true`
  看着是对的，但卡片其实还浮在应用上面。这个 bug 是**看截图**发现的，程序化断言
  当时没查出来。
- **轮询等待稳定状态，不要固定 sleep；断言用 `textContent` 不用 `innerText`。**
  窄屏下应用启动明显更慢（软件 WebGL），固定等待会误判成「没翻译」；而
  `innerText` 对隐藏/折叠元素返回空串，同样会误判。
- **文本节点与属性必须走同一条翻译路径。** 第一版把锚定正则只接进了文本节点，
  属性（`aria-label` 等）仍是英文 —— 界面看着全中文，屏幕阅读器读到的还是
  `Satellites: ON`。验证脚本现在专门断言这一项。
- **断言前先摘掉署名子树。** 那里的英文是许可要求的原文，本就不该翻译，留着会让
  「无残留英文」误报。另外窄屏下上游只渲染部分图层行，所以「9/9」这类计数断言
  只对宽屏成立。

### 已知的环境限制

本仓库的开发容器出网策略禁止访问 `celestrak.org`、`ll.thespacedevs.com`、
`api.adsb.lol`、`overpass-api.de`、`earthquake.usgs.gov`、`services.arcgisonline.com`
等数据源域名（代理返回 `connect_rejected`）。因此：

- **底图瓦片与地震数据无法在容器内实测**，只能验证到「应用正常启动、图层按失败
  路径优雅降级」。
- **`fetch_space_data.py` 的实际抓取无法在容器内验证**，只能跑它的校验逻辑自测。
  真实抓取由 GitHub Actions 运行器执行（出网无限制），可在 Actions 页面手动触发
  `Globe Space Data` 工作流并看日志确认。

## 7. 大陆直连启动修复（2026-09-14，未部署）

此前启动链存在三个无上限的外部等待：Google Fonts 样式会阻塞入口模块，
Esri 元数据请求和 Re:Earth 地形请求没有应用超时；Esri 失败后改用的 OSM
也需要外网。原包装页插入 iframe 后立即隐藏加载卡，无法识别应用是否真正就绪。

现在由构建后处理器 `scripts/globe/patch-network.mjs` 应用同一份启动策略：
- 删除 Google Fonts 和预连接，文字使用系统字体，图标使用站内 Material 字体。
  字体及 Apache-2.0 许可在 `scripts/globe/fonts/`，两个新图标使用本地 SVG。
- 默认地图为 `local-earth`：直接复用已随 Cesium 发布的 NaturalEarthII JPG
  瓦片（最高 2 级）和椭球表面。它是低分辨率基础地图，不是高清影像或真实地形。
- 保留 Esri 与 OSM，用户可在包装页切换高清影像，也可用原应用的地图菜单。
  元数据超时 6 秒、瓦片超时 8 秒；失败通过原控制器返回基础地图。
  超时后的迟到响应不负责切图，也不把失败缓存成永久回退。
- 无密钥地图不再请求 Re:Earth 地形。已配置密钥的上游功能没有借此接入本站。
- 父页面只接受同源且来源为当前 iframe 的消息；至少一张真实瓦片完成加载、
  Cesium 渲染完成且原加载屏隐藏后才报告就绪。加载失败有中文重试入口。
- 原始数据图层、署名、API 快照和定时工作流保持兼容。
  地震及可选高清影像仍取决于外部数据服务的实际可达性。

实现文件：`network-policy.js`（同源地图与启动协议）、`network.css`（本地图标与
字体）、`patch-network.mjs`（幂等产物处理器）及包装页。处理器对上游压缩代码的
固定结构逐项断言，锚点变化即构建失败；不静默发布未应用策略的新上游。
现有产物也由同一纯函数处理，入口 URL 增加缓存版本。
未来升级上游应重新检查地图菜单、地图类型清单和启动工厂的这几个锚点。

验证：新增 `verify-network.mjs`，在真正的 Chromium 中让所有第三方请求悬挂，
检查 360/768/1280 视口、真实本地瓦片、字体、无溢出、来源面板与重试，
并覆盖直接访问内页、高清影像超时与再次尝试、中英文切换、入口脚本失败。
只读工作流 `Globe Network Quality` 使用上游已有的 Puppeteer 依赖和运行器
Chrome，先验证已提交产物，再重建并检查新产物和原有中文界面。
该工作流不写仓库、不部署、不读取 Secrets。截图保留 7 天。

网络模拟只能证明外部依赖不再阻塞启动；并不等于已在大陆运营商线路实测。
如果 `www.ooglex.com` 主站本身无法连通，页面内的修复不能替代托管网络的调整。


### 基础底图的视角（2026-09-15）

上游默认从奥斯汀上空 25 km 飞到 600 m。这与最高 2 级的 Natural Earth 全球概览底图不匹配，放大后会只看到一块绿色。构建补丁已替换该开场动画，改为从 22,000 km 的全球视角启动；从高清影像回退到基础底图时，若仍在近地视角，则重新拉远。顶栏“全球视角”可随时恢复地球概览。新版本同时更新入口和策略脚本版本号，避免混用旧缓存。

验证要求同时检查相机高度与浏览器实际截图中的地图色彩差异，不能只凭瓦片下载和画布尺寸判断地图可见。

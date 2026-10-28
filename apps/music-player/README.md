# 流光播放器

网页专辑播放器，路径 `/apps/music-player/`。访客只播放已经写进 `data/catalog.json` 的专辑。站长在 `/apps/music-player/admin/` 整理专辑，再发行。

## 听什么

预置两张专辑是 **演示 / 免版税样例**，不是付费曲库：

- 曲目：Kevin MacLeod（incompetech.com）的 *Mesmerizing Galaxy*、*Lord of the Rangs*、*Sergio's Magic Dustbin*、*Morning*、*Pleasant Porridge*
- 许可：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。免版税，使用须署名，不是 CC0
- 本仓库里的 mp3 是从原曲截取的约 28 秒短样，文件里的注释也写了这一点

站长另外发行的专辑必须是自创或已获授权。管理页会要求填写权利说明。

## 全球曲库

专辑列表上方的「全球曲库」入口（`#/global`）按曲风、排序或关键词查询 [Jamendo](https://www.jamendo.com/) 上的独立音乐。约 20 种曲风，可加载更多。

- **本站不存音频**：目录经 `workers/jamendo-proxy` 查询，音频由浏览器直接从 Jamendo 播放
- **版权**：每首是艺人自己用 Creative Commons 许可发布的，列表逐首显示许可并链接到 Jamendo 曲目页。这里没有主流唱片公司的热门歌
- **配置**：`data/global.json`。`api` 为空时页面显示「尚未开通」，不发请求。部署与许可说明见 `workers/jamendo-proxy/README.md`
- **状态**：加载中、正常、部分曲目被略过、无结果、接口未配置、请求过频、超时、连不上、配置读不到，各有提示。加载更多失败时，已加载的曲目保留
- 正在播放的全球曲目切换曲风后仍可继续播放、上一首、下一首。同一曲风再切回来时用本页已加载的结果，不重复请求

## 收藏

每首歌右侧和正在播放歌名旁的 ♡ 用来收藏；专辑页的「我的收藏」入口进入 `#/favorites`。

- 存在这台设备浏览器的 `localStorage`（键 `ooglex.music-player.favorites`，最多 500 首），不需要登录，不跨设备同步
- 每条记下歌名、艺人、封面、播放地址和署名（许可链接、Jamendo 页面），收藏页直接能播
- 读回时逐条校验，只认 `/apps/music-player/media/` 下的路径和 Jamendo、Creative Commons 的 https 地址
- 本机草稿（`idb:`）里的曲目不能收藏

## 全屏播放

手机上点底部迷你播放条打开全屏（复用 `.stage`，加 `.is-full`）。上滑下一首、下滑上一首：竖向位移超过 60px、比横向大 1.5 倍、0.9 秒内完成才算；从 `input`、`button`、`a`、`summary` 上开始的触摸不算。打开时 `history.pushState` 一条记录，返回键先收起。键盘 ↓/↑ 切歌、Esc 收起。

## 分享

正在播放歌名左侧的按钮打开分享面板：系统分享（`navigator.share`，不支持时隐藏）、复制链接、生成海报（canvas 1080×1440，可保存或分享图片）。聊天、社交类应用的内置浏览器里提示用右上角 ··· 菜单分享（页面文字不点名具体应用），并用 `history.replaceState` 把地址换成这首歌的链接。

- 链接：本站专辑 `#/album/<专辑编号>/<曲目编号>`，全球曲库 `#/track/<Jamendo 编号>`（经 `jamendo-proxy` 的 `id` 参数查询）。打开时只摆好曲目，不自动播放
- 海报二维码 `icons/qr-player.svg` 指向播放器首页。换地址时用 segno 重新生成：`segno.make(url, error="m").save(..., kind="svg", border=2)`，再补上 `viewBox` 与 `shape-rendering="crispEdges"`
- 外站封面画不进 canvas（跨域）时退回默认图案

## 数据

`data/catalog.json`：

```json
{
  "albums": [
    {
      "id": "aurora-sketches",
      "title": "Liuguang Sketches",
      "artist": "Kevin MacLeod",
      "cover": "/apps/music-player/media/aurora-sketches/cover.svg",
      "released": true,
      "releasedAt": "2026-10-25",
      "demo": true,
      "license": "CC BY 4.0",
      "tracks": [
        { "id": "morning", "title": "Morning", "artist": "Kevin MacLeod", "src": "/apps/music-player/media/...", "durationSec": 28 }
      ]
    }
  ]
}
```

封面和音频放在 `media/<专辑编号>/`，并写进 `data/catalog.json`。原创完整曲同样走这条路径（例如《Black Gold Night》，以及其后的《Guilin Drift》《Dongping Homecoming》《Xuzhuang Lane》《Song City After Dark》《Taian Power》，`demo: false`）。`released: false` 的专辑不会出现在访客页。

## 管理口令

初始口令：`liuguang`

校验与站内轻量密码门相同（djb2，源码只留哈希）。更换时重算后改 `js/gate.js` 的 `HASH`：

```bash
node -e 'function h(s){var x=5381;for(var i=0;i<s.length;i++)x=((x<<5)+x+s.charCodeAt(i))>>>0;console.log(x)} h(process.argv[1])' '新口令'
```

这只是浏览器里的一道门，能读仓库的人可以推算短口令。管理页也没有放进 sitemap。

## 发行

优先用管理页的 GitHub 途径：

1. 建一张细粒度 PAT，只给本仓库 Contents 读写。
2. 打开管理页，口令通过后，把令牌填进「记住令牌到本次会话」。令牌进 `sessionStorage`，关掉标签页就没了，不会写入仓库、localStorage 或提交说明。
3. 分支填功能分支。写入 `main` / `master` 必须另外勾选确认，否则会被拒绝。写入 `main` 可能触发生产部署。
4. 勾选「对访客发行」后点「发行到 GitHub」。脚本用 Git Data API 做成一次提交：新媒体 blob，加上更新后的 `catalog.json`。

没有令牌时点「导出待发布包」。zip 里是 `catalog.json`、新媒体和 `PUBLISH.txt`。解压到仓库根目录后自己提交。

本机预览打开 `/apps/music-player/?draft=1`，读这台浏览器的 localStorage 清单和 IndexedDB 文件。别人的浏览器看不到。

未勾选发行的专辑不会进 zip，也不会进 GitHub。从公开清单拿掉一张专辑，不会自动删除仓库里已经提交的旧音频。

不使用付费对象存储。R2 / Worker 不是这条路径的一部分。

## 本地验证

在仓库根目录：

```bash
python3 -m http.server 8765
```

打开 `http://127.0.0.1:8765/apps/music-player/`。点一张专辑，再点曲目。页面不会自己出声。可以暂停、上一首、下一首、循环、随机、拖进度、调音量。第一首再点上一首会回到该专辑最后一首，不会报错。最后一首自然播完会停住；列表循环会回到第一首，单曲循环会重播当前这首。

管理页：`http://127.0.0.1:8765/apps/music-player/admin/`，口令见上文。新建专辑、加一首本地 mp3、勾选发行之前，用「本机预览」确认听得到。

## 已知限制

- 浏览器禁止自动播放。第一次要有点击或按键。
- 部分手机浏览器把音量交给系统按键，页内音量条可能不起作用。桌面 Chrome 可以调。
- iOS 对无用户手势的 `play()` 会拒绝，页面会提示再点一次。
- 令牌放在浏览器里，只防无意把密钥写进 Git，不防这台电脑上的恶意脚本。
- 单文件建议小于 15MB。更大的音频请先压短。
- 管理页的 GitHub 写入在这次改动里没有用真实令牌跑过；请求封装和清单生成可以本地用导出包核对。

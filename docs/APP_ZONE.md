# App 专区

首页 `#app-zone`（导航「App」）是 Ooglex 新创意点子的落脚处：以后每个新想法做成的 App 都加在这一栏。

## 现有条目

| 序号 | App | 入口 | 说明 |
|---|---|---|---|
| 27 | OOGLE X · 科技领袖 | `/apps/tech-leaders/app/` | 「科技领袖实时动态流」安卓应用下载页，见 `docs/ANDROID_TECH_LEADERS.md` |

## 新增一个 App

1. 页面放在 `apps/<英文短名>/`（或已有应用下的子目录），沿用现有主题脚本、`canonical` 与返回首页链接。
2. 在 `index.html` 的 `<section id="app-zone">` 里追加一行 `<a class="row">`，序号接着上一条往后编。
3. 同时在首页英文词典里补 `item.<key>.name` / `item.<key>.desc`。
4. 有金融数据的 App 按 `AGENTS.md` 的数据规范标注来源、更新时间和状态；演示数据必须在首屏标「模拟数据」。
5. 更新 `CHANGELOG.md`，并在上表登记。

## 回退

删除 `index.html` 中 `#app-zone` 整段、导航里的 `#app-zone` 链接和英文词典中的 `nav.appZone`、`section.appZone*`、`badge.android`、`item.oogleX.*`。各 App 自身页面不受影响。

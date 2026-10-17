# App 专区

Ooglex 新创意点子做成的 App 都放在这里。

- 首页 `#app-zone`（导航「App」）：接在「工具与游戏」之后，**只显示 App 图标**，右上角「全部 App →」进入专区页。
- 专区页 `/apps/app-zone/`：同样只显示图标（为将来上百个 App 设计的自适应网格，手机每行 4 个）。
- 点图标进入该 App 的单独下载/安装页。
- App 名称不显示在图标下，只作为无障碍名称（`aria-label`）与悬停提示（`title`），所以**图标本身要有辨识度**。

两处图标都由 `apps/app-zone/registry.js` 的同一份登记表渲染，不要在页面里手写图标。

## 现有 App

| id | App | 类型 | 下载/安装页 |
|---|---|---|---|
| `oogle-x` | OOGLE X · 科技领袖 | 安卓 APK | `/apps/tech-leaders/app/`（见 `docs/ANDROID_TECH_LEADERS.md`） |
| `radio` | 环球电波 | 安卓 APK + 网页 App | `/apps/radio/download/` |
| `tv` | 环球TV | 网页 App（PWA） | `/apps/app-zone/tv/` |
| `ai-chat` | 万象智聊 | 网页 App（PWA） | `/apps/app-zone/ai-chat/` |

## 新增一个 App

1. 做好 App 本身（页面放 `apps/<英文短名>/`）。
2. 准备图标：512×512 方形 SVG，圆角 `rx≈112`，背景铺满（与现有图标统一）；放在 App 自己的 `icons/` 或 `apps/app-zone/icons/`。
3. 准备单独的下载/安装页：有安装包的照 `/apps/tech-leaders/app/`；网页 App 照 `/apps/app-zone/tv/` 复制一份到 `/apps/app-zone/<id>/` 改文字。
4. 在 `apps/app-zone/registry.js` 的数组末尾加一项（`id`、`name`、`en`、`icon`、`href`、`platform`），并把首页与专区页引用里的 `registry.js?v=` 改成当天日期，避免浏览器缓存旧列表。
5. 新页面加入 `sitemap.xml`；有金融数据的 App 按 `AGENTS.md` 标注来源、更新时间和状态。
6. 更新 `CHANGELOG.md` 与上表。

## 回退

删除 `index.html` 中 `#app-zone` 整段、相应 CSS（「App 专区」注释块）、导航里的 `#app-zone` 链接、页尾加载 `registry.js` 的两段脚本、英文词典中的 `nav.appZone` 与 `section.appZone*`，再删除 `apps/app-zone/` 目录与 sitemap 中的三条。各 App 自身页面不受影响。

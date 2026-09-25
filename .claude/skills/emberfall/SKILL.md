---
name: emberfall
description: 继续开发原创暗黑风 ARPG《余烬陷落》EMBERFALL 的大作版本（games/emberfall3d，Godot 4）或维护 V0.1（games/emberfall）。加载路线图台账、原创红线和每步的收尾流程。用户说「继续开发余烬陷落」「余烬陷落下一步」「EMBERFALL 步骤 X.Y」或输入 /emberfall 时使用。
---

# 余烬陷落：持续开发

这是长期工程。每次接手：

1. 读 `docs/EMBERFALL_ROADMAP.md`：看「所有者的决定」和「当前状态」，找到下一个未完成的步骤。
   用户指定了步骤号（如「步骤 1.3」）就做那一步；没指定就做台账里下一个「待开始」。
2. 所有者的决定（D1–D6）里还有「待定」、且这一步依赖它时，**先问，不要替所有者拍板**。
3. 一次只做一个步骤。做完就收尾，不顺手做下一步。

## 一、原创红线（与 AGENTS.md 同等级）

- 不用《暗黑破坏神》系列的任何专有名词、谐音或近形名；不复刻其关卡、角色外形、技能名、UI、配乐、台词。
- 不拿暴雪的截图、模型、贴图、音频当素材或 AI 生成的输入。所有者发来的官方截图只能用来理解「想要的氛围和画质档次」。
- 每个外部素材（模型、贴图、动作、音频、字体）记入 `games/emberfall3d/assets/SOURCES.md`：名称、作者、许可、原始链接、下载日期。
  许可不清楚的一律不用。
- 我画不出 AAA 美术资产。需要资产时，列出候选素材（附许可）或说明需要所有者提供，不要用粗糙占位冒充成品；占位就写明是占位。

## 二、目录与复用

- V0.1：`games/emberfall/`（Canvas 2D，已上线，URL 不变）。其物品、词缀、怪物、剧情数据是大作版的设计种子，可以移植，不要删。
- 大作版：`games/emberfall3d/`（`design/` 设计文档、`godot/` 工程、`tools/` 构建脚本、`play/` 网页导出）。
- 构建与测试脚本先复用 `games/working-life/tools/`（`build_web.sh`、`run_tests.sh`、`stamp_web_build.py`），改路径，不另起一套。
- Godot 网页导出只能用兼容渲染器（GL Compatibility），画质方案都按这个前提设计。
- 本环境可能没有安装 Godot，素材站也可能被网络策略拦截。先检查；装不了或下不了，就如实说明哪些没验证，并读 `read_documentation`（environment.network / environment.dependencies）告诉所有者怎么放行。

## 三、每一步的收尾

1. 运行适用的检查：GDScript 语法与自动化测试（能运行时）、网页导出、`git diff --check`；网页页面按 360 / 768 / 1280px 截图检查。
2. 实机截图或录屏发给所有者（画质类步骤必须有）。
3. 更新 `docs/EMBERFALL_ROADMAP.md`：该步骤的状态、「当前状态」一段、新出现的待定问题。
4. 更新根目录 `CHANGELOG.md`，写明「未部署」。
5. 提交到功能分支。**合并 `main` / 上线必须所有者明确同意**。

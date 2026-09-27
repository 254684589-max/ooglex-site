---
name: ironcrown
description: 继续开发原创第一人称中世纪权谋角色扮演游戏《铁冠之争》THE IRON CROWN（games/ironcrown，Godot 4 网页导出）。加载路线图台账、原创红线和每步的收尾流程。用户说「继续开发铁冠之争」「铁冠之争下一步」「铁冠 步骤 X.Y」或输入 /ironcrown 时使用。
---

# 铁冠之争：持续开发

这是长期工程，所有者 2026-09-27 决定**优先于《余烬陷落》**。每次接手：

1. 读 `docs/IRONCROWN_ROADMAP.md`：看「所有者的决定」和「当前状态」，找到下一个未完成的步骤。
   用户指定了步骤号就做那一步；没指定就做台账里下一个「待开始」。
2. 这一步依赖的决定还是「待确认」时：有「建议」的按建议推进并在台账里写明；没有建议的**先问，不替所有者拍板**。
3. 一次只做一个步骤，做完就收尾，不顺手做下一步。
4. 动手前读与这一步相关的设计文档（`games/ironcrown/design/`）。

## 一、原创红线（与 AGENTS.md 同等级）

- 题材借鉴《权力的游戏》一类的家族权谋，**世界观、地名、家族、人物、徽记、情节全部原创**。禁用词与禁止复刻的桥段见 `design/WORLD.md` 第九节，新增任何名字前先对照。
- 所有者发来的参考截图（其他商业游戏的画面）只用来理解氛围：不复刻建筑、布局与界面，不进仓库，不作 AI 生成的输入。
- 每个外部素材（贴图、模型、动作、音频、字体）记入 `games/ironcrown/assets/SOURCES.md`：名称、作者、许可、原始链接、下载日期。许可不清楚的一律不用。
- 做不出的美术资产，列出候选素材（附许可）或说明需要所有者提供；占位就写明是占位。

## 二、目录与复用

- 工程：`games/ironcrown/`（`design/` 设计文档、`godot/` 工程、`tools/` 构建脚本、`play/` 网页导出，不入库）。
- 构建与测试脚本从 `games/emberfall3d/tools/` 复制后改路径，不另起一套；需要复用《余烬陷落》的 GDScript 时复制过来并在文件头注明来源。
- 《余烬陷落》踩过的坑写在 `games/emberfall3d/design/TECH.md` 与 `docs/EMBERFALL_ROADMAP.md`，遇到导航、触屏、雾、贴图、网页 gzip、章节包问题先查那里。
- Godot 网页导出只能用兼容渲染器（GL Compatibility）；本环境没有 Vulkan，无法烘焙光照贴图。
- 本环境默认没有 Godot：`python3 games/emberfall3d/tools/fetch_godot.py <scratchpad>/godot`（1.1 之后用本工程自己的副本），再 `export GODOT=…`。
- 素材站可能被网络策略拦截（2026-09-27：Poly Haven、ambientCG 能访问；Quaternius、Kenney、OpenGameArt 被拦截）。下不了就如实说明，并读 `read_documentation`（environment.network）告诉所有者怎么放行。

## 三、每一步的收尾

1. 运行适用的检查：GDScript 语法与自动化测试、网页导出、网页冒烟（360 / 768 / 1280px）、`git diff --check`。纯文档步骤写明「构建：不适用」。
2. 画面类步骤必须把实机截图发给所有者。
3. 更新 `docs/IRONCROWN_ROADMAP.md`：该步骤的状态、「当前状态」一段、新出现的待定问题。
4. 更新根目录 `CHANGELOG.md`，写明「未部署」。
5. 提交到功能分支。**合并 `main` / 上线 / 在游戏中心加入口必须所有者明确同意**。

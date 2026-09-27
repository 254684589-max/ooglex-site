# 铁冠之争 THE IRON CROWN（立项中）

原创的第一人称中世纪权谋角色扮演游戏，题材气质借鉴《权力的游戏》一类的家族权谋故事，世界观、家族、人物全部原创（原创红线见 `design/WORLD.md` 第九节）。
引擎：Godot 4.7.2，网页导出（与《余烬陷落》大作版同一套管线）。

- 设计文档：`design/`（WORLD 世界观 · STORY 主线 · GDD 玩法 · ART 美术 · TECH 技术）
- 路线图与进度台账：`../../docs/IRONCROWN_ROADMAP.md`
- 开发规则与收尾流程：`../../.claude/skills/ironcrown/SKILL.md`

当前是技术原型（阶段 1）：一段静止的雾夜灰盒街道，画面全部是占位几何体。`play/` 不入库，网站上没有入口。

## 本地构建

```bash
python3 games/ironcrown/tools/fetch_godot.py ~/godot          # 下载编辑器 + 只取网页导出模板（约 10 MB）
export GODOT=~/godot/Godot_v4.7.2-stable_linux.x86_64
games/ironcrown/tools/run_tests.sh                            # 语法检查 + 自动化测试
games/ironcrown/tools/build_web.sh                            # 测试后导出到 play/
python3 games/ironcrown/tools/serve_gzip.py . 8765 &          # 在仓库根目录（gzip 传输，模拟线上）
node games/ironcrown/tools/smoke_web.js /tmp                  # 三个宽度的网页冒烟测试 + 截图
```

- 工具脚本复制自 `games/emberfall3d/tools/`，只改路径与文件名前缀（`ic-`）；复用的 GDScript 在文件头注明来源。
- 内置中文字体 `godot/assets/fonts/NotoSansSC-IC.ttf` 暂时直接复制《余烬陷落》的子集（Noto Sans SC，SIL OFL 1.1，许可见同目录 `OFL.txt`）；
  界面文字是否都在字体里由自动化测试检查，缺字时再按本工程字符集重做子集。
- 测试结果：`TEST_REPORT.md`。

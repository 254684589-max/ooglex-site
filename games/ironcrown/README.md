# 铁冠之争 THE IRON CROWN（立项中）

原创的第一人称中世纪权谋角色扮演游戏，题材气质借鉴《权力的游戏》一类的家族权谋故事，世界观、家族、人物全部原创（原创红线见 `design/WORLD.md` 第九节）。
引擎：Godot 4.7.2，网页导出（与《余烬陷落》大作版同一套管线）。

- 设计文档：`design/`（WORLD 世界观 · STORY 主线 · GDD 玩法 · ART 美术 · TECH 技术）
- 路线图与进度台账：`../../docs/IRONCROWN_ROADMAP.md`
- 开发规则与收尾流程：`../../.claude/skills/ironcrown/SKILL.md`

当前是技术原型（阶段 1）：可以用第一人称在雾夜里的霜渡镇主街走动、交互（`play/?test=1` 是灰盒测试场），建筑用写实贴图；主角的第三人称是 CC0 人物模型 + 动作库（A.1），NPC 与敌人仍是占位胶囊；「倒钩鱼」酒馆能进去（3.1，`play/?area=tavern` 直接从酒馆开始），主街的窄巷通往星铁小教堂与墓园（3.2，`?area=churchyard`、`?area=chapel`）；没拿武器时用拳头，酒馆里能和醉汉大桶徒手打一架（3.3，`?area=tavern&brawl=1` 一进门就开打）；敌人会沿导航网格绕路（3.4）；出主街南门是镇外桦林和无旗者的哨卡（3.5，`?area=birch`），再往南是渡口和「灰手」奥弗（3.6，`?area=ferry`）；在渡口决定少爷和借据的去处后，奥尔本修士来交书，出现「第一章 · 黑鹭堡　开发中」结束画面（3.7，`?ending=deliver` 直接看结束画面）。新游戏从开场开始：标题卡、镇上的钟声、宅邸门口被管家叫住，之后各系统第一次用到时有一次性的教学提示（3.8）。整个序章做完了，评审单见 `SLICE_REVIEW.md`。已上线到 `/games/ironcrown/play/`（2026-09-27，开发中预览），游戏中心有「开发中预览」卡片（直接进游戏，还没有介绍页）；`play/` 随上线入库，每次上线前用 `tools/build_web.sh` 重新构建。

## 本地构建

```bash
python3 games/ironcrown/tools/fetch_godot.py ~/godot          # 下载编辑器 + 只取网页导出模板（约 10 MB）
export GODOT=~/godot/Godot_v4.7.2-stable_linux.x86_64
games/ironcrown/tools/run_tests.sh                            # 语法检查 + 自动化测试
games/ironcrown/tools/build_web.sh                            # 测试后导出到 play/
python3 games/ironcrown/tools/serve_gzip.py . 8765 &          # 在仓库根目录（gzip 传输，模拟线上）
node games/ironcrown/tools/smoke_web.js /tmp                  # 三个宽度的网页冒烟测试 + 截图
node games/ironcrown/tools/shots_web.js /tmp medium           # 3 个固定机位截图 + 性能统计（画质类步骤给所有者看）
node games/ironcrown/tools/bench_web.js /tmp medium           # 网页自动基准测试（?perf=1），等结果表出来截图
xvfb-run -a $GODOT --path games/ironcrown/godot --rendering-driver opengl3 res://tests/perf_stats.tscn   # 本机渲染开销对照
$GODOT --headless --path games/ironcrown/godot --fixed-fps 60 res://tests/army_bench.tscn -- mode=combat model=1   # 军队规模压力测试（D8）
games/ironcrown/tools/army_bench_web.sh "mode=combat&model=1&no3d=1"                                           # 同上，网页版（临时导出，不动 play/）
```

网页参数：`?test=1` 灰盒测试场、`?q=low|medium|high` 画质、`?view=0|1|2` 固定机位、`?perf=1` 自动基准测试（结果表显示在画面上）。游戏里按 F3 显示性能浮层。

- 工具脚本复制自 `games/emberfall3d/tools/`，只改路径与文件名前缀（`ic-`）；复用的 GDScript 在文件头注明来源。
- 内置中文字体 `godot/assets/fonts/NotoSansSC-IC.ttf` 是按本工程字符集做的子集（Noto Sans SC，SIL OFL 1.1，许可见同目录 `OFL.txt`）。
  界面与台词的字是否都在字体里由自动化测试检查；缺字时 `pip install fonttools` 后运行 `python3 games/ironcrown/tools/build_font.py path/to/NotoSansSC[wght].ttf` 重做
  （原字体可从 https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf 下载）。
- 外部素材（贴图、字体）的来源与许可：`assets/SOURCES.md`。
- 测试结果：`TEST_REPORT.md`。

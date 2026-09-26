# 余烬陷落 EMBERFALL · 大作版（开发中）

原创暗黑风动作角色扮演游戏的 3D 大作版本，Godot 4.7.2。已上线的 Canvas 2D 版在 `../emberfall/`（V0.1），两者互不影响。

- 设计文档：`design/`（WORLD 世界观 · STORY 剧情 · GDD 玩法 · ART 美术 · TECH 技术）
- 路线图与进度台账：`../../docs/EMBERFALL_ROADMAP.md`
- 素材来源台账：`assets/SOURCES.md`

## 本地构建

```bash
python3 games/emberfall3d/tools/fetch_godot.py ~/godot          # 下载编辑器 + 只取网页导出模板
export GODOT=~/godot/Godot_v4.7.2-stable_linux.x86_64
games/emberfall3d/tools/run_tests.sh                            # 语法检查 + 自动化测试
games/emberfall3d/tools/build_web.sh                            # 测试后导出到 play/
python3 -m http.server 8765 &                                   # 在仓库根目录
node games/emberfall3d/tools/smoke_web.js /tmp                  # 三个宽度的网页冒烟测试
```

`play/` 与 `godot/.godot/` 不入库（见 `.gitignore`）；垂直切片完成、所有者同意上线前，网站上没有这个版本的入口。

# 铁冠之争 · 测试报告

每一步的实际命令与结果，最新的在上面。

## 2026-09-27 · 阶段 1.1 工程与网页导出

环境：云端开发环境（Linux，无显卡），Godot 4.7.2 编辑器 + `web_nothreads_release.zip`（`tools/fetch_godot.py` 下载）；
网页冒烟用预装 Chromium（SwiftShader 软件渲染 WebGL 2）。

| 检查 | 命令 | 结果 |
|---|---|---|
| 语法 | `tools/run_tests.sh`（内含 `tests/parse_all.gd`） | PARSE OK |
| 自动化测试 | 同上（boot、ui 两组） | **14 项全部通过**：兼容渲染器（桌面 + 移动）、相机当前且视高 1.65 米、视野角 75°、深度雾与夜雾蓝背景、ACES、点光源 2 盏（预算 ≤ 4）、界面标注「占位」、界面文字全部在字体子集里、界面缩放三个尺寸 |
| 网页导出 | `tools/build_web.sh` | 通过，`play/` 共 39.0 MB（引擎 wasm 37.7 MB，游戏包 1.0 MB，主要是中文字体） |
| 网页冒烟 | `tools/serve_gzip.py` + `tools/smoke_web.js` | **三个宽度全部 PASS**：1280×720 / 768×1024（触屏）/ 360×740（触屏）都打出 `IC_READY renderer=gl_compatibility web=true`，加载画面消失，控制台 0 报错，横向溢出 0px；启动 2.1–4.5 秒（本机服务器） |
| 站点资源版本 | `python3 scripts/validate_asset_versions.py` | 通过 |
| 空白 | `git diff --check` | 通过 |

截图检查中发现并修掉两处：说明文字在「阶段」后的空格处断行（改为中文按字换行），窗光自发光过曝成白色（强度 2.0 → 0.8）。

未验证：真机（手机 / 平板实体设备）与真实显卡上的帧率——1.5 性能基线时做。

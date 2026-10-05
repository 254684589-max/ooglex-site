#!/usr/bin/env bash
# 《铁冠之争》军队规模压力测试的网页版（2026-10-04，路线图 D8；B.5 复测用）。
# 把工程复制到临时目录，主场景换成 tests/army_bench.tscn，导出网页，用无头 Chromium（SwiftShader）打开，打印每档人数的 ICB 行。
# 不动仓库里的工程和 play/。SwiftShader 是软件渲染，帧率不代表真机；看 logic60_ms（逻辑耗时）和绘制调用、图元数。
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 games/ironcrown/tools/army_bench_web.sh "mode=combat&model=1&no3d=1"
#   参数见 godot/tests/army_bench.gd 文件头；PORT=8790 可改端口。
set -euo pipefail

GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERY="${1:-mode=combat&model=1&no3d=1}"
PORT="${PORT:-8790}"
TMP="$(mktemp -d)"
SRV=""
trap '[[ -n "$SRV" ]] && kill "$SRV" 2>/dev/null; rm -rf "$TMP"' EXIT

mkdir -p "$TMP/proj" "$TMP/web"
(cd "$HERE/godot" && tar --exclude=.godot -cf - .) | tar -xf - -C "$TMP/proj"
# 正式导出排除了 tests/；这里要把压力测试场景打进包、当主场景
sed -i 's#^exclude_filter=.*#exclude_filter=""#' "$TMP/proj/export_presets.cfg"
sed -i 's#^run/main_scene=.*#run/main_scene="res://tests/army_bench.tscn"#' "$TMP/proj/project.godot"

echo "== 导入、导出（临时目录）"
"$GODOT" --headless --path "$TMP/proj" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$TMP/proj" --export-release "Web" "$TMP/web/index.html" >/dev/null 2>&1

echo "== 浏览器里运行：$QUERY"
python3 "$HERE/tools/serve_gzip.py" "$TMP/web" "$PORT" >/dev/null 2>&1 &
SRV=$!
sleep 1
node "$HERE/tools/army_bench_web.js" "$QUERY" "$PORT"

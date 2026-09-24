#!/usr/bin/env bash
# 《工地搬砖》网页版构建：Godot 工程 → games/construction-worker/play/
#
# 需要：Godot 4.7.x 编辑器 + 对应版本的导出模板（只用到 web_nothreads_release.zip）。
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 games/construction-worker/tools/build_web.sh
#
# 步骤：导入资源 → 跑自动化验收测试 → 导出 Web（无线程版，GitHub Pages 不需要
# 跨源隔离响应头）→ 给文件名加内容哈希并放进 play/。
set -euo pipefail

GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$HERE/godot"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "== 导入资源"
"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  echo "== 自动化验收测试"
  "$GODOT" --headless --path "$PROJECT" res://tests/test_game_loop.tscn
fi

echo "== 导出 Web"
"$GODOT" --headless --path "$PROJECT" --export-release "Web" "$OUT/index.html"

echo "== 整理到 play/"
python3 "$HERE/tools/stamp_web_build.py" "$OUT" "$HERE/play"

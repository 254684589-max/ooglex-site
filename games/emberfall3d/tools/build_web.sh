#!/usr/bin/env bash
# 《余烬陷落》大作版网页构建：Godot 工程 → games/emberfall3d/play/（结构沿用 games/working-life/tools/build_web.sh）
#
# 需要：Godot 4.7.2 编辑器 + 同版本导出模板（只用到 web_nothreads_release.zip）。
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 games/emberfall3d/tools/build_web.sh [输出目录]
#
# 步骤：导入资源 → 语法检查 + 自动化测试 → 导出 Web（无线程版）→ 导出章节包 → 给文件名加内容哈希。
# SKIP_TESTS=1 可跳过测试。输出目录默认是 play/（play/ 在垂直切片前不入库，见 ../.gitignore）。
set -euo pipefail

GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$HERE/godot"
DEST="${1:-$HERE/play}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "== 导入资源"
"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  GODOT="$GODOT" "$HERE/tools/run_tests.sh"
fi

echo "== 导出 Web"
"$GODOT" --headless --path "$PROJECT" --export-release "Web" "$OUT/index.html"

echo "== 导出章节包"
mkdir -p "$OUT/packs"
"$GODOT" --headless --path "$PROJECT" --export-pack "ChapterTest" "$OUT/packs/ch_test.pck"

echo "== 整理到 $DEST"
python3 "$HERE/tools/stamp_web_build.py" "$OUT" "$DEST"

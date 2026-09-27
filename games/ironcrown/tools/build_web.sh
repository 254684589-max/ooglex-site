#!/usr/bin/env bash
# 《铁冠之争》网页构建：Godot 工程 → games/ironcrown/play/
# 复制自 games/emberfall3d/tools/build_web.sh（阶段 1.1），去掉了章节包导出。
#
# 需要：Godot 4.7.2 编辑器 + 同版本网页导出模板（只用到 web_nothreads_release.zip，tools/fetch_godot.py 会下载）。
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 games/ironcrown/tools/build_web.sh [输出目录]
#
# 步骤：导入资源 → 语法检查 + 自动化测试 → 导出 Web（无线程版）→ 给文件名加内容哈希。
# SKIP_TESTS=1 可跳过测试。输出目录默认是 play/（play/ 在所有者同意上线前不入库，见 ../.gitignore）。
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

echo "== 整理到 $DEST"
python3 "$HERE/tools/stamp_web_build.py" "$OUT" "$DEST"

#!/usr/bin/env bash
# 《余烬陷落》大作版自动化检查：语法检查 → 导出测试章节包 → 自动化测试（全部通过时退出码为 0）。
# 结构沿用 games/working-life/tools/run_tests.sh。
#   GODOT=/path/to/godot games/emberfall3d/tools/run_tests.sh [测试组 ...]
set -uo pipefail
GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$HERE/godot"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
echo "== 语法检查"
if "$GODOT" --headless --path "$PROJECT" -s res://tests/parse_all.gd 2>&1 | grep -E "PARSE FAILED|SCRIPT ERROR|at: GDScript"; then
  exit 1
fi
echo "PARSE OK"
echo "== 导出测试章节包"
"$GODOT" --headless --path "$PROJECT" --export-pack "ChapterTest" "$TMP/ch_test.pck" >/dev/null 2>&1
[[ -s "$TMP/ch_test.pck" ]] || { echo "FAIL 章节包导出失败（需要安装 4.7.2 网页导出模板）"; exit 1; }
echo "ch_test.pck $(stat -c %s "$TMP/ch_test.pck") 字节"
echo "== 自动化测试"
LOG="$TMP/test.log"
timeout 300 "$GODOT" --headless --path "$PROJECT" res://tests/test_runner.tscn -- "$@" "--pack=$TMP/ch_test.pck" >"$LOG" 2>&1
CODE=$?
grep -vE "^\s*$" "$LOG" | grep -vE "^\s+at: " | grep -E "^== |ok |FAIL|SCRIPT ERROR|^ERROR|PASSED|FAILED|WATCHDOG"
exit $CODE

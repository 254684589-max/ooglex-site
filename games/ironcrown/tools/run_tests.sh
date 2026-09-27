#!/usr/bin/env bash
# 《铁冠之争》自动化检查：语法检查 → 自动化测试（全部通过时退出码为 0）。
# 复制自 games/emberfall3d/tools/run_tests.sh（阶段 1.1），去掉了章节包导出（章节包到有第二个区域时再加，TECH.md 第六节）。
#   GODOT=/path/to/godot games/ironcrown/tools/run_tests.sh [测试组 ...]
set -uo pipefail
GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$HERE/godot"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
echo "== 语法检查"
# 先存输出再检查：用管道的话，pipefail 会让 if 取到 Godot 的非零退出码而判断反了（余烬陷落 1.4 发现）
PARSE_OUT="$("$GODOT" --headless --path "$PROJECT" -s res://tests/parse_all.gd 2>&1)"
PARSE_CODE=$?
if [[ $PARSE_CODE -ne 0 ]] || grep -qE "PARSE FAILED|SCRIPT ERROR" <<<"$PARSE_OUT"; then
  grep -E "PARSE FAILED|SCRIPT ERROR|at: GDScript" <<<"$PARSE_OUT"
  echo "FAIL 语法检查未通过"
  exit 1
fi
echo "PARSE OK"
echo "== 自动化测试"
LOG="$TMP/test.log"
timeout 300 "$GODOT" --headless --path "$PROJECT" res://tests/test_runner.tscn -- "$@" >"$LOG" 2>&1
CODE=$?
grep -vE "^\s*$" "$LOG" | grep -vE "^\s+at: " | grep -E "^== |ok |info |FAIL|SCRIPT ERROR|^ERROR|PASSED|FAILED|WATCHDOG"
exit $CODE

#!/usr/bin/env bash
# 《打工》自动化检查：语法检查 → 自动化测试（全部通过时退出码为 0）。
#   GODOT=/path/to/godot games/working-life/tools/run_tests.sh [测试组 ...]
set -uo pipefail
GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$HERE/godot"
"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
echo "== 语法检查"
if ! "$GODOT" --headless --path "$PROJECT" -s res://tests/parse_all.gd 2>&1 | grep -E "PARSE|SCRIPT ERROR|at: GDScript"; then
  exit 1
fi
"$GODOT" --headless --path "$PROJECT" -s res://tests/parse_all.gd >/dev/null 2>&1 || exit 1
echo "== 自动化测试"
LOG="$(mktemp)"
timeout 1200 "$GODOT" --headless --path "$PROJECT" res://tests/test_runner.tscn -- "$@" >"$LOG" 2>&1
CODE=$?
grep -vE "^\s*$" "$LOG" | grep -vE "^\s+at: " | grep -E "^== |ok |FAIL|SCRIPT ERROR|^ERROR|PASSED|FAILED|WATCHDOG" 
ERRORS=$(grep -cE "SCRIPT ERROR|^ERROR: (?!.*(resources still in use|RID allocations|shaders of type|leaked))" "$LOG" 2>/dev/null || true)
rm -f "$LOG"
exit $CODE

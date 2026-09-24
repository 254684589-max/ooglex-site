#!/usr/bin/env bash
# 《打工》桌面版导出（需要对应平台的 Godot 导出模板）。产物在 games/working-life/build/（不入库）。
#   GODOT=godot games/working-life/tools/build_desktop.sh [macos|windows|linux ...]
# macOS 在非 Mac 主机上只能导出 .zip（内含 WorkingLife.app，ad-hoc 签名）；解压即得 .app。
set -euo pipefail
GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$HERE/godot"
TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then TARGETS=(macos windows linux); fi
"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
for t in "${TARGETS[@]}"; do
  case "$t" in
    macos)
      mkdir -p "$HERE/build/macos"
      "$GODOT" --headless --path "$PROJECT" --export-release "macOS" "$HERE/build/macos/WorkingLife.zip"
      (cd "$HERE/build/macos" && rm -rf ./*.app && unzip -q -o WorkingLife.zip && for a in ./*.app; do [[ "$a" != "./WorkingLife.app" ]] && mv "$a" WorkingLife.app; done)
      echo "macOS：build/macos/WorkingLife.app" ;;
    windows)
      mkdir -p "$HERE/build/windows"
      "$GODOT" --headless --path "$PROJECT" --export-release "Windows" "$HERE/build/windows/WorkingLife.exe"
      echo "Windows：build/windows/WorkingLife.exe" ;;
    linux)
      mkdir -p "$HERE/build/linux"
      "$GODOT" --headless --path "$PROJECT" --export-release "Linux" "$HERE/build/linux/WorkingLife.x86_64"
      echo "Linux：build/linux/WorkingLife.x86_64" ;;
  esac
done

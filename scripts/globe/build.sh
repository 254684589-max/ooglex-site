#!/usr/bin/env bash
# 构建「上帝之眼 · 全球态势地球」（产物输出到 apps/globe/app/）。
#
# 上游：bilawalsidhu/gods-eye-view —— 代码 MIT，数据各自授权。
# 数据来源、许可红线与图层可用性见 docs/GLOBE_INTEGRATION.md。
#
# 本脚本不修改上游仓库，补丁只作用于临时构建目录；不注入任何密钥。
#
# 用法：
#   bash scripts/globe/build.sh                        # 非商业模式（默认）
#   GLOBE_COMMERCIAL=1 bash scripts/globe/build.sh     # 商业模式：删除非商业数据集
#   GLOBE_UPSTREAM_REF=<sha> bash scripts/globe/build.sh
#   GLOBE_BASE=/ bash scripts/globe/build.sh           # 部署到独立域名根目录时
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# 上游固定版本。升级时改这里，并在 docs/GLOBE_INTEGRATION.md 记录版本与验证结果。
UPSTREAM_URL="https://github.com/bilawalsidhu/gods-eye-view"
UPSTREAM_REF="${GLOBE_UPSTREAM_REF:-844c25212c06cfa26ff6c0f3cb82bc9c325f4a85}"

# 站内部署基址：产物挂 www.ooglex.com/apps/globe/app/，中文包装页在 /apps/globe/
BASE="${GLOBE_BASE:-/apps/globe/app/}"

OUT_DIR="$REPO_ROOT/apps/globe/app"
WORK_DIR="${GLOBE_WORK_DIR:-${TMPDIR:-/tmp}/ooglex-globe-build}"
SRC_DIR="$WORK_DIR/src"
DIST="$SRC_DIR/dist-ooglex"

log() { printf '\n\033[1m[globe] %s\033[0m\n' "$*"; }
die() { echo "::error:: $*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. 取上游源码
log "拉取上游 ${UPSTREAM_REF:0:12}"
mkdir -p "$WORK_DIR"
if [ "$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || true)" = "$UPSTREAM_REF" ]; then
  echo "已有匹配版本的检出，重置工作区后复用。"
  git -C "$SRC_DIR" checkout -q -- .    # 丢弃上一轮补丁，保证补丁幂等
else
  rm -rf "$SRC_DIR"
  git init -q "$SRC_DIR"
  git -C "$SRC_DIR" remote add origin "$UPSTREAM_URL"
  GIT_LFS_SKIP_SMUDGE=1 git -C "$SRC_DIR" fetch -q --depth 1 origin "$UPSTREAM_REF"
  git -C "$SRC_DIR" checkout -q FETCH_HEAD
fi
echo "上游版本：$(git -C "$SRC_DIR" rev-parse --short HEAD)"

# ------------------------------------------------------- 2. 许可裁剪（可选）
# TeleGeography 海底电缆为 CC BY-NC-SA 3.0：非商业可用，商业必须删除。
# 依据：上游 DATA_SOURCES.md「TeleGeography is bundled but NonCommercial」。
NC_CABLES="$SRC_DIR/src/data/local_data/telegeography_submarine_cables"
if [ "${GLOBE_COMMERCIAL:-0}" = "1" ]; then
  log "商业模式：移除非商业数据集"
  rm -rf "$NC_CABLES"
  echo "已删除 telegeography_submarine_cables/（CC BY-NC-SA，商业不可用）"
else
  log "非商业模式：保留 CC BY-NC-SA 数据集（仅限个人学习等非商业用途）"
  [ -d "$NC_CABLES" ] && echo "保留 telegeography_submarine_cables/" || echo "上游已无该目录"
fi

# --------------------------------------------------------- 3. 子路径补丁
log "为子路径 $BASE 打补丁"
node "$REPO_ROOT/scripts/globe/patch-base.mjs" "$SRC_DIR" "$BASE"

# ------------------------------------------------------------------ 4. 构建
log "安装依赖"
# --ignore-scripts 跳过 puppeteer/sharp 的二进制下载；构建不需要它们
(cd "$SRC_DIR" && npm install --ignore-scripts --no-audit --no-fund --loglevel=error)

log "构建（base=$BASE，不注入密钥）"
# GOOGLE_MAPS_API_KEY / CESIUM_ION_TOKEN 留空：上游会把这两个值打进浏览器包，
# 留空即满足仓库规则「密钥绝不写入前端」。应用按无密钥模式启动
# （Esri World Imagery，失败自动降级 OSM）。
(cd "$SRC_DIR" && GOOGLE_MAPS_API_KEY= CESIUM_ION_TOKEN= \
  npx vite build --base="$BASE" --outDir dist-ooglex)

# ------------------------------------------------------- 4b. 注入中文化层
# 上游无国际化层，界面文案散落在模板与 JS 里。运行时做一层 DOM 文案映射，
# 避免分叉源码导致每次同步上游都要重做。实现与三条安全约束见该文件头部注释。
log "注入界面中文化层"
cp "$REPO_ROOT/scripts/globe/i18n-zh.js" "$DIST/i18n-zh.js"
python3 - "$DIST/index.html" "$BASE" <<'PYEOF'
import sys, pathlib
page, base = pathlib.Path(sys.argv[1]), sys.argv[2]
html = page.read_text(encoding='utf-8')
tag = f'<script src="{base}i18n-zh.js" defer></script>'
assert tag not in html, '中文化层已注入过'
assert '</body>' in html, '产物 index.html 缺少 </body>，无法注入'
page.write_text(html.replace('</body>', f'  {tag}\n</body>', 1), encoding='utf-8')
print(f'已注入 {tag}')
PYEOF

# ------------------------------------------- 5. 修正 vite-plugin-cesium 的目录
# vite-plugin-cesium 把 Cesium 静态资源拷到 <outDir>/<base>/cesium，
# 而 index.html 引用的是 <base>cesium/。产物根目录下必须是 cesium/。
BASE_NO_SLASH="${BASE%/}"
NESTED="$DIST$BASE_NO_SLASH/cesium"
if [ -d "$NESTED" ]; then
  log "上移 Cesium 资源目录"
  rm -rf "$DIST/cesium"
  mkdir -p "$DIST/cesium"
  mv "$NESTED"/* "$DIST/cesium/"
  rm -rf "$DIST/$(echo "$BASE_NO_SLASH" | cut -d/ -f2)"   # 清掉 base 造成的空壳目录
fi
[ -f "$DIST/cesium/Cesium.js" ] || die "未找到 dist/cesium/Cesium.js，Cesium 目录修正失败。"

# ------------------------------------------------------- 5b. 同源启动与地图回退
log "应用同源启动策略"
node "$REPO_ROOT/scripts/globe/patch-network.mjs" "$DIST" "$BASE"

# ------------------------------------------------------------ 6. 产物自检
log "产物自检"
[ -f "$DIST/index.html" ] || die "产物缺少 index.html。"

# 6a. index.html 内所有本地绝对引用都必须带 base 前缀
bad_html=$(grep -oE '(src|href)="/[^"]*"' "$DIST/index.html" | grep -v "\"$BASE" || true)
[ -z "$bad_html" ] || { echo "$bad_html" >&2; die "index.html 存在未加 base 前缀的绝对引用。"; }

# 6b. 全产物扫描：JS/HTML 里不应残留写死根路径的资产与接口引用
bad_dist=$(grep -rhoE "['\"\`=](/models/|/api/|/(logo|pin|mic|location|visual-presets)\.svg)" \
  "$DIST" --include='*.js' --include='*.html' 2>/dev/null | sort -u || true)
[ -z "$bad_dist" ] || { echo "$bad_dist" >&2; die "产物残留写死的根路径引用，子路径下会 404。"; }

# 6c. 关键静态资源必须真实存在于 base 对应位置
grep -q 'i18n-zh.js' "$DIST/index.html" || die "index.html 未引用中文化层。"
for f in cesium/Cesium.js logo.svg pin.svg mic.svg models/airplane.glb i18n-zh.js; do
  [ -f "$DIST/$f" ] || die "产物缺少被引用的资源 $f。"
done

# 6d. 确认没有密钥被打进包
if grep -rqE '"AIza[0-9A-Za-z_-]{20,}"|eyJhbGciOiJIUzI1NiJ9\.eyJqdGki' "$DIST" --include='*.js' 2>/dev/null; then
  die "产物中检测到疑似 API 密钥/令牌，拒绝输出。"
fi

echo "通过。大小 $(du -sh "$DIST" | cut -f1)，文件数 $(find "$DIST" -type f | wc -l)"

# ------------------------------------------------------------ 7. 输出到仓库
log "写入 $OUT_DIR"
# api/ 下是由 .github/workflows/globe_space_data.yml 定时生成的静态数据快照
# （卫星 TLE、航天任务），不属于构建产物，重建时必须保住。
API_KEEP=""
if [ -d "$OUT_DIR/api" ]; then
  API_KEEP="$WORK_DIR/api-keep"
  rm -rf "$API_KEEP"
  cp -r "$OUT_DIR/api" "$API_KEEP"
  echo "已暂存现有静态数据 api/（$(find "$API_KEEP" -type f | wc -l) 个文件）"
fi
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp -r "$DIST"/. "$OUT_DIR"/
if [ -n "$API_KEEP" ]; then
  cp -r "$API_KEEP" "$OUT_DIR/api"
  echo "已恢复静态数据 api/"
fi
cat > "$OUT_DIR/BUILD_INFO.json" <<INFO
{
  "upstream": "$UPSTREAM_URL",
  "upstreamRef": "$(git -C "$SRC_DIR" rev-parse HEAD)",
  "base": "$BASE",
  "commercialMode": ${GLOBE_COMMERCIAL:-0},
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "keysInjected": false,
  "note": "由 scripts/globe/build.sh 生成，勿手改。数据来源与许可见 docs/GLOBE_INTEGRATION.md。"
}
INFO

log "完成"
echo "产物：$OUT_DIR"
echo "本地预览：npx http-server -p 8899 \"$REPO_ROOT\" → http://127.0.0.1:8899/apps/globe/"

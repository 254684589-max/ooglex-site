#!/usr/bin/env python3
"""为全球态势地球生成卫星与航天任务的静态数据快照。

为什么用静态快照而不是服务端代理：

- 站点是 GitHub Pages 纯静态托管，没有服务端；而 CelesTrak **不发 CORS 头**
  （上游 server/providers/space/celestrak.js 的注释明确写了这一点），浏览器
  无法直连，所以必须由构建期/定时任务取好放成同源静态文件。
- 上游这两个接口都是**透传**：`/api/celestrak/<group>` 返回 TLE 纯文本，
  `/api/launches` 返回 Launch Library 2 的 JSON 原样。因此把文件直接放在
  客户端已经在请求的路径上即可，**不需要改任何客户端代码**。
- 卫星位置由前端 satellite.js 按 TLE 用 SGP4 实时推算，所以 TLE 每日刷新
  一次也足够——星点在图上依然是实时移动的。这正是真实卫星跟踪的做法。

数据写入 apps/globe/app/api/ 下，路径与客户端请求完全一致：
    api/celestrak/stations, visual, gps-ops, glo-ops, galileo, geo
    api/launches

失败处理遵循仓库规则第 13 条：**任何一项抓取失败都保留上一份有效数据**，
绝不用空文件或部分数据覆盖，并把状态写进 apps/globe/status.json 供页面显示。
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
API_DIR = REPO / "apps" / "globe" / "app" / "api"
STATUS_PATH = REPO / "apps" / "globe" / "status.json"

# 与上游 src/layers/satellites/policy.js 的 CelesTrak 分组保持一致（约 840 颗）。
# 注意 GLONASS 的分组名是 glo-ops 而不是 glonass —— 上游注释专门提示过。
# 刻意不取 active 全集（约 1.2 万颗、数MB）：它只被航天任务层当作**可选**的
# 在轨匹配增强（src/layers/launches/source.js 的 "optional active-orbit
# catalog"，失败仅记警告），不值得每天往仓库里塞几 MB。
CELESTRAK_GROUPS = ["stations", "visual", "gps-ops", "glo-ops", "galileo", "geo"]
CELESTRAK_URL = "https://celestrak.org/NORAD/elements/gp.php?GROUP={group}&FORMAT=tle"
LAUNCH_URL = (
    "https://ll.thespacedevs.com/2.3.0/launches/"
    "?net__gte={start}&net__lte={end}&limit=100&mode=detailed"
)
UA = "ooglex-globe-static-snapshot/1.0 (+https://www.ooglex.com/apps/globe/)"
TIMEOUT = 60


def fetch(url: str, token: str | None = None) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    if token:
        req.add_header("Authorization", f"Token {token}")
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status}")
        return resp.read()


def valid_tle(text: str) -> tuple[bool, str]:
    """TLE 必须是 3 行一组，且第 2、3 行以 '1 ' / '2 ' 开头。"""
    lines = [ln.rstrip() for ln in text.strip().splitlines() if ln.strip()]
    if not lines:
        return False, "空响应"
    if len(lines) % 3 != 0:
        return False, f"行数 {len(lines)} 不是 3 的倍数"
    for i in range(1, len(lines), 3):
        if not lines[i].startswith("1 ") or not lines[i + 1].startswith("2 "):
            return False, f"第 {i} 组不是合法 TLE"
    return True, f"{len(lines) // 3} 颗"


def write_if_valid(path: Path, data: bytes, check, reformat=None) -> tuple[bool, str]:
    """校验通过才落盘；失败则保留磁盘上已有的那份（规则第 13 条）。

    `reformat` 可选，在**校验通过之后**对字节做一次等价重排（例如展开 JSON 便于
    git 增量存储）。放在校验之后是刻意的：校验始终针对上游原始响应。
    """
    try:
        ok, detail = check(data)
    except Exception as exc:                      # 解析本身异常也算校验失败
        ok, detail = False, f"校验异常: {exc}"
    if not ok:
        kept = "保留上一份" if path.exists() else "此前也无数据"
        return False, f"{detail}；{kept}"
    if reformat is not None:
        try:
            data = reformat(data)
        except Exception as exc:                  # 重排失败就写原始字节，不因格式丢数据
            detail = f"{detail}（重排失败，按原始字节写入: {exc}）"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True, detail


def main() -> int:
    results: dict[str, dict] = {}
    failures = 0

    # ----------------------------------------------------------- 卫星 TLE
    for group in CELESTRAK_GROUPS:
        target = API_DIR / "celestrak" / group
        try:
            raw = fetch(CELESTRAK_URL.format(group=group))
            ok, detail = write_if_valid(
                target, raw, lambda b: valid_tle(b.decode("utf-8", "replace"))
            )
        except Exception as exc:
            ok, detail = False, f"抓取失败: {exc}；" + (
                "保留上一份" if target.exists() else "此前也无数据"
            )
        results[f"celestrak/{group}"] = {"ok": ok, "detail": detail}
        failures += 0 if ok else 1
        print(f"[{'OK ' if ok else 'FAIL'}] celestrak/{group}: {detail}")

    # ------------------------------------------------------- 航天任务 (LL2)
    # 公开访问限 15 次/小时；本脚本每次只请求 1 次，按天调度绰绰有余。
    # LL2_API_TOKEN 可选，配了额度更高。
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=30)
    url = LAUNCH_URL.format(
        start=start.strftime("%Y-%m-%dT%H:%M:%SZ"), end=end.strftime("%Y-%m-%dT%H:%M:%SZ")
    )
    target = API_DIR / "launches"

    def check_launches(b: bytes) -> tuple[bool, str]:
        payload = json.loads(b.decode("utf-8"))
        rows = payload.get("results")
        if not isinstance(rows, list):
            return False, "响应缺少 results 数组"
        return True, f"{len(rows)} 条发射记录"

    def reformat_launches(b: bytes) -> bytes:
        """按行展开再落盘，纯粹为了 git 的增量存储。

        LL2 的 detailed 响应是**紧凑单行** JSON，约 1MB。单行文件每天换一次，
        git 做不了行级 delta，每次都要存一个全新的 1MB blob —— 相比本仓库其他
        数据文件（多为 1 行级改动）重得多。展开成多行后，每天真正变化的只有少数
        记录对应的那些行，打包时 delta 效果好得多。

        客户端走 response.json()，空白与它无关；HTTP 层有 gzip，展开带来的体积
        增长在传输上基本抵消。刻意不改用 mode=normal 来省空间 —— 那会丢掉载荷与
        箭体回收等细节，是拿功能换空间。
        """
        return (
            json.dumps(json.loads(b.decode("utf-8")), ensure_ascii=False, indent=1)
            + "\n"
        ).encode("utf-8")

    try:
        raw = fetch(url, token=os.environ.get("LL2_API_TOKEN") or None)
        ok, detail = write_if_valid(target, raw, check_launches, reformat_launches)
    except Exception as exc:
        ok, detail = False, f"抓取失败: {exc}；" + (
            "保留上一份" if target.exists() else "此前也无数据"
        )
    results["launches"] = {"ok": ok, "detail": detail}
    failures += 0 if ok else 1
    print(f"[{'OK ' if ok else 'FAIL'}] launches: {detail}")

    # ------------------------------------------------------------- 状态台账
    # 供包装页的「数据来源」面板显示来源与更新时间（仓库规则第 6 条）。
    ok_count = sum(1 for r in results.values() if r["ok"])
    status = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "frequency": "daily",
        "status": "ok" if failures == 0 else ("partial" if ok_count else "error"),
        "demo": False,
        "sources": {
            "celestrak": {
                "name": "CelesTrak",
                "url": "https://celestrak.org",
                "note": "卫星两行根数（TLE）；轨道位置由前端按 SGP4 实时推算，"
                        "所以每日刷新一次不影响星点实时移动",
                "attribution": "CelesTrak (celestrak.org), Dr. T.S. Kelso",
            },
            "launches": {
                "name": "Launch Library 2 — The Space Devs",
                "url": "https://ll.thespacedevs.com",
                "note": "近 30 天发射记录",
                "attribution": "Launch Library 2 — The Space Devs",
            },
        },
        "items": results,
    }
    STATUS_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATUS_PATH.write_text(
        json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print(f"\n汇总：{ok_count}/{len(results)} 项成功，状态 {status['status']}")
    # 全部失败才算任务失败（保留了上一份数据的部分失败不应让工作流变红）
    return 1 if ok_count == 0 else 0


if __name__ == "__main__":
    sys.exit(main())

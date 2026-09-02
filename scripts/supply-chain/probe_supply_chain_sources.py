#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：全球供应链板块的候选数据源在 Actions 机房到底取不取得到、许可能不能用。

这个脚本回答三个问题，一个都不落地到页面：

1. **取不取得到**——候选接口在 Actions 机房是否返回结构合法的数据、末次观测是哪天；
2. **是不是还在更新**——取到了不等于还在更新，逐条报告末次观测日；
3. **许可能不能用**——逐条标注权利方性质（政府作品／国际组织／私营指数），
   私营指数一律标红，不得进入登记清单。

写这个脚本的直接原因写在 `scripts/probe_commodity_sources.py` 顶部：凭印象登记
`B0=F` 实测取不到，一行 unavailable 把整条日更管道标成 degraded。供应链领域的坑
更深——行业最知名的几个指数（波罗的海干散货 BDI、Drewry WCI、Freightos FBX、
ISM 供应商交付）全是商业授权，和仓库已经因许可放弃的 SPX／DXY／LBMA 定盘价同类。
**所以本探针把「许可」和「可取」当作同等的准入条件，两项都过才允许登记。**

与商品探针一样：只读、不写仓库任何数据文件、不改任何清单、密钥只从环境变量读取
且绝不打印、逐个候选独立 try/except、请求之间留间隔、有硬性请求上限。

PortWatch 部分刻意采用「先发现、后探测」：不写死 ArcGIS 服务 ID，而是先读站点的
DCAT 开放数据目录列出真实存在的数据集，再探测其中与港口／咽喉要道相关的图层。
凭印象写死的服务 ID 正是上面那个教训要避免的东西。
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from urllib import error, parse, request

TIMEOUT = 25
GAP = 0.4                 # 逐个请求之间留出间隔，不给对方造成压力
MAX_REQUESTS = 90         # 硬上限：这是探测不是爬取
BODY_LIMIT = 3_000_000    # 目录文件可能较大，但仍然封顶
MIN_POINTS = 2            # 少于两个观测就画不出变化，等同于没有

UA = ("OoglexSupplyChainProbe/1.0 (+https://www.ooglex.com; "
      "read-only source availability and licensing discovery; contact via site)")

# ── 许可性质分级 ────────────────────────────────────────────────────────────
# GOV   美国等政府作品／官方统计，通常可再分发（仍须标注来源）
# IGO   国际组织公开数据（IMF／世行／联合国），一般允许署名再使用
# PRIV  私营指数或商业基准——即使技术上取得到也不得登记，与 SPX/DXY/LBMA 同类
LICENSE_GOV, LICENSE_IGO, LICENSE_PRIV = "GOV", "IGO", "PRIV"

# ── FRED 候选：只要政府作品口径 ──────────────────────────────────────────────
# 频率与末次观测由探测结果决定，这里只登记「想要什么」和「权利方是谁」。
# 标 PRIV 的两条故意留在清单里：它们在 FRED 上确实存在且常被引用，探测结果会
# 显示「取得到」，正因如此更需要在报告里把它们钉死为不可登记，避免以后有人手滑加回来。
FRED_CANDIDATES = [
    # 货运与运输量 · 政府作品
    ("TSIFRGHT", "货运运输服务指数", LICENSE_GOV, "美国交通部 BTS"),
    ("TSIFRGHTC", "货运运输服务指数（可比口径）", LICENSE_GOV, "美国交通部 BTS"),
    ("RAILFRTINTERMODAL", "铁路联运运量", LICENSE_GOV, "待确认权利方，疑为 AAR"),
    # 库存与订单 · 政府作品
    ("ISRATIO", "全行业库存销售比", LICENSE_GOV, "美国普查局"),
    ("RETAILIRSA", "零售业库存销售比", LICENSE_GOV, "美国普查局"),
    ("WHLSLRIRSA", "批发业库存销售比", LICENSE_GOV, "美国普查局"),
    ("MNFCTRIRSA", "制造业库存销售比", LICENSE_GOV, "美国普查局"),
    ("AMTMUO", "制造业未完成订单", LICENSE_GOV, "美国普查局"),
    ("AMTMNO", "制造业新订单", LICENSE_GOV, "美国普查局"),
    # 运输价格 · 政府作品（BLS 生产者价格指数）
    ("PCU483111483111", "远洋货运 PPI", LICENSE_GOV, "美国劳工统计局"),
    ("PCU484121484121", "长途整车公路运输 PPI", LICENSE_GOV, "美国劳工统计局"),
    ("PCU481111481111", "航空运输 PPI", LICENSE_GOV, "美国劳工统计局"),
    ("PCU4831114831112", "远洋货运 PPI（细分口径）", LICENSE_GOV, "美国劳工统计局"),
    # 贸易与产能 · 政府作品
    ("BOPGSTB", "商品与服务贸易差额", LICENSE_GOV, "美国经济分析局"),
    ("IR", "进口价格指数", LICENSE_GOV, "美国劳工统计局"),
    ("IQ", "出口价格指数", LICENSE_GOV, "美国劳工统计局"),
    ("IPG3344S", "半导体及电子元件工业生产", LICENSE_GOV, "美联储 G.17"),
    ("IPMAN", "制造业工业生产", LICENSE_GOV, "美联储 G.17"),
    # 以下两条为私营指数：探测只为留证，永不登记
    ("TRUCKD11", "卡车吨位指数", LICENSE_PRIV, "美国卡车运输协会 ATA · 私营指数"),
    ("FRGSHPUSM649NCIS", "Cass 货运发运量指数", LICENSE_PRIV, "Cass Information Systems · 私营指数"),
]

# ── 世界银行候选：结构层（年频／两年频），沿用 world-economy 已验证的免密钥接口 ──
WORLDBANK_CANDIDATES = [
    ("IS.SHP.GOOD.TU", "集装箱港口吞吐量（TEU）", LICENSE_IGO),
    ("LP.LPI.OVRL.XQ", "物流绩效指数 总分", LICENSE_IGO),
    ("LP.LPI.INFR.XQ", "物流绩效指数 基础设施", LICENSE_IGO),
    ("LP.LPI.TRAC.XQ", "物流绩效指数 追踪能力", LICENSE_IGO),
    ("LP.LPI.TIME.XQ", "物流绩效指数 时效性", LICENSE_IGO),
    ("LP.LPI.CUST.XQ", "物流绩效指数 清关效率", LICENSE_IGO),
    ("NE.IMP.GNFS.ZS", "货物与服务进口占GDP比重", LICENSE_IGO),
    ("NE.EXP.GNFS.ZS", "货物与服务出口占GDP比重", LICENSE_IGO),
    ("TX.VAL.MRCH.CD.WT", "货物出口额", LICENSE_IGO),
    ("TM.VAL.MRCH.CD.WT", "货物进口额", LICENSE_IGO),
]

# ── 纽约联储 GSCPI：全球供应链压力指数，压力层的头号指标 ──────────────────────
# 只探测「页面在不在、数据文件是什么格式」。xlsx 能否用标准库解析直接决定要不要
# 新增依赖——仓库规则不自动装依赖，所以这一项必须在落地前问清楚。
GSCPI_PAGE = "https://www.newyorkfed.org/research/policy/gscpi"
GSCPI_DATA_CANDIDATES = [
    "https://www.newyorkfed.org/medialibrary/research/interactives/gscpi/downloads/gscpi_data.xlsx",
    "https://www.newyorkfed.org/medialibrary/research/interactives/gscpi/downloads/gscpi_data.csv",
]

# ── IMF PortWatch：先发现、后探测 ───────────────────────────────────────────
# 不写死 ArcGIS 服务 ID。ArcGIS Hub 站点统一提供 DCAT 开放数据目录，先把真实存在
# 的数据集列出来，再挑与港口／咽喉要道相关的图层做字段与记录探测。
PORTWATCH_HOST = "https://portwatch.imf.org"
PORTWATCH_CATALOGS = [
    f"{PORTWATCH_HOST}/api/feed/dcat-us/1.1.json",
    f"{PORTWATCH_HOST}/api/feed/dcat-ap/2.1.1.json",
    f"{PORTWATCH_HOST}/api/search/v1/collections/dataset/items?limit=100",
]
# 目录里挑图层用的关键词：命中即认为值得进一步探测字段
PORTWATCH_KEYWORDS = ("chokepoint", "port", "trade", "transit", "vessel", "daily")


class Budget:
    """全局请求预算：防止探测退化成爬取。"""

    def __init__(self, total: int = MAX_REQUESTS) -> None:
        self.left = total

    def spend(self) -> bool:
        if self.left <= 0:
            return False
        self.left -= 1
        return True


BUDGET = Budget()


def _fetch(url: str, accept: str = "*/*") -> tuple[bytes, dict]:
    """发起一次只读请求，返回（正文, 元信息）。超预算或失败都抛异常由调用方接住。"""
    if not BUDGET.spend():
        raise RuntimeError("已达全局请求上限，未发起")
    req = request.Request(url, headers={"User-Agent": UA, "Accept": accept})
    with request.urlopen(req, timeout=TIMEOUT) as response:
        body = response.read(BODY_LIMIT)
        meta = {
            "status": response.status,
            "finalUrl": response.geturl(),
            "contentType": response.headers.get("Content-Type", ""),
            "contentLength": response.headers.get("Content-Length", ""),
            "bytes": len(body),
        }
        return body, meta


def _why(exc: Exception) -> str:
    """把异常压成一行可读原因，不带堆栈也不带正文。"""
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    if isinstance(exc, error.URLError):
        return f"网络失败 {exc.reason}"
    return f"{type(exc).__name__}: {exc}"


# ── FRED ────────────────────────────────────────────────────────────────────
def probe_fred(series_id: str) -> dict:
    """走免密钥的 fredgraph.csv 公开导出，与仓库现有回退路径同一条。"""
    url = f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={parse.quote(series_id)}"
    body, meta = _fetch(url, accept="text/csv,*/*")
    rows = body.decode("utf-8", "replace").strip().splitlines()
    points = []
    for line in rows[1:]:
        parts = line.split(",")
        if len(parts) < 2:
            continue
        date, raw = parts[0].strip(), parts[1].strip()
        if not date or raw in ("", "."):     # FRED 用 "." 表示缺失
            continue
        try:
            points.append((date, float(raw)))
        except ValueError:
            continue
    if len(points) < MIN_POINTS:
        return {"ok": False, "why": f"行情数据点不足（{len(points)}）", "httpBytes": meta["bytes"]}
    return {
        "ok": True,
        "points": len(points),
        "asOf": points[-1][0],
        "latest": points[-1][1],
        "firstObs": points[0][0],
    }


# ── 世界银行 ─────────────────────────────────────────────────────────────────
def probe_worldbank(code: str) -> dict:
    """沿用 world-economy 已验证的免密钥 v2 接口；未知指标会返回 message 而不是数据。"""
    url = (f"https://api.worldbank.org/v2/country/all/indicator/{parse.quote(code)}"
           f"?format=json&mrnev=1&per_page=400")
    body, _ = _fetch(url, accept="application/json")
    payload = json.loads(body.decode("utf-8", "replace"))
    if not isinstance(payload, list) or len(payload) < 2 or not isinstance(payload[1], list):
        note = ""
        if isinstance(payload, list) and payload and isinstance(payload[0], dict):
            messages = payload[0].get("message") or []
            if messages and isinstance(messages[0], dict):
                note = str(messages[0].get("value", ""))[:120]
        return {"ok": False, "why": f"接口未返回数据行 {note}".strip()}
    rows = [r for r in payload[1] if isinstance(r, dict) and r.get("value") is not None]
    if not rows:
        return {"ok": False, "why": "指标存在但没有非空观测"}
    years = sorted({str(r.get("date")) for r in rows if r.get("date")})
    return {
        "ok": True,
        "countries": len(rows),
        "latestYear": years[-1] if years else "",
        "yearSpread": f"{years[0]}~{years[-1]}" if years else "",
        "sample": [
            {"country": (r.get("country") or {}).get("value"), "year": r.get("date"), "value": r.get("value")}
            for r in rows[:3]
        ],
    }


# ── 纽约联储 GSCPI ───────────────────────────────────────────────────────────
def probe_gscpi() -> dict:
    """探测页面与数据文件是否存在，并判断能否用标准库解析（决定要不要新增依赖）。"""
    result: dict = {"page": {}, "files": {}}
    try:
        _, meta = _fetch(GSCPI_PAGE, accept="text/html,*/*")
        result["page"] = {"ok": True, **meta}
    except Exception as exc:                      # noqa: BLE001 — 探测不因单点失败中断
        result["page"] = {"ok": False, "why": _why(exc)}
    time.sleep(GAP)

    for url in GSCPI_DATA_CANDIDATES:
        name = url.rsplit("/", 1)[-1]
        try:
            body, meta = _fetch(url)
            entry = {"ok": True, **meta}
            # xlsx 本质是 zip：能用标准库 zipfile + xml 解析就不必新增依赖。
            if body[:2] == b"PK":
                entry["container"] = "zip(xlsx) · 标准库 zipfile+ElementTree 可解析，无需新增依赖"
            elif body[:1] in (b"<",):
                entry["container"] = "疑似HTML错误页，不是数据文件"
            else:
                head = body[:200].decode("utf-8", "replace").replace("\n", " ")
                entry["container"] = f"文本 · 开头：{head[:120]}"
            result["files"][name] = entry
        except Exception as exc:                  # noqa: BLE001
            result["files"][name] = {"ok": False, "why": _why(exc)}
        time.sleep(GAP)
    return result


# ── IMF PortWatch：先发现目录，再探测图层 ────────────────────────────────────
def discover_portwatch() -> dict:
    """读 ArcGIS Hub 开放数据目录，列出真实存在的数据集及其接口地址。"""
    found: dict = {"catalog": {}, "datasets": []}
    for url in PORTWATCH_CATALOGS:
        try:
            body, meta = _fetch(url, accept="application/json")
            payload = json.loads(body.decode("utf-8", "replace"))
        except Exception as exc:                  # noqa: BLE001
            found["catalog"][url] = {"ok": False, "why": _why(exc)}
            time.sleep(GAP)
            continue
        # DCAT 用 dataset，STAC/OGC 用 features；两种都认。
        entries = payload.get("dataset") or payload.get("features") or []
        found["catalog"][url] = {"ok": True, "datasets": len(entries), **meta}
        for item in entries:
            if not isinstance(item, dict):
                continue
            props = item.get("properties") if "properties" in item else item
            title = str(props.get("title") or props.get("name") or "")
            urls = []
            for dist in props.get("distribution") or []:
                if isinstance(dist, dict) and dist.get("accessURL"):
                    urls.append(str(dist["accessURL"]))
            for link in props.get("links") or []:
                if isinstance(link, dict) and link.get("href"):
                    urls.append(str(link["href"]))
            found["datasets"].append({
                "title": title,
                "identifier": str(props.get("identifier") or props.get("id") or ""),
                "urls": urls[:6],
                "relevant": any(k in title.lower() for k in PORTWATCH_KEYWORDS),
            })
        time.sleep(GAP)
        if found["datasets"]:
            break        # 一个目录够用就不再打第二个
    return found


def _feature_query_url(access_url: str) -> str | None:
    """把目录里的 FeatureServer 地址转成一次最小查询；不是要素服务就返回 None。"""
    match = re.search(r"(https://[^\s\"']*?FeatureServer(?:/\d+)?)", access_url, re.I)
    if not match:
        return None
    base = match.group(1)
    if not re.search(r"/\d+$", base):
        base += "/0"
    return (base + "/query?where=1%3D1&outFields=*&resultRecordCount=3"
                   "&returnGeometry=false&f=json")


def probe_portwatch_layer(query_url: str) -> dict:
    """取三条记录，只报告字段名与样本键，不保存业务数值正文。"""
    body, meta = _fetch(query_url, accept="application/json")
    payload = json.loads(body.decode("utf-8", "replace"))
    if isinstance(payload, dict) and payload.get("error"):
        return {"ok": False, "why": str(payload["error"])[:160]}
    features = payload.get("features") or []
    if not features:
        return {"ok": False, "why": "要素服务可访问但没有返回记录"}
    fields = [f.get("name") for f in (payload.get("fields") or []) if isinstance(f, dict)]
    attrs = features[0].get("attributes") or {}
    # 找出疑似日期字段，用来判断这条管道是不是日频、末次到哪天。
    date_like = [k for k in attrs if re.search(r"date|time|day|period", str(k), re.I)]
    return {
        "ok": True,
        "records": len(features),
        "fieldCount": len(fields) or len(attrs),
        "fields": (fields or list(attrs))[:25],
        "dateFields": date_like[:5],
        "sampleKeys": list(attrs)[:12],
        "bytes": meta["bytes"],
    }


# ── 主流程 ───────────────────────────────────────────────────────────────────
def main() -> None:
    report: dict = {"fred": {}, "worldbank": {}, "gscpi": {}, "portwatch": {}}

    print("── FRED 候选（只要政府作品口径；PRIV 行仅留证，永不登记）"
          " ─────────────────────")
    for series_id, label, license_kind, owner in FRED_CANDIDATES:
        try:
            outcome = probe_fred(series_id)
        except Exception as exc:                  # noqa: BLE001
            outcome = {"ok": False, "why": _why(exc)}
        outcome.update({"label": label, "license": license_kind, "owner": owner})
        report["fred"][series_id] = outcome
        flag = "OK" if outcome.get("ok") else "XX"
        if outcome.get("ok") and license_kind == LICENSE_PRIV:
            flag = "!!"                            # 取得到但不许用，最需要被看见的一类
        detail = (f"末次 {outcome['asOf']}  值 {outcome['latest']}  {outcome['points']} 点"
                  if outcome.get("ok") else outcome.get("why", ""))
        print(f"[{flag}] {series_id:<18} {license_kind:<4} {label:<22} {detail}")
        time.sleep(GAP)

    print("\n── 世界银行候选（结构层，年频／两年频）"
          " ──────────────────────────────────")
    for code, label, license_kind in WORLDBANK_CANDIDATES:
        try:
            outcome = probe_worldbank(code)
        except Exception as exc:                  # noqa: BLE001
            outcome = {"ok": False, "why": _why(exc)}
        outcome.update({"label": label, "license": license_kind})
        report["worldbank"][code] = outcome
        detail = (f"最新 {outcome['latestYear']}  覆盖 {outcome['countries']} 经济体  区间 {outcome['yearSpread']}"
                  if outcome.get("ok") else outcome.get("why", ""))
        print(f"[{'OK' if outcome.get('ok') else 'XX'}] {code:<20} {label:<24} {detail}")
        time.sleep(GAP)

    print("\n── 纽约联储 GSCPI（压力层头号指标）"
          " ──────────────────────────────────────")
    report["gscpi"] = probe_gscpi()
    page = report["gscpi"]["page"]
    print(f"[{'OK' if page.get('ok') else 'XX'}] 页面 "
          + (str(page.get("finalUrl", "")) if page.get("ok") else str(page.get("why", ""))))
    for name, entry in report["gscpi"]["files"].items():
        detail = (f"{entry.get('bytes')} 字节  {entry.get('container','')}"
                  if entry.get("ok") else entry.get("why", ""))
        print(f"[{'OK' if entry.get('ok') else 'XX'}] {name:<20} {detail}")

    print("\n── IMF PortWatch（通道层核心；先发现目录再探测图层）"
          " ─────────────────────")
    discovered = discover_portwatch()
    report["portwatch"] = {"discovery": discovered, "layers": {}}
    for url, entry in discovered["catalog"].items():
        detail = (f"{entry.get('datasets')} 个数据集" if entry.get("ok") else entry.get("why", ""))
        print(f"[{'OK' if entry.get('ok') else 'XX'}] 目录 {url.rsplit('/', 2)[-2]}/{url.rsplit('/', 1)[-1]:<28} {detail}")

    relevant = [d for d in discovered["datasets"] if d["relevant"]]
    print(f"    目录共 {len(discovered['datasets'])} 个数据集，命中关键词 {len(relevant)} 个")
    for item in relevant[:12]:
        print(f"      · {item['title'][:70]}")

    probed = 0
    for item in relevant:
        if probed >= 8:                            # 只探前几个，够判断结构即可
            break
        for access_url in item["urls"]:
            query_url = _feature_query_url(access_url)
            if not query_url:
                continue
            try:
                outcome = probe_portwatch_layer(query_url)
            except Exception as exc:              # noqa: BLE001
                outcome = {"ok": False, "why": _why(exc)}
            outcome["title"] = item["title"]
            report["portwatch"]["layers"][query_url] = outcome
            detail = (f"{outcome['fieldCount']} 字段  日期字段 {outcome.get('dateFields')}"
                      if outcome.get("ok") else outcome.get("why", ""))
            print(f"[{'OK' if outcome.get('ok') else 'XX'}] 图层 {item['title'][:44]:<46} {detail}")
            probed += 1
            time.sleep(GAP)
            break

    # ── 结论 ────────────────────────────────────────────────────────────────
    fred_ok = [k for k, v in report["fred"].items() if v.get("ok") and v["license"] != LICENSE_PRIV]
    fred_blocked = [k for k, v in report["fred"].items() if v.get("ok") and v["license"] == LICENSE_PRIV]
    wb_ok = [k for k, v in report["worldbank"].items() if v.get("ok")]
    pw_ok = [k for k, v in report["portwatch"]["layers"].items() if v.get("ok")]
    gscpi_ok = any(v.get("ok") for v in report["gscpi"]["files"].values())

    print("\n── 结论 ────────────────────────────────────────────────────────────")
    print(f"可登记：FRED 政府口径 {len(fred_ok)}/{len([c for c in FRED_CANDIDATES if c[2] != LICENSE_PRIV])}，"
          f"世界银行 {len(wb_ok)}/{len(WORLDBANK_CANDIDATES)}，"
          f"PortWatch 图层 {len(pw_ok)}，GSCPI 数据文件 {'有' if gscpi_ok else '无'}")
    if fred_blocked:
        print(f"取得到但许可禁止登记（私营指数）：{', '.join(fred_blocked)}")
    print("通道层可行性：" + ("PortWatch 有可用日频图层，按原方案做压力层+通道层"
                             if pw_ok else
                             "PortWatch 未探到可用图层，通道层需降级为月频/年频口径"))

    report["verdict"] = {
        "fredRegistrable": fred_ok,
        "fredLicenseBlocked": fred_blocked,
        "worldbankRegistrable": wb_ok,
        "portwatchLayers": pw_ok,
        "gscpiDataFile": gscpi_ok,
        "chokepointLayerAvailable": bool(pw_ok),
        "requestsSpent": MAX_REQUESTS - BUDGET.left,
    }

    out = os.environ.get("PROBE_OUTPUT")
    if out:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2)
        print(f"报告：{out}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)

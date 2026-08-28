#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建「商品现货与官方指数」数据：从 FRED 读官方公开序列，写 apps/commodities/data.json。

这条管道补的是期货管道补不到的那一半。站内原有的商品行情全部来自 Yahoo 的交易所
期货（日频），而参考站上大量品种——铀、铁矿石、锌、镍、铅、锡、动力煤、棕榈油、
橡胶、羊毛、牛肉、三文鱼——在免费日频源上根本没有代码。它们有官方序列，只是频率
更低：EIA 的现货价是日频/周频，IMF 初级商品价格是月频。

诚实边界（数据与页面都写明）：

- **频率逐条如实标注**。月频就是月频，不当日频用，也不与期货的当日涨跌混着比。
  涨跌一律是「相对该序列自己的上一观测」，不是「今日涨跌」。
- 每条都带来源名、官方链接、数据日与频率；本轮取不到的沿用上一份并标 stale，
  从来没取到过的留空并标 unavailable，不用邻近品种或推断值顶替。
- 本轮全失败则保留上次的 data.json，不用空数据覆盖好数据。

登记进这份清单的每一个代码都在 Actions 机房实测取到过（scripts/probe_commodity_sources.py）。
凭印象登记会让整条管道长期标成 degraded，而页面上一行都不会多。

由 .github/workflows/commodities.yml 每日运行并提交回仓库。FRED_API_KEY 可选：
有则走官方 API，缺失时退到免密钥的 fredgraph.csv 公开导出。
"""
from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timezone
from urllib import error, parse, request

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SCRIPTS_DIR)

from market_data_quality import (  # noqa: E402
    fallback_data_meta,
    make_data_meta,
    summarize_data_quality,
)
from market_history import build_rolling_history  # noqa: E402
from market_source_health import (  # noqa: E402
    load_json as load_health_json,
    make_source_health,
    write_health,
)

OUT_PATH = os.path.join("apps", "commodities", "data.json")
HEALTH_PATH = os.path.join("apps", "commodities", "health.json")
HISTORY_PATH = os.path.join("apps", "commodities", "history.json")

DAILY_POINTS = 400      # 日频/周频序列滚动保留的观测数
MONTHLY_POINTS = 400    # 月频序列滚动保留的观测数（约 33 年）

EIA_SOURCE = "FRED / U.S. EIA"
IMF_SOURCE = "FRED / IMF Primary Commodity Prices"

NOTE = ("商品现货与官方指数：逐条取自 FRED 转发的官方序列——日频/周频现货来自美国能源信息署"
        "（EIA），月频初级商品价格来自国际货币基金组织（IMF）。频率逐条标注，"
        "涨跌一律相对该序列自己的上一观测，不是当日涨跌，也不与交易所期货的日频口径混用。"
        "仅供参考，非投资建议。")
HISTORY_NOTE = ("各序列自身的观测历史，与 data.json 同一次取数、同一来源。日频与月频分开存放，"
                "各自共享一条日期轴；某序列在该日期没有观测即留空，不做前向填充。"
                "本轮未取到的序列沿用上次，不补造新点。")

# ── 序列清单 ─────────────────────────────────────────────────────────────
# (FRED代码, 中文名, 分组, 中文单位, 说明)
# 分组键与行情板的商品二级分组一致：energy / precious / base / grain / soft / livestock / index
SERIES = [
    # —— 能源 ——
    ("DCOILBRENTEU", "布伦特原油现货", "energy", "美元/桶",
     "欧洲布伦特原油现货离岸价，与站内的 ICE 布油期货是现货与期货两个口径"),
    ("DHHNGSP", "亨利港天然气现货", "energy", "美元/百万英热",
     "美国天然气基准现货价，与站内 NYMEX 天然气期货口径不同"),
    ("DPROPANEMBTX", "丙烷现货", "energy", "美元/加仑",
     "德州蒙贝尔维尤丙烷现货，天然气液（NGL）的基准价"),
    ("DJFUELUSGULF", "航空煤油现货", "energy", "美元/加仑",
     "美国墨西哥湾沿岸航空煤油现货价"),
    ("GASREGW", "美国汽油零售均价", "energy", "美元/加仑",
     "全美普通汽油零售均价，含税，是终端零售价而非批发或期货价"),
    ("PCOALAUUSDM", "澳大利亚动力煤", "energy", "美元/吨",
     "纽卡斯尔港动力煤离岸价"),
    ("PNGASJPUSDM", "日本液化天然气", "energy", "美元/百万英热",
     "日本到岸液化天然气价格"),
    ("PURANUSDM", "铀", "energy", "美元/磅",
     "八氧化三铀（U3O8）现货价"),
    # —— 工业金属 ——
    ("PIORECRUSDM", "铁矿石", "base", "美元/吨",
     "中国到岸铁矿石（含铁量62%）价格"),
    ("PNICKUSDM", "镍", "base", "美元/吨", "伦敦金属交易所镍现货价"),
    ("PZINCUSDM", "锌", "base", "美元/吨", "伦敦金属交易所锌现货价"),
    ("PLEADUSDM", "铅", "base", "美元/吨", "伦敦金属交易所铅现货价"),
    ("PTINUSDM", "锡", "base", "美元/吨", "伦敦金属交易所锡现货价"),
    # —— 农产品（油脂与谷物）——
    ("PPOILUSDM", "棕榈油", "grain", "美元/吨", "马来西亚棕榈油价格"),
    ("PSUNOUSDM", "葵花籽油", "grain", "美元/吨", ""),
    ("PROILUSDM", "菜籽油", "grain", "美元/吨", ""),
    ("POLVOILUSDM", "橄榄油", "grain", "美元/吨", ""),
    ("PBARLUSDM", "大麦", "grain", "美元/吨", ""),
    # —— 软商品与林产品 ——
    ("PRUBBUSDM", "天然橡胶", "soft", "美分/磅", ""),
    ("PTEAUSDM", "茶叶", "soft", "美分/公斤", ""),
    ("PBANSOPUSDM", "香蕉", "soft", "美元/吨", ""),
    ("PWOOLCUSDM", "粗羊毛", "soft", "美分/公斤", ""),
    ("PWOOLFUSDM", "细羊毛", "soft", "美分/公斤", ""),
    ("PLOGSKUSDM", "原木", "soft", "美元/立方米", ""),
    ("PSAWMALUSDM", "锯材", "soft", "美元/立方米", ""),
    # —— 畜牧与水产 ——
    ("PBEEFUSDM", "牛肉", "livestock", "美分/磅", ""),
    ("PPORKUSDM", "猪肉", "livestock", "美分/磅", ""),
    ("PPOULTUSDM", "禽肉", "livestock", "美分/磅", ""),
    ("PSALMUSDM", "三文鱼", "livestock", "美元/公斤", ""),
    ("PSHRIUSDM", "虾", "livestock", "美元/公斤", ""),
    ("PFISHUSDM", "鱼粉", "livestock", "美元/吨", ""),
    # —— 商品指数（IMF，2016=100）——
    ("PALLFNFINDEXM", "IMF全部初级商品指数", "index", "指数 2016=100",
     "涵盖能源与非能源初级商品的加权指数，是指数点位而不是任何单一商品价格"),
    ("PNRGINDEXM", "IMF能源指数", "index", "指数 2016=100", "原油、天然气与煤炭的加权指数"),
    ("PMETAINDEXM", "IMF金属指数", "index", "指数 2016=100", "基本金属与铁矿石的加权指数"),
    ("PFOODINDEXM", "IMF食品指数", "index", "指数 2016=100", "谷物、植物油、肉类与海产的加权指数"),
    ("PRAWMINDEXM", "IMF工业原料指数", "index", "指数 2016=100", "木材、棉花、羊毛与橡胶的加权指数"),
]

FREQUENCY_BY_CODE = {"D": "daily", "W": "weekly", "M": "monthly", "BW": "weekly"}
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/123.0 Safari/537.36")
TIMEOUT = 20
GAP = 0.2


def source_of(series_id: str) -> str:
    """EIA 的现货序列以 D/G/W 开头，IMF 初级商品价格一律 P…USDM 或 P…INDEXM。"""
    return IMF_SOURCE if series_id.startswith("P") else EIA_SOURCE


def series_url(series_id: str) -> str:
    return f"https://fred.stlouisfed.org/series/{parse.quote(series_id)}"


def _get_json(url: str) -> dict:
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with request.urlopen(req, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def _get_text(url: str) -> str:
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with request.urlopen(req, timeout=TIMEOUT) as response:
        return response.read().decode("utf-8", "replace")


def fetch_series(series_id: str, limit: int, monthly: bool = False):
    """返回 (按日期升序的 [(date, value)], 频率)。取不到就抛异常，绝不返回占位值。

    monthly=True 时向 FRED 要「按月末聚合」的同一条序列（frequency=m,
    aggregation_method=eop）——这是官方自己做的降采样，不是我们本地折算，
    用来给日频现货补上 5 年 / 10 年 / 25 年 / 全部这几档长区间。
    """
    key = os.environ.get("FRED_API_KEY")
    if key:
        params = {
            "series_id": series_id, "api_key": key, "file_type": "json",
            "sort_order": "desc", "limit": limit,
        }
        if monthly:
            params["frequency"] = "m"
            params["aggregation_method"] = "eop"
        query = parse.urlencode(params)
        payload = _get_json(f"https://api.stlouisfed.org/fred/series/observations?{query}")
        points = [(row["date"], float(row["value"]))
                  for row in payload.get("observations", [])
                  if row.get("value") not in (".", "", None)]
        if len(points) < 2:
            raise ValueError(f"观测点不足（{len(points)}）")
        meta = _get_json("https://api.stlouisfed.org/fred/series?"
                         + parse.urlencode({"series_id": series_id, "api_key": key,
                                            "file_type": "json"}))
        info = (meta.get("seriess") or [{}])[0]
        frequency = FREQUENCY_BY_CODE.get(info.get("frequency_short", ""), "")
        return sorted(points), ("monthly" if monthly else frequency)
    body = _get_text(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={parse.quote(series_id)}")
    points = []
    for line in body.strip().splitlines()[1:]:
        parts = line.split(",")
        if len(parts) >= 2 and parts[1] not in (".", ""):
            points.append((parts[0], float(parts[1])))
    if len(points) < 2:
        raise ValueError(f"观测点不足（{len(points)}）")
    return points[-limit:], ""


def change_pct(current: float, previous: float):
    """相对该序列自己的上一观测的变化（%）；上一观测缺失或为0时返回 None。"""
    if not previous:
        return None
    return round((current / previous - 1.0) * 100, 2)


def build() -> None:
    previous_data = load_previous(OUT_PATH)
    previous_rows = {row.get("id"): row for row in (previous_data or {}).get("series", [])
                     if isinstance(row, dict) and row.get("id")}
    previous_health = load_health_json(HEALTH_PATH)
    run_updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    rows, daily_points, monthly_points, ok, latest = [], {}, {}, 0, ""
    for series_id, name, group, unit, note in SERIES:
        # 月频序列一次取满 400 个月；日频/周频同样 400 个观测（约一年半）。
        want_monthly = series_id.startswith("P")
        limit = MONTHLY_POINTS if want_monthly else DAILY_POINTS
        record = {"id": series_id, "name": name, "group": group, "unit": unit}
        if note:
            record["note"] = note
        try:
            points, reported = fetch_series(series_id, limit)
        except (error.HTTPError, error.URLError, ValueError, KeyError, IndexError) as exc:
            old = previous_rows.get(series_id)
            if old and isinstance(old.get("price"), (int, float)):
                record.update({
                    "price": old.get("price"),
                    "changePct": old.get("changePct"),
                    "previousAsOf": old.get("previousAsOf", ""),
                    "frequency": old.get("frequency", ""),
                    "stale": True,
                    "dataMeta": fallback_data_meta(
                        old, source=source_of(series_id),
                        frequency=old.get("frequency") or "monthly",
                        legacy_updated_at=(previous_data or {}).get("updatedAt")),
                })
                print(f"[==] {name}（{series_id}）本轮失败，沿用上次（stale）：{str(exc)[:50]}")
            else:
                record.update({
                    "price": None, "changePct": None, "previousAsOf": "",
                    "frequency": "monthly" if want_monthly else "daily", "stale": False,
                    "dataMeta": make_data_meta(
                        "unavailable", source_of(series_id), as_of=None,
                        updated_at=run_updated_at,
                        frequency="monthly" if want_monthly else "daily",
                        note="本轮未返回有效观测。"),
                })
                print(f"[XX] {name}（{series_id}）取数失败，留空：{str(exc)[:50]}")
            rows.append(record)
            continue

        as_of, value = points[-1]
        previous_as_of, previous_value = points[-2]
        frequency = reported or ("monthly" if want_monthly else "daily")
        record.update({
            "price": round(value, 6),
            "changePct": change_pct(value, previous_value),
            "previousAsOf": previous_as_of,
            "frequency": frequency,
            "stale": False,
            "dataMeta": make_data_meta(
                "market", source_of(series_id), as_of=as_of,
                updated_at=run_updated_at, frequency=frequency, note=note or None),
        })
        (monthly_points if frequency == "monthly" else daily_points)[series_id] = points
        if frequency != "monthly":
            # 日频/周频序列再取一份官方月末聚合：400 个日观测只有一年半，撑不起
            # 5年/10年/25年/全部这几档。取不到就只是没有长区间，不影响近端。
            try:
                long_points, _ = fetch_series(series_id, MONTHLY_POINTS, monthly=True)
                monthly_points[series_id] = long_points
            except (error.HTTPError, error.URLError, ValueError, KeyError, IndexError) as exc:
                print(f"[..] {name}（{series_id}）月末聚合未取到，仅有近端区间：{str(exc)[:40]}")
            time.sleep(GAP)
        latest = max(latest, as_of)
        ok += 1
        print(f"[OK] {name:<16} {series_id:<14} {as_of}  {value:>14,.4f}  {frequency}")
        rows.append(record)
        time.sleep(GAP)

    if ok == 0:
        health = make_source_health(
            "commodities",
            published_rows=(previous_data or {}).get("series", []),
            attempted_rows=rows,
            attempted_at=run_updated_at,
            published_snapshot_at=(previous_data or {}).get("updatedAt"),
            published=False,
            previous_health=previous_health,
            failure_reason=f"{len(SERIES)}条FRED序列本轮均未返回可发布观测，本轮未发布新快照。",
        )
        write_health(HEALTH_PATH, health)
        print("\n本轮 0 条成功，保留上次的 data.json，不覆盖。")
        return

    quality = summarize_data_quality(rows)
    payload = {
        "updatedAt": run_updated_at,
        "asOf": latest,
        "frequency": "mixed",
        "status": quality["status"],
        "source": "FRED (U.S. EIA / IMF Primary Commodity Prices)",
        "note": NOTE,
        "count": len(rows),
        "series": rows,
        "dataQuality": quality,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
    print(f"\n写入 {OUT_PATH}：{ok}/{len(SERIES)} 条成功，as_of={latest}")

    write_history(daily_points, monthly_points, run_updated_at)
    health = make_source_health(
        "commodities",
        published_rows=rows,
        attempted_rows=rows,
        attempted_at=run_updated_at,
        published_snapshot_at=run_updated_at,
        published=True,
        previous_health=previous_health,
    )
    write_health(HEALTH_PATH, health)


def load_previous(path: str):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def write_history(daily_points, monthly_points, updated_at: str) -> None:
    """日频与月频分开存放：把两种频率压进同一条日期轴会让月频序列几乎全是空位。"""
    previous = load_previous(HISTORY_PATH) or {}
    daily, daily_retained = build_rolling_history(
        daily_points, previous.get("daily") or {}, updated_at,
        source="FRED / U.S. EIA", note=HISTORY_NOTE, limit=DAILY_POINTS)
    monthly, monthly_retained = build_rolling_history(
        monthly_points, previous.get("monthly") or {}, updated_at,
        source=IMF_SOURCE, note=HISTORY_NOTE, limit=MONTHLY_POINTS)
    if not daily and not monthly:
        print(f"本轮无可用序列，保留上次 {HISTORY_PATH}，不覆盖。")
        return
    payload = {
        "updatedAt": updated_at,
        "source": "FRED (U.S. EIA / IMF Primary Commodity Prices)",
        "note": HISTORY_NOTE,
        "daily": daily or previous.get("daily") or {},
        "monthly": monthly or previous.get("monthly") or {},
    }
    with open(HISTORY_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
    retained = len(daily_retained) + len(monthly_retained)
    extra = f"，其中 {retained} 条沿用上次序列" if retained else ""
    print(f"写入 {HISTORY_PATH}：日频 {len((daily or {}).get('series', {}))} 条 / "
          f"月频 {len((monthly or {}).get('series', {}))} 条{extra}")


if __name__ == "__main__":
    build()

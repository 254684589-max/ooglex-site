#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建「各国主权债收益率」数据：写 apps/bonds/data.json。

站内债券品类原本只有两半：美债收益率曲线 11 个期限（日频，FRED），以及 11 只债券
ETF 的份额价格（日频，Yahoo，逐行标着「不是收益率」）。参考站按地区列出的约五十
个国家十年期国债收益率，站内一条都没有。

**频率是这条管道最要紧的一件事。** 免费公开源里各国十年期收益率基本只有月频：

- FRED 转发的 OECD《主要经济指标》长期国债收益率（`IRLTLT01{ISO2}M156N`），月频，
  32 个国家，是本管道的主来源；
- ECB 数据门户（免密钥）补三条 OECD 给不了的：罗马尼亚、口径更新的欧元区月度
  长期利率，以及欧元区 AAA 国债收益率曲线十年点——那是本管道里**唯一**一条
  日频的非美主权收益率。

因此逐行如实标注频率，涨跌一律是「相对该序列自己的上一观测」的基点变化，
绝不写成「当日涨跌」，也绝不与美债曲线的日频当日变动混着比。

登记进 SERIES / ECB_SERIES 的每一个代码都在 Actions 机房实测取到过、且末次观测
确实是近月（scripts/probe_commodity_sources.py，2026-08-29 那一轮）。同一轮实测
拦下的：爱沙尼亚/拉脱维亚/立陶宛/土耳其/保加利亚/克罗地亚/罗马尼亚/巴西/哥伦比亚/
哥斯达黎加/中国/印度/印尼在 OECD 那一族根本不存在（HTTP 400）；冰岛末次观测停在
2022-08、俄罗斯停在 2018-06，取得到但早就不更新了，一律不登记——把一条 2018 年的
观测摆成今天的行情，比不摆更糟。IMF IFS 那一族（`INTGSB…`）12 条取得到，但美国停在
2021、日本/德国/法国/加拿大/印度停在 2017，同样不用。

由 .github/workflows/bonds.yml 每日运行并提交回仓库。FRED_API_KEY 可选：有则走官方
API，缺失时退到免密钥的 fredgraph.csv 公开导出；ECB 数据门户本身不需要任何密钥。
"""
from __future__ import annotations

import csv
import io
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

OUT_PATH = os.path.join("apps", "bonds", "data.json")
HEALTH_PATH = os.path.join("apps", "bonds", "health.json")
HISTORY_PATH = os.path.join("apps", "bonds", "history.json")

MONTHLY_POINTS = 400    # 约 33 年
DAILY_POINTS = 400      # 约一年半

OECD_SOURCE = "FRED / OECD Main Economic Indicators"
ECB_SOURCE = "ECB Data Portal"

NOTE = ("各国十年期国债收益率：主来源为 FRED 转发的 OECD《主要经济指标》长期国债收益率"
        "（月频），欧元区口径与罗马尼亚取自欧洲央行数据门户。除欧元区 AAA 曲线一条为日频外，"
        "其余全部为月频——涨跌一律是相对该序列自己上一观测的基点变化，不是当日变动，"
        "也不与美债收益率曲线的日频口径混用。收益率是年化百分数，不是债券价格。"
        "仅供参考，非投资建议。")
HISTORY_NOTE = ("各序列自身的观测历史，与 data.json 同一次取数、同一来源。日频与月频分开存放，"
                "各自共享一条日期轴；某序列在该日期没有观测即留空，不做前向填充。"
                "本轮未取到的序列沿用上次，不补造新点。")

# ── OECD 十年期国债收益率（FRED 转发，月频）─────────────────────────────
# (FRED代码, 中文名, 英文名, 地区组, 说明)
SERIES = [
    # —— 美洲 ——
    ("IRLTLT01USM156N", "美国10年期国债", "United States", "americas",
     "与站内美债收益率曲线的10年期是同一条资产的两个口径：曲线那条是日频，这条是 OECD 月频"),
    ("IRLTLT01CAM156N", "加拿大10年期国债", "Canada", "americas", ""),
    ("IRLTLT01MXM156N", "墨西哥10年期国债", "Mexico", "americas", ""),
    ("IRLTLT01CLM156N", "智利10年期国债", "Chile", "americas", ""),
    # —— 欧洲 ——
    ("IRLTLT01GBM156N", "英国10年期国债", "United Kingdom", "europe", ""),
    ("IRLTLT01DEM156N", "德国10年期国债", "Germany", "europe", ""),
    ("IRLTLT01FRM156N", "法国10年期国债", "France", "europe", ""),
    ("IRLTLT01ITM156N", "意大利10年期国债", "Italy", "europe", ""),
    ("IRLTLT01ESM156N", "西班牙10年期国债", "Spain", "europe", ""),
    ("IRLTLT01NLM156N", "荷兰10年期国债", "Netherlands", "europe", ""),
    ("IRLTLT01BEM156N", "比利时10年期国债", "Belgium", "europe", ""),
    ("IRLTLT01ATM156N", "奥地利10年期国债", "Austria", "europe", ""),
    ("IRLTLT01CHM156N", "瑞士10年期国债", "Switzerland", "europe", ""),
    ("IRLTLT01SEM156N", "瑞典10年期国债", "Sweden", "europe", ""),
    ("IRLTLT01NOM156N", "挪威10年期国债", "Norway", "europe", ""),
    ("IRLTLT01DKM156N", "丹麦10年期国债", "Denmark", "europe", ""),
    ("IRLTLT01FIM156N", "芬兰10年期国债", "Finland", "europe", ""),
    ("IRLTLT01IEM156N", "爱尔兰10年期国债", "Ireland", "europe", ""),
    ("IRLTLT01PTM156N", "葡萄牙10年期国债", "Portugal", "europe", ""),
    ("IRLTLT01GRM156N", "希腊10年期国债", "Greece", "europe", ""),
    ("IRLTLT01LUM156N", "卢森堡10年期国债", "Luxembourg", "europe", ""),
    ("IRLTLT01PLM156N", "波兰10年期国债", "Poland", "europe", ""),
    ("IRLTLT01CZM156N", "捷克10年期国债", "Czechia", "europe", ""),
    ("IRLTLT01HUM156N", "匈牙利10年期国债", "Hungary", "europe", ""),
    ("IRLTLT01SKM156N", "斯洛伐克10年期国债", "Slovakia", "europe", ""),
    ("IRLTLT01SIM156N", "斯洛文尼亚10年期国债", "Slovenia", "europe", ""),
    # —— 亚洲 ——
    ("IRLTLT01JPM156N", "日本10年期国债", "Japan", "asia", ""),
    ("IRLTLT01KRM156N", "韩国10年期国债", "South Korea", "asia", ""),
    ("IRLTLT01ILM156N", "以色列10年期国债", "Israel", "asia", ""),
    # —— 大洋洲 ——
    ("IRLTLT01AUM156N", "澳大利亚10年期国债", "Australia", "oceania", ""),
    ("IRLTLT01NZM156N", "新西兰10年期国债", "New Zealand", "oceania", ""),
    # —— 非洲 ——
    ("IRLTLT01ZAM156N", "南非10年期国债", "South Africa", "africa", ""),
]

# ── ECB 数据门户（免密钥）─────────────────────────────────────────────────
# (本站内部代码, ECB序列键, 中文名, 英文名, 地区组, 频率, 说明)
ECB_SERIES = [
    ("ECB-RO-10Y", "IRS/M.RO.L.L40.CI.0000.RON.N.Z",
     "罗马尼亚10年期国债", "Romania", "europe", "monthly",
     "OECD 那一族没有罗马尼亚，改用欧洲央行的趋同用长期利率（本币计价）"),
    ("ECB-EA-10Y", "IRS/M.U2.L.L40.CI.0000.EUR.N.Z",
     "欧元区10年期国债", "Euro Area", "europe", "monthly",
     "欧元区整体的趋同用长期利率；FRED 上的同名 OECD 序列已滞后半年以上，改用本条"),
    ("ECB-EA-AAA-10Y", "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_10Y",
     "欧元区AAA国债曲线10年", "Euro Area AAA Curve", "europe", "daily",
     "欧元区 AAA 评级政府债收益率曲线的十年点，是本类里唯一一条日频的非美主权收益率"),
]

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/123.0 Safari/537.36")
TIMEOUT = 25
GAP = 0.2


def fred_series_url(series_id: str) -> str:
    return f"https://fred.stlouisfed.org/series/{parse.quote(series_id)}"


def ecb_series_url(key: str) -> str:
    return f"https://data.ecb.europa.eu/data/datasets/{parse.quote(key.split('/')[0])}"


def _get_json(url: str) -> dict:
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with request.urlopen(req, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def _get_text(url: str) -> str:
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with request.urlopen(req, timeout=TIMEOUT) as response:
        return response.read().decode("utf-8", "replace")


def fetch_fred(series_id: str, limit: int):
    """返回按日期升序的 [(date, value)]。取不到就抛异常，绝不返回占位值。"""
    key = os.environ.get("FRED_API_KEY")
    if key:
        query = parse.urlencode({
            "series_id": series_id, "api_key": key, "file_type": "json",
            "sort_order": "desc", "limit": limit,
        })
        payload = _get_json(f"https://api.stlouisfed.org/fred/series/observations?{query}")
        points = [(row["date"], float(row["value"]))
                  for row in payload.get("observations", [])
                  if row.get("value") not in (".", "", None)]
        if len(points) < 2:
            raise ValueError(f"观测点不足（{len(points)}）")
        return sorted(points)
    body = _get_text(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={parse.quote(series_id)}")
    points = []
    for line in body.strip().splitlines()[1:]:
        parts = line.split(",")
        if len(parts) >= 2 and parts[1] not in (".", ""):
            points.append((parts[0], float(parts[1])))
    if len(points) < 2:
        raise ValueError(f"观测点不足（{len(points)}）")
    return points[-limit:]


def fetch_ecb(key: str, limit: int):
    """ECB 数据门户，免密钥。要 csvdata 而不是 SDMX-JSON：CSV 逐行就是一个观测。

    月频序列的 TIME_PERIOD 是 `YYYY-MM`，为了和站内其他历史共用日期轴，统一补成
    该月首日 `YYYY-MM-01`——补的是格式不是观测，值一个都没动。
    """
    url = (f"https://data-api.ecb.europa.eu/service/data/{key}"
           f"?lastNObservations={limit}&format=csvdata")
    body = _get_text(url)
    reader = csv.DictReader(io.StringIO(body))
    points = []
    for row in reader:
        period = (row.get("TIME_PERIOD") or "").strip()
        raw = (row.get("OBS_VALUE") or "").strip()
        if not period or raw in ("", "."):
            continue
        try:
            value = float(raw)
        except ValueError:
            continue
        if len(period) == 7:
            period = f"{period}-01"
        points.append((period, value))
    if len(points) < 2:
        raise ValueError(f"观测点不足（{len(points)}）")
    return sorted(points)


def change_bp(current: float, previous: float):
    """相对该序列自己上一观测的变化，单位基点：(今 − 上) × 100。

    收益率用基点而不是百分比变化——2.97% 到 3.07% 是「上行10个基点」，
    写成「+3.37%」会被读成价格涨了 3%，那是另一回事。
    """
    if previous is None or current is None:
        return None
    return round((current - previous) * 100, 1)


def load_previous(path: str):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


FETCH_ERRORS = (error.HTTPError, error.URLError, ValueError, KeyError, IndexError, TypeError)


def build() -> None:
    previous_data = load_previous(OUT_PATH)
    previous_rows = {row.get("id"): row for row in (previous_data or {}).get("series", [])
                     if isinstance(row, dict) and row.get("id")}
    previous_health = load_health_json(HEALTH_PATH)
    run_updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    rows, daily_points, monthly_points, ok, latest = [], {}, {}, 0, ""

    plan = [(sid, name, name_en, region, "monthly", note, OECD_SOURCE, None)
            for sid, name, name_en, region, note in SERIES]
    plan += [(sid, name, name_en, region, frequency, note, ECB_SOURCE, key)
             for sid, key, name, name_en, region, frequency, note in ECB_SERIES]

    for series_id, name, name_en, region, frequency, note, source, ecb_key in plan:
        limit = DAILY_POINTS if frequency == "daily" else MONTHLY_POINTS
        record = {"id": series_id, "name": name, "nameEn": name_en,
                  "region": region, "unit": "年化收益率"}
        if note:
            record["note"] = note
        try:
            points = fetch_ecb(ecb_key, limit) if ecb_key else fetch_fred(series_id, limit)
        except FETCH_ERRORS as exc:
            old = previous_rows.get(series_id)
            if old and isinstance(old.get("price"), (int, float)):
                record.update({
                    "price": old.get("price"),
                    "changeBp": old.get("changeBp"),
                    "previousAsOf": old.get("previousAsOf", ""),
                    "frequency": old.get("frequency", frequency),
                    "stale": True,
                    "dataMeta": fallback_data_meta(
                        old, source=source, frequency=old.get("frequency") or frequency,
                        legacy_updated_at=(previous_data or {}).get("updatedAt")),
                })
                print(f"[==] {name}（{series_id}）本轮失败，沿用上次（stale）：{str(exc)[:50]}")
            else:
                record.update({
                    "price": None, "changeBp": None, "previousAsOf": "",
                    "frequency": frequency, "stale": False,
                    "dataMeta": make_data_meta(
                        "unavailable", source, as_of=None, updated_at=run_updated_at,
                        frequency=frequency, note="本轮未返回有效观测。"),
                })
                print(f"[XX] {name}（{series_id}）取数失败，留空：{str(exc)[:50]}")
            rows.append(record)
            continue

        as_of, value = points[-1]
        previous_as_of, previous_value = points[-2]
        record.update({
            "price": round(value, 4),
            "changeBp": change_bp(value, previous_value),
            "previousAsOf": previous_as_of,
            "frequency": frequency,
            "stale": False,
            "dataMeta": make_data_meta(
                "market", source, as_of=as_of, updated_at=run_updated_at,
                frequency=frequency, note=note or None),
        })
        (daily_points if frequency == "daily" else monthly_points)[series_id] = points
        latest = max(latest, as_of)
        ok += 1
        print(f"[OK] {name:<18} {series_id:<18} {as_of}  {value:>8.4f}%  {frequency}")
        rows.append(record)
        time.sleep(GAP)

    if ok == 0:
        health = make_source_health(
            "bonds",
            published_rows=(previous_data or {}).get("series", []),
            attempted_rows=rows,
            attempted_at=run_updated_at,
            published_snapshot_at=(previous_data or {}).get("updatedAt"),
            published=False,
            previous_health=previous_health,
            failure_reason=f"{len(plan)}条主权债序列本轮均未返回可发布观测，本轮未发布新快照。",
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
        "source": "FRED (OECD Main Economic Indicators) / ECB Data Portal",
        "note": NOTE,
        "count": len(rows),
        "series": rows,
        "dataQuality": quality,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
    print(f"\n写入 {OUT_PATH}：{ok}/{len(plan)} 条成功，as_of={latest}")

    write_history(daily_points, monthly_points, run_updated_at)
    health = make_source_health(
        "bonds",
        published_rows=rows,
        attempted_rows=rows,
        attempted_at=run_updated_at,
        published_snapshot_at=run_updated_at,
        published=True,
        previous_health=previous_health,
    )
    write_health(HEALTH_PATH, health)


def write_history(daily_points, monthly_points, updated_at: str) -> None:
    """日频与月频分开存放：把两种频率压进同一条日期轴会让月频序列几乎全是空位。"""
    previous = load_previous(HISTORY_PATH) or {}
    daily, daily_retained = build_rolling_history(
        daily_points, previous.get("daily") or {}, updated_at,
        source=ECB_SOURCE, note=HISTORY_NOTE, limit=DAILY_POINTS)
    monthly, monthly_retained = build_rolling_history(
        monthly_points, previous.get("monthly") or {}, updated_at,
        source=OECD_SOURCE, note=HISTORY_NOTE, limit=MONTHLY_POINTS)
    if not daily and not monthly:
        print(f"本轮无可用序列，保留上次 {HISTORY_PATH}，不覆盖。")
        return
    payload = {
        "updatedAt": updated_at,
        "source": "FRED (OECD Main Economic Indicators) / ECB Data Portal",
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

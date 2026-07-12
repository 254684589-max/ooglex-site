#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球主要国家房价走势」→ apps/house-prices/data.json。

数据源（免密钥、机房可达）：
  · 主源 OECD 分析性房价指数（Analytical house prices，季度，名义/实际，2015=100）
  · 备源 BIS 住宅物业价格长序列（WS_LONG_PP）
房价本质是季度数据，本脚本每日运行、自动接住各国最新已发布季度并算同比/环比与趋势序列。

稳健性（沿用本仓库风格）：
  · 纯 requests + 硬超时；SDMX-JSON 通用解析（不写死维度顺序，靠结构元数据识别名义/实际指数）；
  · 逐国独立：OECD/BIS 都取不到的国家，回退沿用上次 data.json 的值 → 内置种子，绝不掉榜；
  · 全源失败则保留上次 data.json、或输出种子（标 seed），绝不空榜。首次接入前用近似种子占位。
  · 首轮会打印各源发现的维度/量度，便于据线上 Actions 日志核对与微调。
由 .github/workflows/house_prices.yml 每日运行并提交回仓库。
"""
import json
import os
import sys
from datetime import datetime, timezone

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from countries import REGIONS, SEED, OVERRIDE  # noqa: E402

OUT_PATH = os.path.join("apps", "house-prices", "data.json")
ISO_SET = {r[2] for r in SEED}
UA = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                     "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")}
START = "2005-Q1"          # 取近 20 年历史（各国实际起点视 OECD 覆盖而定）

# OECD 分析性房价指数：多个候选 flowRef（版本/名称可能微调，逐个尝试）
OECD_FLOWS = [
    "OECD.ECO.MPD,DSD_AN_HOUSE_PRICES@DF_HOUSE_PRICES,1.0",
    "OECD.ECO.MPD,DSD_AN_HOUSE_PRICES@DF_HOUSE_PRICES,1.1",
    "OECD.ECO.MPD,DSD_AN_HOUSE_PRICES@DF_HOUSE_PRICES",
]
OECD_BASE = "https://sdmx.oecd.org/public/rest/data/"
# BIS 住宅物业价格长序列（备源）
BIS_FLOW = "BIS,WS_LONG_PP,1.0"
BIS_BASE = "https://stats.bis.org/api/v1/data/"


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


# ————————————————————— 通用 SDMX-JSON 解析 —————————————————————
def sdmx_get(url):
    """取 SDMX-JSON（AllDimensions），返回 (dims, observations) 或 None。"""
    try:
        r = requests.get(url, headers={**UA, "Accept": "application/vnd.sdmx.data+json"}, timeout=40)
        if r.status_code != 200 or not r.text:
            print(f"[..] {r.status_code} {url[:90]}")
            return None
        js = r.json()
    except Exception as e:
        print(f"[..] 请求失败 {str(e)[:60]}")
        return None
    struct = (js.get("data", {}).get("structures") or [None])[0] or js.get("structure")
    dsets = js.get("data", {}).get("dataSets") or js.get("dataSets")
    if not struct or not dsets:
        return None
    dims = (struct.get("dimensions") or {}).get("observation") or []
    dims = sorted(dims, key=lambda d: d.get("keyPosition", 0)) if any("keyPosition" in d for d in dims) else dims
    obs = (dsets[0] or {}).get("observations") or {}
    return dims, obs


def parse_series(dims, obs):
    """把 SDMX 观测解析为 {iso: {combo: [(period, value)...]}}，combo 为量度维度组合的可读串。"""
    idx_area = idx_time = None
    dim_ids = [d.get("id", "") for d in dims]
    for i, d in enumerate(dims):
        did = d.get("id", "").upper()
        if did in ("REF_AREA", "LOCATION", "COUNTRY", "AREA"):
            idx_area = i
        if did in ("TIME_PERIOD", "TIME"):
            idx_time = i
    if idx_area is None or idx_time is None:
        print(f"[!!] 维度里找不到国家/时间：{dim_ids}")
        return {}
    # 量度维度 = 除国家/时间/频率外的其它维度
    meas_dims = [i for i, d in enumerate(dims)
                 if i not in (idx_area, idx_time) and d.get("id", "").upper() not in ("FREQ", "FREQUENCY")]
    out = {}
    for key, val in obs.items():
        parts = key.split(":")
        if len(parts) != len(dims):
            continue
        try:
            area = dims[idx_area]["values"][int(parts[idx_area])]["id"]
        except Exception:
            continue
        if area not in ISO_SET:
            continue
        try:
            period = dims[idx_time]["values"][int(parts[idx_time])]["id"]
            v = val[0] if isinstance(val, list) else val
            if v is None:
                continue
            v = float(v)
        except Exception:
            continue
        combo = "|".join(
            (dims[i]["values"][int(parts[i])].get("id", "") + "~" +
             dims[i]["values"][int(parts[i])].get("name", "")) for i in meas_dims)
        out.setdefault(area, {}).setdefault(combo, []).append((period, v))
    return out


NEG = ("real", "实际", "rent", "income", "ratio", "growth", "yoy", "percentage change",
       "price to", "price-to", "affordab")


def pick_series(combos, want_real=False):
    """从一国的所有量度组合里挑出「名义/实际 房价指数」季度序列。"""
    best, best_score = None, -1e9
    for combo, pts in combos.items():
        if len(pts) < 6:
            continue
        low = combo.lower()
        vals = [v for _, v in pts]
        med = sorted(vals)[len(vals) // 2]
        score = 0.0
        has_real = ("real" in low) or ("实际" in low)
        if want_real:
            score += 40 if has_real else -40
        else:
            score += -40 if has_real else 10
        if any(k in low for k in NEG if k not in ("real", "实际")):
            score -= 60                              # 排除 租金/收入比/增长率 等
        if ("index" in low) or ("指数" in low) or ("ix" == combo.split("~")[0].lower()):
            score += 20
        if 20 <= med <= 6000:                        # 像指数量级（含高通胀国家）
            score += 15
        else:
            score -= 30
        score += min(len(pts), 60) * 0.1             # 序列越长越好
        if score > best_score:
            best, best_score = pts, score
    return best


def q_shift(period, dq):
    """季度标签平移：'2025-Q4' + dq 季 → '2026-Q1'。非季度格式返回 None。"""
    try:
        y, q = period.split("-Q")
        n = int(y) * 4 + (int(q) - 1) + dq
        return f"{n // 4}-Q{n % 4 + 1}"
    except Exception:
        return None


def series_metrics(pts):
    """由名义指数季度序列算 最新指数/同比/环比/趋势（近 16 季）。
    同比/环比按「真实季度标签」对齐（上一季 / 去年同季），序列有缺季也不会算错。"""
    s = sorted(pts, key=lambda x: x[0])
    period, idx = s[-1]
    by_p = {p: v for p, v in s}
    prev1 = by_p.get(q_shift(period, -1))
    prev4 = by_p.get(q_shift(period, -4))
    if prev1 is None and len(s) > 1:                 # 缺季兜底：退回相邻观测
        prev1 = s[-2][1]
    yoy = round((idx / prev4 - 1) * 100, 1) if prev4 else None
    qoq = round((idx / prev1 - 1) * 100, 1) if prev1 else None
    trend = [{"p": p, "v": round(v, 1)} for p, v in s]     # 全历史序列（供展开的长期走势图）
    return period, round(idx, 1), yoy, qoq, trend


def real_yoy(rl_pts, period):
    """实际同比：在名义序列的最新季度 period 上对齐计算（与名义同一时间窗口）；
    若实际序列缺该季，则退回实际序列自身最新季度。避免名义/实际口径错位导致的失真。"""
    by = {p: v for p, v in rl_pts}
    def at(pp):
        now, prev = by.get(pp), by.get(q_shift(pp, -4))
        return round((now / prev - 1) * 100, 1) if (now and prev) else None
    r = at(period)
    if r is None:
        s = sorted(rl_pts)
        if s:
            r = at(s[-1][0])
    return r


def fetch_source(base, flows, label):
    """尝试一个数据源的多个 flowRef，返回首个成功解析的 {iso:{combo:[...]}}。"""
    flows = flows if isinstance(flows, list) else [flows]
    for flow in flows:
        url = f"{base}{flow}/all?startPeriod={START}&dimensionAtObservation=AllDimensions"
        got = sdmx_get(url)
        if not got:
            continue
        series = parse_series(*got)
        if series:
            print(f"[OK] {label} 命中 flow={flow.split(',')[1].split('@')[0]}，覆盖 {len(series)} 国")
            # 首轮诊断：打印一个样例国家的可用量度组合，便于核对
            sample = next(iter(series))
            print(f"     样例 {sample} 量度组合：" +
                  " ; ".join(list(series[sample].keys())[:6])[:400])
            return series
    print(f"[XX] {label} 全部候选失败")
    return {}


# ————————————————————— 主流程 —————————————————————
def curated_metrics(anchors, cpi):
    """由「历年名义同比」锚点复原季度指数序列（2015=100 归一），返回与 OECD 同口径的指标。
    用于 OECD 未收录 / 口径失真的经济体改用其官方指数（中国 70 城、香港差饷署等）。"""
    now = datetime.now(timezone.utc)
    end = q_shift(f"{now.year}-Q{(now.month - 1) // 3 + 1}", -1)   # 最新已发布季度（滞后一季）
    quarters, p = [], "2010-Q4"
    while p <= end:
        quarters.append(p); p = q_shift(p, 1)
    last_yr = max(anchors)
    raw, v = [], 100.0
    for i, p in enumerate(quarters):
        yr = int(p.split("-Q")[0])
        yoy = anchors.get(yr, anchors[last_yr])
        if i:
            v *= (1 + yoy / 100.0) ** 0.25
        raw.append(v)
    base = [raw[i] for i, p in enumerate(quarters) if p.startswith("2015")]
    norm = (sum(base) / len(base)) if base else raw[0]
    series = [(p, raw[i] / norm * 100) for i, p in enumerate(quarters)]
    by = {p: val for p, val in series}
    last_p, last_v = series[-1]
    y, q1 = by.get(q_shift(last_p, -4)), by.get(q_shift(last_p, -1))
    yoy = round((last_v / y - 1) * 100, 1) if y else None
    qoq = round((last_v / q1 - 1) * 100, 1) if q1 else None
    real = round(yoy - cpi, 1) if yoy is not None else None
    trend = [{"p": p, "v": round(val, 1)} for p, val in series]
    return last_p, round(last_v, 1), yoy, real, qoq, trend


def synth_trend(idx, yoy):
    """种子/兜底：据 最新指数 与 名义同比 合成近 20 年（80 季）近似序列（平滑回推），标注为种子。"""
    q = (1 + (yoy or 0) / 100.0) ** 0.25            # 由同比折算季度增速
    out, v = [], idx
    yr = datetime.now(timezone.utc).year
    qn = (datetime.now(timezone.utc).month - 1) // 3 + 1
    seq = []
    for _ in range(80):
        seq.append((f"{yr}-Q{qn}", round(v, 1)))
        v = v / q
        qn -= 1
        if qn == 0:
            qn = 4; yr -= 1
    for p, val in reversed(seq):
        out.append({"p": p, "v": val})
    return out


def build():
    prev = load_json(OUT_PATH)
    prev_rows = {c["iso"]: c for c in (prev or {}).get("countries", []) if c.get("iso")}

    oecd = fetch_source(OECD_BASE, OECD_FLOWS, "OECD")
    bis = fetch_source(BIS_BASE, BIS_FLOW, "BIS") if len(oecd) < len(ISO_SET) else {}

    countries, as_of, live_n = [], "", 0
    for zh, en, iso, flag, region, idx0, yoy0, real0, qoq0 in SEED:
        rec = {"name": zh, "nameEn": en, "iso": iso, "flag": flag, "region": region,
               "base": "2015=100"}
        used_live = False
        ov = OVERRIDE.get(iso)
        if ov:                                          # 官方指数覆盖（中国 70 城 / 香港差饷署 等）
            period, idx, yoy, real, qoq, trend = curated_metrics(ov["yoy"], ov["cpi"])
            rec.update({"index": idx, "yoyNominal": yoy, "yoyReal": real, "qoq": qoq,
                        "asOf": period, "trend": trend, "src": ov["src"]})
            as_of = max(as_of, period); live_n += 1; used_live = True
        src = oecd.get(iso) or bis.get(iso)
        if not used_live and src:
            nom = pick_series(src, want_real=False)
            rl = pick_series(src, want_real=True)
            if nom:
                period, idx, yoy, qoq, trend = series_metrics(nom)
                real = real_yoy(rl, period) if rl else None
                # 合理性护栏：隐含通胀(名义-实际)超出常识区间 → 判为口径/对齐异常，宁可留空也不展示错误值
                if real is not None and yoy is not None:
                    impl = yoy - real
                    if impl > (40 if iso == "TUR" else 9) or impl < -3:
                        print(f"[!!] {iso} 实际同比疑异常(名义{yoy}/实际{real}/隐含通胀{impl:.1f})，置空")
                        real = None
                rec.update({"index": idx, "yoyNominal": yoy, "yoyReal": real, "qoq": qoq,
                            "asOf": period, "trend": trend, "src": "OECD 分析性房价指数"})
                as_of = max(as_of, period); live_n += 1; used_live = True
        if not used_live:
            old = prev_rows.get(iso)
            if old and old.get("yoyNominal") is not None and not old.get("seed"):
                rec.update({k: old.get(k) for k in ("index", "yoyNominal", "yoyReal", "qoq", "asOf", "trend")})
                rec["stale"] = True
            else:                                     # 内置种子
                rec.update({"index": idx0, "yoyNominal": yoy0, "yoyReal": real0, "qoq": qoq0,
                            "asOf": "近期", "trend": synth_trend(idx0, yoy0), "seed": True})
        countries.append(rec)

    # 名义同比降序（最热在前）；同比缺失垫底
    countries.sort(key=lambda c: (c.get("yoyNominal") if c.get("yoyNominal") is not None else -1e9), reverse=True)
    for i, c in enumerate(countries, 1):
        c["rank"] = i

    all_seed = live_n == 0
    if all_seed and prev and not (prev.get("seed", True)):
        print("本轮 OECD/BIS 全失败，保留上次 data.json（含真实数据），不覆盖。")
        return

    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": as_of or "近期",
        "source": ("OECD 分析性房价指数 · 各国官方统计（中国国家统计局 70 城 / 香港差饷署 等）· BIS（每周自动刷新）"
                   if not all_seed else "最近公布近似值（示例）· 待 OECD/BIS 每周刷新"),
        "seed": all_seed,
        "count": len(countries),
        "liveCount": live_n,
        "regions": REGIONS,
        "note": ("全球主要国家住宅房价指数（名义/实际同比、环比与近 20 年季度走势）。多数国家采用 OECD 分析性房价指数"
                 "（跨国可比、口径一致）；OECD 未收录或口径差异较大的经济体改用其官方指数——中国用国家统计局 70 城"
                 "新建商品住宅价格指数、香港用差饷物业估价署售价指数、新加坡用 URA 指数等。每周自动刷新，名义为当地"
                 "货币现价、实际为经通胀调整，基期统一 2015=100。各国统计口径仍略有差异，仅供参考，不构成投资建议。"),
        "countries": countries,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{len(countries)} 国（实时 {live_n}），as_of={data['asOf']}，seed={all_seed}")


if __name__ == "__main__":
    build()

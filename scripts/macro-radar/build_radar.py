#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「宏观雷达 · Macro Radar」数据：

- 跨资产热力图：Yahoo Finance 免登录行情（1D/1W/1M/3M/YTD 收益）；
- 8 大制度信号（0–100，越高越"宽松·支持"），Yahoo 免 key + FRED（需 key，缺则降级）：
    流动性  = 3M 短端利率(^IRX) —— 代理货币政策松紧
    波动率  = VIX 及其期限结构(^VIX / ^VIX3M)
    期限溢价 = 收益率曲线 10Y−3M(^TNX − ^IRX) —— 期限结构代理
    实际利率 = 5Y TIPS 实际收益率(DFII5, FRED) —— 久期资产贴现率
    信用    = 高收益/投资级比价(HYG ÷ LQD) —— 信用风险偏好代理
    增长    = 铜金比(HG=F / GC=F) —— 增长动能代理
    美元    = 美元指数(DX-Y.NYB) + 离岸/在岸人民币基差
    广度    = 等权/市值加权(RSP / SPY) —— 市场广度代理
- 综合机制读数 = 8 个信号加权平均；
- 异动流：从当日读数/穿越阈值自动生成（非人工编写）。

注：FRED通过官方API读取并使用 FRED_API_KEY；EIA优先使用带 EIA_API_KEY 的API v2，
密钥缺失或接口失败时改读同一RWTC标的的EIA公开日频历史页。各项独立降级。
信用、期限、流动性仍保留上述市场化Yahoo代理指标作为部分场景的回退。

设计原则：每个数据源独立 try，单点失败只降级该项、不拖垮整份文件；
整源全挂时保留上次有效数据；日志不得输出API密钥或带密钥的请求URL。
由 .github/workflows/macro_radar.yml 每日定时运行并提交回仓库。
"""
import copy
import json
import math
import os
import re
import sys
import time
from datetime import datetime, timezone, timedelta
from html.parser import HTMLParser

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SCRIPTS_DIR)
from macro_source_health import (  # noqa: E402
    load_json as load_health_json,
    make_macro_health,
    write_macro_health,
)

OUT_PATH = os.path.join("apps", "macro-radar", "data.json")
DGS10_ID = "DGS10"
DGS10_SOURCE = {
    "name": "FRED / Federal Reserve H.15",
    "url": "https://fred.stlouisfed.org/series/DGS10",
    "seriesId": DGS10_ID,
}
DTWEXBGS_ID = "DTWEXBGS"
DTWEXBGS_SOURCE = {
    "name": "FRED / Federal Reserve H.10",
    "url": "https://fred.stlouisfed.org/series/DTWEXBGS",
    "seriesId": DTWEXBGS_ID,
}
RWTC_ID = "RWTC"
RWTC_SOURCE = {
    "name": "U.S. EIA / Cushing WTI Spot",
    "url": "https://www.eia.gov/dnav/pet/hist/rwtcd.htm",
    "seriesId": RWTC_ID,
}
EIA_API_URL = "https://api.eia.gov/v2/petroleum/pri/spt/data/"
EIA_HISTORY_URL = "https://www.eia.gov/dnav/pet/hist/RWTCD.htm"
HEALTH_PATH = os.path.join("apps", "macro-radar", "health.json")
UA = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                     "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")}
WIN = 504    # 分位窗口 ≈ 两年「日频」交易日（VIX/OAS/曲线/汇率/比价等日频序列）
WIN_W = 104  # 分位窗口 ≈ 两年「周频」（净流动性 WALCL 等周报序列；504 会拉成≈10 年）



# ── 取数：Yahoo 日线 ────────────────────────────────────────────────────
def yahoo_series(symbols, rng="2y"):
    """返回按时间升序的 [(date_str, close_float), ...]；失败返回 []。"""
    syms = symbols if isinstance(symbols, (list, tuple)) else [symbols]
    for sym in syms:
        for host in ("query1", "query2"):
            url = ("https://%s.finance.yahoo.com/v8/finance/chart/%s"
                   "?range=%s&interval=1d" % (host, sym, rng))
            try:
                r = requests.get(url, headers=UA, timeout=20)
                if r.status_code != 200:
                    continue
                res = (r.json().get("chart") or {}).get("result") or []
                if not res:
                    continue
                res = res[0]
                ts = res.get("timestamp") or []
                closes = (((res.get("indicators") or {}).get("quote") or [{}])[0]
                          .get("close") or [])
                out = []
                for t, c in zip(ts, closes):
                    if c is None:
                        continue
                    d = datetime.fromtimestamp(t, tz=timezone.utc).strftime("%Y-%m-%d")
                    out.append((d, float(c)))
                if len(out) >= 5:
                    return out
            except Exception:
                continue
        time.sleep(0.2)
    return []


# ── 工具 ────────────────────────────────────────────────────────────────
def pct_rank(values, x=None, win=WIN):
    """x 在 values（尾部窗口）中的百分位 0–100；x 缺省取最后一个。
    win 缺省 WIN(≈2 年日频)；周频/月频序列须显式传入对应点数（如净流动性用
    WIN_W=104），否则 504 点窗口会把周频拉成≈10 年、与方法学的『2 年分位』不符。"""
    w = [v for v in values[-win:] if v is not None]
    if not w:
        return None
    x = w[-1] if x is None else x
    below = sum(1 for v in w if v <= x)
    return round(100.0 * below / len(w), 1)






def align_ratio(a, b):
    """按日期对齐两条序列，返回比值序列 [(d, a/b), ...] 升序。"""
    mb = dict(b)
    out = []
    for d, va in a:
        vb = mb.get(d)
        if vb:
            out.append((d, va / vb))
    return out


def align_diff(a, b):
    """按日期对齐两条序列，返回差值序列 [(d, a-b), ...] 升序。"""
    mb = dict(b)
    out = []
    for d, va in a:
        vb = mb.get(d)
        if vb is not None:
            out.append((d, va - vb))
    return out


def spark(series, n=40):
    """取尾部序列的数值，降采样到 ~n 点，供前端画迷你曲线。"""
    vals = [v for _, v in series][-max(n * 3, 120):]
    if not vals:
        return []
    step = max(1, len(vals) // n)
    return [round(v, 4) for v in vals[::step]][-n:]


def status_of(score):
    if score is None:
        return "neutral", "—"
    if score < 40:
        return "stress", "承压"
    if score <= 60:
        return "neutral", "中性"
    return "support", "支持"


# ── 宏观管道（FRED 官方 API，需 FRED_API_KEY；折叠分组呈现）────────────────
# 每类一组；序列 = (FRED series_id, 中文名, 单位类型 pct/usd_m/usd_b/idx)。
FRED_CATS = [
    ("利率走廊", "POLICY RATES", [
        ("DFF", "联邦基金有效利率", "pct"),
        ("SOFR", "SOFR 担保隔夜融资利率", "pct"),
        ("IORB", "准备金利率 (IORB)", "pct"),
        ("DFEDTARU", "联邦基金目标上限", "pct"),
        ("DFEDTARL", "联邦基金目标下限", "pct"),
        ("DPCREDIT", "贴现窗口一级信贷利率", "pct"),
    ]),
    ("联储流动性", "FED LIQUIDITY", [
        ("WALCL", "美联储总资产", "usd_m"),
        ("WRESBAL", "准备金余额", "usd_m"),
        ("WTREGEN", "财政部一般账户 (TGA)", "usd_m"),
        ("RRPONTSYD", "隔夜逆回购用量 (RRP)", "usd_b"),
    ]),
    ("实际利率与通胀预期", "RATES & INFLATION", [
        ("DGS10", "10 年期美债收益率", "pct"),
        ("DFII5", "5 年期 TIPS 实际收益率", "pct"),
        ("DFII10", "10 年期 TIPS 实际收益率", "pct"),
        ("T10YIE", "10 年盈亏平衡通胀预期", "pct"),
        ("T5YIE", "5 年盈亏平衡通胀预期", "pct"),
        ("T5YIFR", "5 年 5 年远期通胀预期", "pct"),
    ]),
    ("期限结构与利差", "TERM STRUCTURE", [
        ("DGS2", "2 年期美债收益率", "pct"),
        ("DGS30", "30 年期美债收益率", "pct"),
        ("T10Y2Y", "10Y−2Y 期限利差", "pct"),
        ("T10Y3M", "10Y−3M 期限利差", "pct"),
        ("THREEFYTP10", "10Y 期限溢价 (ACM/KW)", "pct"),
    ]),
    ("金融压力", "FINANCIAL STRESS", [
        ("NFCI", "芝加哥联储金融状况指数", "idx"),
        ("ANFCI", "调整后金融状况指数", "idx"),
        ("STLFSI4", "圣路易斯联储金融压力指数", "idx"),
    ]),
    ("信用利差", "CREDIT SPREADS", [
        ("BAMLH0A0HYM2", "高收益债 OAS", "pct"),
        ("BAMLC0A4CBBB", "BBB 级公司债 OAS", "pct"),
        ("BAMLC0A0CM", "投资级债 OAS", "pct"),
        ("BAA10Y", "Baa 公司债–10Y 利差", "pct"),
    ]),
]

# 波动率全景：Yahoo/CBOE 免 key（symbol, 中文名）。MOVE=债券波动率，对利率驱动的宏观最关键。
VOL_SET = [
    ("^MOVE", "MOVE 债券波动率"), ("^VIX9D", "VIX 9 日"), ("^VIX", "VIX"),
    ("^VIX3M", "VIX 3 月"), ("^VIX6M", "VIX 6 月"), ("^SKEW", "SKEW 偏度"),
    ("^VVIX", "VVIX 波动之波动"),
]


_FRED_CACHE = {}


def fred_api(series_id, limit=8):
    """FRED 官方 API 序列，返回升序 [(date,value)]；无 key 或失败返回 []。
    进程内按 series_id 缓存（统一取 ~2 年历史），保证打分与展示同源、消除跨源快照不一致。"""
    if series_id in _FRED_CACHE:
        return _FRED_CACHE[series_id]
    key = os.environ.get("FRED_API_KEY")
    if not key:
        return []
    n = max(limit, 520)  # 统一取足够历史，一次缓存供打分(2y 分位)与展示复用
    url = "https://api.stlouisfed.org/fred/series/observations"
    params = {
        "series_id": series_id,
        "api_key": key,
        "file_type": "json",
        "sort_order": "desc",
        "limit": n,
    }
    last = ""
    for attempt in range(2):
        try:
            r = requests.get(url, params=params, headers=UA, timeout=(8, 15))
            r.raise_for_status()
            obs = (r.json() or {}).get("observations") or []
            out = []
            for o in obs:
                v = o.get("value")
                if v in (".", "", None):
                    continue
                try:
                    out.append((o.get("date"), float(v)))
                except (TypeError, ValueError):
                    continue
            out.reverse()
            if out:
                _FRED_CACHE[series_id] = out
                return out
            last = "空数据"
        except Exception as e:
            status = getattr(getattr(e, "response", None), "status_code", None)
            last = "%s%s" % (type(e).__name__, " HTTP %s" % status if status else "")
        time.sleep(1.0)
    print("FRED-API %s 失败：%s" % (series_id, last))
    _FRED_CACHE[series_id] = []  # 同一 run 内一致降级，避免打分/展示各拿到不同快照
    return []


def _parse_utc_timestamp(value):
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _parse_observation_date(value):
    if not isinstance(value, str):
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


def _positive_number(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and value > 0)


def normalize_official_observations(series, limit=8):
    """Validate an ascending official observation window without inventing dates or values."""
    try:
        maximum = max(2, min(8, int(limit)))
    except (TypeError, ValueError):
        maximum = 8
    observations = []
    previous_date = None
    for item in series or []:
        if not isinstance(item, (list, tuple)) or len(item) != 2:
            return []
        observed, value = item
        parsed = _parse_observation_date(observed)
        if parsed is None or not _positive_number(value) \
                or (previous_date is not None and parsed <= previous_date):
            return []
        observations.append({"asOf": observed, "value": float(value)})
        previous_date = parsed
    return observations[-maximum:]


def retained_official_observations(record):
    """Reuse a valid window, or seed only the dated observations an old record proves."""
    existing = record.get("observations") if isinstance(record, dict) else None
    if isinstance(existing, list) and existing:
        pairs = [(item.get("asOf"), item.get("value")) for item in existing if isinstance(item, dict)]
        normalized = normalize_official_observations(pairs)
        if len(normalized) == len(existing):
            return normalized

    if not isinstance(record, dict):
        return []
    pairs = []
    previous_as_of = record.get("previousAsOf")
    previous_price = record.get("previousPrice")
    as_of = record.get("asOf")
    price = record.get("price")
    if _parse_observation_date(previous_as_of) and _positive_number(previous_price):
        pairs.append((previous_as_of, previous_price))
    if _parse_observation_date(as_of) and _positive_number(price):
        pairs.append((as_of, price))
    return normalize_official_observations(pairs)


def _find_dgs10_row(data):
    for category in (data or {}).get("macro") or []:
        if not isinstance(category, dict):
            continue
        for row in category.get("rows") or []:
            if isinstance(row, dict) and row.get("id") == DGS10_ID:
                return category, row
    return None, None


def _unit_number(value, suffix):
    text = str(value or "").strip()
    if not text.lower().endswith(suffix.lower()):
        return None
    try:
        return float(text[:-len(suffix)].strip())
    except (TypeError, ValueError):
        return None


def previous_dgs10_reference(previous_data):
    """兼容旧宏观行并补成可保留的DGS10逐源记录，不伪造前值日期。"""
    category, row = _find_dgs10_row(previous_data or {})
    if not isinstance(category, dict) or not isinstance(row, dict) \
            or str(category.get("src", "")).upper() != "FRED":
        return None
    price = row.get("price") if _positive_number(row.get("price")) else _unit_number(row.get("val"), "%")
    change_bps = row.get("changeBps") if isinstance(row.get("changeBps"), (int, float)) \
        else _unit_number(row.get("chg"), "bp")
    as_of = row.get("asOf")
    updated_at = row.get("updatedAt") or (previous_data or {}).get("updatedAt")
    if not _positive_number(price) or not isinstance(change_bps, (int, float)) \
            or _parse_observation_date(as_of) is None or _parse_utc_timestamp(updated_at) is None:
        return None
    previous_price = row.get("previousPrice")
    if not _positive_number(previous_price):
        previous_price = price - float(change_bps) / 100
    retained = {
        **copy.deepcopy(row),
        "id": DGS10_ID,
        "name": "10 年期美债收益率",
        "frequency": "daily",
        "status": row.get("status") if row.get("status") in ("ok", "stale") else "ok",
        "price": float(price),
        "previousPrice": float(previous_price),
        "changeBps": float(change_bps),
        "asOf": as_of,
        "previousAsOf": row.get("previousAsOf"),
        "updatedAt": updated_at,
        "lastAttemptAt": row.get("lastAttemptAt") or updated_at,
        "source": dict(DGS10_SOURCE),
    }
    retained["observations"] = retained_official_observations(retained)
    return retained


def build_dgs10_reference(previous_data, updated_at, fetcher=None):
    """独立刷新DGS10；失败时保留旧值，并记录本轮失败时间。"""
    fetch = fetcher or fred_api
    try:
        series = fetch(DGS10_ID, 8) or []
    except Exception:
        series = []
    observations = normalize_official_observations(series)
    if len(observations) >= 2:
        previous_as_of, previous_price = observations[-2]["asOf"], observations[-2]["value"]
        as_of, price = observations[-1]["asOf"], observations[-1]["value"]
        if _parse_observation_date(previous_as_of) and _parse_observation_date(as_of) \
                and previous_as_of < as_of and _positive_number(previous_price) and _positive_number(price):
            change_bps = round((price - previous_price) * 100)
            return {
                "id": DGS10_ID,
                "name": "10 年期美债收益率",
                "frequency": "daily",
                "status": "ok",
                "val": "%.2f%%" % price,
                "chg": "%+dbp" % change_bps,
                "tone": "flat" if price == previous_price else ("up" if price > previous_price else "down"),
                "price": float(price),
                "previousPrice": float(previous_price),
                "changeBps": change_bps,
                "asOf": as_of,
                "previousAsOf": previous_as_of,
                "updatedAt": updated_at,
                "lastAttemptAt": updated_at,
                "source": dict(DGS10_SOURCE),
                "observations": observations,
                "note": "FRED官方日频数据；变化为相对上一观测值的基点数。",
            }
    old = previous_dgs10_reference(previous_data)
    if old:
        fallback = copy.deepcopy(old)
        fallback["status"] = "stale"
        fallback["lastAttemptAt"] = updated_at
        fallback["note"] = "本轮FRED自动更新失败，保留上次有效DGS10观测值。"
        return fallback
    return {
        "id": DGS10_ID,
        "name": "10 年期美债收益率",
        "frequency": "daily",
        "status": "error",
        "val": None,
        "chg": None,
        "tone": "flat",
        "price": None,
        "previousPrice": None,
        "changeBps": None,
        "asOf": None,
        "previousAsOf": None,
        "updatedAt": None,
        "lastAttemptAt": updated_at,
        "source": dict(DGS10_SOURCE),
        "observations": [],
        "note": "FRED自动更新失败，且没有可保留的历史DGS10观测值。",
    }


def upsert_dgs10_macro(categories, record):
    """在不改变宏观页面旧结构的前提下，替换或移除DGS10逐条记录。"""
    output = copy.deepcopy(categories or [])
    target = None
    for category in output:
        if not isinstance(category, dict):
            continue
        rows = category.get("rows")
        if not isinstance(rows, list):
            continue
        category["rows"] = [row for row in rows if not (isinstance(row, dict) and row.get("id") == DGS10_ID)]
        if str(category.get("src", "")).upper() == "FRED" \
                and category.get("zh") == "实际利率与通胀预期":
            target = category
    if record.get("status") == "error":
        return [category for category in output if not isinstance(category, dict) or category.get("rows")]
    if target is None:
        target = {"zh": "实际利率与通胀预期", "en": "RATES & INFLATION", "src": "FRED", "rows": []}
        output.append(target)
    target.setdefault("rows", []).insert(0, copy.deepcopy(record))
    return output


def parse_eia_rwtc_rows(payload):
    """Parse and source-check EIA API v2 RWTC rows into ascending observations."""
    response = payload.get("response") if isinstance(payload, dict) else None
    if not isinstance(response, dict) or response.get("frequency") not in (None, "daily"):
        return []
    observations = {}
    for row in response.get("data") or []:
        if not isinstance(row, dict) or row.get("series") != RWTC_ID:
            continue
        observed = row.get("period")
        if _parse_observation_date(observed) is None:
            continue
        units = str(row.get("value-units") or "").lower()
        if units and not ("dollar" in units and "barrel" in units):
            continue
        try:
            value = float(row.get("value"))
        except (TypeError, ValueError):
            continue
        if _positive_number(value):
            observations[observed] = value
    return sorted(observations.items())


def eia_rwtc_api(limit=8, requester=None, api_key=None):
    """EIA API v2 daily RWTC observations; missing key or failure returns []."""
    key = api_key if api_key is not None else os.environ.get("EIA_API_KEY")
    if not key:
        return []
    params = {
        "api_key": key,
        "frequency": "daily",
        "data[0]": "value",
        "facets[series][]": RWTC_ID,
        "sort[0][column]": "period",
        "sort[0][direction]": "desc",
        "offset": 0,
        "length": max(2, int(limit)),
    }
    get = requester or requests.get
    last = ""
    for attempt in range(2):
        try:
            response = get(EIA_API_URL, params=params, headers=UA, timeout=(8, 15))
            response.raise_for_status()
            out = parse_eia_rwtc_rows(response.json() or {})
            if len(out) >= 2:
                return out
            last = "有效观测不足"
        except Exception as exc:
            status = getattr(getattr(exc, "response", None), "status_code", None)
            last = "%s%s" % (type(exc).__name__, " HTTP %s" % status if status else "")
        if attempt == 0:
            time.sleep(1.0)
    print("EIA-API %s 失败：%s" % (RWTC_ID, last))
    return []


class _EiaHistoryTableParser(HTMLParser):
    """Collect table cells without depending on EIA's presentation classes."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows = []
        self._row = None
        self._cell = None

    def handle_starttag(self, tag, attrs):
        del attrs
        if tag.lower() == "tr":
            self._row = []
        elif tag.lower() in ("td", "th") and self._row is not None:
            self._cell = []

    def handle_data(self, data):
        if self._cell is not None:
            self._cell.append(data)

    def handle_endtag(self, tag):
        lowered = tag.lower()
        if lowered in ("td", "th") and self._row is not None and self._cell is not None:
            value = re.sub(r"\s+", " ", "".join(self._cell).replace("\xa0", " ")).strip()
            self._row.append(value)
            self._cell = None
        elif lowered == "tr" and self._row is not None:
            if self._row:
                self.rows.append(self._row)
            self._row = None
            self._cell = None


_EIA_WEEK_LABEL = re.compile(
    r"^(\d{4})\s+([A-Z][a-z]{2})-\s*(\d{1,2})\s+to\s+([A-Z][a-z]{2})-\s*(\d{1,2})$"
)
_MONTH_NUMBER = {
    name: index for index, name in enumerate(
        ("", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    ) if name
}


def parse_eia_rwtc_history_html(page, limit=8):
    """Parse EIA's public daily RWTC history table into ascending observations."""
    if not isinstance(page, str) or len(page) > 8_000_000:
        return []
    parser = _EiaHistoryTableParser()
    try:
        parser.feed(page)
        parser.close()
    except (TypeError, ValueError):
        return []
    page_text = " ".join(cell for row in parser.rows for cell in row)
    if "Cushing, OK WTI Spot Price FOB" not in page_text or "Dollars per Barrel" not in page_text:
        return []

    observations = {}
    for row in parser.rows:
        if len(row) < 6:
            continue
        match = _EIA_WEEK_LABEL.fullmatch(row[0])
        if not match:
            continue
        year, start_month, start_day, end_month, end_day = match.groups()
        start_month_number = _MONTH_NUMBER.get(start_month)
        end_month_number = _MONTH_NUMBER.get(end_month)
        if not start_month_number or not end_month_number:
            continue
        start_year = int(year)
        end_year = start_year + (1 if end_month_number < start_month_number else 0)
        try:
            week_start = datetime(start_year, start_month_number, int(start_day), tzinfo=timezone.utc)
            week_end = datetime(end_year, end_month_number, int(end_day), tzinfo=timezone.utc)
        except ValueError:
            continue
        if week_end != week_start + timedelta(days=4) or week_start.weekday() != 0:
            continue
        for offset, raw_value in enumerate(row[1:6]):
            try:
                value = float(raw_value.replace(",", ""))
            except (AttributeError, TypeError, ValueError):
                continue
            if _positive_number(value):
                observed = (week_start + timedelta(days=offset)).strftime("%Y-%m-%d")
                observations[observed] = value
    try:
        maximum = max(2, min(8, int(limit)))
    except (TypeError, ValueError):
        maximum = 8
    return sorted(observations.items())[-maximum:]


def eia_rwtc_history(limit=8, requester=None):
    """Read the official public EIA RWTC history page when API credentials are unavailable."""
    get = requester or requests.get
    last = ""
    for attempt in range(2):
        try:
            response = get(EIA_HISTORY_URL, headers=UA, timeout=(8, 20))
            response.raise_for_status()
            out = parse_eia_rwtc_history_html(response.text, limit)
            if len(out) >= 2:
                return out
            last = "有效观测不足"
        except Exception as exc:
            status = getattr(getattr(exc, "response", None), "status_code", None)
            last = "%s%s" % (type(exc).__name__, " HTTP %s" % status if status else "")
        if attempt == 0:
            time.sleep(1.0)
    print("EIA-HISTORY %s 失败：%s" % (RWTC_ID, last))
    return []


def valid_dtwexbgs_reference(record):
    """Return True only for a reusable, source-verified DTWEXBGS observation pair."""
    if not isinstance(record, dict) or record.get("id") != DTWEXBGS_ID:
        return False
    source = record.get("source") or {}
    if source.get("seriesId") != DTWEXBGS_ID or not str(source.get("name", "")).startswith("FRED"):
        return False
    observed = _parse_observation_date(record.get("asOf"))
    previous = _parse_observation_date(record.get("previousAsOf"))
    updated = _parse_utc_timestamp(record.get("updatedAt"))
    raw_observations = record.get("observations")
    observations_valid = True
    if raw_observations is not None:
        observations = retained_official_observations(record)
        observations_valid = bool(
            isinstance(raw_observations, list)
            and len(observations) == len(raw_observations)
            and observations
            and observations[-1]["asOf"] == record.get("asOf")
            and abs(observations[-1]["value"] - record.get("price", 0)) <= 1e-9
        )
    return bool(
        record.get("status") in ("ok", "stale")
        and _positive_number(record.get("price"))
        and _positive_number(record.get("previousPrice"))
        and observed and previous and previous < observed
        and updated and updated.tzinfo is not None
        and observations_valid
    )


def build_dtwexbgs_reference(previous_data, updated_at, fetcher=None):
    """Build the finance-terminal DTWEXBGS record from the shared FRED client.

    A failed refresh never replaces a valid observation with zero, null, or demo data.
    The last successful timestamp is retained and the failed attempt is exposed separately.
    """
    fetch = fetcher or fred_api
    try:
        series = fetch(DTWEXBGS_ID, 8) or []
    except Exception:
        series = []

    observations = normalize_official_observations(series)
    if len(observations) >= 2:
        previous_as_of, previous_price = observations[-2]["asOf"], observations[-2]["value"]
        as_of, price = observations[-1]["asOf"], observations[-1]["value"]
        record = {
            "id": DTWEXBGS_ID,
            "name": "美联储广义美元指数",
            "nameEn": "Nominal Broad U.S. Dollar Index",
            "frequency": "daily",
            "demo": False,
            "status": "ok",
            "price": price,
            "previousPrice": previous_price,
            "changePct": (price / previous_price - 1) * 100 if previous_price else None,
            "asOf": as_of,
            "previousAsOf": previous_as_of,
            "updatedAt": updated_at,
            "lastAttemptAt": updated_at,
            "source": dict(DTWEXBGS_SOURCE),
            "observations": observations,
            "note": "FRED官方日频数据；由宏观雷达任务自动更新。",
        }
        if valid_dtwexbgs_reference(record):
            return record

    old = (((previous_data or {}).get("referenceSeries") or {}).get(DTWEXBGS_ID))
    if valid_dtwexbgs_reference(old):
        fallback = copy.deepcopy(old)
        fallback["status"] = "stale"
        fallback["lastAttemptAt"] = updated_at
        fallback["note"] = "本轮FRED自动更新失败，保留上次有效观测值。"
        return fallback

    return {
        "id": DTWEXBGS_ID,
        "name": "美联储广义美元指数",
        "nameEn": "Nominal Broad U.S. Dollar Index",
        "frequency": "daily",
        "demo": False,
        "status": "error",
        "price": None,
        "previousPrice": None,
        "changePct": None,
        "asOf": None,
        "previousAsOf": None,
        "updatedAt": None,
        "lastAttemptAt": updated_at,
        "source": dict(DTWEXBGS_SOURCE),
        "observations": [],
        "note": "FRED自动更新失败，且没有可保留的历史有效值。",
    }


def valid_rwtc_reference(record):
    """Return True only for a reusable, source-verified EIA RWTC observation pair."""
    if not isinstance(record, dict) or record.get("id") != RWTC_ID:
        return False
    source = record.get("source") or {}
    if source.get("seriesId") != RWTC_ID or "EIA" not in str(source.get("name", "")):
        return False
    observed = _parse_observation_date(record.get("asOf"))
    previous = _parse_observation_date(record.get("previousAsOf"))
    updated = _parse_utc_timestamp(record.get("updatedAt"))
    raw_observations = record.get("observations")
    observations_valid = True
    if raw_observations is not None:
        observations = retained_official_observations(record)
        observations_valid = bool(
            isinstance(raw_observations, list)
            and len(observations) == len(raw_observations)
            and observations
            and observations[-1]["asOf"] == record.get("asOf")
            and abs(observations[-1]["value"] - record.get("price", 0)) <= 1e-9
        )
    return bool(
        record.get("status") in ("ok", "stale")
        and _positive_number(record.get("price"))
        and _positive_number(record.get("previousPrice"))
        and observed and previous and previous < observed
        and updated and updated.tzinfo is not None
        and observations_valid
    )


def build_rwtc_reference(previous_data, updated_at, fetcher=None):
    """Build the finance-terminal WTI spot record from EIA series RWTC.

    A failed refresh retains the last valid observation pair and exposes the failed attempt.
    """
    access_method = None
    try:
        if fetcher is not None:
            series = fetcher(8) or []
        else:
            series = eia_rwtc_api(8) or []
            if series:
                access_method = "EIA API v2"
            else:
                series = eia_rwtc_history(8) or []
                if series:
                    access_method = "EIA public history page"
    except Exception:
        series = []

    observations = normalize_official_observations(series)
    if len(observations) >= 2:
        previous_as_of, previous_price = observations[-2]["asOf"], observations[-2]["value"]
        as_of, price = observations[-1]["asOf"], observations[-1]["value"]
        source = dict(RWTC_SOURCE)
        if access_method:
            source["accessMethod"] = access_method
        record = {
            "id": RWTC_ID,
            "name": "库欣WTI原油现货",
            "nameEn": "Cushing WTI Spot Price FOB",
            "frequency": "daily",
            "demo": False,
            "status": "ok",
            "price": price,
            "previousPrice": previous_price,
            "changePct": (price / previous_price - 1) * 100 if previous_price else None,
            "asOf": as_of,
            "previousAsOf": previous_as_of,
            "updatedAt": updated_at,
            "lastAttemptAt": updated_at,
            "source": source,
            "observations": observations,
            "note": ("EIA官方日频现货数据；通过%s自动更新。" % access_method
                     if access_method else "EIA官方日频现货数据；由宏观雷达任务自动更新。"),
        }
        if valid_rwtc_reference(record):
            return record

    old = (((previous_data or {}).get("referenceSeries") or {}).get(RWTC_ID))
    if valid_rwtc_reference(old):
        fallback = copy.deepcopy(old)
        fallback["status"] = "stale"
        fallback["lastAttemptAt"] = updated_at
        fallback["note"] = "本轮EIA自动更新失败，保留上次有效观测值。"
        return fallback

    return {
        "id": RWTC_ID,
        "name": "库欣WTI原油现货",
        "nameEn": "Cushing WTI Spot Price FOB",
        "frequency": "daily",
        "demo": False,
        "status": "error",
        "price": None,
        "previousPrice": None,
        "changePct": None,
        "asOf": None,
        "previousAsOf": None,
        "updatedAt": None,
        "lastAttemptAt": updated_at,
        "source": dict(RWTC_SOURCE),
        "observations": [],
        "note": "EIA自动更新失败，且没有可保留的历史有效值。",
    }


def fetch_net_liquidity():
    """美联储净流动性 = 总资产 − TGA − 隔夜逆回购，返回升序 [(date, 十亿美元)]。"""
    wal = fred_api("WALCL", 520)      # 百万美元
    tga = fred_api("WTREGEN", 520)    # 百万美元
    rrp = fred_api("RRPONTSYD", 520)  # 十亿美元
    if not (wal and tga and rrp):
        return []
    mtga, mrrp = dict(tga), dict(rrp)
    out = []
    for d, w in wal:
        t, r = mtga.get(d), mrrp.get(d)
        if t is None or r is None:
            continue
        out.append((d, w / 1e3 - t / 1e3 - r))  # 统一到十亿美元
    return out


def fmt_macro(kind, series):
    """把一条序列格式化为 {val, chg, tone, asOf}（展示就绪）。"""
    if not series:
        return None
    v = series[-1][1]
    prev = series[-2][1] if len(series) >= 2 else None
    if kind == "pct":
        val = "%.2f%%" % v
        chg = None if prev is None else "%+dbp" % round((v - prev) * 100)
    elif kind in ("usd_m", "usd_b"):
        billions = (v / 1e3) if kind == "usd_m" else v
        pbill = None if prev is None else ((prev / 1e3) if kind == "usd_m" else prev)
        val = ("%.2fT" % (billions / 1e3)) if abs(billions) >= 1000 else ("%.0fB" % billions)
        if pbill is None:
            chg = None
        elif abs(pbill) < 50:   # 近零基数（如 RRP 仅剩数十亿）：用绝对变化，避免百分比噪音
            chg = "%+.1fB" % (billions - pbill)
        else:
            chg = "%+.1f%%" % ((v / prev - 1) * 100)
    else:  # idx
        val = "%.2f" % v
        chg = None if prev is None else "%+.2f" % (v - prev)
    if prev is None or v == prev:
        tone = "flat"
    else:
        tone = "up" if v > prev else "down"
    return {"val": val, "chg": chg, "tone": tone, "asOf": series[-1][0]}


def build_macro():
    """组装折叠式宏观管道：FRED 各类（需 key）+ 波动率全景（Yahoo）。返回 cats 列表。"""
    cats = []
    # FRED 分类
    for zh, en, items in FRED_CATS:
        rows = []
        for sid, name, kind in items:
            s = fred_api(sid)
            f = fmt_macro(kind, s)
            if f:
                f["name"] = name
                f["id"] = sid
                rows.append(f)
        if rows:
            cats.append({"zh": zh, "en": en, "src": "FRED", "rows": rows})
    # 商品比率（经济周期 / 避险，Yahoo 计算）
    _hg = yahoo_series("HG=F", "3mo"); _gc = yahoo_series("GC=F", "3mo")
    _si = yahoo_series("SI=F", "3mo"); _cl = yahoo_series("CL=F", "3mo")

    def ratio_row(name, a, b, fmt, scale=1.0):
        s = align_ratio(a, b)
        if len(s) < 2:
            return None
        v, prev = s[-1][1], s[-2][1]
        return {"name": name, "id": "", "val": fmt % (v * scale),
                "chg": "%+.1f%%" % ((v / prev - 1) * 100) if prev else None,
                "asOf": s[-1][0],
                "tone": "flat" if v == prev else ("up" if v > prev else "down")}
    rrows = [r for r in [
        ratio_row("铜/金 ×1000 (工业 vs 避险)", _hg, _gc, "%.2f", 1000),
        ratio_row("金/银", _gc, _si, "%.1f"),
        ratio_row("油/铜", _cl, _hg, "%.2f"),
        ratio_row("油/金 ×100", _cl, _gc, "%.2f", 100),
    ] if r]
    if rrows:
        cats.append({"zh": "商品比率", "en": "COMMODITY RATIOS", "src": "Yahoo", "rows": rrows})

    # 融资压力（RRP 归零后关键：SOFR−IORB / EFFR−IORB 爬升 = 准备金稀缺、融资趋紧信号）
    def spread_row(name, a_id, b_id):
        a, b = fred_api(a_id), fred_api(b_id)
        if not a or not b:
            return None
        bp = round((a[-1][1] - b[-1][1]) * 100)
        chg = None
        if len(a) >= 2 and len(b) >= 2:
            chg = "%+dbp" % (bp - round((a[-2][1] - b[-2][1]) * 100))
        return {"name": name, "id": "%s−%s" % (a_id, b_id), "val": "%+dbp" % bp, "chg": chg,
                "asOf": a[-1][0], "tone": "up" if bp > 0 else ("down" if bp < 0 else "flat")}
    frows = [r for r in [
        spread_row("SOFR − IORB", "SOFR", "IORB"),
        spread_row("EFFR − IORB", "DFF", "IORB"),
    ] if r]
    if frows:
        cats.append({"zh": "融资压力", "en": "FUNDING STRESS", "src": "FRED", "rows": frows})

    # （市场宽度 %>均线：^S5TH/^S5FI/^NDTH 在 Yahoo 上取不到，已按"抓不到不用"移除；
    #   市场广度已由制度信号中的 等权/市值加权 代理覆盖。）

    # 波动率全景（Yahoo）+ VIX/VIX3M 期限结构比
    vrows = []
    vlast = {}
    for sym, name in VOL_SET:
        s = yahoo_series(sym, "1mo")
        if not s or len(s) < 2:
            continue
        v, prev = s[-1][1], s[-2][1]
        vlast[sym] = v
        chgp = (v / prev - 1) * 100 if prev else 0
        vrows.append({"name": name, "id": sym.lstrip("^"), "val": "%.2f" % v,
                      "chg": "%+.1f%%" % chgp, "asOf": s[-1][0],
                      "tone": "flat" if v == prev else ("up" if v > prev else "down")})
    if vlast.get("^VIX") and vlast.get("^VIX3M"):
        r = vlast["^VIX"] / vlast["^VIX3M"]
        vrows.append({"name": "VIX/VIX3M 期限结构", "id": "",
                      "val": "%.2f" % r, "chg": "倒挂" if r > 1 else "正向", "asOf": "",
                      "tone": "down" if r > 1 else "up"})
    if vrows:
        cats.append({"zh": "波动率全景", "en": "VOLATILITY", "src": "Yahoo", "rows": vrows})
    return cats


# ── 组装 ────────────────────────────────────────────────────────────────
def build():
    prev = None
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            prev = json.load(f)
    except Exception:
        pass
    prev_health = load_health_json(HEALTH_PATH)

    hit = 0  # 成功抓到的数据源计数，用于判断是否 LIVE

    # —— 底层序列（全部 Yahoo）——
    vix = yahoo_series("^VIX", "2y")   # 2 年窗口：波动率分位与方法学/时光机(WIN=504)对齐
    vix3m = yahoo_series("^VIX3M", "1y")
    dxy = yahoo_series(["DX-Y.NYB", "DX=F"], "2y")
    hg = yahoo_series("HG=F", "2y")
    gc = yahoo_series("GC=F", "2y")
    rsp = yahoo_series("RSP", "2y")
    spy = yahoo_series("SPY", "2y")
    cnh = yahoo_series("CNH=X", "1y")
    cny = yahoo_series("CNY=X", "1y")
    tnx = yahoo_series("^TNX", "2y")   # 10Y 国债收益率（%）
    irx = yahoo_series("^IRX", "2y")   # 13 周 T-bill 收益率（%）
    hyg = yahoo_series("HYG", "2y")    # 高收益信用 ETF
    lqd = yahoo_series("LQD", "2y")    # 投资级信用 ETF
    sox = yahoo_series("^SOX", "2y")   # 费城半导体 → 增长/周期领先
    xly = yahoo_series("XLY", "2y")    # 可选消费（周期）
    xlp = yahoo_series("XLP", "2y")    # 必需消费（防御）

    for s in (vix, dxy, hg, gc, rsp, spy, tnx, irx, hyg, lqd):
        if s:
            hit += 1

    cg = align_ratio(hg, gc)          # 铜金比 → 增长动能代理
    breadth = align_ratio(rsp, spy)   # 等权/市值加权 → 广度代理
    hyglqd = align_ratio(hyg, lqd)    # 高收益/投资级比价 → 信用风险偏好代理
    slope = align_diff(tnx, irx)      # 10Y−3M 曲线陡峭度 → 期限结构代理（Yahoo 回退用）

    # —— 7 个制度信号（越高越"宽松·支持"）——
    signals = []

    def add(key, en, zh, score, desc, sp):
        if score is not None:
            score = int(round(max(0, min(100, score))))
        st, stzh = status_of(score)
        signals.append({"key": key, "en": en, "zh": zh, "score": score,
                        "status": st, "statusZh": stzh, "desc": desc, "spark": sp})

    # 流动性（三合一：净流动性 水平分位 0.35 + 13 周流量 impulse 0.40 + 融资验证 SOFR−IORB 0.25）
    #   水平=QT 累计抽水位置；impulse=真正驱动风险资产的流量；融资=准备金稀缺的实时市场检验。
    liq = None
    liq_desc = "3M 短端利率代理货币政策松紧"
    liq_spark = spark(irx)
    netliq = fetch_net_liquidity()
    if netliq and len(netliq) > 14:
        nl = [v for _, v in netliq]
        comps = []  # (权重, 0–100 分)
        # 净流动性为周频（WALCL 周报）：分位窗口用 WIN_W=104(≈2 年)，与时光机口径一致；
        # 若沿用日频默认 504，会把窗口拉成≈10 年，令流动性分位系统性偏高、两块面板对不上。
        level_p = pct_rank(nl, win=WIN_W)
        if level_p is not None:
            comps.append((0.35, level_p))
        imp = [nl[i] - nl[i - 13] for i in range(13, len(nl))]   # 13 周净流动性变化序列
        imp_p = pct_rank(imp, win=WIN_W)
        if imp_p is not None:
            comps.append((0.40, imp_p))
        sofr = fred_api("SOFR")
        iorb = fred_api("IORB")
        fund_bp = None
        if sofr and iorb:
            fund_bp = round((sofr[-1][1] - iorb[-1][1]) * 100)   # 负=充裕，正=准备金稀缺
            comps.append((0.25, max(0, min(100, 50 - fund_bp * 3))))
        wsum = sum(w for w, _ in comps)
        liq = sum(w * s for w, s in comps) / wsum if wsum else None
        liq_spark = spark(netliq)
        imp13 = nl[-1] - nl[-14]
        liq_desc = "净流动性 %.2fT，近 13 周 %+.0fB（%s）%s" % (
            nl[-1] / 1000, imp13, "回升" if imp13 > 0 else "收缩",
            ("；SOFR−IORB %+dbp（%s）" % (fund_bp, "充裕" if fund_bp <= 0 else "趋紧"))
            if fund_bp is not None else "")
    elif irx:
        liq = 100 - (pct_rank([v for _, v in irx]) or 50)
        liq_desc = "3M 短端利率 %.2f%%，%s" % (
            irx[-1][1], "政策偏松" if liq and liq > 55 else "政策偏紧")
    add("liquidity", "LIQUIDITY", "流动性", liq, liq_desc, liq_spark)

    # 波动率
    vol = None
    vol_desc = "VIX 水平与期限结构"
    if vix:
        vol = 100 - (pct_rank([v for _, v in vix]) or 50)
        if vix3m and vix and vix3m[-1][1] and vix[-1][1]:
            back = vix[-1][1] > vix3m[-1][1]
            vol_desc = "VIX %s，期限结构%s" % (
                "抬升" if (vix[-1][1] > vix[-6][1] if len(vix) > 6 else False) else "回落",
                "倒挂 (backwardation)" if back else "正向 (contango)")
    add("volatility", "VOLATILITY", "波动率", vol, vol_desc, spark(vix))

    # 期限（统一用 FRED 10Y−3M，与管道卡同源；并按期限溢价区分牛陡/熊陡：
    #   陡峭本身利多，但若由长端 term premium 抬升驱动（熊陡）则对风险资产偏紧，扣分。）
    term = None
    term_desc = "收益率曲线 10Y−3M 期限结构代理"
    term_spark = spark(slope)
    t10y3m = fred_api("T10Y3M", 520)
    tp = fred_api("THREEFYTP10", 520)
    if t10y3m:
        slope_p = pct_rank([v for _, v in t10y3m]) or 50
        bp = round(t10y3m[-1][1] * 100)
        term_spark = spark(t10y3m)
        if tp:
            tp_p = pct_rank([v for _, v in tp]) or 50
            term = 0.55 * slope_p + 0.45 * (100 - tp_p)
            term_desc = "10Y−3M %+dbp，期限溢价 %.2f%%（%s）" % (
                bp, tp[-1][1], "牛陡偏松" if tp_p < 50 else "熊陡偏紧")
        else:
            term = slope_p
            term_desc = "收益率曲线 10Y−3M %+dbp，%s" % (bp, "曲线陡峭" if bp > 0 else "曲线倒挂")
    elif slope:
        term = pct_rank([v for _, v in slope])
        bp = round(slope[-1][1] * 100)
        term_desc = "收益率曲线 10Y−3M %+dbp，%s" % (
            bp, "曲线陡峭" if slope[-1][1] > 0 else "曲线倒挂")
    add("term", "TERM PREMIUM", "期限溢价", term, term_desc, term_spark)

    # 实际利率（5Y TIPS 实际收益率 DFII5：水平分位 0.5 + 63 日冲量分位 0.5，均反向计分）
    #   实际利率是长久期资产（高估值成长股、无息的黄金白银）的贴现分母：水平量"限制性
    #   多高"，冲量量"是否在急升"——杀估值的从来是急升（2013 缩减恐慌、2022 紧缩）。
    #   与期限信号不重复：期限量曲线"形状"，这里量贴现率"水平"；与流动性互补：
    #   流动性量钱的"数量"，这里量钱的"价格"。描述用 T5YIE 分解驱动：
    #   实际升+通胀预期落=紧缩驱动（对风险资产最凶）；两者同升=增长驱动（较温和）。
    rr = None
    rr_desc = "5Y TIPS 实际收益率：久期资产贴现率"
    rr_spark = []
    dfii5 = fred_api("DFII5", 520)
    if dfii5 and len(dfii5) > 64:
        rv = [v for _, v in dfii5]
        level_p = pct_rank(rv)
        imp_p = pct_rank([rv[i] - rv[i - 63] for i in range(63, len(rv))])
        comps = [(0.5, 100 - p) for p in (level_p, imp_p) if p is not None]
        wsum = sum(w for w, _ in comps)
        rr = sum(w * s for w, s in comps) / wsum if wsum else None
        rr_spark = spark(dfii5)
        d63 = round((rv[-1] - rv[-64]) * 100)
        drive = ""
        t5yie = fred_api("T5YIE")
        if d63 > 0 and t5yie and len(t5yie) > 64:
            ie63 = round((t5yie[-1][1] - t5yie[-64][1]) * 100)
            drive = "（%s）" % ("紧缩驱动" if ie63 <= 0 else "增长驱动")
        rr_desc = "5Y 实际利率 %.2f%%，近 13 周 %+dbp%s" % (rv[-1], d63, drive)
    add("realrate", "REAL RATE", "实际利率", rr, rr_desc, rr_spark)

    # 信用（优先美银高收益债 OAS 权威口径：利差越窄越支持；取不到回退 HYG/LQD 比价）
    cred = None
    cred_desc = "高收益/投资级比价 (HYG÷LQD)"
    cred_spark = spark(hyglqd)
    hyoas = fred_api("BAMLH0A0HYM2", 520)
    if hyoas:
        cred = 100 - (pct_rank([v for _, v in hyoas]) or 50)
        cred_spark = spark(hyoas)
        cred_desc = "高收益债 OAS %.0fbp，%s" % (
            hyoas[-1][1] * 100, "利差温和" if cred and cred > 55 else "利差走阔")
    elif hyglqd:
        cred = pct_rank([v for _, v in hyglqd])
        cred_desc = "高收益/投资级比价 (HYG÷LQD)，%s" % (
            "风险偏好回升" if cred and cred > 55 else "信用边际走弱")
    add("credit", "CREDIT", "信用利差", cred, cred_desc, cred_spark)

    # 增长（多代理综合：铜金比 + 半导体/大盘 + 周期/防御，降低对金价的单一依赖）
    gp = []
    if cg:
        gp.append(pct_rank([v for _, v in cg]))
    soxspy = align_ratio(sox, spy)
    if soxspy:
        gp.append(pct_rank([v for _, v in soxspy]))
    cycdef = align_ratio(xly, xlp)
    if cycdef:
        gp.append(pct_rank([v for _, v in cycdef]))
    gp = [x for x in gp if x is not None]
    grw = round(sum(gp) / len(gp), 1) if gp else None
    add("growth", "GROWTH", "增长动能", grw,
        "增长动能综合：铜金比 · 半导体/大盘(SOX) · 周期/防御(XLY/XLP)",
        spark(soxspy or cg))

    # 美元 / 汇率（越弱越是全球流动性顺风 → 分越高；即分数=对风险资产友好度）
    usd = None
    usd_desc = "美元指数与人民币基差"
    if dxy:
        pctd = pct_rank([v for _, v in dxy]) or 50
        usd = 100 - pctd
        dirn = "走强偏紧" if pctd >= 50 else "走弱、流动性顺风"
        if cnh and cny and cnh[-1][1] and cny[-1][1]:
            basis = round((cnh[-1][1] - cny[-1][1]) * 10000)
            usd_desc = "美元指数 %.1f（%s），离岸-在岸基差 %+dpips" % (dxy[-1][1], dirn, basis)
        else:
            usd_desc = "美元指数 %.1f（%s）" % (dxy[-1][1], dirn)
    add("usd", "USD / FX", "美元汇率", usd, usd_desc, spark(dxy))

    # 广度（水平分位 0.5 + 13周参与度 impulse 0.5：区分"存量集中"与"边际是否走扩"，
    #   避免被多年"龙头集中"趋势单向拖低）
    brd = None
    brd_desc = "等权/市值加权代理广度：涨势是否分散"
    brd_spark = spark(breadth)
    if breadth and len(breadth) > 70:
        bv = [v for _, v in breadth]
        level_p = pct_rank(bv)
        n = 63  # ≈ 13 周（交易日）
        imp = [bv[i] - bv[i - n] for i in range(n, len(bv))]
        imp_p = pct_rank(imp)
        comps = [(0.5, level_p)] + ([(0.5, imp_p)] if imp_p is not None else [])
        wsum = sum(w for w, _ in comps)
        brd = sum(w * s for w, s in comps) / wsum if wsum else level_p
        brd_desc = "等权/市值加权广度：存量近两年 %.0f%% 分位，近 13 周%s" % (
            level_p or 0, "走扩" if bv[-1] > bv[-(n + 1)] else "更集中")
    elif breadth:
        brd = pct_rank([v for _, v in breadth])
    add("breadth", "BREADTH", "市场广度", brd, brd_desc, brd_spark)

    # —— 综合机制读数 ——
    # 分块去相关：利率块 = 期限(曲线形状) + 实际利率(贴现率水平)合计 24%，主要从与
    # 实际利率相关性最高的期限、美元、广度匀出权重；波动率+信用同属"风险定价"合计 24%；
    # 货币的数量(流动性 18%)与价格(实际利率 12%)分开计量。
    W = {"liquidity": .18, "term": .12, "realrate": .12, "volatility": .12,
         "credit": .12, "growth": .14, "usd": .10, "breadth": .10}
    num = den = 0.0
    for s in signals:
        if s["score"] is not None:
            num += W[s["key"]] * s["score"]
            den += W[s["key"]]
    raw = (num / den) if den else None
    # 持续性滤波（EMA，α=0.6）：与上一日读数融合，抑制单日抖动
    if raw is not None:
        pr = ((prev or {}).get("regime") or {}).get("score")
        raw = 0.6 * raw + 0.4 * pr if isinstance(pr, (int, float)) else raw
        regime_score = int(round(raw))
    else:
        regime_score = None

    def regime_label(x):
        if x is None:
            return "数据缺失", "NO DATA"
        if x < 35:
            return "收紧 · 风险", "RISK-OFF"
        if x < 48:
            return "中性偏紧", "NEUTRAL-TIGHT"
        if x < 58:
            return "中性", "NEUTRAL"
        if x < 68:
            return "中性偏松", "NEUTRAL-EASY"
        return "宽松 · 支持", "SUPPORTIVE"

    lz, le = regime_label(regime_score)
    weak = sorted([s for s in signals if s["score"] is not None],
                  key=lambda s: s["score"])[:2]
    strong = sorted([s for s in signals if s["score"] is not None],
                    key=lambda s: -s["score"])[:2]
    if weak and strong:
        regime_desc = "%s走弱压制风险偏好；%s相对稳健，%s。" % (
            "、".join(s["zh"] for s in weak),
            "、".join(s["zh"] for s in strong),
            "尚未进入系统性压力区" if (regime_score or 0) >= 40 else "已进入压力区")
    else:
        regime_desc = "多资产制度信号综合读数。"

    # —— 异动流：从真实读数/穿越自动生成 ——
    mut = []

    def mrow(sig, status, text):
        mut.append({"sig": sig, "status": status, "text": text})

    if slope:
        bp = round(slope[-1][1] * 100)
        d5 = None
        if len(slope) >= 6:
            d5 = round((slope[-1][1] - slope[-6][1]) * 100)
        if slope[-1][1] < 0:
            mrow("期限溢价", "amber", "收益率曲线 10Y−3M 倒挂 %+dbp" % bp)
        elif d5 is not None and abs(d5) >= 8:
            mrow("期限溢价", "green" if d5 > 0 else "amber",
                 "收益率曲线周环比 %+dbp（%s）" % (d5, "走陡" if d5 > 0 else "走平"))
    if vix and vix3m and vix[-1][1] and vix3m[-1][1]:
        if vix[-1][1] > vix3m[-1][1]:
            mrow("波动率", "red", "VIX 期限结构呈 backwardation（VIX>VIX3M）")
    if irx and len(irx) >= 6:
        dbp = round((irx[-1][1] - irx[-6][1]) * 100)
        if abs(dbp) >= 3:
            mrow("利率", "red" if dbp > 0 else "green",
                 "3M 短端利率周环比 %+dbp（%s）" % (
                     dbp, "加息定价升温、边际收紧" if dbp > 0 else "宽松定价升温"))
    if dfii5 and len(dfii5) >= 6:
        dbp5 = round((dfii5[-1][1] - dfii5[-6][1]) * 100)
        if abs(dbp5) >= 10:
            mrow("实际利率", "red" if dbp5 > 0 else "green",
                 "5Y 实际利率周环比 %+dbp（%s）" % (
                     dbp5, "贴现率急升、压制久期资产" if dbp5 > 0 else "贴现压力缓解"))
    if breadth:
        bp2 = pct_rank([v for _, v in breadth])
        if bp2 is not None and bp2 < 40:
            mrow("市场广度", "red", "广度代理处于近两年 %.0f%% 分位，涨势集中" % bp2)
    if cnh and cny and cnh[-1][1] and cny[-1][1]:
        basis = round((cnh[-1][1] - cny[-1][1]) * 10000)
        if abs(basis) >= 50:
            mrow("美元汇率", "amber", "CNH–CNY 基差 %+dpips" % basis)
    if hyglqd and len(hyglqd) >= 6:
        chg = (hyglqd[-1][1] / hyglqd[-6][1] - 1) * 100
        if abs(chg) >= 0.3:
            mrow("信用利差", "green" if chg >= 0 else "amber",
                 "高收益/投资级比价周环比 %+.1f%%，%s" % (
                     chg, "风险偏好回升" if chg >= 0 else "信用走弱"))

    # 市场异动一句话解读
    g = sum(1 for m in mut if m["status"] == "green")
    r = sum(1 for m in mut if m["status"] == "red")
    if not mut:
        mut_summary = "今日无显著市场异动，跨资产结构平稳。"
    else:
        lean = ("风险偏好占优、结构偏支持" if g > r else
                "避险情绪升温、结构偏承压" if r > g else "多空交织、结构中性分化")
        mut_summary = "今日 %d 条市场异动，%s；与机制读数 %d（%s）方向一致。" % (
            len(mut), lean, regime_score, lz)

    now = datetime.now(timezone.utc)
    now_iso = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    dgs10_reference = build_dgs10_reference(prev, now_iso)
    reference_series = {
        DTWEXBGS_ID: build_dtwexbgs_reference(prev, now_iso),
        RWTC_ID: build_rwtc_reference(prev, now_iso),
    }

    live = hit >= 6  # 至少 6 个 Yahoo 底层序列命中才算 LIVE，否则保留上次
    if not live and prev:
        fallback_out = copy.deepcopy(prev)
        fallback_out["macro"] = upsert_dgs10_macro(fallback_out.get("macro"), dgs10_reference)
        fallback_out["referenceSeries"] = reference_series
        os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
        with open(OUT_PATH, "w", encoding="utf-8") as f:
            json.dump(fallback_out, f, ensure_ascii=False, indent=2)
        health = make_macro_health(
            fallback_out, attempted_at=now_iso, previous_health=prev_health,
        )
        write_macro_health(HEALTH_PATH, health)
        print("有效Yahoo数据源不足（hit=%d），保留原面板；仅更新DGS10/DTWEXBGS/RWTC逐源状态。" % hit)
        return

    # —— 宏观管道（FRED 需 key；波动率全景 Yahoo）——
    macro = upsert_dgs10_macro(build_macro(), dgs10_reference)
    macro_series = sum(len(c["rows"]) for c in macro)
    has_fred = (any(c["src"] == "FRED" for c in macro)
                or reference_series[DTWEXBGS_ID]["status"] in ("ok", "stale"))
    has_eia = reference_series[RWTC_ID]["status"] in ("ok", "stale")

    sh = now + timedelta(hours=8)
    out = {
        "updatedAt": now_iso,
        "asOf": now.strftime("%Y-%m-%d"),
        "asOfSh": sh.strftime("%Y-%m-%d %H:%M"),
        "live": live,
        "source": ("FRED · EIA · Yahoo Finance · 交易所行情" if has_fred and has_eia else
                   "FRED · Yahoo Finance · 交易所行情" if has_fred else
                   "EIA · Yahoo Finance · 交易所行情" if has_eia else
                   "Yahoo Finance · 交易所行情"),
        "regime": {"score": regime_score, "labelZh": lz, "labelEn": le,
                   "desc": regime_desc},
        "signals": signals,
        "mutations": mut,
        "mutSummary": mut_summary,
        "macro": macro,
        "referenceSeries": reference_series,
        "note": ("制度信号为 0–100 相对分位读数，越高越偏『宽松·支持』；"
                 "信用/期限/流动性/增长/广度为市场化代理指标"
                 "（HYG÷LQD、10Y−3M 曲线、3M 短端利率、铜金比、等权·市值加权）；"
                 "实际利率取 5 年期 TIPS 实际收益率（DFII5）；"
                 "宏观管道取自 FRED 官方数据。每日自动更新，仅供研究，非投资建议。"),
    }
    if prev and not macro and prev.get("macro"):
        out["macro"] = prev["macro"]  # 本次宏观全挂时沿用上次，避免面板空白
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    health = make_macro_health(out, attempted_at=now_iso, previous_health=prev_health)
    write_macro_health(HEALTH_PATH, health)
    print("写入 %s：机制 %s(%s)，信号 %d，异动 %d，宏观 %d 项(FRED=%s)，LIVE=%s"
          % (OUT_PATH, regime_score, lz, len(signals), len(mut),
             macro_series, has_fred, live))


if __name__ == "__main__":
    build()

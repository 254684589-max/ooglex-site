#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""基本面适配器：SEC XBRL。唯一与数据源耦合的文件，换源只换这一个。

## 为什么选 SEC，而不是某个行情站的基本面端点

1. **这是美国政府的公开披露。** EDGAR 存在的目的就是向公众分发这些数字，
   不需要我去解释某家私营公司的使用条款 —— 而条款解释正是我在这个环境里最不该
   替 owner 做的事（没有外网，核实不了当前条款）。
2. **一手数据。** 数字来自公司自己递交的报表，不是某个厂商加工过的产品，
   所以不存在「再分发别人的编纂成果」这个问题。
3. **比率由我们自己算，口径因此是我们自己的、可写明的。** 一手披露给的是报表项
   （营收、净利、权益、股数），PE/PB/ROE 全是按写在页面上的公式现算 —— 这比抄
   一个别人算好的 PE 干净，因为别人的口径你未必知道。
4. **SEC 的访问要求是可实现的工程约束，不是需要解释的法律条款**：声明
   User-Agent（含联系方式）、限速。两条下面都实现了。

## 两处硬限制，如实说明

**一、联系邮箱不写死在代码里。** SEC 要求 User-Agent 带联系方式。那是 owner 的
邮箱，属于个人信息，不该由我填进仓库、更不该由我替 owner 发给第三方服务。改为从
环境变量 `SEC_CONTACT` 读；没设就直接失败并给出设置方法，不偷偷用默认值去撞
SEC 的限流策略。

**二、我没法在开发容器里验证返回结构。** 这个容器没有外网（FRED / Yahoo / SEC
全部返回 000）。所以下面对每个响应都做显式结构校验：形状不对就抛异常，让上层保留
上一份 JSON，**绝不把猜错的结构写成数据**。第一次真实运行在 CI 里。

## 取数策略：用 frames 而不是 companyfacts

`companyfacts` 是一家公司一次调用、返回该公司全部历史，450 家就是 450 次、每次
几 MB。`frames` 是一个标签一个期间一次调用、返回**所有申报人**的该项值 —— 八个
标签 × 几个期间 ≈ 几十次调用，CI 里跑得动。

## 覆盖面：只有美国申报人

SEC 只有向它申报的公司。台积电、三星这类非美申报人（或只发 ADR 的）可能完全没有、
或只有 20-F 的部分项。缺就是缺，**返回 None，不返回 0** —— 0 是一个有意义的值。
"""
from __future__ import annotations

import json
import os
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"
FRAMES_URL = "https://data.sec.gov/api/xbrl/frames/us-gaap/{tag}/{unit}/{period}.json"

SOURCE_NAME = "SEC EDGAR XBRL"
DOC_URL = "https://www.sec.gov/search-filings/edgar-application-programming-interfaces"

# SEC 公布的自动化访问上限是每秒 10 次。这里取每次 0.15 秒（≈6.7 次/秒）留出余量：
# 被限流的代价是整轮失败，跑快一点省下的几秒不值这个风险。
MIN_INTERVAL = 0.15
TIMEOUT = 30

# 需要的报表项。每项都可能缺 —— 不同公司用的标签不完全一样，缺了就是 None。
# duration = 期间数（营收、净利），instant = 时点数（权益、股数）。
WANT: list[tuple[str, str, str]] = [
    ("Revenues", "USD", "duration"),
    ("RevenueFromContractWithCustomerExcludingAssessedTax", "USD", "duration"),
    ("NetIncomeLoss", "USD", "duration"),
    ("StockholdersEquity", "USD", "instant"),
    ("Assets", "USD", "instant"),
    ("Liabilities", "USD", "instant"),
    ("EarningsPerShareDiluted", "USD/shares", "duration"),
]


class AdapterError(RuntimeError):
    """取数或结构校验失败。上层据此保留上一份 JSON，不写半份数据。"""


def _contact() -> str:
    """SEC 要求 User-Agent 带联系方式。这是 owner 的个人信息，必须由 owner 自己设。"""
    v = (os.environ.get("SEC_CONTACT") or "").strip()
    if not v or "@" not in v:
        raise AdapterError(
            "未设置 SEC_CONTACT。SEC 要求自动化访问在 User-Agent 里声明联系方式，"
            "而那是你的邮箱、不该写死在仓库里。\n"
            "设置方法：GitHub → 仓库 Settings → Secrets and variables → Actions → "
            "Variables → New repository variable，名字 SEC_CONTACT，值填你愿意对 SEC "
            "公开的联系邮箱。本地跑可以 export SEC_CONTACT=you@example.com。\n"
            "没有它就不发请求 —— 不带联系方式撞 SEC 的限流策略是拿你的 IP 去冒险。"
        )
    return v


_last_call = [0.0]


def _get(url: str) -> Any:
    """带 User-Agent 与限速的 GET。非 2xx、超时、JSON 解析失败都抛 AdapterError。"""
    wait = MIN_INTERVAL - (time.monotonic() - _last_call[0])
    if wait > 0:
        time.sleep(wait)
    req = Request(url, headers={
        "User-Agent": f"ooglex.com fundamentals pipeline ({_contact()})",
        "Accept": "application/json",
        "Accept-Encoding": "gzip, deflate",
    })
    try:
        with urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read()
    except HTTPError as exc:
        raise AdapterError(f"{url} 返回 HTTP {exc.code}") from exc
    except URLError as exc:
        raise AdapterError(f"{url} 请求失败：{exc.reason}") from exc
    finally:
        _last_call[0] = time.monotonic()
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise AdapterError(f"{url} 返回的不是合法 JSON：{exc}") from exc


def ticker_to_cik() -> dict[str, int]:
    """ticker → CIK。company_tickers.json 的结构是 {"0": {cik_str, ticker, title}, ...}。

    结构不符就抛异常 —— 我在开发容器里验证不了它，所以运行时必须自己确认。
    """
    data = _get(TICKERS_URL)
    if not isinstance(data, dict) or not data:
        raise AdapterError("company_tickers.json 不是预期的非空对象")
    out: dict[str, int] = {}
    for row in data.values():
        if not isinstance(row, dict):
            continue
        tk = row.get("ticker")
        cik = row.get("cik_str")
        if isinstance(tk, str) and tk and isinstance(cik, int):
            out[tk.upper()] = cik
    if len(out) < 1000:
        raise AdapterError(
            f"company_tickers.json 只解析出 {len(out)} 条 ticker→CIK，"
            "远低于预期（SEC 登记的申报人有上万家）—— 结构可能变了，不继续。"
        )
    return out


def _frame(tag: str, unit: str, period: str) -> dict[int, dict[str, Any]]:
    """取一个 frame，返回 {cik: {val, end, accn, fy, fp, form}}。

    frames 响应的预期结构：{"taxonomy","tag","unit","label","pts",
                            "data":[{"cik","entityName","val","end",...}, ...]}
    """
    data = _get(FRAMES_URL.format(tag=tag, unit=unit, period=period))
    if not isinstance(data, dict):
        raise AdapterError(f"frames({tag},{period}) 返回的不是对象")
    rows = data.get("data")
    if not isinstance(rows, list):
        raise AdapterError(f"frames({tag},{period}) 缺少 data 数组")
    out: dict[int, dict[str, Any]] = {}
    for r in rows:
        if not isinstance(r, dict):
            continue
        cik, val = r.get("cik"), r.get("val")
        if not isinstance(cik, int) or not isinstance(val, (int, float)):
            continue
        out[cik] = {"val": float(val), "end": r.get("end"),
                    "fy": r.get("fy"), "fp": r.get("fp"), "form": r.get("form")}
    return out


def _periods(kind: str, year: int, back: int = 3) -> list[str]:
    """生成候选期间标识，从新到旧。frames 的期间写法：
       duration 年报 CY2025；instant 时点 CY2025Q4I。
       最近一期常常还没归档，所以往回多试几年，取到就停。
    """
    if kind == "instant":
        return [f"CY{year - i}Q4I" for i in range(back)]
    return [f"CY{year - i}" for i in range(back)]


def fetch(symbols: list[str], *, year: int, log=print) -> dict[str, dict[str, Any]]:
    """返回 {symbol: {字段: 值或 None, ...}}。

    取不到的字段一律 None，不返回 0。整体结构校验失败时抛 AdapterError，
    让上层保留上一份 JSON。
    """
    want = {s.upper() for s in symbols if s and s != "—"}
    cikmap = ticker_to_cik()
    hit = {s: cikmap[s] for s in want if s in cikmap}
    log(f"  ticker→CIK：{len(cikmap)} 条登记，命中站内 {len(hit)}/{len(want)} 个标的")
    if not hit:
        raise AdapterError("站内标的没有一个能对上 SEC 的 CIK —— 不继续")

    by_cik: dict[int, dict[str, Any]] = {c: {} for c in hit.values()}
    used_periods: dict[str, str] = {}

    for tag, unit, kind in WANT:
        got = {}
        for period in _periods(kind, year):
            try:
                frame = _frame(tag, unit, period)
            except AdapterError as exc:
                log(f"  {tag} {period}：{exc}")
                continue
            # 只要这一期覆盖到了站内一部分标的就用它，并记下实际用的是哪一期
            covered = sum(1 for c in by_cik if c in frame)
            log(f"  {tag} {period}：{len(frame)} 家申报，覆盖站内 {covered}")
            if covered:
                got = frame
                used_periods[tag] = period
                break
        for cik in by_cik:
            row = got.get(cik)
            by_cik[cik][tag] = row["val"] if row else None
            if row and row.get("end"):
                by_cik[cik].setdefault("_ends", {})[tag] = row["end"]

    if not used_periods:
        raise AdapterError("所有标签所有期间都没取到数据 —— 不写任何东西")

    out: dict[str, dict[str, Any]] = {}
    for sym, cik in hit.items():
        f = by_cik.get(cik) or {}
        ends = f.get("_ends") or {}
        # 营收有两个常用标签，取到哪个用哪个（不同公司用法不同）
        rev = f.get("Revenues")
        if rev is None:
            rev = f.get("RevenueFromContractWithCustomerExcludingAssessedTax")
        out[sym] = {
            "cik": cik,
            "revenue": rev,
            "netIncome": f.get("NetIncomeLoss"),
            "equity": f.get("StockholdersEquity"),
            "assets": f.get("Assets"),
            "liabilities": f.get("Liabilities"),
            "epsDiluted": f.get("EarningsPerShareDiluted"),
            "ends": ends,
        }
    return {"rows": out, "periods": used_periods,
            "source": SOURCE_NAME, "docUrl": DOC_URL,
            "matched": len(hit), "requested": len(want)}

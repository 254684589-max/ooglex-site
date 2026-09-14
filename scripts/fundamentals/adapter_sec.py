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

import gzip
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
# 单位串是 URL 路径的一段，**斜杠会把路径切断**。frames 的约定是把 `/` 写成
# `-per-`，所以每股收益是 `USD-per-shares` 而不是 `USD/shares`。第一版写了斜杠，
# 结果每个期间都 404、这个标签一条数据都没取到，PE 因此全是 None —— 而当时的
# 闸门只问「至少有一个比率」，就把 PE 全空的文件放过去了。
WANT: list[tuple[str, str, str]] = [
    ("Revenues", "USD", "duration"),
    ("RevenueFromContractWithCustomerExcludingAssessedTax", "USD", "duration"),
    ("NetIncomeLoss", "USD", "duration"),
    ("EarningsPerShareDiluted", "USD-per-shares", "duration"),
    ("StockholdersEquity", "USD", "instant"),
    ("Assets", "USD", "instant"),
    ("Liabilities", "USD", "instant"),
]

# 选期间用的探针标签：先用它在候选期间里挑出覆盖最好的那一期，同类的其余标签
# 都取同一期。这样同类标签之间口径一致 —— 否则营收可能来自 CY2024、净利来自
# CY2025，算出来的净利率是两个年度的拼接。
PROBE = {"duration": "NetIncomeLoss", "instant": "Assets"}

# 一期至少要覆盖站内多少比例的标的才算可用。第一版是「覆盖到任何一个就用」，
# 结果在 9 月被少数非日历财年的早报公司劫持：CY2026 只覆盖十几家，却因为
# 「有覆盖」就停下，把能覆盖几百家的 CY2025 整整跳过。
MIN_TAG_COVERAGE = 0.25


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


GZIP_MAGIC = b"\x1f\x8b"


def _decompress(raw: bytes, encoding: str) -> bytes:
    """按 Content-Encoding 解压。

    **这里踩过一次真坑，记下来。** 第一版在请求头里发了
    `Accept-Encoding: gzip, deflate`，却没写解压 —— 而 `urllib` **不会**自动解压
    （`requests` 会，`urllib` 不会）。SEC 照着这个头返回了 gzip 字节流，
    `json.loads` 拿到 `\x1f\x8b...` 当场抛 UnicodeDecodeError：
    `'utf-8' codec can't decode byte 0x8b in position 1`。
    **发了一个自己没实现的头，就是在要求对方给你处理不了的东西。**

    两处稳妥做法：
      1. 只声明 gzip，不声明 deflate —— deflate 有 zlib 包装与裸流两种，
         服务器给哪种要猜，而 gzip 只有一种，没有歧义。
      2. 除了看 Content-Encoding，**再嗅一次魔数**：经过代理或某些网关时
         头可能被剥掉而正文仍是压缩的。两条任一命中就解压。
    """
    if "gzip" in encoding or raw[:2] == GZIP_MAGIC:
        try:
            return gzip.decompress(raw)
        except (OSError, EOFError) as exc:
            raise AdapterError(f"响应声明是 gzip 但解不开：{exc}") from exc
    return raw


def _get(url: str) -> Any:
    """带 User-Agent 与限速的 GET。

    任何取数或解码失败都收敛成 AdapterError —— 这一点是硬要求：上层只捕获
    AdapterError 才会走「保留上一份 JSON 不覆盖」那条路。漏出去一个别的异常型，
    整个脚本会带着 traceback 崩掉，**那条保护路径就被绕过了**（第一版的
    UnicodeDecodeError 正是这样漏出去的）。所以这里兜底捕获 Exception。
    """
    wait = MIN_INTERVAL - (time.monotonic() - _last_call[0])
    if wait > 0:
        time.sleep(wait)
    try:
        req = Request(url, headers={
            "User-Agent": f"ooglex.com fundamentals pipeline ({_contact()})",
            "Accept": "application/json",
            # 只声明 gzip：frames 的响应有几 MB，压缩值得留着；deflate 去掉是因为
            # 它有两种封装、要猜，而下面的 _decompress 只保证 gzip 这一种。
            "Accept-Encoding": "gzip",
        })
        with urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read()
            enc = (resp.headers.get("Content-Encoding") or "").lower()
    except HTTPError as exc:
        raise AdapterError(f"{url} 返回 HTTP {exc.code}") from exc
    except URLError as exc:
        raise AdapterError(f"{url} 请求失败：{exc.reason}") from exc
    except Exception as exc:            # 连 Request() 构造在内，一律不许漏出去
        raise AdapterError(f"{url} 请求阶段出错（{type(exc).__name__}）：{exc}") from exc
    finally:
        _last_call[0] = time.monotonic()

    try:
        raw = _decompress(raw, enc)
        return json.loads(raw)
    except AdapterError:
        raise                                     # 已经是想要的类型，原样上抛
    except json.JSONDecodeError as exc:
        raise AdapterError(f"{url} 返回的不是合法 JSON：{exc}") from exc
    except UnicodeDecodeError as exc:
        raise AdapterError(
            f"{url} 的响应不是 UTF-8 文本（前两字节 {raw[:2]!r}，"
            f"Content-Encoding={enc or '空'}）——可能是没解开的压缩流：{exc}"
        ) from exc
    except Exception as exc:                      # 兜底：绝不让非 AdapterError 漏出去
        raise AdapterError(f"{url} 解析响应时出错（{type(exc).__name__}）：{exc}") from exc


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

       **不是「取到就停」** —— 见 MIN_TAG_COVERAGE 那段注释。这里只负责给出候选，
       挑哪一期由 _pick_period 按覆盖面决定。
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
    coverage: dict[str, int] = {}
    need = max(1, int(len(hit) * MIN_TAG_COVERAGE))

    def absorb(tag: str, frame: dict[int, dict[str, Any]]) -> None:
        for cik in by_cik:
            row = frame.get(cik)
            by_cik[cik][tag] = row["val"] if row else None
            if row and row.get("end"):
                by_cik[cik].setdefault("_ends", {})[tag] = row["end"]

    def _pick_period(kind: str) -> tuple[str | None, dict[int, dict[str, Any]]]:
        """用探针标签在候选期间里挑覆盖最好的一期。

        **挑最好的，不是挑第一个有覆盖的。** 现在是 9 月，只有少数非日历财年的
        公司报了本年度年报；「第一个有覆盖」会选中 CY2026（十几家），把能覆盖
        几百家的 CY2025 整整跳过 —— 第一版就是这么坏的。
        """
        probe, best, best_frame, best_n = PROBE[kind], None, {}, -1
        for period in _periods(kind, year):
            try:
                frame = _frame(probe, "USD", period)
            except AdapterError as exc:
                log(f"  探针 {probe} {period}：{exc}")
                continue
            n = sum(1 for c in by_cik if c in frame)
            log(f"  探针 {probe} {period}：{len(frame)} 家申报，覆盖站内 {n}")
            if n > best_n:
                best, best_frame, best_n = period, frame, n
        if best is None or best_n < need:
            log(f"  {kind} 类：最好的一期只覆盖 {max(best_n, 0)} 家，"
                f"低于下限 {need}（{MIN_TAG_COVERAGE:.0%}）—— 这一类整体不取")
            return None, {}
        log(f"  {kind} 类定为 {best}（覆盖 {best_n} 家），同类标签都取这一期")
        return best, best_frame

    for kind in ("duration", "instant"):
        period, probe_frame = _pick_period(kind)
        probe = PROBE[kind]
        if period is None:
            for tag, _u, k in WANT:
                if k == kind:
                    absorb(tag, {})
            continue
        absorb(probe, probe_frame)
        used_periods[probe] = period
        coverage[probe] = sum(1 for c in by_cik if c in probe_frame)
        for tag, unit, k in WANT:
            if k != kind or tag == probe:
                continue
            try:
                frame = _frame(tag, unit, period)
            except AdapterError as exc:
                log(f"  {tag} {period}：{exc} —— 该项按缺失处理（None，不写 0）")
                absorb(tag, {})
                continue
            n = sum(1 for c in by_cik if c in frame)
            log(f"  {tag} {period}：{len(frame)} 家申报，覆盖站内 {n}")
            absorb(tag, frame)
            used_periods[tag] = period
            coverage[tag] = n

    # ── ROE 的分母必须和分子同期 ────────────────────────────────────────────
    # 期间类与时点类各自按覆盖面挑期，结果可能不是同一个财年：实测利润表挑到
    # CY2024（净利覆盖 366 家最好）、资产负债表挑到 CY2025Q4I（资产覆盖 391 家）。
    # 那么 ROE = 2024 年净利 ÷ 2025 年末权益，**混了两个时点**。
    #
    # PB 用最新账面价值是对的（市价是今天的，账面取最近一期），所以时点期不改；
    # 这里另取一次「与利润表同财年」的权益，专门给 ROE 当分母。多一次请求，
    # 换一个口径自洽的 ROE。取不到就让 ROE 为 None —— 不拿跨期的数凑一个。
    dur_period = used_periods.get(PROBE["duration"])
    if dur_period and dur_period.startswith("CY"):
        try:
            dur_year = int(dur_period[2:6])
        except ValueError:
            dur_year = None
        if dur_year is not None:
            aligned = f"CY{dur_year}Q4I"
            if aligned == used_periods.get("StockholdersEquity"):
                for cik in by_cik:                     # 已经同期，直接复用
                    by_cik[cik]["_equityAligned"] = by_cik[cik].get("StockholdersEquity")
                used_periods["_equityAligned"] = aligned
            else:
                try:
                    frame = _frame("StockholdersEquity", "USD", aligned)
                    n = sum(1 for c in by_cik if c in frame)
                    log(f"  与利润表同期的权益 {aligned}：覆盖站内 {n}（专供 ROE 当分母）")
                    for cik in by_cik:
                        row = frame.get(cik)
                        by_cik[cik]["_equityAligned"] = row["val"] if row else None
                    used_periods["_equityAligned"] = aligned
                    coverage["_equityAligned"] = n
                except AdapterError as exc:
                    log(f"  与利润表同期的权益 {aligned}：{exc} —— ROE 将为 None，"
                        "不拿跨期的权益当分母")

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
            # 与利润表同财年的权益，只给 ROE 当分母；PB 仍用最新那一期
            "equityAligned": f.get("_equityAligned"),
            "ends": ends,
        }
    return {"rows": out, "periods": used_periods, "coverage": coverage,
            "source": SOURCE_NAME, "docUrl": DOC_URL,
            "matched": len(hit), "requested": len(want)}

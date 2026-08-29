#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""常备探测：候选行情来源在 Actions 机房到底取不取得到（商品、指数、小时线、国债）。

这个脚本只回答一个问题——「这个代码有没有真实可用的公开序列」，因此：

- 只读。不写仓库里的任何数据文件，也不改任何清单；
- 逐个候选独立 try/except，单个失败不影响其余；
- 输出逐条结果（最新观测日、最新值、观测点数、频率），供人工挑选后再登记；
- 密钥只从环境变量读取，绝不打印。

背景：2026-08-28 扩容凭印象登记了 `B0=F`，实测返回「行情数据点不足」，那一行
unavailable 把整条日更管道标成 degraded，还弄红了发布校验。同一轮还差点登记
`QA=F`——它在数据源上真实存在，但返回的是 GBP/AUD 汇率而不是原油。

因此这个脚本是常备工具而不是一次性脚手架：**往任何行情清单里加代码之前，先把候选
写进下面的数组、跑一次 Commodity Source Probe 工作流，只登记 [OK] 且名称与计价单位
都对得上的那些。** 它只读、不写仓库、不改任何清单，跑一次的代价远小于一次错误登记。
"""
from __future__ import annotations

import json
import os
import sys
import time
from urllib import error, parse, request

TIMEOUT = 20
GAP = 0.25          # 逐个请求之间留出间隔，不给对方造成压力
MIN_POINTS = 2      # 少于两个观测就画不出变化，等同于没有

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/123.0 Safari/537.36")

# ── FRED 候选 ────────────────────────────────────────────────────────────
# 参考站（TradingEconomics）列出但站内没有的品种，优先找官方公开序列。
# 日频：EIA 经 FRED 发布的现货价；月频：IMF Primary Commodity Prices。
FRED_CANDIDATES = [
    # 能源 · 日频现货
    ("DCOILBRENTEU", "布伦特原油现货"),
    ("DCOILWTICO", "WTI原油现货"),
    ("DHHNGSP", "亨利港天然气现货"),
    ("DPROPANEMBTX", "蒙贝尔维尤丙烷现货"),
    ("DJFUELUSGULF", "美湾航空煤油现货"),
    ("DHOILNYH", "纽约港取暖油现货"),
    ("DGASNYH", "纽约港汽油现货"),
    ("DGASUSGULF", "美湾汽油现货"),
    ("GASREGW", "美国普通汽油零售均价"),
    # 能源 · 月频
    ("PNGASEUUSDM", "欧洲天然气"),
    ("PNGASJPUSDM", "日本液化天然气"),
    ("PCOALAUUSDM", "澳大利亚动力煤"),
    ("PURANUSDM", "铀"),
    # 金属 · 月频
    ("PIORECRUSDM", "铁矿石"),
    ("PALUMUSDM", "铝"),
    ("PCOPPUSDM", "铜"),
    ("PNICKUSDM", "镍"),
    ("PZINCUSDM", "锌"),
    ("PLEADUSDM", "铅"),
    ("PTINUSDM", "锡"),
    ("PGOLDUSDM", "黄金"),
    ("PSILVERUSDM", "白银"),
    ("PPLATUSDM", "铂金"),
    # 农产品 · 月频
    ("PRUBBUSDM", "橡胶"),
    ("PPOILUSDM", "棕榈油"),
    ("PSUNOUSDM", "葵花籽油"),
    ("POLVOILUSDM", "橄榄油"),
    ("PROILUSDM", "菜籽油"),
    ("PSOILUSDM", "豆油"),
    ("PSMEAUSDM", "豆粕"),
    ("PBARLUSDM", "大麦"),
    ("PMAIZMTUSDM", "玉米"),
    ("PWHEAMTUSDM", "小麦"),
    ("PRICENPQUSDM", "大米"),
    ("PSOYBUSDM", "大豆"),
    ("PCOFFOTMUSDM", "咖啡"),
    ("PCOCOUSDM", "可可"),
    ("PSUGAISAUSDM", "食糖"),
    ("PCOTTINDUSDM", "棉花"),
    ("PTEAUSDM", "茶叶"),
    ("PORANGUSDM", "橙"),
    ("PBANSOPUSDM", "香蕉"),
    ("PWOOLCUSDM", "粗羊毛"),
    ("PWOOLFUSDM", "细羊毛"),
    ("PLOGSKUSDM", "原木"),
    ("PSAWMALUSDM", "锯材"),
    ("PHARDWUSDM", "硬木"),
    # 畜牧与水产 · 月频
    ("PBEEFUSDM", "牛肉"),
    ("PPORKUSDM", "猪肉"),
    ("PPOULTUSDM", "禽肉"),
    ("PSALMUSDM", "三文鱼"),
    ("PSHRIUSDM", "虾"),
    ("PFISHUSDM", "鱼粉"),
    # 商品指数 · 月频
    ("PALLFNFINDEXM", "IMF全部初级商品指数"),
    ("PNRGINDEXM", "IMF能源指数"),
    ("PMETAINDEXM", "IMF金属指数"),
    ("PFOODINDEXM", "IMF食品指数"),
    ("PAGRIINDEXM", "IMF农业原料指数"),
    ("PRAWMINDEXM", "IMF工业原料指数"),
]

# ── Yahoo 候选 ───────────────────────────────────────────────────────────
# 上一轮凭印象登记而没实测的那几个，这次一并验证清楚。
YAHOO_CANDIDATES = [
    ("RS=F", "ICE油菜籽期货"),
    ("DC=F", "CME三类牛奶期货"),
    ("CSC=F", "CME奶酪期货"),
    ("HRC=F", "热轧卷板钢期货"),
    ("TTF=F", "荷兰TTF天然气期货"),
    ("B0=F", "蒙贝尔维尤丙烷期货（上轮失败，复核）"),
    ("ALW=F", "LME铝远期"),
    ("QA=F", "迷你原油"),
    ("DBA", "农产品篮子ETF"),
    ("DBE", "能源篮子ETF"),
    ("CPER", "美国铜指数基金"),
    ("PALL", "实物钯ETF"),
    ("PPLT", "实物铂ETF"),
    ("WEAT", "小麦ETF"),
    ("CORN", "玉米ETF"),
    ("SOYB", "大豆ETF"),
    ("CANE", "食糖ETF"),
    ("UNG", "美国天然气基金"),
    ("USO", "美国原油基金"),
    ("BNO", "布伦特原油基金"),
    ("UGA", "美国汽油基金"),
    ("URA", "铀矿业ETF（矿股，非铀价）"),
    ("SRUUF", "斯普鲁特实物铀信托"),
    ("SLX", "钢铁ETF（矿股，非钢价）"),
    ("REMX", "稀土战略金属ETF（矿股）"),
    ("LIT", "锂电ETF（股票）"),
    ("WOOD", "林业木材ETF（股票）"),
    ("COMT", "iShares商品动态展期ETF"),
    ("PDBC", "景顺优化收益多元商品ETF"),
    ("BCI", "abrdn彭博全商品ETF"),
    ("FTGC", "First Trust全球战术商品ETF"),
    ("GCC", "WisdomTree增强商品ETF"),
]


# ── 小时线候选 ───────────────────────────────────────────────────────────
# 4小时线要由小时线聚合而来。这里逐类各取代表标的，确认三件事：
# 能不能取到、返回的是不是这个标的本身（名称与计价单位）、覆盖多长时间。
HOURLY_CANDIDATES = [
    ("GC=F", "COMEX黄金期货"),
    ("CL=F", "WTI原油期货"),
    ("TTF=F", "荷兰TTF天然气期货（欧元计价）"),
    ("HRC=F", "热轧卷板钢期货"),
    ("^GSPC", "标普500指数"),
    ("^HSI", "恒生指数"),
    ("USDJPY=X", "美元兑日元"),
    ("EURUSD=X", "欧元兑美元"),
    ("NVDA", "英伟达（股票）"),
    ("TLT", "美国长期国债ETF"),
    ("KRBN", "全球碳排放权ETF"),
    ("BTC-USD", "比特币（Yahoo代码）"),
    ("ETH-USD", "以太坊（Yahoo代码）"),
]


# ── 指数候选 ─────────────────────────────────────────────────────────────
# 参考站（TradingEconomics）的 Indexes 分区列了一百多条，站内目前 38 条。
# 这里把「参考站有、站内没有」的按地区列成候选，逐个确认三件事：能不能取到、
# 返回的到底是不是这条指数（名称 + instrumentType 必须是 INDEX，不能是汇率或个股）、
# 计价币种是什么。凭印象登记的代价见本文件开头的 B0=F 与 QA=F。
INDEX_CANDIDATES = [
    # —— 欧洲 ——
    ("^STOXX50E", "欧元区斯托克50"),
    ("^N100", "泛欧Euronext 100"),
    ("^MDAXI", "德国MDAX中盘"),
    ("^SDAXI", "德国SDAX小盘"),
    ("^TECDAX", "德国TecDAX科技"),
    ("^SX7E", "欧元区斯托克银行"),
    ("OSEBX.OL", "挪威OSEBX"),
    ("^OSEAX", "挪威奥斯陆全指"),
    ("^OMXC25", "丹麦OMXC25"),
    ("^OMXH25", "芬兰OMXH25"),
    ("^OMXHPI", "芬兰赫尔辛基全指"),
    ("^ISEQ", "爱尔兰ISEQ"),
    ("GD.AT", "希腊雅典综合"),
    ("PSI20.LS", "葡萄牙PSI"),
    ("^PX", "捷克PX"),
    ("^BUX", "匈牙利BUX"),
    ("BUX.BD", "匈牙利BUX（布达佩斯所）"),
    ("^SOFIX", "保加利亚SOFIX"),
    ("^BETI", "罗马尼亚BET"),
    ("WIG.WA", "波兰WIG全指"),
    ("WIG20.WA", "波兰WIG20"),
    ("^OMXRGI", "拉脱维亚里加全指"),
    ("^OMXVGI", "立陶宛维尔纽斯全指"),
    ("^OMXTGI", "爱沙尼亚塔林全指"),
    ("^OMXIPI", "冰岛全指"),
    ("^CRBEX", "克罗地亚CROBEX"),
    ("IMOEX.ME", "俄罗斯MOEX"),
    # —— 美洲 ——
    ("^RUI", "美国罗素1000"),
    ("^NYA", "纽约证交所综合"),
    ("^SP400", "标普400中盘"),
    ("^W5000", "威尔希尔5000全市场"),
    ("^IPSA", "智利IPSA（现由ETF代理）"),
    ("^COLCAP", "哥伦比亚COLCAP"),
    ("^MERV", "阿根廷MERVAL（已在站内，作对照）"),
    # —— 亚洲 ——
    ("000001.SS", "上证综合指数"),
    ("000016.SS", "上证50"),
    ("399001.SZ", "深证成指"),
    ("399006.SZ", "创业板指"),
    ("^NSEI", "印度NIFTY50"),
    ("^HSCE", "恒生中国企业指数"),
    ("^KS200", "韩国KOSPI200"),
    ("^TASI.SR", "沙特TASI"),
    ("^KSE", "巴基斯坦KSE100"),
    ("^TA35.TA", "以色列TA-35"),
    ("^SET.BK", "泰国SET（现由ETF代理）"),
    ("PSEI.PS", "菲律宾PSEi（现由ETF代理）"),
    ("^VNINDEX", "越南VN指数"),
    ("^DFMGI", "迪拜DFM综合"),
    ("^ADI", "阿布扎比ADX综合"),
    # —— 大洋洲 ——
    ("^AORD", "澳洲全普通股"),
    ("^AXKO", "澳洲标普300"),
    # —— 中东非洲 ——
    ("^CASE30", "埃及EGX30"),
    ("^JN0U.JO", "南非Top40（美元计）"),
    ("^J203.JO", "南非全股指数"),
    ("^NGSEINDX", "尼日利亚全股指数"),
]


# ── 标普500成分股名单候选 ────────────────────────────────────────────────
# 站内的公司榜是「全球市值前500」，不是标普500：里面有台积电、沙特阿美、三星、
# 阿斯麦，还有 50 家未上市公司。两者是不同的集合，不能拿一个冒充另一个。
# 要做真的标普500，先得拿到真的成分股名单。这里探测几个公开来源，比较：
# 能不能取到、条数是不是 ~503、以及取到的代码彼此对不对得上。
SP500_SOURCES = [
    ("datahub-csv",
     "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/main/data/constituents.csv"),
    ("datahub-csv-master",
     "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/master/data/constituents.csv"),
    ("wikipedia-api",
     "https://en.wikipedia.org/w/api.php?action=parse&page=List_of_S%26P_500_companies"
     "&prop=wikitext&section=1&format=json"),
    ("ishares-ivv",
     "https://www.ishares.com/us/products/239726/ishares-core-sp-500-etf/1467271812596.ajax"
     "?fileType=csv&fileName=IVV_holdings&dataType=fund"),
]


def probe_sp500(name: str, url: str) -> dict:
    """标普500成分名单：只关心「取不取得到」与「像不像一份 ~503 条的成分表」。

    不同来源格式不同（CSV / Wiki 源码），这里统一用一个宽松的代码抽取：
    找出所有像股票代码的 token，去重后报条数与样例，由人核对。
    """
    import re
    try:
        text = get_text(url)
    except (error.HTTPError, error.URLError, ValueError) as exc:
        return {"ok": False, "why": f"{type(exc).__name__}: {str(exc)[:70]}"}
    if not text or len(text) < 200:
        return {"ok": False, "why": f"响应过短（{len(text)}字节）"}
    if name.startswith("datahub") or name.startswith("ishares"):
        rows = [line.split(",")[0].strip().strip('"') for line in text.splitlines()[1:]]
        symbols = [s for s in rows if re.fullmatch(r"[A-Z][A-Z.\-]{0,6}", s)]
    else:
        symbols = re.findall(r"\{\{NYSE\|([A-Z.\-]{1,7})\}\}|\{\{Nasdaq\|([A-Z.\-]{1,7})\}\}", text)
        symbols = [a or b for a, b in symbols]
    unique = sorted(set(symbols))
    return {
        "ok": len(unique) >= 400, "count": len(unique), "bytes": len(text),
        "sample": unique[:8], "why": "" if len(unique) >= 400 else f"只抽到 {len(unique)} 个代码",
    }


def probe_sp500_coverage() -> dict:
    """把成分名单与站内 universe.json 对一遍，报覆盖度与缺口。

    universe.json 里每条都带流通股数，市值就是「价 × 股数」；名单里有、清单里没有的
    那几家算不出市值，也就进不了热力图——这个缺口必须量出来并写到页面上。
    """
    import csv, io, os.path
    url = SP500_SOURCES[0][1]
    try:
        text = get_text(url)
    except (error.HTTPError, error.URLError, ValueError) as exc:
        return {"ok": False, "why": f"{type(exc).__name__}: {str(exc)[:60]}"}
    rows = list(csv.DictReader(io.StringIO(text)))
    members = {r["Symbol"].strip(): r for r in rows if r.get("Symbol")}
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "companies", "universe.json"), encoding="utf-8") as handle:
        universe = json.load(handle)
    known = {u["symbol"] for u in universe if u.get("symbol")}
    us_known = {u["symbol"] for u in universe if u.get("country") == "US"}
    missing = sorted(set(members) - known)
    return {
        "ok": True, "total": len(members), "covered": len(set(members) & known),
        "missing": missing, "extraUS": sorted(us_known - set(members)),
        "sectors": sorted({(r.get("GICS Sector") or "").strip() for r in rows if r.get("GICS Sector")}),
    }


def probe_index(symbol: str) -> dict:
    """指数候选：除了「取不取得到」，还要确认它到底是不是一条指数。

    QA=F 的教训是「取得到，但返回的是别的东西」。这里额外读回 instrumentType 与
    交易所名称：不是 INDEX 的一律标出来，由人决定要不要按代理登记。
    """
    last = "无可用数据"
    for host in ("query1.finance.yahoo.com", "query2.finance.yahoo.com"):
        url = (f"https://{host}/v8/finance/chart/{parse.quote(symbol)}"
               "?range=1y&interval=1d")
        try:
            payload = get_json(url)
            result = payload["chart"]["result"][0]
            stamps = result.get("timestamp") or []
            closes = [c for c in result["indicators"]["quote"][0]["close"] if c is not None]
            if len(closes) < 60:
                last = f"日线数据点不足（{len(closes)}）"
                continue
            meta = result.get("meta") or {}
            return {
                "ok": True, "points": len(closes), "value": round(float(closes[-1]), 4),
                "asOf": time.strftime("%Y-%m-%d", time.gmtime(stamps[-1])),
                "currency": meta.get("currency", ""),
                "name": meta.get("shortName", "") or meta.get("longName", ""),
                "type": meta.get("instrumentType", ""),
                "exchange": meta.get("fullExchangeName", "") or meta.get("exchangeName", ""),
                "tz": meta.get("exchangeTimezoneName", ""),
            }
        except (error.HTTPError, error.URLError, ValueError, KeyError, IndexError) as exc:
            last = f"{type(exc).__name__}: {str(exc)[:60]}"
    return {"ok": False, "why": last}


def probe_hourly(symbol: str) -> dict:
    """Yahoo 小时线：确认能取到、是本标的、且覆盖足够长。

    只请求 interval=1h。4小时线由小时线聚合而来，聚合是我们本地做的确定性运算，
    真正要验证的是「源头有没有小时级观测」这一件事。
    """
    last = "无可用数据"
    for host in ("query1.finance.yahoo.com", "query2.finance.yahoo.com"):
        url = (f"https://{host}/v8/finance/chart/{parse.quote(symbol)}"
               "?range=730d&interval=1h")
        try:
            payload = get_json(url)
            result = payload["chart"]["result"][0]
            stamps = result.get("timestamp") or []
            closes = result["indicators"]["quote"][0]["close"]
            bars = [(t, c) for t, c in zip(stamps, closes) if c is not None]
            if len(bars) < 24:
                last = f"小时线数据点不足（{len(bars)}）"
                continue
            meta = result.get("meta") or {}
            span_days = round((bars[-1][0] - bars[0][0]) / 86400.0, 1)
            return {
                "ok": True, "bars": len(bars), "spanDays": span_days,
                "first": time.strftime("%Y-%m-%d %H:%M", time.gmtime(bars[0][0])),
                "last": time.strftime("%Y-%m-%d %H:%M", time.gmtime(bars[-1][0])),
                "value": round(float(bars[-1][1]), 4),
                "currency": meta.get("currency", ""), "name": meta.get("shortName", ""),
                "granularity": meta.get("dataGranularity", ""),
                "exchangeTz": meta.get("exchangeTimezoneName", ""),
            }
        except (error.HTTPError, error.URLError, ValueError, KeyError, IndexError) as exc:
            last = f"{type(exc).__name__}: {str(exc)[:60]}"
    return {"ok": False, "why": last}


# ── 各国10年期国债收益率候选 ─────────────────────────────────────────────
# 参考站（TradingEconomics）的 Bonds 分区按地区列了约 50 个国家的十年期收益率，
# 站内债券品类目前只有美债曲线 11 个期限 + 中国国债 + 三段美债ETF代理。
#
# 这里要回答的不只是「取不取得到」，还有**频率**：站内绝不能把月频序列摆成日频。
# 因此三个来源家族各留一批候选，逐个实测后再决定登记哪一份：
#   A. FRED / OECD 主要经济指标长期国债收益率 `IRLTLT01{ISO2}M156N`（月频，覆盖广）
#      —— 注意 OECD 2024 年改了数据投送方式，FRED 上这一族有相当一部分已停更，
#      必须实测最后观测日，不能只看「取到了」。
#   B. FRED / IMF IFS 政府债券利率 `INTGSB{ISO2}M193N`（月频，另一条独立口径）
#   C. ECB 数据门户（免密钥）——欧盟趋同用长期利率（月频）与欧元区收益率曲线（日频）
# 另附几个日频的官方接口（加拿大央行 Valet）与 Yahoo 的债券代码，看有没有日频可用。
BOND_FRED_CANDIDATES = [
    # —— 欧洲 ——
    ("IRLTLT01ATM156N", "奥地利10年期"), ("IRLTLT01BEM156N", "比利时10年期"),
    ("IRLTLT01CZM156N", "捷克10年期"), ("IRLTLT01DKM156N", "丹麦10年期"),
    ("IRLTLT01EEM156N", "爱沙尼亚10年期"), ("IRLTLT01FIM156N", "芬兰10年期"),
    ("IRLTLT01FRM156N", "法国10年期"), ("IRLTLT01DEM156N", "德国10年期"),
    ("IRLTLT01GRM156N", "希腊10年期"), ("IRLTLT01HUM156N", "匈牙利10年期"),
    ("IRLTLT01ISM156N", "冰岛10年期"), ("IRLTLT01IEM156N", "爱尔兰10年期"),
    ("IRLTLT01ITM156N", "意大利10年期"), ("IRLTLT01LVM156N", "拉脱维亚10年期"),
    ("IRLTLT01LTM156N", "立陶宛10年期"), ("IRLTLT01LUM156N", "卢森堡10年期"),
    ("IRLTLT01NLM156N", "荷兰10年期"), ("IRLTLT01NOM156N", "挪威10年期"),
    ("IRLTLT01PLM156N", "波兰10年期"), ("IRLTLT01PTM156N", "葡萄牙10年期"),
    ("IRLTLT01SKM156N", "斯洛伐克10年期"), ("IRLTLT01SIM156N", "斯洛文尼亚10年期"),
    ("IRLTLT01ESM156N", "西班牙10年期"), ("IRLTLT01SEM156N", "瑞典10年期"),
    ("IRLTLT01CHM156N", "瑞士10年期"), ("IRLTLT01GBM156N", "英国10年期"),
    ("IRLTLT01TRM156N", "土耳其10年期"), ("IRLTLT01RUM156N", "俄罗斯10年期"),
    ("IRLTLT01EZM156N", "欧元区10年期"), ("IRLTLT01BGM156N", "保加利亚10年期"),
    ("IRLTLT01HRM156N", "克罗地亚10年期"), ("IRLTLT01ROM156N", "罗马尼亚10年期"),
    # —— 美洲 ——
    ("IRLTLT01USM156N", "美国10年期"), ("IRLTLT01CAM156N", "加拿大10年期"),
    ("IRLTLT01MXM156N", "墨西哥10年期"), ("IRLTLT01BRM156N", "巴西10年期"),
    ("IRLTLT01CLM156N", "智利10年期"), ("IRLTLT01COM156N", "哥伦比亚10年期"),
    ("IRLTLT01CRM156N", "哥斯达黎加10年期"),
    # —— 亚洲 ——
    ("IRLTLT01JPM156N", "日本10年期"), ("IRLTLT01KRM156N", "韩国10年期"),
    ("IRLTLT01CNM156N", "中国10年期"), ("IRLTLT01INM156N", "印度10年期"),
    ("IRLTLT01IDM156N", "印尼10年期"), ("IRLTLT01ILM156N", "以色列10年期"),
    # —— 大洋洲 / 非洲 ——
    ("IRLTLT01AUM156N", "澳大利亚10年期"), ("IRLTLT01NZM156N", "新西兰10年期"),
    ("IRLTLT01ZAM156N", "南非10年期"),
]

BOND_FRED_IFS_CANDIDATES = [
    ("INTGSBUSM193N", "美国·IMF口径"), ("INTGSBJPM193N", "日本·IMF口径"),
    ("INTGSBGBM193N", "英国·IMF口径"), ("INTGSBDEM193N", "德国·IMF口径"),
    ("INTGSBFRM193N", "法国·IMF口径"), ("INTGSBITM193N", "意大利·IMF口径"),
    ("INTGSBCAM193N", "加拿大·IMF口径"), ("INTGSBAUM193N", "澳大利亚·IMF口径"),
    ("INTGSBCHM193N", "瑞士·IMF口径"), ("INTGSBMXM193N", "墨西哥·IMF口径"),
    ("INTGSBZAM193N", "南非·IMF口径"), ("INTGSBKRM193N", "韩国·IMF口径"),
    ("INTGSBINM193N", "印度·IMF口径"), ("INTGSBIDM193N", "印尼·IMF口径"),
    ("INTGSBTHM193N", "泰国·IMF口径"), ("INTGSBMYM193N", "马来西亚·IMF口径"),
    ("INTGSBPHM193N", "菲律宾·IMF口径"), ("INTGSBSGM193N", "新加坡·IMF口径"),
    ("INTGSBNGM193N", "尼日利亚·IMF口径"), ("INTGSBKEM193N", "肯尼亚·IMF口径"),
    ("INTGSBPKM193N", "巴基斯坦·IMF口径"), ("INTGSBVNM193N", "越南·IMF口径"),
    ("INTGSBPEM193N", "秘鲁·IMF口径"), ("INTGSBCLM193N", "智利·IMF口径"),
]

# ECB 数据门户：免密钥。两个数据集——
#   IRS = 趋同用长期利率（成员国 10 年期国债二级市场收益率，月频）
#   YC  = 欧元区 AAA 国债收益率曲线（日频）
ECB_CANDIDATES = [
    ("IRS/M.DE.L.L40.CI.0000.EUR.N.Z", "德国·趋同长期利率"),
    ("IRS/M.FR.L.L40.CI.0000.EUR.N.Z", "法国·趋同长期利率"),
    ("IRS/M.IT.L.L40.CI.0000.EUR.N.Z", "意大利·趋同长期利率"),
    ("IRS/M.ES.L.L40.CI.0000.EUR.N.Z", "西班牙·趋同长期利率"),
    ("IRS/M.NL.L.L40.CI.0000.EUR.N.Z", "荷兰·趋同长期利率"),
    ("IRS/M.PL.L.L40.CI.0000.PLN.N.Z", "波兰·趋同长期利率（本币）"),
    ("IRS/M.SE.L.L40.CI.0000.SEK.N.Z", "瑞典·趋同长期利率（本币）"),
    ("IRS/M.CZ.L.L40.CI.0000.CZK.N.Z", "捷克·趋同长期利率（本币）"),
    ("IRS/M.HU.L.L40.CI.0000.HUF.N.Z", "匈牙利·趋同长期利率（本币）"),
    ("IRS/M.RO.L.L40.CI.0000.RON.N.Z", "罗马尼亚·趋同长期利率（本币）"),
    ("IRS/M.U2.L.L40.CI.0000.EUR.N.Z", "欧元区·趋同长期利率"),
    ("YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_10Y", "欧元区AAA国债曲线10年（日频）"),
    ("YC/B.U2.EUR.4F.G_N_C.SV_C_YM.SR_10Y", "欧元区全评级国债曲线10年（日频）"),
]

# 官方日频接口与 Yahoo：看有没有能把「日频」这一档补上的免费来源。
BOND_DAILY_CANDIDATES = [
    ("boc", "https://www.bankofcanada.ca/valet/observations/BD.CDN.10YR.DQ.YLD/json?recent=5",
     "加拿大央行 Valet 10年期（日频）"),
    ("ustreasury",
     "https://api.fiscaldata.treasury.gov/services/api/fiscal_service/v2/accounting/od/"
     "avg_interest_rates?sort=-record_date&page[size]=3",
     "美国财政部平均利率（对照）"),
]

BOND_YAHOO_CANDIDATES = [
    ("^TNX", "美国10年期收益率（对照，已在站内）"),
    ("^TYX", "美国30年期收益率"),
    ("^FVX", "美国5年期收益率"),
    ("^IRX", "美国13周国库券"),
    ("^JP10YT=RR", "日本10年期（路透式代码）"),
    ("JP10Y-JP.BD", "日本10年期（另一种写法）"),
    ("^DE10Y", "德国10年期"),
    ("^GB10Y", "英国10年期"),
    ("BND", "先锋全债市ETF"),
    ("BNDX", "先锋国际债券ETF"),
    ("IGOV", "iShares国际国债ETF"),
    ("BWX", "SPDR国际国债ETF"),
    ("EMB", "iShares新兴市场美元债ETF"),
    ("IEF", "iShares 7-10年美债ETF"),
]


def probe_ecb(key: str) -> dict:
    """ECB 数据门户，免密钥。要 CSV 而不是 SDMX-JSON：CSV 的最后一行就是最新观测。"""
    url = (f"https://data-api.ecb.europa.eu/service/data/{key}"
           "?lastNObservations=3&format=csvdata")
    try:
        body = get_text(url)
    except (error.HTTPError, error.URLError) as exc:
        return {"ok": False, "why": f"{type(exc).__name__}: {str(exc)[:70]}"}
    lines = [ln for ln in body.strip().splitlines() if ln.strip()]
    if len(lines) < 2:
        return {"ok": False, "why": "返回体里没有观测行"}
    header = [h.strip().strip('"') for h in lines[0].split(",")]
    try:
        period = header.index("TIME_PERIOD")
        value = header.index("OBS_VALUE")
    except ValueError:
        return {"ok": False, "why": f"表头缺 TIME_PERIOD/OBS_VALUE：{','.join(header[:8])}"}
    rows = []
    for line in lines[1:]:
        parts = [c.strip().strip('"') for c in line.split(",")]
        if len(parts) > max(period, value) and parts[value] not in ("", "."):
            try:
                rows.append((parts[period], float(parts[value])))
            except ValueError:
                continue
    if len(rows) < MIN_POINTS:
        return {"ok": False, "why": f"观测点不足（{len(rows)}）"}
    rows.sort()
    return {"ok": True, "points": len(rows), "asOf": rows[-1][0], "value": rows[-1][1],
            "previous": rows[-2][1], "previousAsOf": rows[-2][0]}


def probe_daily_endpoint(url: str) -> dict:
    """官方日频接口：只确认「取得到 + 返回体里确有观测日」，字段结构逐个来源不同，
    因此这里不硬解字段，把开头一段原样带回报告，由人看过再决定怎么解析。"""
    try:
        body = get_text(url)
    except (error.HTTPError, error.URLError) as exc:
        return {"ok": False, "why": f"{type(exc).__name__}: {str(exc)[:70]}"}
    snippet = " ".join(body.split())[:220]
    return {"ok": True, "bytes": len(body), "snippet": snippet}



def get_json(url: str, headers: dict | None = None) -> dict:
    req = request.Request(url, headers=headers or {"User-Agent": UA, "Accept": "*/*"})
    with request.urlopen(req, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def get_text(url: str) -> str:
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with request.urlopen(req, timeout=TIMEOUT) as response:
        return response.read().decode("utf-8", "replace")


def probe_fred(series_id: str) -> dict:
    """优先用官方 API（有 key 时），否则退到免密钥的 fredgraph.csv。"""
    key = os.environ.get("FRED_API_KEY")
    if key:
        query = parse.urlencode({
            "series_id": series_id, "api_key": key, "file_type": "json",
            "sort_order": "desc", "limit": 400,
        })
        try:
            payload = get_json(f"https://api.stlouisfed.org/fred/series/observations?{query}")
            rows = [r for r in payload.get("observations", []) if r.get("value") not in (".", "", None)]
            if len(rows) < MIN_POINTS:
                return {"ok": False, "via": "api", "why": f"观测点不足（{len(rows)}）"}
            meta = get_json(
                "https://api.stlouisfed.org/fred/series?"
                + parse.urlencode({"series_id": series_id, "api_key": key, "file_type": "json"}))
            info = (meta.get("seriess") or [{}])[0]
            return {
                "ok": True, "via": "api", "points": len(rows),
                "asOf": rows[0]["date"], "value": float(rows[0]["value"]),
                "previous": float(rows[1]["value"]), "previousAsOf": rows[1]["date"],
                "frequency": info.get("frequency_short", ""), "units": info.get("units_short", ""),
                "title": info.get("title", ""), "start": info.get("observation_start", ""),
            }
        except (error.HTTPError, error.URLError, ValueError, KeyError, IndexError) as exc:
            return {"ok": False, "via": "api", "why": f"{type(exc).__name__}: {str(exc)[:70]}"}
    try:
        body = get_text(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={parse.quote(series_id)}")
        rows = []
        for line in body.strip().splitlines()[1:]:
            parts = line.split(",")
            if len(parts) >= 2 and parts[1] not in (".", ""):
                rows.append((parts[0], float(parts[1])))
        if len(rows) < MIN_POINTS:
            return {"ok": False, "via": "csv", "why": f"观测点不足（{len(rows)}）"}
        return {"ok": True, "via": "csv", "points": len(rows), "asOf": rows[-1][0],
                "value": rows[-1][1], "previous": rows[-2][1], "previousAsOf": rows[-2][0]}
    except (error.HTTPError, error.URLError, ValueError) as exc:
        return {"ok": False, "via": "csv", "why": f"{type(exc).__name__}: {str(exc)[:70]}"}


def probe_yahoo(symbol: str) -> dict:
    """与日更管道同一个 v8 图表接口，判定口径也一致：至少两个收盘点。"""
    last = "无可用数据"
    for host in ("query1.finance.yahoo.com", "query2.finance.yahoo.com"):
        url = (f"https://{host}/v8/finance/chart/{parse.quote(symbol)}"
               "?range=1y&interval=1d")
        try:
            payload = get_json(url)
            result = payload["chart"]["result"][0]
            closes = [c for c in result["indicators"]["quote"][0]["close"] if c is not None]
            stamps = result["timestamp"]
            if len(closes) < MIN_POINTS:
                last = f"行情数据点不足（{len(closes)}）"
                continue
            meta = result.get("meta") or {}
            return {"ok": True, "points": len(closes), "value": round(float(closes[-1]), 4),
                    "asOf": time.strftime("%Y-%m-%d", time.gmtime(stamps[-1])),
                    "currency": meta.get("currency", ""), "name": meta.get("shortName", "")}
        except (error.HTTPError, error.URLError, ValueError, KeyError, IndexError) as exc:
            last = f"{type(exc).__name__}: {str(exc)[:60]}"
    return {"ok": False, "why": last}


def main() -> None:
    report = {"fred": {}, "yahoo": {}}
    print("=" * 78)
    print("FRED 候选")
    print("=" * 78)
    for series_id, label in FRED_CANDIDATES:
        outcome = probe_fred(series_id)
        report["fred"][series_id] = dict(outcome, label=label)
        if outcome.get("ok"):
            print(f"[OK] {series_id:<16} {label:<16} {outcome['asOf']}  "
                  f"{outcome['value']:>14,.4f}  freq={outcome.get('frequency', '?'):<3} "
                  f"n={outcome['points']:<5} {outcome.get('units', '')[:22]}")
        else:
            print(f"[XX] {series_id:<16} {label:<16} {outcome.get('why', '')}")
        time.sleep(GAP)

    print()
    print("=" * 78)
    print("Yahoo 候选")
    print("=" * 78)
    for symbol, label in YAHOO_CANDIDATES:
        outcome = probe_yahoo(symbol)
        report["yahoo"][symbol] = dict(outcome, label=label)
        if outcome.get("ok"):
            print(f"[OK] {symbol:<8} {label:<26} {outcome['asOf']}  "
                  f"{outcome['value']:>13,.4f}  n={outcome['points']:<5} "
                  f"{(outcome.get('currency') or '')} {(outcome.get('name') or '')[:26]}")
        else:
            print(f"[XX] {symbol:<8} {label:<26} {outcome.get('why', '')}")
        time.sleep(GAP)

    print()
    print("=" * 78)
    print("标普500成分名单候选")
    print("=" * 78)
    report["sp500"] = {}
    for name, url in SP500_SOURCES:
        outcome = probe_sp500(name, url)
        report["sp500"][name] = dict(outcome, url=url)
        if outcome.get("ok"):
            print(f"[OK] {name:<20} {outcome['count']:>4} 个代码  "
                  f"{outcome['bytes']:>8} 字节  样例 {','.join(outcome['sample'][:6])}")
        else:
            print(f"[XX] {name:<20} {outcome.get('why','')}")
        time.sleep(GAP)
    ok_lists = {k: set(v.get("sample") or []) for k, v in report["sp500"].items() if v.get("ok")}
    if len(ok_lists) > 1:
        print(f"     取到 {len(ok_lists)} 份名单，条数：",
              {k: report["sp500"][k]["count"] for k in ok_lists})
    # 覆盖度：热力图能不能诚实地叫「标普500」，取决于站内清单盖住了多少成分股。
    # 盖不住的必须在页面上写出来，而不是画一张少了几十家的图还叫标普500。
    coverage = probe_sp500_coverage()
    report["sp500Coverage"] = coverage
    if coverage.get("ok"):
        print(f"     覆盖度：站内 universe.json 盖住 {coverage['covered']}/{coverage['total']} 个成分代码；"
              f"缺 {len(coverage['missing'])} 个")
        print(f"     缺的（前25）：{', '.join(coverage['missing'][:25])}")
        print(f"     站内有、但已不在成分名单里的（前15）：{', '.join(coverage['extraUS'][:15])}")
    else:
        print(f"     覆盖度未能计算：{coverage.get('why', '')}")

    print()
    print("=" * 78)
    print("指数候选")
    print("=" * 78)
    report["index"] = {}
    for symbol, label in INDEX_CANDIDATES:
        outcome = probe_index(symbol)
        report["index"][symbol] = dict(outcome, label=label)
        if outcome.get("ok"):
            flag = "OK" if outcome.get("type") == "INDEX" else "??"
            # 上游会把 currency/type 显式返回成 null；dict.get 的默认值对「键存在但为 None」
            # 不生效，直接拿去格式化会抛 TypeError 并弄挂整个探测。一律 or "" 兜住。
            print(f"[{flag}] {symbol:<12} {label:<22} {outcome['asOf']}  "
                  f"{outcome['value']:>13,.2f}  n={outcome['points']:<4} "
                  f"{(outcome.get('currency') or ''):<4} type={(outcome.get('type') or ''):<6} "
                  f"{(outcome.get('name') or '')[:24]}")
        else:
            print(f"[XX] {symbol:<12} {label:<22} {outcome.get('why','')}")
        time.sleep(GAP)

    print()
    print("=" * 78)
    print("小时线候选（4小时线的原料）")
    print("=" * 78)
    report["hourly"] = {}
    for symbol, label in HOURLY_CANDIDATES:
        outcome = probe_hourly(symbol)
        report["hourly"][symbol] = dict(outcome, label=label)
        if outcome.get("ok"):
            print(f"[OK] {symbol:<10} {label:<24} {outcome['bars']:>5}根 "
                  f"跨{outcome['spanDays']:>6}天 粒度={(outcome.get('granularity') or ''):<4} "
                  f"{(outcome.get('currency') or '')} {(outcome.get('name') or '')[:22]}")
            print(f"     {outcome['first']} → {outcome['last']}  最新={outcome['value']}")
        else:
            print(f"[XX] {symbol:<10} {label:<24} {outcome.get('why','')}")
        time.sleep(GAP)

    print()
    print("=" * 78)
    print("国债候选 · FRED / OECD 长期国债收益率（月频，看清最后观测日）")
    print("=" * 78)
    report["bondFred"] = {}
    for series_id, label in BOND_FRED_CANDIDATES:
        outcome = probe_fred(series_id)
        report["bondFred"][series_id] = dict(outcome, label=label)
        if outcome.get("ok"):
            print(f"[OK] {series_id:<18} {label:<20} 末次 {outcome['asOf']}  "
                  f"{outcome['value']:>9,.4f}  freq={outcome.get('frequency', '?'):<3} "
                  f"n={outcome['points']:<5} {(outcome.get('title') or '')[:34]}")
        else:
            print(f"[XX] {series_id:<18} {label:<20} {outcome.get('why', '')}")
        time.sleep(GAP)

    print()
    print("=" * 78)
    print("国债候选 · FRED / IMF IFS 政府债券利率（月频，独立第二口径）")
    print("=" * 78)
    report["bondIfs"] = {}
    for series_id, label in BOND_FRED_IFS_CANDIDATES:
        outcome = probe_fred(series_id)
        report["bondIfs"][series_id] = dict(outcome, label=label)
        if outcome.get("ok"):
            print(f"[OK] {series_id:<16} {label:<20} 末次 {outcome['asOf']}  "
                  f"{outcome['value']:>9,.4f}  freq={outcome.get('frequency', '?'):<3} "
                  f"n={outcome['points']}")
        else:
            print(f"[XX] {series_id:<16} {label:<20} {outcome.get('why', '')}")
        time.sleep(GAP)

    print()
    print("=" * 78)
    print("国债候选 · ECB 数据门户（免密钥）")
    print("=" * 78)
    report["bondEcb"] = {}
    for key, label in ECB_CANDIDATES:
        outcome = probe_ecb(key)
        report["bondEcb"][key] = dict(outcome, label=label)
        if outcome.get("ok"):
            print(f"[OK] {key:<42} {label:<26} 末次 {outcome['asOf']}  "
                  f"{outcome['value']:>9,.4f}  n={outcome['points']}")
        else:
            print(f"[XX] {key:<42} {label:<26} {outcome.get('why', '')}")
        time.sleep(GAP)

    print()
    print("=" * 78)
    print("国债候选 · 官方日频接口与 Yahoo")
    print("=" * 78)
    report["bondDaily"] = {}
    for name, url, label in BOND_DAILY_CANDIDATES:
        outcome = probe_daily_endpoint(url)
        report["bondDaily"][name] = dict(outcome, label=label, url=url)
        if outcome.get("ok"):
            print(f"[OK] {name:<12} {label:<28} {outcome['bytes']:>7} 字节")
            print(f"     {outcome['snippet'][:190]}")
        else:
            print(f"[XX] {name:<12} {label:<28} {outcome.get('why', '')}")
        time.sleep(GAP)
    report["bondYahoo"] = {}
    for symbol, label in BOND_YAHOO_CANDIDATES:
        outcome = probe_yahoo(symbol)
        report["bondYahoo"][symbol] = dict(outcome, label=label)
        if outcome.get("ok"):
            print(f"[OK] {symbol:<14} {label:<28} {outcome['asOf']}  "
                  f"{outcome['value']:>10,.4f}  {(outcome.get('currency') or '')} "
                  f"{(outcome.get('name') or '')[:24]}")
        else:
            print(f"[XX] {symbol:<14} {label:<28} {outcome.get('why', '')}")
        time.sleep(GAP)

    ok_fred = [k for k, v in report["fred"].items() if v.get("ok")]
    ok_yahoo = [k for k, v in report["yahoo"].items() if v.get("ok")]
    print()
    ok_hourly = [k for k, v in report["hourly"].items() if v.get("ok")]
    ok_index = [k for k, v in report["index"].items() if v.get("ok")]
    real_index = [k for k, v in report["index"].items() if v.get("type") == "INDEX"]
    print(f"可用：FRED {len(ok_fred)}/{len(FRED_CANDIDATES)}，"
          f"Yahoo {len(ok_yahoo)}/{len(YAHOO_CANDIDATES)}，"
          f"指数 {len(ok_index)}/{len(INDEX_CANDIDATES)}（其中 type=INDEX 的 {len(real_index)} 条），"
          f"小时线 {len(ok_hourly)}/{len(HOURLY_CANDIDATES)}")
    for bucket, total in (("bondFred", len(BOND_FRED_CANDIDATES)),
                          ("bondIfs", len(BOND_FRED_IFS_CANDIDATES)),
                          ("bondEcb", len(ECB_CANDIDATES)),
                          ("bondYahoo", len(BOND_YAHOO_CANDIDATES))):
        got = [k for k, v in report.get(bucket, {}).items() if v.get("ok")]
        print(f"    {bucket}: {len(got)}/{total} 可用")
    # 「取到了」不等于「还在更新」：把最后观测日按年份点一遍，停更的序列一眼可见。
    stale = {}
    for bucket in ("bondFred", "bondIfs", "bondEcb"):
        for key, value in report.get(bucket, {}).items():
            if value.get("ok"):
                stale.setdefault(str(value.get("asOf", ""))[:4], []).append(key)
    for year in sorted(stale, reverse=True):
        print(f"    末次观测年份 {year}：{len(stale[year])} 条  {', '.join(stale[year][:10])}")
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

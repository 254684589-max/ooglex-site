#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球大类资产收益率」数据：从 Yahoo Finance 抓取各品类标的的日线行情，
计算 今日 / 近一周 / 近一月 / 年初至今 / 近一年 涨跌幅，写入
apps/asset-tracker/data.json，供个人主页的静态页面读取渲染。

设计要点（与仓库里 market-bot 的取数风格保持一致）：
- 纯 requests + 硬超时，绝不挂起；每个标的独立 try/except，单个失败不影响整体；
- 不需要任何 API Key —— Yahoo 图表接口实测可从 GitHub Actions 机房 IP 访问；
- 标的代码支持多个候选（按序回退），某个代码失效时自动尝试下一个；
- 本轮全失败则保留上次的 data.json（不会用空数据覆盖好数据）；
- 本轮个别标的失败但历史上拿到过的，沿用上次的值并标记 stale，避免图表忽隐忽现。

由 .github/workflows/asset_tracker.yml 每日定时运行，并把更新后的 data.json 提交回仓库；
GitHub Pages 直接托管该 JSON，页面前端 fetch 后即时渲染。
"""
import json
import os
import sys
import time
from datetime import datetime, timezone, timedelta

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SCRIPTS_DIR)
from market_data_quality import (  # noqa: E402
    fallback_data_meta,
    make_data_meta,
    make_proxy_meta,
    summarize_data_quality,
)
from market_history import build_rolling_history  # noqa: E402
from market_history_long import build_long_history, monthly_from_daily  # noqa: E402
from market_source_health import (  # noqa: E402
    load_json as load_health_json,
    make_source_health,
    write_health,
)

OUT_PATH = os.path.join("apps", "asset-tracker", "data.json")
HEALTH_PATH = os.path.join("apps", "asset-tracker", "health.json")
HISTORY_PATH = os.path.join("apps", "asset-tracker", "history.json")
HISTORY_POINTS = 260   # 滚动保留约一年交易日，文件大小恒定而非逐日增长
HISTORY_NOTE = ("各标的自身收盘价的滚动历史，与 data.json 同一次取数、同一来源；"
                "共享日期轴上该标的当日无报价则为 null，不做前向填充。"
                "本轮未取到的标的沿用上次序列，不补造新点。")
LONG_HISTORY_PATH = os.path.join("apps", "asset-tracker", "history-monthly.json")
LONG_HISTORY_NOTE = ("各标的自身的月线收盘（每月最后一个交易日），用于 5 年 / 10 年 / 25 年 / "
                     "全部区间的走势；起始月即该标的在数据源上可得的最早月份。"
                     "数据源对超长区间会自行降采样，部分标的的早年只有季度末观测，"
                     "缺月一律留空不做前向填充，页面按真实时间轴作图；"
                     "本轮未取到的标的沿用上次序列。")

# 四大品类：key / 中文名 / 颜色（沿用示例图语义：股市红、商品蓝、外汇橙、债券青，精修为更通透的配色）
CATEGORIES = [
    {"key": "equity",    "label": "股市", "color": "#ff5d6c"},
    {"key": "commodity", "label": "商品", "color": "#4aa3f0"},
    {"key": "fx",        "label": "外汇", "color": "#ffb13d"},
    {"key": "bond",      "label": "债券", "color": "#2ed1b0"},
]

# 展示的时间周期（前端可切换，默认「年初至今」与示例图一致）
PERIODS = [
    {"key": "d1",  "label": "今日"},
    {"key": "w1",  "label": "近一周"},
    {"key": "m1",  "label": "近一月"},
    {"key": "ytd", "label": "年初至今"},
    {"key": "y1",  "label": "近一年"},
]

# 标的清单：完全对应示例图的 28 个品类。
#   name 中文名 / cat 品类 / syms 候选 Yahoo 代码（按序回退）/ note 代理说明（可选）
ASSETS = [
    # —— 股市 ——
    {"name": "标普500",          "cat": "equity",    "syms": ["^GSPC"]},
    {"name": "日经225",          "cat": "equity",    "syms": [
        "^N225", {"sym": "EWJ", "note": "以日本 ETF（美元计）代理"}]},
    {"name": "德国DAX",          "cat": "equity",    "syms": ["^GDAXI"]},
    {"name": "恒生指数",         "cat": "equity",    "syms": ["^HSI"]},
    {"name": "富时新加坡海峡指数", "cat": "equity",   "syms": ["^STI"]},
    {"name": "沪深300",          "cat": "equity",    "syms": [
        "000300.SS",
        {"sym": "510300.SS", "proxy": {
            "type": "etf",
            "targetSymbol": "000300.SS",
            "instrumentName": "沪深300ETF",
            "currency": "CNY",
            "returnBasis": "price",
            "note": "以人民币沪深300ETF价格收益率代理；可能存在跟踪误差、分红与费用差异。",
        }},
    ]},
    {"name": "新西兰NZ50",       "cat": "equity",    "syms": ["^NZ50"]},
    {"name": "印度SENSEX30",     "cat": "equity",    "syms": ["^BSESN"]},
    {"name": "澳洲标普200",      "cat": "equity",    "syms": ["^AXJO"]},
    {"name": "中证500",          "cat": "equity",    "syms": [
        "000905.SS",
        {"sym": "510500.SS", "proxy": {
            "type": "etf",
            "targetSymbol": "000905.SS",
            "instrumentName": "中证500ETF",
            "currency": "CNY",
            "returnBasis": "price",
            "note": "以人民币中证500ETF价格收益率代理；可能存在跟踪误差、分红与费用差异。",
        }},
    ]},
    {"name": "欧洲STOXX600",     "cat": "equity",    "syms": ["^STOXX"]},
    {"name": "英国富时100",      "cat": "equity",    "syms": ["^FTSE"]},
    {"name": "法国CAC40",        "cat": "equity",    "syms": ["^FCHI"]},
    # 韩股 2025-26 处于历史级大牛市，年初至今/近一年涨幅本就极高，放宽护栏以如实呈现
    {"name": "韩国综合指数",     "cat": "equity", "caps": {"ytd": 300, "y1": 400},
     "syms": ["^KS11", {"sym": "^KS200", "note": "以 KOSPI 200 指数代理"},
              {"sym": "EWY", "note": "以韩国 ETF（美元计）代理"}]},
    {"name": "圣保罗IBOVESPA指数", "cat": "equity",  "syms": ["^BVSP"]},
    # 2026-08-25 所有者决定：撤下QQQ代理卡后，纳斯达克改由综合指数进入指数类。
    # 这是纳斯达克综合（^IXIC），不是QQQ跟踪的纳斯达克100（NDX），两者成分与数值不同。
    # DJIA仍由DIA免费组件展示、NDX不再进入本站，二者都不加入本清单。
    {"name": "纳斯达克综合",     "cat": "equity",    "syms": ["^IXIC"]},
    # 2026-08 扩容：继续按「各国家/地区代表性指数」补齐。
    {"name": "台湾加权指数",     "cat": "equity",    "syms": ["^TWII"]},
    {"name": "加拿大S&P/TSX",    "cat": "equity",    "syms": ["^GSPTSE"]},
    {"name": "瑞士SMI",          "cat": "equity",    "syms": ["^SSMI"]},
    {"name": "西班牙IBEX35",     "cat": "equity",    "syms": ["^IBEX"]},
    {"name": "意大利富时MIB",    "cat": "equity",    "syms": ["FTSEMIB.MI", "^FTMIB"]},
    {"name": "墨西哥IPC",        "cat": "equity",    "syms": ["^MXX"]},
    {"name": "印尼雅加达综合",   "cat": "equity",    "syms": ["^JKSE"]},
    {"name": "以色列TA-125",     "cat": "equity",    "syms": ["^TA125.TA"]},
    # 2026-08-26 再扩容：继续按各市场代表性指数补齐，另加两支美股宽基与一支波动率指数。
    {"name": "荷兰AEX",          "cat": "equity",    "syms": ["^AEX"]},
    {"name": "比利时BEL20",      "cat": "equity",    "syms": ["^BFX"]},
    {"name": "瑞典OMXS30",       "cat": "equity",    "syms": ["^OMX"]},
    {"name": "奥地利ATX",        "cat": "equity",    "syms": ["^ATX"]},
    {"name": "土耳其BIST100",    "cat": "equity",    "syms": ["XU100.IS"],
     "caps": {"m1": 90, "ytd": 300, "y1": 400}},
    {"name": "波兰WIG20",        "cat": "equity",    "syms": [
        "WIG20.WA", {"sym": "EPOL", "note": "以波兰 ETF（美元计）代理，含汇率影响"}]},
    {"name": "泰国SET",          "cat": "equity",    "syms": [
        "^SET.BK", {"sym": "THD", "note": "以泰国 ETF（美元计）代理，含汇率影响"}]},
    {"name": "马来西亚KLCI",     "cat": "equity",    "syms": ["^KLSE"]},
    {"name": "菲律宾PSEi",       "cat": "equity",    "syms": [
        "PSEI.PS", {"sym": "EPHE", "note": "以菲律宾 ETF（美元计）代理，含汇率影响"}]},
    {"name": "智利IPSA",         "cat": "equity",    "syms": [
        "^IPSA", {"sym": "ECH", "note": "以智利 ETF（美元计）代理，含汇率影响"}]},
    # 阿根廷长期高通胀，名义指数涨跌本就极大，放宽护栏以如实呈现
    {"name": "阿根廷MERVAL",     "cat": "equity",    "syms": ["^MERV"],
     "caps": {"d1": 40, "w1": 80, "m1": 150, "ytd": 500, "y1": 600}},
    {"name": "美国罗素2000",     "cat": "equity",    "syms": ["^RUT"]},
    {"name": "恒生科技指数",     "cat": "equity",    "syms": [
        "^HSTECH", {"sym": "3033.HK", "note": "以恒生科技指数 ETF（港元计）代理"}],
     "caps": {"m1": 90, "ytd": 200, "y1": 300}},
    # VIX 是标普500期权隐含波动率指数，不是可交易标的，日内跳动本就远大于股指
    {"name": "标普500波动率VIX", "cat": "equity",    "syms": ["^VIX"],
     "note": "CBOE标普500波动率指数，衡量期权隐含波动率，不是可交易标的",
     "caps": {"d1": 80, "w1": 150, "m1": 250, "ytd": 400, "y1": 500}},
    # —— 商品 ——（LME 现货 Yahoo 无免费源，以全球期货代理，涨跌方向高度一致）
    {"name": "COMEX黄金",        "cat": "commodity", "syms": ["GC=F"]},
    {"name": "COMEX白银",        "cat": "commodity", "syms": ["SI=F"]},
    {"name": "LME铝",            "cat": "commodity", "syms": ["ALI=F"], "note": "以期货铝代理 LME 铝"},
    {"name": "LME铜",            "cat": "commodity", "syms": ["HG=F"],  "note": "以 COMEX 铜代理 LME 铜"},
    {"name": "NYMEX WTI原油",    "cat": "commodity", "syms": ["CL=F"]},
    {"name": "ICE布油",          "cat": "commodity", "syms": ["BZ=F"]},
    # 2026-08 扩容：能源、贵金属与农产品期货；天然气与农产品年内波动本就极大，放宽护栏以如实呈现
    {"name": "NYMEX天然气",      "cat": "commodity", "syms": ["NG=F"],
     "caps": {"d1": 40, "w1": 70, "m1": 120, "ytd": 300, "y1": 400}},
    {"name": "NYMEX铂金",        "cat": "commodity", "syms": ["PL=F"]},
    {"name": "NYMEX钯金",        "cat": "commodity", "syms": ["PA=F"]},
    {"name": "CBOT小麦",         "cat": "commodity", "syms": ["ZW=F"]},
    {"name": "CBOT玉米",         "cat": "commodity", "syms": ["ZC=F"]},
    {"name": "CBOT大豆",         "cat": "commodity", "syms": ["ZS=F"]},
    {"name": "ICE咖啡",          "cat": "commodity", "syms": ["KC=F"],
     "caps": {"m1": 90, "ytd": 200, "y1": 300}},
    {"name": "ICE白糖",          "cat": "commodity", "syms": ["SB=F"]},
    {"name": "ICE棉花",          "cat": "commodity", "syms": ["CT=F"]},
    # 2026-08-26 再扩容：能源制品、软商品、油籽制品与畜牧期货。
    {"name": "NYMEX取暖油",      "cat": "commodity", "syms": ["HO=F"],
     "caps": {"m1": 80, "ytd": 200, "y1": 250}},
    {"name": "NYMEX汽油RBOB",    "cat": "commodity", "syms": ["RB=F"],
     "caps": {"m1": 80, "ytd": 200, "y1": 250}},
    {"name": "ICE可可",          "cat": "commodity", "syms": ["CC=F"],
     "caps": {"m1": 90, "ytd": 300, "y1": 400}},
    {"name": "ICE橙汁",          "cat": "commodity", "syms": ["OJ=F"],
     "caps": {"m1": 90, "ytd": 300, "y1": 400}},
    {"name": "CBOT燕麦",         "cat": "commodity", "syms": ["ZO=F"],
     "caps": {"m1": 80, "ytd": 200, "y1": 250}},
    {"name": "CBOT糙米",         "cat": "commodity", "syms": ["ZR=F"]},
    {"name": "CBOT豆油",         "cat": "commodity", "syms": ["ZL=F"]},
    {"name": "CBOT豆粕",         "cat": "commodity", "syms": ["ZM=F"]},
    {"name": "CME活牛",          "cat": "commodity", "syms": ["LE=F"]},
    {"name": "CME饲牛",          "cat": "commodity", "syms": ["GF=F"]},
    {"name": "CME瘦肉猪",        "cat": "commodity", "syms": ["HE=F"],
     "caps": {"m1": 90, "ytd": 250, "y1": 300}},
    {"name": "CME木材",          "cat": "commodity", "syms": ["LBR=F", "LBS=F"],
     "caps": {"m1": 90, "ytd": 250, "y1": 300}},
    # 2026-08-28 再扩容：商品品类要在页面上再分「能源 / 贵金属 / 工业金属 / 农产品 /
    # 软商品 / 畜牧 / 商品指数」七组，这里补的是各组里站内此前完全没有的品种。
    # 只登记在数据源上确实有免费日线的代码：宁可某一组只有三行，也不放进取不到的代码——
    # 取不到的行会让整条管道长期标成 degraded，而页面上仍旧一行都不会多。
    {"name": "NYMEX丙烷",        "cat": "commodity", "syms": ["B0=F"],
     "note": "蒙贝尔维尤LDH丙烷（OPIS）期货，天然气液（NGL）的基准合约",
     "caps": {"m1": 80, "ytd": 200, "y1": 250}},
    {"name": "KCBT硬红冬小麦",   "cat": "commodity", "syms": ["KE=F"],
     "note": "堪萨斯硬红冬小麦期货，与CBOT软红冬小麦（ZW=F）是两个不同品种"},
    # 以下四项是基金份额价格，不是任何一种商品或指数本身的报价，逐条写明代理关系。
    # 它们各自覆盖站内单品期货覆盖不到的东西：锌等基本金属、宽基商品指数、碳配额。
    {"name": "工业金属篮子",     "cat": "commodity", "syms": ["DBB"],
     "note": "以 Invesco DB 基本金属基金（DBB）份额价格代理铝、锌、铜期货篮子，"
             "是基金价格而不是任一金属的现货价"},
    {"name": "综合商品指数",     "cat": "commodity", "syms": ["DBC"],
     "note": "以 Invesco DB 商品指数跟踪基金（DBC）份额价格代理多元化商品指数，"
             "是基金价格而不是指数点位"},
    {"name": "标普GSCI商品指数", "cat": "commodity", "syms": ["GSG"],
     "note": "以 iShares 标普GSCI商品指数信托（GSG）份额价格代理，"
             "是信托价格而不是指数点位"},
    {"name": "全球碳排放权",     "cat": "commodity", "syms": ["KRBN"],
     "note": "以 KraneShares 全球碳排放ETF（KRBN）份额价格代理欧盟、加州与RGGI碳配额期货，"
             "是基金价格而不是任一市场的配额价",
     "caps": {"m1": 80, "ytd": 200, "y1": 250}},
    # —— 外汇 ——（涨跌幅即各汇率自身变动，与示例图口径一致）
    {"name": "美元兑日元",       "cat": "fx",        "syms": ["USDJPY=X", "JPY=X"]},
    {"name": "美元指数",         "cat": "fx",        "syms": ["DX-Y.NYB", "DX=F"]},
    {"name": "美元兑人民币",     "cat": "fx",        "syms": ["USDCNY=X", "CNY=X"]},
    {"name": "英镑兑美元",       "cat": "fx",        "syms": ["GBPUSD=X"]},
    {"name": "欧元兑美元",       "cat": "fx",        "syms": ["EURUSD=X"]},
    {"name": "澳元兑美元",       "cat": "fx",        "syms": ["AUDUSD=X"]},
    # 2026-08 扩容：主要交叉盘与新兴市场货币，涨跌幅仍是各汇率自身变动
    {"name": "美元兑加元",       "cat": "fx",        "syms": ["USDCAD=X", "CAD=X"]},
    {"name": "美元兑瑞郎",       "cat": "fx",        "syms": ["USDCHF=X", "CHF=X"]},
    {"name": "纽元兑美元",       "cat": "fx",        "syms": ["NZDUSD=X"]},
    {"name": "美元兑韩元",       "cat": "fx",        "syms": ["USDKRW=X", "KRW=X"]},
    {"name": "美元兑印度卢比",   "cat": "fx",        "syms": ["USDINR=X", "INR=X"]},
    {"name": "美元兑新加坡元",   "cat": "fx",        "syms": ["USDSGD=X", "SGD=X"]},
    {"name": "美元兑巴西雷亚尔", "cat": "fx",        "syms": ["USDBRL=X", "BRL=X"]},
    # 2026-08-26 再扩容：更多美元盘与两组欧系交叉盘。
    {"name": "美元兑港元",       "cat": "fx",        "syms": ["USDHKD=X", "HKD=X"]},
    {"name": "美元兑墨西哥比索", "cat": "fx",        "syms": ["USDMXN=X", "MXN=X"]},
    {"name": "美元兑南非兰特",   "cat": "fx",        "syms": ["USDZAR=X", "ZAR=X"]},
    # 里拉长期单边贬值，年度变动本就极大，放宽护栏以如实呈现
    {"name": "美元兑土耳其里拉", "cat": "fx",        "syms": ["USDTRY=X", "TRY=X"],
     "caps": {"m1": 80, "ytd": 200, "y1": 300}},
    {"name": "美元兑泰铢",       "cat": "fx",        "syms": ["USDTHB=X", "THB=X"]},
    {"name": "美元兑瑞典克朗",   "cat": "fx",        "syms": ["USDSEK=X", "SEK=X"]},
    {"name": "美元兑挪威克朗",   "cat": "fx",        "syms": ["USDNOK=X", "NOK=X"]},
    {"name": "欧元兑日元",       "cat": "fx",        "syms": ["EURJPY=X"]},
    {"name": "欧元兑英镑",       "cat": "fx",        "syms": ["EURGBP=X"]},
    # —— 债券 ——（中债总财富指数无免费日更源，以国债 ETF 代理）
    {"name": "中国国债",         "cat": "bond",      "syms": ["511260.SS", "511010.SS", "511090.SS"],
     "note": "以国债 ETF 代理（非中债-国债总财富指数）"},
    # 2026-08 扩容：美债三段期限以国债 ETF 价格代理，是债券价格而不是收益率；
    # 收益率本身在金融终端读取 FRED 官方曲线，两者不可混用。
    {"name": "美国长期国债",     "cat": "bond",      "syms": ["TLT"],
     "note": "以 iShares 20年期以上美国国债 ETF 价格代理长端美债，不是国债收益率"},
    {"name": "美国中期国债",     "cat": "bond",      "syms": ["IEF"],
     "note": "以 iShares 7-10年期美国国债 ETF 价格代理中端美债，不是国债收益率"},
    {"name": "美国短期国债",     "cat": "bond",      "syms": ["SHY"],
     "note": "以 iShares 1-3年期美国国债 ETF 价格代理短端美债，不是国债收益率"},
    # 2026-08-26 再扩容：债券各板块同样以 ETF 价格代理，是价格不是收益率，逐行写明口径。
    {"name": "美国通胀保值债",   "cat": "bond",      "syms": ["TIP"],
     "note": "以 iShares TIPS ETF 价格代理美国通胀保值国债，不是实际收益率"},
    {"name": "美国综合债",       "cat": "bond",      "syms": ["AGG"],
     "note": "以 iShares 美国综合债券 ETF 价格代理美国投资级债券总体，不是收益率"},
    {"name": "美国投资级公司债", "cat": "bond",      "syms": ["LQD"],
     "note": "以 iShares 投资级公司债 ETF 价格代理，不是信用利差或收益率"},
    {"name": "美国高收益债",     "cat": "bond",      "syms": ["HYG"],
     "note": "以 iShares 高收益公司债 ETF 价格代理，不是高收益债利差"},
    {"name": "美国市政债",       "cat": "bond",      "syms": ["MUB"],
     "note": "以 iShares 美国市政债 ETF 价格代理，不是市政债收益率"},
    {"name": "新兴市场美元主权债", "cat": "bond",    "syms": ["EMB"],
     "note": "以 iShares 新兴市场美元主权债 ETF 价格代理，不是主权债收益率"},
    {"name": "非美国国债",       "cat": "bond",      "syms": ["BWX"],
     "note": "以 SPDR 非美国国际国债 ETF 价格代理，不是各国国债收益率"},
]

YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
# Yahoo 对非浏览器 UA 容易返回 429，这里伪装成浏览器
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                             "AppleWebKit/537.36 (KHTML, like Gecko) "
                             "Chrome/123.0 Safari/537.36")}


def fetch_series(symbol, rng="1y"):
    """Yahoo 图表接口（requests + 硬超时）：返回按日期升序的 [(YYYY-MM-DD, close), ...]。"""
    sym = requests.utils.quote(symbol)
    last_err = ValueError("无可用数据")
    for host in YF_HOSTS:                 # 主备双域名，单个超时 12s
        url = f"https://{host}/v8/finance/chart/{sym}?range={rng}&interval=1d"
        try:
            r = requests.get(url, headers=YF_HEADERS, timeout=12)
            r.raise_for_status()
            res = r.json()["chart"]["result"][0]
            ts = res["timestamp"]
            closes = res["indicators"]["quote"][0]["close"]
            pts = [(time.strftime("%Y-%m-%d", time.gmtime(t)), float(c))
                   for t, c in zip(ts, closes) if c is not None]
            if len(pts) < 2:
                raise ValueError("行情数据点不足")
            return pts
        except Exception as e:
            last_err = e
    raise last_err


def pct(cur, base):
    """涨跌幅（%），保留两位小数；base 缺失或为 0 时返回 None。"""
    if not base:
        return None
    return round((cur / base - 1.0) * 100, 2)


def close_on_or_before(pts, target_date):
    """pts 按日期升序；返回 date <= target_date 的最后一个收盘价，没有则 None。"""
    chosen = None
    for d, c in pts:
        if d <= target_date:
            chosen = c
        else:
            break
    return chosen


def compute_returns(pts):
    """由日线序列算出各周期涨跌幅，并返回 (returns, 数据日期, 最新价)。"""
    last_date, last = pts[-1][0], pts[-1][1]
    ld = datetime.strptime(last_date, "%Y-%m-%d").date()
    returns = {
        "d1":  pct(last, pts[-2][1]),                                              # 对前一交易日
        "w1":  pct(last, close_on_or_before(pts, str(ld - timedelta(days=7)))),    # 近一周
        "m1":  pct(last, close_on_or_before(pts, str(ld - timedelta(days=30)))),   # 近一月
        "ytd": pct(last, close_on_or_before(pts, f"{ld.year - 1}-12-31")),         # 上年末收盘起算
        "y1":  pct(last, pts[0][1]),                                               # 序列最早点（≈ 一年前）
    }
    return returns, last_date, round(last, 4)


# —— 异常值护栏 ——
# 这 28 个标的都是宽基指数 / 主要商品 / 货币 / 国债，正常情况下不会出现下列量级的涨跌幅。
# 一旦某代码返回超过下列上限的涨跌幅，基本可判定为数据源（Yahoo）对该代码的脏数据/口径异常，
# 据此先尝试下一个候选代码；若所有候选都越界，则隐藏越界的周期、只保留正常周期（并标注 suspect）。
SANE_CAPS = {"d1": 25, "w1": 40, "m1": 60, "ytd": 100, "y1": 150}


def breached_periods(returns, caps=SANE_CAPS):
    """返回涨跌幅超出（该标的）合理上限的周期 key 列表（空列表表示通过护栏）。"""
    return [k for k, cap in caps.items()
            if returns.get(k) is not None and abs(returns[k]) > cap]


def _first_sym(a):
    """取标的第一个候选代码（候选可为字符串或 {sym,note} 字典）。"""
    c = a["syms"][0]
    return c["sym"] if isinstance(c, dict) else c


def candidate_proxy(cand, symbol):
    """把候选中的简写代理配置扩展为可供前端和校验器复核的完整契约。"""
    raw = cand.get("proxy") if isinstance(cand, dict) else None
    if not isinstance(raw, dict):
        return None
    return make_proxy_meta(
        raw.get("type"),
        raw.get("targetSymbol"),
        raw.get("instrumentName"),
        symbol,
        currency=raw.get("currency"),
        return_basis=raw.get("returnBasis"),
        note=raw.get("note"),
    )


def select_candidate(asset, fetcher=fetch_series):
    """按登记顺序选取首个通过数据点与异常值护栏的直接标的或显式代理。"""
    chosen = None
    suspect = None
    caps = {**SANE_CAPS, **asset.get("caps", {})}
    for cand in asset["syms"]:
        sym = cand["sym"] if isinstance(cand, dict) else cand
        proxy = candidate_proxy(cand, sym)
        note = cand.get("note") if isinstance(cand, dict) else None
        note = note or (proxy or {}).get("note")
        try:
            points = fetcher(sym)
            returns, last_date, price = compute_returns(points)
        except Exception as exc:
            print(f"[..] {asset['name']} {sym} 取数失败：{str(exc)[:50]}")
            continue
        bad = breached_periods(returns, caps)
        if not bad:
            chosen = (sym, note, proxy, returns, price, last_date, points)
            break
        print(f"[!!] {asset['name']} {sym} 异常周期 {bad}（ytd={returns.get('ytd')}），改用下一个候选")
        if suspect is None:
            suspect = (sym, note, proxy, returns, price, last_date, bad, points)
    return chosen, suspect


def load_prev_data():
    """读取上次的完整 data.json，保留旧文件级时间供兼容迁移。"""
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def fetch_bdi():
    """波罗的海干散货指数（BDI，真实点位）：取自 CNBC 行情接口（symbol .BADI，免密钥、机房可达）。
    单独存到 data['bdi']（不进 assets，避免影响大类资产收益率页面），供首页行情带读取。"""
    url = ("https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol"
           "?symbols=.BADI&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json")
    try:
        r = requests.get(url, headers=YF_HEADERS, timeout=12)
        r.raise_for_status()
        q = r.json()["FormattedQuoteResult"]["FormattedQuote"][0]
        last = float(str(q.get("last", "")).replace(",", ""))
        raw_pct = str(q.get("change_pct", "")).replace("%", "").replace(",", "").strip()
        raw_chg = str(q.get("change", "")).replace(",", "").strip()
        cp = None
        try:
            cp = abs(float(raw_pct))
            if raw_chg.startswith("-") or raw_pct.startswith("-"):
                cp = -cp
        except Exception:
            cp = None
        if last > 0:
            print(f"[OK] BDI .BADI = {last} ({cp}%)")
            return {"price": round(last, 2), "changePct": cp,
                    "asOf": (str(q.get("last_time", ""))[:10] or None), "symbol": ".BADI", "source": "CNBC"}
    except Exception as e:
        print(f"[..] BDI(.BADI/CNBC) 取数失败：{str(e)[:60]}")
    return None


def prev_bdi():
    """上次 data.json 里的 bdi（CNBC 本轮失败时兜底沿用）。"""
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            return json.load(f).get("bdi")
    except Exception:
        return None


def load_prev_history():
    """读取上次的 history.json；缺失或损坏时返回空结构，绝不据此臆造数据。"""
    try:
        with open(HISTORY_PATH, encoding="utf-8") as f:
            prev = json.load(f)
        if isinstance(prev, dict) and isinstance(prev.get("series"), dict):
            return prev
    except Exception:
        pass
    return {}


def build_history(collected, prev_history, updated_at, limit=HISTORY_POINTS):
    """把本轮已抓到的日线合成共享日期轴的紧凑历史。

    规则与公司榜、加密快照完全一致，实现共用 scripts/market_history.py：
    本轮未取到的标的沿用上次序列（不丢历史、也不补造新点）；
    共享日期轴上没有该标的报价的位置写 null，不做前向填充。
    """
    return build_rolling_history(collected, prev_history, updated_at,
                                 source="Yahoo Finance", note=HISTORY_NOTE, limit=limit)


def load_prev_long_history():
    """读取上次的 history-monthly.json；缺失或损坏时返回空结构。"""
    try:
        with open(LONG_HISTORY_PATH, encoding="utf-8") as f:
            prev = json.load(f)
        if isinstance(prev, dict) and isinstance(prev.get("series"), dict):
            return prev
    except Exception:
        pass
    return {}


def fetch_monthly_range(symbol, rng):
    """Yahoo 月线：返回按月升序的 [(YYYY-MM, close), ...]。

    走的是与日线同一个图表接口，只是把粒度换成 1mo；月线收盘由数据源自己给出，
    不由日线二次聚合，避免两处口径不一致。
    """
    sym = requests.utils.quote(symbol)
    last_err = ValueError("无可用月线")
    for host in YF_HOSTS:
        url = f"https://{host}/v8/finance/chart/{sym}?range={rng}&interval=1mo"
        try:
            r = requests.get(url, headers=YF_HEADERS, timeout=15)
            r.raise_for_status()
            res = r.json()["chart"]["result"][0]
            ts = res["timestamp"]
            closes = res["indicators"]["quote"][0]["close"]
            pts = [(time.strftime("%Y-%m", time.gmtime(t)), float(c))
                   for t, c in zip(ts, closes) if c is not None]
            if len(pts) < 2:
                raise ValueError("月线数据点不足")
            return pts
        except Exception as e:
            last_err = e
    raise last_err


def fetch_monthly(symbol):
    """全区间月线 + 最近十年月线合并。

    数据源对超长区间会自行降采样（部分标的退化成季度末），一次 range=max 拿不到
    逐月点；再取一次 range=10y 把最近十年补稠密，重叠月份以十年那份为准。
    两份都是同一个接口的月线收盘，不做任何本地插值。
    """
    merged = dict(fetch_monthly_range(symbol, "max"))
    try:
        merged.update(dict(fetch_monthly_range(symbol, "10y")))
    except Exception:
        pass
    return sorted(merged.items())


def collect_monthly(symbols, daily_series):
    """逐标的取月线；单个失败只跳过自己，并回退到用本轮日线折出的月线。"""
    collected = {}
    failed = []
    for symbol in symbols:
        try:
            collected[symbol] = fetch_monthly(symbol)
        except Exception as e:
            fallback = monthly_from_daily(daily_series.get(symbol) or [])
            if len(fallback) >= 2:
                collected[symbol] = fallback
                failed.append(f"{symbol}（改用本轮日线折算的月线）")
            else:
                failed.append(f"{symbol}：{e}")
        time.sleep(0.35)
    return collected, failed


def build():
    prev_data = load_prev_data()
    prev_health = load_health_json(HEALTH_PATH)
    prev = {a["name"]: a for a in (prev_data or {}).get("assets", []) if a.get("name")}
    assets_out, as_of, ok = [], "", 0
    collected_series = {}
    run_updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    for a in ASSETS:
        rec = {"name": a["name"], "category": a["cat"]}
        if a.get("note"):
            rec["note"] = a["note"]

        chosen, suspect = select_candidate(a)

        if chosen:
            sym, note, proxy, returns, price, last_date, points = chosen
            collected_series[sym] = points
            rec.update({
                "symbol": sym,
                "price": price,
                "returns": returns,
                "stale": False,
                "dataMeta": make_data_meta(
                    "market",
                    "Yahoo Finance",
                    as_of=last_date,
                    updated_at=run_updated_at,
                    frequency="daily",
                    note=note,
                ),
            })
            if note:
                rec["note"] = note
            if proxy:
                rec["proxy"] = proxy
            as_of = max(as_of, last_date); ok += 1
            print(f"[OK] {a['name']:<16} {sym:<12} ytd={returns['ytd']}")
        elif suspect:
            # 所有候选都越界：隐藏越界周期、只保留正常周期，并标注 suspect
            sym, note, proxy, returns, price, last_date, bad, points = suspect
            collected_series[sym] = points
            for k in bad:
                returns[k] = None
            rec.update({
                "symbol": sym,
                "price": price,
                "returns": returns,
                "stale": False,
                "suspect": True,
                "dataMeta": make_data_meta(
                    "market",
                    "Yahoo Finance",
                    as_of=last_date,
                    updated_at=run_updated_at,
                    frequency="daily",
                    status="partial",
                    note="部分周期越过异常值护栏，已隐藏异常值。",
                ),
            })
            rec["note"] = (note + "；" if note else "") + "部分周期数据异常，已隐藏"
            if proxy:
                rec["proxy"] = proxy
            as_of = max(as_of, last_date); ok += 1
            print(f"[~~] {a['name']:<16} {sym:<12} 仅保留正常周期，隐藏 {bad}")
        else:
            # 本轮一个候选都没取到：优先沿用上次的有效值（标 stale），否则留空
            old = prev.get(a["name"])
            if old and old.get("returns", {}).get("ytd") is not None:
                rec.update({"symbol": old.get("symbol", _first_sym(a)),
                            "price": old.get("price"),
                            "returns": old["returns"], "stale": True,
                            "dataMeta": fallback_data_meta(
                                old,
                                source="Yahoo Finance",
                                frequency="daily",
                                legacy_updated_at=(prev_data or {}).get("updatedAt"),
                            )})
                for field in ("note", "proxy"):
                    if old.get(field):
                        rec[field] = old[field]
                print(f"[==] {a['name']} 本轮失败，沿用上次数据（stale）")
            else:
                rec.update({"symbol": _first_sym(a), "price": None,
                            "returns": {p["key"]: None for p in PERIODS},
                            "stale": False,
                            "dataMeta": make_data_meta(
                                "unavailable",
                                "Yahoo Finance",
                                as_of=None,
                                updated_at=run_updated_at,
                                frequency="daily",
                                note="本轮所有候选代码均未返回有效行情。",
                            )})
                print(f"[XX] {a['name']} 全部候选失败，留空")
        assets_out.append(rec)
        time.sleep(0.4)   # 轻微限速，降低 Yahoo 429 概率

    if ok == 0:
        health = make_source_health(
            "asset-tracker",
            published_rows=(prev_data or {}).get("assets", []),
            attempted_rows=assets_out,
            attempted_at=run_updated_at,
            published_snapshot_at=(prev_data or {}).get("updatedAt"),
            published=False,
            previous_health=prev_health,
            failure_reason=f"{len(ASSETS)}项Yahoo候选代码本轮均未返回可发布行情，本轮未发布新快照。",
        )
        write_health(HEALTH_PATH, health)
        print("\n本轮 0 个标的成功（可能整源被限流），保留上次的 data.json，不覆盖。")
        return

    bdi = fetch_bdi() or prev_bdi()   # 真实 BDI 点位（CNBC .BADI），失败则沿用上次

    data_quality = summarize_data_quality(assets_out)
    data = {
        "updatedAt": run_updated_at,
        "asOf": as_of,
        "frequency": "daily",
        "status": data_quality["status"],
        "defaultPeriod": "ytd",
        "source": "Yahoo Finance",
        "note": ("数据来自 Yahoo Finance 公开行情，每日自动更新；涨跌幅为各标的自身价格变动。"
                 "LME 金属以全球期货代理、债券以国债 ETF 代理（详见各条备注）。仅供参考，非投资建议。"),
        "categories": CATEGORIES,
        "periods": PERIODS,
        "assets": assets_out,
        "dataQuality": data_quality,
        "bdi": bdi,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    health = make_source_health(
        "asset-tracker",
        published_rows=assets_out,
        attempted_rows=assets_out,
        attempted_at=run_updated_at,
        published_snapshot_at=run_updated_at,
        published=True,
        previous_health=prev_health,
    )
    write_health(HEALTH_PATH, health)
    print(f"\n写入 {OUT_PATH}：{ok}/{len(ASSETS)} 个标的成功，as_of={as_of}")

    history, retained = build_history(collected_series, load_prev_history(), run_updated_at)
    if history:
        with open(HISTORY_PATH, "w", encoding="utf-8") as f:
            json.dump(history, f, ensure_ascii=False, separators=(",", ":"))
        note = f"，其中 {len(retained)} 项沿用上次序列" if retained else ""
        print(f"写入 {HISTORY_PATH}：{len(history['series'])} 个标的 × {history['points']} 点{note}")
    else:
        print(f"本轮无可用历史序列，保留上次 {HISTORY_PATH}，不覆盖。")

    monthly, monthly_failed = collect_monthly(sorted(collected_series), collected_series)
    long_history, long_retained = build_long_history(
        monthly, load_prev_long_history(), run_updated_at,
        source="Yahoo Finance", note=LONG_HISTORY_NOTE)
    if long_history:
        with open(LONG_HISTORY_PATH, "w", encoding="utf-8") as f:
            json.dump(long_history, f, ensure_ascii=False, separators=(",", ":"))
        note = f"，其中 {len(long_retained)} 项沿用上次序列" if long_retained else ""
        print(f"写入 {LONG_HISTORY_PATH}：{long_history['symbols']} 个标的月线，"
              f"最新月 {long_history['asOf']}{note}")
    else:
        print(f"本轮无可用月线序列，保留上次 {LONG_HISTORY_PATH}，不覆盖。")
    if monthly_failed:
        print(f"月线未取到：{'; '.join(monthly_failed[:8])}")


if __name__ == "__main__":
    build()

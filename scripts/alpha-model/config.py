#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ooglex Alpha 60 V1 的全部可调参数，集中一处，便于审阅与回退。

设计规格见 docs/OOGLEX_ALPHA_MODEL.md。改这里的任何数字都会改变排名，
因此每个常量都标注了它的作用与选它的理由，不留“魔法数字”。
"""

MODEL_NAME = "Ooglex Alpha 60"
MODEL_VERSION = "1.0.0"

# 预测目标：未来 60 个交易日相对基准的超额收益（约 3 个月）。
HORIZON_DAYS = 60
BENCHMARK = "SPY"

# ---------------------------------------------------------------------------
# 因子族权重。分成两层：
#   A 层（可回测）只用日线价格与成交量，历史天然 point-in-time。
#   B 层（只可前瞻验证）用基本面快照，没有 PIT 历史，进回测就是未来函数。
# 两层权重分开列，是为了让“哪部分结论有回测支撑”一眼可辨。
# ---------------------------------------------------------------------------
WEIGHTS_A = {
    "momentum": 30.0,     # 中期动量，跳过最近 21 日
    "reversal": 5.0,      # 短期反转，取负号
    "risk": 15.0,         # 风险质量，高分=波动/回撤小
    "positioning": 10.0,  # 量能与吸筹
}
WEIGHTS_B = {
    "fundamental": 20.0,  # 增长、盈利能力、现金流、资产负债表
    "valuation": 10.0,    # 行业相对估值 + GARP
    "revision": 10.0,     # 盈利预测修正
}
WEIGHTS = {**WEIGHTS_A, **WEIGHTS_B}          # 合计 100
BACKTESTABLE_BLOCKS = tuple(WEIGHTS_A)

# 子因子权重。族内先各自百分位，再按这里加权，最后族分数再进总合成。
SUBWEIGHTS = {
    "momentum": {
        "mom_12_1": 0.35,     # 12 个月收益剔除最近 1 个月（经典动量口径）
        "mom_6_1": 0.25,
        "rs_120": 0.20,       # 120 日相对基准超额
        "trend_200": 0.20,    # 收盘价 / 200 日均线 − 1
    },
    "reversal": {"reversal_21": 1.0},
    "risk": {
        "low_vol_60": 0.35,
        "low_maxdd_120": 0.25,
        "low_downside_120": 0.20,
        "low_tail_252": 0.20,
    },
    "positioning": {
        "volume_expansion": 0.30,   # ADV20 / ADV120 − 1
        "accumulation_60": 0.30,    # 上涨日均量 / 下跌日均量
        "near_52w_high": 0.25,
        "volume_confirm_60": 0.15,  # 收益与成交量变化的相关性
    },
    # ---- 以下三族属 B 层：实时可用，但没有 point-in-time 历史，不进回测 ----
    "fundamental": {
        "revenue_growth": 0.20,     # 营收同比
        "earnings_growth": 0.20,    # 盈利同比
        "operating_margin": 0.13,
        "gross_margin": 0.12,
        "roe": 0.15,
        "fcf_margin": 0.12,         # 自由现金流 / 营收
        "low_leverage": 0.08,       # −净负债/EBITDA，取负号使高分=负债轻
    },
    "valuation": {
        "earnings_yield": 0.35,     # 1 / 前瞻市盈率，高=便宜
        "ev_ebitda_yield": 0.25,    # 1 / EV/EBITDA
        "fcf_yield": 0.25,          # 自由现金流 / 市值
        "ev_sales_yield": 0.15,     # 1 / EV/Sales
    },
    "revision": {
        "eps_revision_90d": 0.40,   # 明年EPS一致预期 90 日变化率
        "revision_breadth": 0.30,   # (上调−下调)/分析师总数
        "eps_revision_30d": 0.15,   # 30 日变化率，捕捉更新的转向
        "target_upside": 0.15,      # 目标价相对现价
    },
}

# ---------------------------------------------------------------------------
# 归一化
# ---------------------------------------------------------------------------
WINSOR_LOW = 0.01          # 去极值下界分位
WINSOR_HIGH = 0.99         # 去极值上界分位
SECTOR_BLEND = 0.5         # 最终分 = λ·全市场分位 + (1−λ)·行业内分位
SECTOR_MIN_MEMBERS = 8     # 行业样本少于此数时不做行业内排名，退回全市场
MIN_BLOCK_COVERAGE = 0.6   # 族内子因子可得比例低于此值，该族判为缺失
MIN_TOTAL_COVERAGE = 0.6   # 有效族权重占比低于此值的股票不给分，直接剔除

# ---------------------------------------------------------------------------
# 硬过滤（打分之前）。目的是把“统计上算得出但实际交易不了”的标的排除。
# ---------------------------------------------------------------------------
MIN_ADV_USD = 20_000_000.0   # 20 日平均成交额下限
MIN_PRICE_USD = 5.0
MIN_HISTORY_DAYS = 252       # 至少一年历史，否则长周期因子无定义
MAX_RECENT_GAPS = 2          # 最近 20 个交易日允许的缺失天数

# 候选池（打分之后）
CANDIDATE_MIN_ALPHA = 80.0
CANDIDATE_MIN_RISK = 50.0
CANDIDATE_MIN_CONFLUENCE = 2   # 独立块中至少 2 块达标

# Confluence 的独立块划分：同源因子只算一票，避免价格类因子重复计数。
CONFLUENCE_BLOCKS = {
    "price": ("momentum", "reversal", "risk", "positioning"),
    "quality": ("fundamental",),
    "expectation": ("valuation", "revision"),
}
CONFLUENCE_THRESHOLD = 70.0

# ---------------------------------------------------------------------------
# 回测
# ---------------------------------------------------------------------------
BACKTEST_TOP_N = 20              # 组合持仓数
BACKTEST_COST_BPS_ONE_WAY = 10.0  # 单边成本：价差 + 冲击 + 佣金
DECILES = 10

# 模型验收线。任一项不过，V1 判为不可用，不做“再调调看”。
GATE_IC_MEAN = 0.02
GATE_IC_IR = 0.30
GATE_IC_HIT_RATE = 0.55
GATE_DECILE_SPEARMAN = 0.70      # |分组序号与分组收益的秩相关|
GATE_NET_SPREAD = 0.0            # 扣成本后 D1−D10 必须为正

# ---------------------------------------------------------------------------
# 数据源
# ---------------------------------------------------------------------------
YF_HOSTS = ("query1.finance.yahoo.com", "query2.finance.yahoo.com")
YF_HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/123.0 Safari/537.36"),
    "Accept": "application/json",
}
HTTP_TIMEOUT = 15
CACHE_TTL_HOURS = 12
SOURCE_NAME = "Yahoo Finance"

# quoteSummary 需要 cookie + crumb 握手（v8/chart 不需要）。握手失败时 B 层整体缺失，
# 总分按 A 层权重重新归一化——不用中位数把缺失伪装成中性。
YF_QUOTE_MODULES = ("financialData", "defaultKeyStatistics",
                    "summaryDetail", "earningsTrend", "price")
YF_CRUMB_URL = "https://query2.finance.yahoo.com/v1/test/getcrumb"
YF_COOKIE_URLS = ("https://fc.yahoo.com", "https://finance.yahoo.com")
FUNDAMENTAL_CACHE_TTL_HOURS = 20   # 财务是慢变量，一天抓一次足够

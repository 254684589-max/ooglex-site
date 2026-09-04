#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：USAspending.gov 的联邦采购数据能不能成为第三条有出处的关系源。

## 为什么要这条

按板块拆开覆盖率之后，缺口的形状一眼就能看出来，而且它是**数据源的形状**：

    科技 34/84   工业 17/76   原材料 5/20      ← Form SD 够得着的
    金融  0/70   房地产 0/29  公用事业 1/32    ← 永远够不着

Form SD 只管「产品中含钽锡钨金」的发行人。银行没有产品，REIT 没有产品，
这三个板块的 0 不是抓取失败，再怎么优化抽取器也不会变。要补这些板块，
只能换一条**适用范围不同**的源。

USAspending 是美国联邦采购的官方公开库，覆盖的是「谁向政府卖了什么」，
与「产品里有没有矿」完全正交。国防、IT 服务、医疗、公用事业都在里面。

## 关键在分包，不在中标

`政府 → 承包商` 只是「政府是它的客户」，价值有限。真正想要的是 FFATA 要求
披露的**分包**：承包商自己申报「这份合同我分包给了谁、多少钱」。那正是
**一级供应关系**——用户从第一天要的那一层，也是 SEC 申报给不了的
（ASC 280 要求披露客户集中度的幅度、不要求披露身份，已实测否决）。

## 这个探针要回答五件事

1. **接口通不通**、限流多少。（本机代理按组织策略拒绝 api.usaspending.gov，
   所以只能在 Actions 里跑。这不是故障，不要绕。）
2. **字段到底叫什么**。不背文档、不猜——把第一条结果的**原始键名**打出来。
   前几轮的教训是「不看原始数据就改规则，等于用假设换假设」。
3. **分包数据存不存在**、一条记录能不能同时定位到分包方与总包方。
4. **认公司认得准不准**——这是本条源最大的风险。我们手里只有公司名和 CIK，
   没有 UEI，只能按名字搜。名字搜很容易把「Apple Inc.」搜成
   「Apple Valley School District」。所以**把返回的收款方原名逐条打出来**，
   由人看，不由匹配率的数字说了算。
5. **量级**。几千条还是几千万条，决定要不要以及怎么设闸门。

## 边界

**本探针不写任何数据文件，不建任何边。** 只回答「这条源可不可行」。
凡是本探针没实测到的，结论里一律不写。
"""
from __future__ import annotations

import json
import os
import sys
import time
from urllib import error, request

API = "https://api.usaspending.gov/api/v2"
TIMEOUT = 45
GAP = 1.0                 # 官方接口有限流，给足间隔
MAX_REQUESTS = 40
BODY_LIMIT = 12_000_000

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

# 刻意按板块选，重点是 Form SD 够不着的那几个。
# 每组末尾那家是对照：预期在联邦采购里没有或极少，若也「匹配成功」，
# 说明是名字搜出来的假阳性，不是真有合同。
TARGETS = [
    ("LMT",  "洛克希德马丁", "Lockheed Martin",       "工业"),
    ("RTX",  "雷神技术",     "Raytheon",              "工业"),
    ("LDOS", "莱多斯",       "Leidos",                "工业"),
    ("JPM",  "摩根大通",     "JPMorgan Chase",        "金融"),
    ("UNH",  "联合健康",     "UnitedHealth",          "医疗健康"),
    ("MCK",  "麦克森",       "McKesson",              "医疗健康"),
    ("IBM",  "IBM",          "International Business Machines", "科技"),
    ("MSFT", "微软",         "Microsoft",             "科技"),
    ("NEE",  "新纪元能源",   "NextEra Energy",        "公用事业"),
    ("PLD",  "安博",         "Prologis",              "房地产"),
]

TIME_PERIOD = [{"start_date": "2023-10-01", "end_date": "2025-09-30"}]
# A=BPA Call B=采购订单 C=交付订单 D=定期合同。只看合同，不看拨款与贷款——
# 拨款给大学和州政府，与企业供应链无关。
CONTRACT_CODES = ["A", "B", "C", "D"]


class Budget:
    def __init__(self) -> None:
        self.used = 0

    def take(self) -> bool:
        if self.used >= MAX_REQUESTS:
            return False
        self.used += 1
        return True


BUDGET = Budget()


def _post(path: str, payload: dict) -> tuple[dict | None, str]:
    """POST 一次。返回 (解析后的 JSON, 说明)。失败不抛异常，如实返回原因。"""
    if not BUDGET.take():
        return None, "请求预算用尽"
    body = json.dumps(payload).encode("utf-8")
    req = request.Request(API + path, data=body, method="POST", headers={
        "User-Agent": UA,
        "Content-Type": "application/json",
        "Accept": "application/json",
    })
    try:
        with request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read(BODY_LIMIT)
            return json.loads(raw.decode("utf-8", "replace")), f"HTTP {resp.status}"
    except error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read(2000).decode("utf-8", "replace")[:300]
        except Exception:                                   # noqa: BLE001
            pass
        return None, f"HTTP {exc.code} {detail}"
    except (error.URLError, ValueError, OSError) as exc:
        return None, f"{type(exc).__name__}: {exc}"
    finally:
        time.sleep(GAP)


def _get(path: str) -> tuple[dict | None, str]:
    if not BUDGET.take():
        return None, "请求预算用尽"
    req = request.Request(API + path, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read(BODY_LIMIT)
            return json.loads(raw.decode("utf-8", "replace")), f"HTTP {resp.status}"
    except error.HTTPError as exc:
        return None, f"HTTP {exc.code}"
    except (error.URLError, ValueError, OSError) as exc:
        return None, f"{type(exc).__name__}: {exc}"
    finally:
        time.sleep(GAP)


def award_search(name: str, subawards: bool, fields: list[str], limit: int = 5) -> tuple[list, str]:
    """按收款方名字搜奖项。subawards=True 时搜分包。"""
    payload = {
        "filters": {
            "award_type_codes": CONTRACT_CODES,
            "recipient_search_text": [name],
            "time_period": TIME_PERIOD,
        },
        "fields": fields,
        "limit": limit,
        "page": 1,
        "subawards": subawards,
    }
    data, why = _post("/search/spending_by_award/", payload)
    if data is None:
        return [], why
    return data.get("results") or [], why


def show_keys(rows: list, label: str) -> None:
    """把第一条结果的原始键名打出来。

    这一步不是调试残留，是**判据**：字段名靠背文档会背错，靠猜会猜错，
    只有把接口实际返回的键打出来，后面写抽取器时才不是在拿假设换假设。
    """
    if not rows:
        print(f"       {label}：无结果，看不到字段名")
        return
    keys = sorted(rows[0].keys())
    print(f"       {label}原始字段（{len(keys)} 个）：")
    line = ""
    for k in keys:
        piece = k + "  "
        if len(line) + len(piece) > 86:
            print("         " + line.rstrip())
            line = ""
        line += piece
    if line:
        print("         " + line.rstrip())


def main() -> None:
    print("── USAspending 联邦采购：接口、字段、分包、认名、量级 ──────────────\n")

    root, why = _get("/references/toptier_agencies/")
    n_agency = len((root or {}).get("results") or [])
    print(f"[{'OK' if root else 'XX'}] 接口连通性  {why}"
          + (f"  机构 {n_agency} 个" if root else ""))
    if not root:
        print("\n接口不通，后面的结论都无从谈起。")
        print(f"请求用掉 {BUDGET.used}/{MAX_REQUESTS}")
        return

    # 一、总包（政府 → 承包商）。先确认按名字搜得到东西、字段叫什么。
    print("\n── 一、总包：政府作为客户 ──────────────────────────────────────")
    prime_fields = ["Award ID", "Recipient Name", "Award Amount",
                    "Awarding Agency", "Start Date", "End Date", "recipient_id",
                    "generated_internal_id"]
    prime_seen = 0
    for symbol, zh, query, sector in TARGETS:
        rows, why = award_search(query, False, prime_fields, limit=5)
        if not rows:
            print(f"[--] {symbol:<5} {zh:<7}（{sector}）  无结果  {why}")
            continue
        prime_seen += 1
        names = []
        for r in rows:
            nm = r.get("Recipient Name") or "（无名字字段）"
            if nm not in names:
                names.append(nm)
        print(f"[OK] {symbol:<5} {zh:<7}（{sector}）  {len(rows)} 条")
        # 认名风险全在这里：搜「Apple」会不会搜出「Apple Valley 学区」，
        # 只能靠人看原名，不能靠匹配率。
        for nm in names[:5]:
            print(f"         收款方原名：{nm}")
        if prime_seen == 1:
            show_keys(rows, "总包")

    # 二、分包（承包商 → 分包商）。这才是一级供应关系。
    print("\n── 二、分包：一级供应关系 ──────────────────────────────────────")
    print("    问题：一条分包记录里能不能同时看到分包方与总包方？看原始字段。\n")
    sub_fields = ["Sub-Award ID", "Sub-Awardee Name", "Sub-Award Amount",
                  "Sub-Award Date", "Prime Recipient Name", "Prime Award ID",
                  "Awarding Agency", "Sub-Award Description"]
    sub_seen = 0
    for symbol, zh, query, sector in TARGETS:
        rows, why = award_search(query, True, sub_fields, limit=5)
        if not rows:
            print(f"[--] {symbol:<5} {zh:<7}（{sector}）  无分包记录  {why}")
            continue
        sub_seen += 1
        print(f"[OK] {symbol:<5} {zh:<7}（{sector}）  {len(rows)} 条")
        for r in rows[:3]:
            prime = r.get("Prime Recipient Name") or "（无总包字段）"
            sub = r.get("Sub-Awardee Name") or "（无分包字段）"
            amt = r.get("Sub-Award Amount")
            date = r.get("Sub-Award Date") or "（无日期）"
            print(f"         {prime}  →  {sub}")
            print(f"           金额 {amt}  日期 {date}")
        if sub_seen == 1:
            show_keys(rows, "分包")

    print("\n── 结论 ────────────────────────────────────────────────────────")
    print(f"总包：{prime_seen}/{len(TARGETS)} 家搜到记录")
    print(f"分包：{sub_seen}/{len(TARGETS)} 家搜到记录")
    print(f"请求用掉 {BUDGET.used}/{MAX_REQUESTS}")
    print("\n注意：以上「搜到记录」只表示**按名字搜返回了东西**，"
          "不表示那些记录真属于这家上市公司。")
    print("按名字搜必然有假阳性（子公司、同名机构、政府单位），"
          "而本探针拿不到 UEI，无法自动判定归属。")
    print("因此接不接这条源、以及要不要限定到分包，"
          "由人看上面的收款方原名逐条判断，不由本脚本的计数决定。")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)

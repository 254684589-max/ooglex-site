#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补名单工程 阶段 3：USAspending 分包能不能给出一级供应关系（实体锚点版）。

**先校正一个名字。** 规划里写的是「UEI 锚点」，但实测（run 43）打出的
`/search/spending_by_award/` 返回键名里**没有 UEI**：

    Award Amount、Award ID、Awarding Agency、Recipient Name、Start Date、
    agency_slug、awarding_agency_id、generated_internal_id、internal_id、recipient_id

所以锚的是 `recipient_id`——USAspending 自己的实体 id，不是 UEI。这不影响
锚点的作用（它一样是唯一实体标识），但**名字要照实说**：叫它 UEI 锚点就是
在写没有核验过的东西。

## 为什么重探，以及上一轮留下的是什么尾巴

第一轮（`probe_usaspending.py`）实测过这条源，结论是**暂不接**，理由两条：

    一、按名字搜有假阳性——搜 Leidos 会搜出 KALEIDOSCOPE
    二、想补的那几个板块（金融／房地产／公用事业）恰恰没有分包记录

第一条是**仪器问题**：`recipient_search_text` 是子串搜索，它本来就会这样。
第二条是**源本身的形状**。上一轮没有把两者分开量，所以结论只能停在「暂不接」。
本轮把它们分开：先把认名做成能锚定的，再量增量。

## 锚点是什么意思

不再「按名字搜到什么就算什么」，改成两步：

    一、按名字搜 → 候选收件方（原名 + 身份字段）
    二、**只有严格同名且身份唯一的候选才算锚定**，否则标「不锚定」并写原因

严格同名的口径比仓库里 `probe_ex21_subsidiaries.py` 的 `norm()` **更紧**：
那一套连 holdings／group／technologies／international 一起去掉，用在这里会把
「General Dynamics Information Technology」折成「general dynamics」，
**自己造出假阳性**。本文件只去法律形式后缀（Inc／Corp／Company／LLC／Ltd…）与领头的 the，
业务描述词一个都不去。

这条界线是离线验出来的，不是想出来的：第一版把 `company` 也当成业务描述词
排除在外，结果「3M Company」与「3M CO」判成了两家——**那是同一家的两种
写法，方向是假阴性。** 界线在「这个词说的是法律形式，还是说的是业务」。

## 判据（探之前写死，改它等于改判据）

    Gate A 准确性：锚定的公司里，人工核对判为错配的 > 5% → 判死
    Gate B 增量：抽样 100 家里，能产出至少一条带具名分包方关系的
                 ≥15 家 → 才建；< 15 判「收益不足，不建」

Gate B 的 15 与阶段 2 同一个数，因为**建的成本完全一样**：一级供应商从零
起步要建整条新管线（新 relation 类型、新边文件格式、页面新分区、公司页新
区块），两到三轮工作量。100 家里不足 15 家，外推全池不足 900 条且分布极散，
撑不起一个新分区。

**两道闸门都过才建。** 准确但没有量 → 不值得建；有量但不准 → 不许建。

## 逐层报数，让失败发生在哪一层一眼可见

    按名字搜到候选   → 搜不到就是这家公司不是联邦承包商
    严格同名可锚定   → 锚不上就是认名问题（本轮要修的就是这一层）
    锚定后查到总包   → 查不到就是身份字段用错了
    查到分包记录     → 查不到就是 FFATA 这一档本来就薄
    解出分包方名称   → 解不出就是字段格式问题
    分包方在池内     → 能对回池内的才是双向边，更有价值

阶段 2 的教训：**前面的层没通，后面的数就不是数据，是仪器读数。**

## 字段不猜

本探针**先把第一条总包记录与第一条分包记录的原始键名打出来**，再依赖它们。
身份字段（UEI 或内部 id）如果根本不在返回里，锚点这一步就无从做起——
那时报「结论无效」并非零退出，**不据此判死**（拿取数失败冒充业务事实是禁止的）。

## 边界

只读。不写任何数据文件、不建任何边。本机代理按组织策略拒绝
api.usaspending.gov，**只能在 Actions 里跑**，这不是故障，不要绕。
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from urllib import error, request

# **名字口径与阶段 4 共用一个模块，不各写一份。** 第二十六轮刚踩过「同一件事
# 两个来源」的坑；这套规范化离线验过 27 条，复制一份出去就等于埋下第二份。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from entity_names import (  # noqa: E402
    LEADING_THE, LEGAL_SUFFIX, NOT_A_COMPANY, core_query, norm)

API = "https://api.usaspending.gov/api/v2"
NODES_PATH = "apps/supply-chain/nodes.json"
TIMEOUT = 45
GAP = 0.6
SAMPLE = int(os.environ.get("UEI_SAMPLE", "100"))
MAX_REQUESTS = int(os.environ.get("UEI_MAX_REQUESTS", "600"))
# 判据。改这两个数等于改判据，必须连同上面的理由一起改。
HIT_FLOOR = int(os.environ.get("UEI_HIT_FLOOR", "15"))
MISMATCH_CEIL = float(os.environ.get("UEI_MISMATCH_CEIL", "0.05"))

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

TIME_PERIOD = [{"start_date": "2022-10-01", "end_date": "2026-09-30"}]
CONTRACT_CODES = ["A", "B", "C", "D"]



class Budget:
    def __init__(self, total: int = MAX_REQUESTS) -> None:
        self.used = 0
        self.total = total

    def take(self) -> bool:
        if self.used >= self.total:
            return False
        self.used += 1
        return True


BUDGET = Budget()




def post(path: str, payload: dict) -> tuple[dict | None, str]:
    if not BUDGET.take():
        return None, "请求预算用尽"
    body = json.dumps(payload).encode("utf-8")
    req = request.Request(API + path, data=body, method="POST", headers={
        "User-Agent": UA, "Content-Type": "application/json",
        "Accept": "application/json"})
    try:
        with request.urlopen(req, timeout=TIMEOUT) as resp:
            return json.loads(resp.read().decode("utf-8", "replace")), f"HTTP {resp.status}"
    except error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read(600).decode("utf-8", "replace")[:200]
        except Exception:                                    # noqa: BLE001
            pass
        return None, f"HTTP {exc.code} {detail}"
    except (error.URLError, ValueError, OSError) as exc:
        return None, f"{type(exc).__name__}: {exc}"
    finally:
        time.sleep(GAP)




def award_rows(name: str, subawards: bool, fields: list[str],
               limit: int = 10) -> tuple[list, str]:
    return_rows, note = post("/search/spending_by_award/", {
        "filters": {"award_type_codes": CONTRACT_CODES,
                    "recipient_search_text": [name],
                    "time_period": TIME_PERIOD},
        "fields": fields, "limit": limit, "page": 1, "subawards": subawards})
    if return_rows is None:
        return [], note
    return return_rows.get("results") or [], note


PRIME_FIELDS = ["Award ID", "Recipient Name", "Award Amount", "Awarding Agency",
                "Start Date", "recipient_id", "generated_internal_id"]
SUB_FIELDS = ["Sub-Award ID", "Sub-Awardee Name", "Sub-Award Amount",
              "Sub-Award Date", "Prime Recipient Name", "Prime Award ID",
              "Sub-Award Description"]

# 身份字段候选。**按返回里真有的那个用，没有就报结论无效。**
ID_KEYS = ("recipient_uei", "Recipient UEI", "uei", "recipient_id",
           "generated_internal_id")


def identity_of(row: dict) -> tuple[str, str] | None:
    for key in ID_KEYS:
        value = row.get(key)
        if value:
            return key, str(value)
    return None


def anchor(company: str, rows: list[dict]) -> tuple[str, str, object]:
    """返回 (结果, 说明, 载荷)。结果 ∈ anchored / ambiguous / no-exact。"""
    target = norm(company)
    if not target:
        return "no-exact", "公司名规范化后为空", None
    exact = [r for r in rows if norm(r.get("Recipient Name")) == target]
    if not exact:
        seen = []
        for r in rows:
            nm = r.get("Recipient Name")
            if nm and nm not in seen:
                seen.append(nm)
        return "no-exact", "候选里没有严格同名：" + "；".join(seen[:3]), None
    ids = {}
    for r in exact:
        found = identity_of(r)
        if found:
            ids.setdefault(found[1], r)
    if not ids:
        return "no-exact", "严格同名但返回里没有任何身份字段", None
    if len(ids) > 1:
        return "ambiguous", f"严格同名的实体有 {len(ids)} 个不同身份，不锚定", None
    return "anchored", "", exact[0]


def main() -> int:
    with open(NODES_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)
    pool = [n for n in (payload.get("nodes") or []) if n.get("name")]
    pool.sort(key=lambda n: n.get("symbol") or "")
    if not pool:
        print("[XX] 节点表为空")
        return 1
    in_pool = {norm(n.get("name")): n.get("symbol") for n in pool}

    # 按环节分层，与阶段 1／2 同一条理由：按代码排序取步长会让某些环节占比腰斩。
    by_stage: dict[str, list] = {}
    for node in pool:
        by_stage.setdefault(node.get("stage") or "未判定", []).append(node)
    sample: list[dict] = []
    for _, members in sorted(by_stage.items(), key=lambda kv: -len(kv[1])):
        want = max(1, round(len(members) / len(pool) * SAMPLE))
        step = max(1, len(members) // want)
        sample.extend(members[::step][:want])
    sample = sample[:SAMPLE]

    print(f"全池 {len(pool)} 家 · 按环节分层取样 {len(sample)} 家")
    print("判据（探之前已写死，两道都过才建）：")
    print(f"  Gate A 准确性：错配 > {MISMATCH_CEIL:.0%} → 判死")
    print(f"  Gate B 增量：能产出具名分包关系的 ≥{HIT_FLOOR} 家 → 才建")
    print("逐层报数：搜到候选 → 严格同名可锚定 → 查到总包 → 查到分包 "
          "→ 解出分包方 → 分包方在池内\n")

    got_cand = anchored = got_prime = got_sub = named = both_sides = 0
    ambiguous: list[tuple[str, str]] = []
    no_exact: list[tuple[str, str]] = []
    mismatched: list[tuple[str, str, str]] = []
    direction_misses: list[tuple[str, str, str]] = []
    dropped_non_company: list[tuple[str, str]] = []
    edges: list[tuple[str, str, str, str]] = []
    id_key_seen: str | None = None
    keys_printed = {"prime": False, "sub": False}
    failed = 0

    for index, node in enumerate(sample, 1):
        symbol = node.get("symbol") or "?"
        name = node.get("name") or ""
        query = core_query(name)
        rows, note = award_rows(query, False, PRIME_FIELDS)
        if not rows:
            if "HTTP 200" not in note and "请求预算" not in note:
                failed += 1
            continue
        got_cand += 1
        if not keys_printed["prime"]:
            keys_printed["prime"] = True
            print("总包记录的原始键名（不猜字段，照实打出来）：")
            print("   " + "、".join(sorted(rows[0].keys())) + "\n")
        state, reason, hit = anchor(name, rows)
        if state == "ambiguous":
            ambiguous.append((symbol, reason))
            continue
        if state == "no-exact":
            no_exact.append((symbol, reason))
            continue
        anchored += 1
        found = identity_of(hit)
        id_key_seen = id_key_seen or (found[0] if found else None)
        matched_name = hit.get("Recipient Name") or ""
        # Gate A：锚到了政府／学校这类实体一律算错配，人工核对清单照样全列。
        if NOT_A_COMPANY.search(matched_name):
            mismatched.append((symbol, name, matched_name))
            continue
        got_prime += 1
        subs, _note2 = award_rows(query, True, SUB_FIELDS)
        if not subs:
            continue
        got_sub += 1
        if not keys_printed["sub"]:
            keys_printed["sub"] = True
            print("分包记录的原始键名：")
            print("   " + "、".join(sorted(subs[0].keys())) + "\n")
        # **方向不许假设。** 第一版只收「总包方严格同名」的那些分包，于是
        # 查到分包记录的 2 家全被自己过滤掉了，Gate B 报 0 ——那不是数据，
        # 是我假设了 recipient_search_text 匹配总包方。它也可能匹配分包方，
        # 那时我们这家公司是**分包方**，对方是总包方，关系方向正好反过来，
        # 而那仍然是一条真实的一级供应关系。
        #
        # 所以两侧都认，并把**我们这家公司出现在哪一侧**记下来。
        mine_name = norm(name)
        parties = []
        for r in subs:
            prime = (r.get("Prime Recipient Name") or "").strip()
            sub_name = (r.get("Sub-Awardee Name") or "").strip()
            if norm(prime) == mine_name:
                other, side = sub_name, "我方是总包"
            elif norm(sub_name) == mine_name:
                other, side = prime, "我方是分包"
            else:
                direction_misses.append((symbol, prime[:34], sub_name[:34]))
                continue
            if not other:
                continue
            if NOT_A_COMPANY.search(other):
                dropped_non_company.append((symbol, other[:40]))
                continue
            parties.append((other, side, r.get("Sub-Award Date")
                            or r.get("Sub-Award ID") or ""))
        if not parties:
            continue
        named += 1
        inside = [p for p in parties if norm(p[0]) in in_pool]  # 对方也在池内
        if inside:
            both_sides += 1
        for other, side, token in parties[:2]:
            edges.append((symbol, other + "  [" + side + "]",
                          in_pool.get(norm(other)) or "—", token))
        if index % 20 == 0 or index == len(sample):
            print(f"     … 已处理 {index}/{len(sample)}，"
                  f"锚定 {anchored} 家、具名分包 {named} 家，"
                  f"请求用掉 {BUDGET.used}")

    print("\n" + "─" * 74)
    print(f"按名字搜到候选 {got_cand} 家 · 失败 {failed} 家 · 请求 {BUDGET.used}")
    print(f"  严格同名可锚定 {anchored} 家"
          + (f"（身份字段用的是 {id_key_seen}）" if id_key_seen else ""))
    print(f"    其中锚到非企业实体（错配）{len(mismatched)} 家")
    print(f"  锚定且是企业、查到总包 {got_prime} 家")
    print(f"    查到分包记录 {got_sub} 家")
    print(f"      **解出具名分包方 {named} 家**")
    print(f"        分包方也在池内（双向边）{both_sides} 家")
    print(f"  同名但身份不唯一、不锚定 {len(ambiguous)} 家")
    print(f"  没有严格同名候选 {len(no_exact)} 家")

    if got_cand == 0:
        print("\n[XX] 一条总包记录都没取到——**结论无效**，不输出判据。")
        print("     这是取数或接口问题，不是业务事实。先修取数再重跑。")
        return 1
    if id_key_seen is None:
        print("\n[XX] 返回里没有任何身份字段，锚点这一步无从做起"
              "——**结论无效**，不输出判据。")
        print(f"     试过的键名：{'、'.join(ID_KEYS)}。先确认接口字段再重跑。")
        return 1

    if no_exact:
        print("\n没有严格同名候选的样例（判断是不是认名太紧）：")
        for symbol, reason in no_exact[:8]:
            print(f"   {symbol}：{reason[:120]}")
    if ambiguous:
        print("\n同名但身份不唯一（这一档宁可不锚，也不猜）：")
        for symbol, reason in ambiguous[:6]:
            print(f"   {symbol}：{reason}")
    if mismatched:
        print("\n锚到非企业实体的，全部列出（**Gate A 就是看这一档**）：")
        for symbol, want, got in mismatched:
            print(f"   {symbol}：池内「{want}」→ 匹配到「{got}」")
    if direction_misses:
        print("\n分包记录里两侧都不是这家公司（说明搜到的是第三方的记录）：")
        for symbol, prime, sub_name in direction_misses[:8]:
            print(f"   {symbol}：总包「{prime}」→ 分包「{sub_name}」")
    if dropped_non_company:
        print("\n对方是非企业实体、不计入的：")
        for symbol, other in dropped_non_company[:6]:
            print(f"   {symbol} → {other}")
    if edges:
        print("\n解出的分包关系，全部列出（**人工核对用，别只看计数**）：")
        for symbol, sub_name, inside, token in edges:
            tag = f"池内 {inside}" if inside != "—" else "池外"
            print(f"   {symbol:<6} → {sub_name[:46]:<48} | {tag} | {token}")

    rate = (len(mismatched) / anchored) if anchored else 0.0
    print("\n" + "─" * 74)
    print(f"Gate A 准确性：锚定 {anchored} 家里错配 {len(mismatched)} 家 = "
          f"{rate:.1%}（上限 {MISMATCH_CEIL:.0%}）"
          + ("  → 过" if rate <= MISMATCH_CEIL else "  → **不过**"))
    print(f"Gate B 增量：具名分包 {named} 家（门槛 {HIT_FLOOR}）"
          + ("  → 过" if named >= HIT_FLOOR else "  → **不过**"))
    if rate <= MISMATCH_CEIL and named >= HIT_FLOOR:
        print("\n判据：两道都过 → **值得建**，进入接入设计")
    else:
        print("\n判据：有闸门不过 → **不建**，写进判决表并写清依据")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)

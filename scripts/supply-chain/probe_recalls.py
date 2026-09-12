#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补名单工程 阶段 5：政府召回公告能不能点名零部件供应商。

## 这条源的形状，以及它自带的一个必须说在明处的偏向

召回公告里常常写着「某型号的气囊充气机由 X 公司制造」——那是一条**真实的
零部件供应关系**，出处是政府文件，许可干净（GOV）。

但它有个结构性偏向，**比覆盖面窄更要紧**：

    只有**出过问题**的供应关系才会被记录。

一家公司有一百个供应商、其中一个的零件出了事故，这条源只会让那一个出现在
图上。若日后真要建，页面必须写明这一点——否则读者会把「这家公司的供应商」
读成一份名单，而它其实是一份**事故清单**。这句话在判据通过之前就要定死，
不能等建完再补。

## 判据

规划里探前写死的那一条**一字不动**：

    抽样 200 条召回，能点名对方的 ≥20 条才建

这一条与前几个阶段不同：它数的是**条**（召回记录），不是家。所以不另设
第二道闸门——「点名对方」本身就已经是关系的定义，不存在阶段 4 那种
「锚上了但没有第二方」的空转。

## 逐层报数

    接口通不通 / 字段叫什么   → 不通就报「结论无效」，不出判据
    取到召回记录              → 取不到就是取数问题
    召回方能锚回池内          → 锚不上说明这条记录与本池无关
    正文里点到第二家公司      → 点不到就是这类公告本来不写供应商
    第二家是可用的公司名      → 解不出就是正文格式问题

## 字段与端点都不凭记忆写

阶段 4 的教训：两个 Socrata 数据集 id 是我凭记忆填的，实测 `dataset.missing`。
这一轮**每个候选端点都先打一次、把 HTTP 状态与第一条记录的原始键名打出来**，
再决定用哪个字段。三家机构各试几个候选，哪个活着用哪个；全都不活就报
「结论无效」并非零退出，**不据此判死**。

## 边界

只读。不写任何数据文件、不建任何边。本机代理取不到这些域，只能在 Actions 里跑。
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from urllib import error, parse, request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from entity_names import NOT_A_COMPANY, norm, same_entity  # noqa: E402

NODES_PATH = "apps/supply-chain/nodes.json"
TIMEOUT = 45
GAP = 0.4
SAMPLE = int(os.environ.get("RECALL_SAMPLE", "200"))
MAX_REQUESTS = int(os.environ.get("RECALL_MAX_REQUESTS", "400"))
# 判据。规划原话，改它等于改判据。
HIT_FLOOR = int(os.environ.get("RECALL_HIT_FLOOR", "20"))

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

# 候选端点。**逐个打、把真实状态与键名打出来**，不预设哪个能用。
# 每条给一个取列表的 URL 和一个「这条记录的叙述文字在哪些键里」的候选清单。
CANDIDATES = [
    ("nhtsa-recalls", "https://api.nhtsa.gov/recalls/recallsByVehicle"
                      "?make=honda&model=accord&modelYear=2020"),
    ("nhtsa-products", "https://api.nhtsa.gov/products/vehicle/models"
                       "?modelYear=2020&make=honda&issueType=r"),
    ("openfda-device", "https://api.fda.gov/device/recall.json?limit=100"),
    ("openfda-food", "https://api.fda.gov/food/enforcement.json?limit=100"),
    ("openfda-drug", "https://api.fda.gov/drug/enforcement.json?limit=100"),
    ("cpsc-recalls", "https://www.saferproducts.gov/RestWebServices/Recall"
                     "?format=json&RecallDateStart=2023-01-01"),
]
# 叙述文字可能在的键。按真实返回里有的用。
TEXT_KEYS = ("Consequence", "Remedy", "Summary", "NHTSAActionNumber",
             "Component", "Notes", "product_description", "reason_for_recall",
             "code_info", "Description", "Title", "ConsumerContact",
             "res_event_number", "root_cause_description", "action")
# 召回方名字可能在的键。
FIRM_KEYS = ("Manufacturer", "recalling_firm", "firm_name", "Firms",
             "manufacturer_name", "Name", "CompanyName")

# 从叙述里抓第二家公司。
#
# **第一版是按「正文里的大写短语」抓的，拿真实召回文字一试就露馅**，三个假阳性：
#
#     「Certain Ford Escape and Lincoln Corsair vehicles…」 → 抓出 Ford Escape（车型名）
#     「the Fisher-Price Rock 'n Play Sleeper…」            → 抓出 Fisher-Price Rock（产品名）
#     「reported to the National Highway Traffic Safety Administration」 → 抓出那个机构
#
# 而我自己写的那 12 条用例全过了——**因为那些用例是我照着实现写的**。
#
# 结论不是「再补几条排除词」，是**设计错了**：名字出现在正文里说明不了任何事，
# 它可能是零售商、车型、产品线、政府机构。要让它成为一条**供应关系**，
# 必须有一个明说的线索词：「manufactured by X」「supplied by X」。
#
# 所以改成**先找线索词，再取紧跟其后的名字**。这也正好把判据里「点名对方」
# 的口径定死：点名 = 被指为供应方，不是在文里出现过。
SUPPLY_CUE = re.compile(
    r"\b(?:manufactured|produced|made|supplied|fabricated|assembled|built)\s+"
    r"(?:for\s+\w+\s+)?by\s+|"
    r"\b(?:supplier|manufacturer|vendor)\s+(?:is|was|:)\s+|"
    r"\bsourced\s+from\s+", re.I)
# 线索词后面那一段名字：最多 6 个词，允许 & . - ' 与数字。
NAME_AFTER = re.compile(
    r"((?:[A-Z][A-Za-z0-9&.\-']*(?:\s+(?:of|and|de|du|van|von))?\s+){0,5}"
    r"[A-Z][A-Za-z0-9&.\-']*)")
SUFFIX = re.compile(
    r"\b(?:Inc|Corp|Corporation|Company|Co|LLC|L\.?L\.?C|Ltd|Limited|PLC|"
    r"GmbH|S\.?A|N\.?V|A\.?G|KG|Oy|AB|AS|BV|Pte|Sdn|Bhd|KK|Holdings?|Group|"
    r"Industries|Technologies|Manufacturing|Mfg)\b\.?")
# 线索词之后也可能跟的是机构或套话，照旧挡一道。
BOILER = re.compile(
    r"^(?:The|This|These|Those|A|An|All|Some|Any|Its|Our|Their|"
    r"NHTSA|FDA|CPSC|Recall|Federal|National|United States|US|U\.S)\b", re.I)
# 政府机构／学校那一类（entity_names 里那套之外，再补召回文书常见的几个）。
NOT_A_FIRM = re.compile(
    r"\b(?:administration|agency|bureau|ministry|council|"
    r"department|commission|authority)\b", re.I)


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


def get(url: str) -> tuple[object | None, str]:
    if not BUDGET.take():
        return None, "请求预算用尽"
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read(12_000_000)
            return json.loads(raw.decode("utf-8", "replace")), f"HTTP {resp.status}"
    except error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read(300).decode("utf-8", "replace")[:140]
        except Exception:                                    # noqa: BLE001
            pass
        return None, f"HTTP {exc.code} {detail}"
    except (error.URLError, ValueError, OSError) as exc:
        return None, f"{type(exc).__name__}: {exc}"
    finally:
        time.sleep(GAP)


def rows_of(payload) -> list[dict]:
    """不同机构的外层包装不一样。按真实形状剥，剥不出就返回空。"""
    if isinstance(payload, list):
        return [r for r in payload if isinstance(r, dict)]
    if isinstance(payload, dict):
        for key in ("results", "Results", "data"):
            value = payload.get(key)
            if isinstance(value, list):
                return [r for r in value if isinstance(r, dict)]
    return []


def narrative(row: dict) -> str:
    """把这条记录里所有叙述性字段拼起来。只拼字符串，不碰嵌套结构。"""
    parts = []
    for key in TEXT_KEYS:
        value = row.get(key)
        if isinstance(value, str) and len(value) > 12:
            parts.append(value)
    return " ".join(parts)


def firm_of(row: dict) -> str:
    for key in FIRM_KEYS:
        value = row.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def second_party(text: str, firm: str, pool: dict) -> tuple[str, bool] | None:
    """正文里**被指为供应方**的另一家公司。没有线索词就返回 None。

    返回 (名字, 是否在池内)。**宁可抓不到，不许抓错**——判据数的是「点名对方」，
    抓错一条就把判据虚高一条。
    """
    body = text or ""
    for cue in SUPPLY_CUE.finditer(body):
        tail = body[cue.end():cue.end() + 120].lstrip()
        hit = NAME_AFTER.match(tail)
        if not hit:
            continue
        name = " ".join(hit.group(1).split()).strip(" .,;:")
        if len(name) < 4 or BOILER.match(name):
            continue
        if NOT_A_COMPANY.search(name) or NOT_A_FIRM.search(name):
            continue
        # 要么带主体后缀，要么至少两个大写开头的词。
        caps = sum(1 for w in name.split() if w[:1].isupper())
        if not SUFFIX.search(name) and caps < 2:
            continue
        if same_entity(name, firm):
            continue
        return name, norm(name) in pool
    return None


def discover() -> list[tuple[str, str, list[dict], list[str]]]:
    """逐个打候选端点，返回活着的那些 (标签, url, 记录, 字段名)。"""
    print("── 〇、先打每个候选端点，把状态与字段名打出来（不凭记忆写）──────────")
    alive = []
    for label, url in CANDIDATES:
        payload, note = get(url)
        rows = rows_of(payload)
        if not rows:
            shape = type(payload).__name__ if payload is not None else "无"
            print(f"  [--] {label:<16} {note}（剥不出记录列表，外层是 {shape}）")
            continue
        keys = sorted(rows[0].keys())
        print(f"  [OK] {label:<16} {note}，{len(rows)} 条")
        print(f"       字段名：{'、'.join(keys)[:260]}")
        firm_key = next((k for k in FIRM_KEYS if k in rows[0]), None)
        text_keys = [k for k in TEXT_KEYS if isinstance(rows[0].get(k), str)]
        print(f"       召回方字段：{firm_key or '（没有）'} · "
              f"叙述字段：{'、'.join(text_keys) or '（没有）'}")
        if not firm_key or not text_keys:
            print("       [--] 缺召回方或叙述字段，这个端点给不出关系，跳过")
            continue
        alive.append((label, url, rows, keys))
    return alive


def main() -> int:
    with open(NODES_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)
    nodes = payload.get("nodes") or []
    pool = {norm(n.get("name")): n.get("symbol") for n in nodes if n.get("name")}
    if not pool:
        print("[XX] 节点表为空")
        return 1

    alive = discover()
    if not alive:
        print("\n[XX] 没有一个候选端点返回可用的召回记录——**结论无效**，"
              "不输出判据。")
        print("     这是取数／接口问题，不是业务事实（拿取数失败冒充业务事实"
              "是禁止的）。先人工确认三家机构当前的数据出口再重跑。")
        print(f"     试过：{'、'.join(label for label, _ in CANDIDATES)}")
        return 1

    print(f"\n判据（探前写死，规划原话）：抽样 {SAMPLE} 条召回，"
          f"能点名对方的 ≥{HIT_FLOOR} 条才建")
    print("**这条源自带负面偏向**：只有出过问题的供应关系才被记录。"
          "若建，页面必须写明它是事故清单、不是供应商名单。")
    print("逐层报数：取到记录 → 召回方锚回池内 → 正文点到第二家 → 第二家可用\n")

    seen = in_pool = named = both = 0
    per_source: dict[str, list[int]] = {}
    hits: list[tuple[str, str, str, bool]] = []
    no_second: list[str] = []

    for label, _url, rows, _keys in alive:
        stat = per_source.setdefault(label, [0, 0, 0])
        for row in rows:
            if seen >= SAMPLE:
                break
            seen += 1
            stat[0] += 1
            firm = firm_of(row)
            symbol = pool.get(norm(firm))
            if symbol:
                in_pool += 1
                stat[1] += 1
            found = second_party(narrative(row), firm, pool)
            if not found:
                if len(no_second) < 10 and firm:
                    no_second.append(f"{label}/{firm[:30]}")
                continue
            named += 1
            stat[2] += 1
            if found[1]:
                both += 1
            if len(hits) < 40:
                hits.append((label, firm[:34], found[0][:44], found[1]))

    print("─" * 74)
    print(f"取到召回记录 {seen} 条 · 请求 {BUDGET.used}")
    print(f"  召回方能锚回池内 {in_pool} 条")
    print(f"  正文点到第二家公司 **{named} 条**")
    print(f"    第二家也在池内（双向边）{both} 条")
    print("  按来源拆（取到 / 召回方在池内 / 点到第二家）：")
    for label, (a, b, c) in per_source.items():
        print(f"    {label:<16} {a} / {b} / {c}")

    if seen == 0:
        print("\n[XX] 一条记录都没取到——**结论无效**，不输出判据。")
        return 1

    if no_second:
        print("\n点不到第二家的样例（判断是不是这类公告本来不写供应商）：")
        for line in no_second:
            print(f"   {line}")
    if hits:
        print("\n点到第二家的，逐条列出（**人工核对用，别只看计数**）：")
        for label, firm, other, inside in hits:
            tag = "池内" if inside else "池外"
            print(f"   {label:<15} {firm:<36} → {other:<46} | {tag}")

    print("\n" + "─" * 74)
    print(f"判据：点名对方 {named} 条（门槛 {HIT_FLOOR}）"
          + ("  → 过" if named >= HIT_FLOOR else "  → **不过**"))
    if named >= HIT_FLOOR:
        print("\n判据：过 → **值得建**。但上面那些「第二家」必须逐条人工核对，"
              "自动计数不能代替核对（这个板块栽过一次：探针说 2/8 家可用，"
              "实际只有 1 家）。而且建之前先把负面偏向那句话定稿。")
    else:
        print("\n判据：不过 → **不建**，写进判决表并写清依据")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)

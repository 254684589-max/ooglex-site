#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补名单工程 阶段 4：FCC 设备认证能不能给出品牌↔代工关系。

## 这条路的假设，以及它哪一半是我没核验过的

规划里写的是「一个品牌的设备由哪家 ODM 制造，grantee code 能看出」。
**这句话只有前半句是确定的。**

确定的：每台在美销售的射频设备都有 FCC ID，FCC ID 的前 3–5 位是 grantee
code，对应一个**持证实体**（responsible party）。这是公开政府记录，许可干净。

**我没核验过的**：持证实体到底是品牌方还是代工方。两种都存在——有的设备由
代工厂持证、贴品牌方的牌子卖；有的由品牌方自己持证。**光有 grantee 一侧，
拿到的只是「这家公司做射频设备」，那不是一条关系。** 一条关系要两个当事方。

所以本探针**先探接口与字段，再谈判据**。凡是本探针没实测到的字段，
一个字都不往结论里写。

## 判据

规划里探前写死的那一条**一个字不动**：

    Gate A 锚定：池内公司能严格同名匹配上 grantee 的 ≥30 家

但它单独过不了事：「30 家公司是持证人」说明的是这 30 家做射频设备，**不是
30 条关系**。所以**加**一道（不是放宽）：

    Gate B 关系：一条记录里能同时定位到两个不同当事方的 ≥15 家

15 与阶段 2／3 同一个数，因为建的成本完全一样：一级供应商从零起步要建整条
新管线（新 relation 类型、新边格式、页面新分区、公司页新区块）。
**加闸门不是放宽判据**——Gate A 照原样执行，Gate B 是它本来就缺的那一半。

两道都过才建。

## 逐层报数

    接口通不通 / 字段叫什么   → 不通就报「结论无效」，不出判据
    按名字搜到候选            → 搜不到就是这家不做射频设备
    严格同名可锚定            → 锚不上就是认名问题
    记录里有第二个当事方      → 没有就说明这条源只有单侧，给不出关系

阶段 2／3 的教训：**前面的层没通，后面的数就不是数据，是仪器读数。**
而且**我连续两轮的第一次阴性结果都是自己造的**（范围选错、方向假设错），
所以这一轮的每一层都要把真实返回打出来给人看。

## 边界

只读。不写任何数据文件、不建任何边。FCC 的库在本机代理下取不到，
**只能在 Actions 里跑**。
"""
from __future__ import annotations

import json
import os
import sys
import time
from urllib import error, parse, request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from entity_names import NOT_A_COMPANY, core_query, norm, same_entity  # noqa: E402

NODES_PATH = "apps/supply-chain/nodes.json"
TIMEOUT = 45
GAP = 0.5
SAMPLE = int(os.environ.get("FCC_SAMPLE", "120"))
MAX_REQUESTS = int(os.environ.get("FCC_MAX_REQUESTS", "600"))
# 判据。Gate A 来自规划文档，Gate B 是本轮补上的另一半。改动任一个等于改判据。
ANCHOR_FLOOR = int(os.environ.get("FCC_ANCHOR_FLOOR", "30"))
PAIR_FLOOR = int(os.environ.get("FCC_PAIR_FLOOR", "15"))

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

# **数据集 id 不准写死。** 第一版我凭记忆填了两个 Socrata id，实测两个都
# 返回 `dataset.missing`（run 45）——那就是「凭记忆写标识符等于在编数据」，
# 探针自己的守门人把它拦成了「结论无效」。
#
# 改成**先查目录再取数**：Socrata 的发现 API 按关键词列出这个域上真实存在的
# 数据集，id 从目录里来，不从我的记忆里来。目录查不到就报结论无效，
# 仍然不下判决。
CATALOG = "http://api.us.socrata.com/api/catalog/v1"
CATALOG_DOMAIN = "opendata.fcc.gov"
# 关键词按「设备认证」这件事的官方叫法列，多给几个同义说法，命中哪个打出来。
CATALOG_TERMS = ["equipment authorization", "grantee", "equipment authorization grantee",
                 "FCC ID", "OET equipment"]
# 目录之外再留一个已知的 HTML 出口，**只为把它的真实状态打出来**，不指望解析它。
HTML_FALLBACK = ("apps-eas-oet",
                 "https://apps.fcc.gov/oetcf/eas/reports/GenericSearchResult.cfm")
# 一条记录里可能出现的「当事方」字段名。**全部当候选，按真实返回里有的用。**
PARTY_KEYS = ("grantee_name", "applicant_name", "grantee", "applicant",
              "company", "company_name", "name", "grantee_code_name",
              "original_grantee", "original_grantee_name",
              "manufacturer", "manufacturer_name", "oem", "oem_name")


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
    """GET 一次。失败不抛异常，如实返回原因。"""
    if not BUDGET.take():
        return None, "请求预算用尽"
    req = request.Request(url, headers={
        "User-Agent": UA, "Accept": "application/json"})
    try:
        with request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read(8_000_000)
            ctype = resp.headers.get("Content-Type", "")
            if "json" not in ctype.lower():
                return None, f"HTTP {resp.status} 但 Content-Type 是 {ctype!r}"
            return json.loads(raw.decode("utf-8", "replace")), f"HTTP {resp.status}"
    except error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read(400).decode("utf-8", "replace")[:160]
        except Exception:                                    # noqa: BLE001
            pass
        return None, f"HTTP {exc.code} {detail}"
    except (error.URLError, ValueError, OSError) as exc:
        return None, f"{type(exc).__name__}: {exc}"
    finally:
        time.sleep(GAP)


def catalog_lookup() -> list[tuple[str, str]]:
    """按关键词查 Socrata 目录，返回 [(数据集 id, 名称)]。**id 来自目录，不来自记忆。**"""
    found: dict[str, str] = {}
    for term in CATALOG_TERMS:
        url = CATALOG + "?" + parse.urlencode(
            {"domains": CATALOG_DOMAIN, "q": term, "limit": 12})
        data, note = get(url)
        results = (data or {}).get("results") if isinstance(data, dict) else None
        if not results:
            print(f"  [--] 目录查「{term}」：{note}")
            continue
        hits = []
        for item in results:
            res = item.get("resource") or {}
            ident, name = res.get("id"), res.get("name") or ""
            if ident and ident not in found:
                found[ident] = name
                hits.append(f"{ident} {name[:46]}")
        print(f"  [OK] 目录查「{term}」：{note}，新增 {len(hits)} 个数据集")
        for line in hits[:6]:
            print(f"         {line}")
    return list(found.items())


def discover() -> tuple[str | None, str | None, list[str]]:
    """探接口。返回 (可用的 base, 当事方字段名, 全部字段名)。"""
    print("── 〇、先查目录，再探字段（id 不凭记忆写）──────────────────────────")
    datasets = catalog_lookup()
    if not datasets:
        print("  [!!] 目录一个数据集都没返回")
    for ident, name in datasets:
        base = f"https://{CATALOG_DOMAIN}/resource/{ident}.json"
        data, note = get(base + "?" + parse.urlencode({"$limit": 1}))
        if not isinstance(data, list) or not data:
            print(f"  [--] {ident} {name[:34]:<36} {note}")
            continue
        keys = sorted(data[0].keys())
        party = next((k for k in PARTY_KEYS if k in data[0]), None)
        print(f"  [OK] {ident} {name[:34]:<36} {note}")
        print(f"       字段名：{'、'.join(keys)}")
        if party is None:
            print("       [--] 这些字段里没有可当「当事方」的名字字段，跳过")
            continue
        print(f"       当事方字段用：{party}")
        return base, party, keys
    # 目录这条路走不通时，把那个 HTML 出口的真实状态也打出来——不解析它，
    # 只是让下一个人知道它当时返回什么。
    label, url = HTML_FALLBACK
    _data, note = get(url)
    print(f"  [--] {label:<18} {note}（HTML 出口，本探针不解析）")
    return None, None, []


def search(base: str, party: str, name: str, limit: int = 20) -> tuple[list, str]:
    """按当事方名字搜。用 Socrata 的 $q 全文检索，拿不到就退回 $where like。"""
    url = base + ("&" if "?" in base else "?") + parse.urlencode(
        {"$limit": limit, "$q": name})
    data, note = get(url)
    if isinstance(data, list):
        return data, note
    safe = name.replace("'", "''").upper()
    url = base + ("&" if "?" in base else "?") + parse.urlencode(
        {"$limit": limit,
         "$where": f"upper({party}) like '%{safe}%'"})
    data, note2 = get(url)
    if isinstance(data, list):
        return data, f"{note} → 退回 $where：{note2}"
    return [], f"{note} / {note2}"


def other_party(row: dict, party: str, mine: str) -> tuple[str, str] | None:
    """同一条记录里找出**另一个**当事方。找不到返回 None，不猜。"""
    for key in PARTY_KEYS:
        if key == party:
            continue
        value = (row.get(key) or "").strip() if isinstance(row.get(key), str) else ""
        if not value or same_entity(value, mine):
            continue
        if NOT_A_COMPANY.search(value):
            continue
        return key, value
    return None


def main() -> int:
    with open(NODES_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)
    pool = [n for n in (payload.get("nodes") or []) if n.get("name")]
    pool.sort(key=lambda n: n.get("symbol") or "")
    if not pool:
        print("[XX] 节点表为空")
        return 1

    base, party, all_keys = discover()
    if base is None or party is None:
        print("\n[XX] 没有一个候选接口返回可用的 JSON 记录，或返回里没有当事方"
              "字段——**结论无效**，不输出判据。")
        print("     这是取数／接口问题，不是业务事实（拿取数失败冒充业务事实"
              "是禁止的）。先确认 FCC 的数据出口再重跑。")
        print(f"     查目录用的关键词：{'、'.join(CATALOG_TERMS)}")
        print("     **第一版凭记忆写死了两个数据集 id，两个都是 dataset.missing**"
              "——所以这一版改成从目录里取 id。若目录也查不到，"
              "说明这条源的公开出口要人工确认，不是探针能自己绕过去的。")
        return 1

    # 这条源只覆盖电子。按环节分层取样会把大半预算花在金融／服务上，
    # 那不是「取样偏差」，是**把判据用在它本来不适用的范围上**。
    # 所以先收窄到射频设备**可能**出现的环节，并把收窄写在输出里。
    WANT_STAGES = {"component", "capital-equipment", "finished-goods",
                   "material-processing", "technology"}
    narrowed = [n for n in pool if n.get("stage") in WANT_STAGES]
    by_stage: dict[str, list] = {}
    for node in narrowed:
        by_stage.setdefault(node.get("stage") or "未判定", []).append(node)
    sample: list[dict] = []
    for _, members in sorted(by_stage.items(), key=lambda kv: -len(kv[1])):
        want = max(1, round(len(members) / max(1, len(narrowed)) * SAMPLE))
        step = max(1, len(members) // want)
        sample.extend(members[::step][:want])
    sample = sample[:SAMPLE]

    print(f"\n全池 {len(pool)} 家；这条源只覆盖电子，先收窄到 "
          f"{'／'.join(sorted(WANT_STAGES))} 五个环节共 {len(narrowed)} 家，"
          f"再分层取样 {len(sample)} 家")
    print("**收窄的是「可能为真的范围」，不是「我希望为真的范围」**——"
          "判据两个数一个没动，而且外推时要按收窄后的分母说话。")
    print(f"判据（Gate A 来自规划文档，Gate B 是本轮补上的另一半，两道都过才建）：")
    print(f"  Gate A 锚定：严格同名匹配上 grantee 的 ≥{ANCHOR_FLOOR} 家")
    print(f"  Gate B 关系：记录里能定位到第二个当事方的 ≥{PAIR_FLOOR} 家\n")

    got_cand = anchored = paired = 0
    no_exact: list[tuple[str, str]] = []
    pairs: list[tuple[str, str, str]] = []
    single_side: list[str] = []
    failed = 0

    for index, node in enumerate(sample, 1):
        symbol = node.get("symbol") or "?"
        name = node.get("name") or ""
        rows, note = search(base, party, core_query(name))
        if not rows:
            if "HTTP 200" not in note and "请求预算" not in note:
                failed += 1
            continue
        got_cand += 1
        exact = [r for r in rows if same_entity(r.get(party), name)]
        if not exact:
            seen = []
            for r in rows:
                value = r.get(party)
                if isinstance(value, str) and value and value not in seen:
                    seen.append(value)
            no_exact.append((symbol, "；".join(seen[:3])))
            continue
        anchored += 1
        found = None
        for row in exact:
            found = other_party(row, party, name)
            if found:
                break
        if not found:
            single_side.append(symbol)
            continue
        paired += 1
        pairs.append((symbol, found[1], found[0]))
        if index % 20 == 0 or index == len(sample):
            print(f"     … 已处理 {index}/{len(sample)}，锚定 {anchored} 家、"
                  f"成对 {paired} 家，请求用掉 {BUDGET.used}")

    print("\n" + "─" * 74)
    print(f"按名字搜到候选 {got_cand} 家 · 失败 {failed} 家 · 请求 {BUDGET.used}")
    print(f"  严格同名可锚定 {anchored} 家（当事方字段 = {party}）")
    print(f"    记录里有第二个当事方 **{paired} 家**")
    print(f"    只有单侧（拿不到第二个当事方）{len(single_side)} 家")
    print(f"  有候选但不严格同名 {len(no_exact)} 家")

    if got_cand == 0:
        print("\n[XX] 一条记录都没搜到——**结论无效**，不输出判据。先修取数。")
        return 1

    if no_exact:
        print("\n有候选但不严格同名的样例（判断是不是认名太紧）：")
        for symbol, seen in no_exact[:8]:
            print(f"   {symbol}：{seen[:110]}")
    if single_side:
        print(f"\n只有单侧的（这一档说明这条源给不出关系）："
              f"{'、'.join(single_side[:14])}")
    if pairs:
        print("\n解出的两方关系，全部列出（**人工核对用，别只看计数**）：")
        for symbol, other, key in pairs:
            print(f"   {symbol:<6} ↔ {other[:46]:<48} | 字段 {key}")

    print("\n" + "─" * 74)
    a_ok, b_ok = anchored >= ANCHOR_FLOOR, paired >= PAIR_FLOOR
    print(f"Gate A 锚定：{anchored} 家（门槛 {ANCHOR_FLOOR}）"
          + ("  → 过" if a_ok else "  → **不过**"))
    print(f"Gate B 关系：{paired} 家（门槛 {PAIR_FLOOR}）"
          + ("  → 过" if b_ok else "  → **不过**"))
    if a_ok and b_ok:
        print("\n判据：两道都过 → **值得建**，进入接入设计")
    else:
        print("\n判据：有闸门不过 → **不建**，写进判决表并写清依据")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""离线校验：供应链关系抽取规则能不能定位真实的客户集中度披露，以及有没有误报。

**为什么需要这个校验**：供应链图谱的每条边都必须挂着可核验的原始申报文件，而边是从
10-K 的客户集中度披露（ASC 280 要求披露占营收 10% 以上的客户）里抽出来的。抽取规则
一旦悄悄退化，后果不是「少几条边」，而是「边指向错的公司」——那是对真实企业断言假
关系，比没有数据严重得多。

**这个校验拦下过什么**（用例都来自开发时的真实失败，不是补写的）：

1. 限定词只写单层时，`accounted for 20% of our net revenue` 命中不了——而这恰恰是
   唯一会点名客户的那类句式。规则「能跑」但抽不到任何有用的边。
2. 裸 `Co` 后缀会把小标题 `Customer Concentration` 误抽成公司名 `Customer Co`。
3. 后缀不按长度排序时，`Corp` 会把 `Microsoft Corporation` 截成 `Microsoft Corp`。

**定位命中 ≠ 能抽出边**：大量公司只写「一家客户占 22%」而不写是谁。这类段落是线索，
不是边。因此本校验把「定位」和「点名」分成两组独立断言——只有点名的才可能成为边。

纯离线，不发网络请求，不读写任何数据文件。
"""
from __future__ import annotations

import importlib.util
import os
import re
import sys

PROBE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "supply-chain", "probe_edgar_relationships.py")
REVERSE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "supply-chain", "probe_edgar_fulltext_reverse.py")

# ── 反查上下文分类用例 ──────────────────────────────────────────────────────
# 「提到某公司」不等于「与它有供应关系」。反查探针的精度数字完全依赖这套分类，
# 分类错了数字就没意义。最后两条是对抗用例：窗口里同时出现多种线索时，
# 线索必须落在提及所在的那一句里——整窗匹配会把「我们与 Apple 竞争」误判成
# 「Apple 是我们的客户」（因为窗口别处有个讲分部营收的 accounted for），
# 精度虚高，正好是会误导人去建错误边的方向。
CONTEXT_CASES: list[tuple[str, str, str]] = [
    ("客户·点名占比", "Apple Inc. accounted for 22% of our net revenue in fiscal 2025.", "customer"),
    ("客户·最大客户", "Our largest customer, Apple Inc., represented a substantial portion "
                    "of shipments.", "customer"),
    ("客户·销售给", "Sales to Apple Inc. increased during the period.", "customer"),
    ("竞争对手", "We compete with Apple Inc. and Samsung in the smartphone market.", "competitor"),
    ("举例", "Companies such as Apple Inc. have adopted similar practices.", "competitor"),
    ("诉讼", "In re Apple Inc. Securities Litigation, the court granted summary judgment.", "legal"),
    ("专利诉讼", "We filed a patent infringement complaint against Apple Inc.", "legal"),
    ("纯提及·无关", "Our headquarters are located near the Apple Inc. campus in Cupertino.", "other"),
    ("持仓", "The fund held 1,200 shares of Apple Inc. as of year end.", "other"),
    ("对抗·竞争但窗口有无关的 accounted for",
     "Our Americas segment accounted for 42% of consolidated net revenue in fiscal 2025. "
     "We face intense competition in the consumer electronics market, where we compete with "
     "Apple Inc., Samsung Electronics and other large manufacturers with greater resources.",
     "competitor"),
    ("对抗·真客户但同句附近提竞争",
     "Apple Inc. accounted for approximately 20% of our net revenue in fiscal 2025. "
     "We also compete with other suppliers for this business and may lose share.",
     "customer"),
]

# ── 用例：措辞取自 10-K 客户集中度披露的常见写法 ────────────────────────────
# (标签, 文本, 应否定位到披露, 应抽出的客户名或 None)
CASES: list[tuple[str, str, bool, str | None]] = [
    ("点名·单一客户", "One customer, Apple Inc., accounted for approximately 20% of our "
                      "net revenue in fiscal 2025.", True, "Apple Inc."),
    ("点名·its 限定", "Revenue from Dell Technologies Inc. accounted for 13% of its "
                      "consolidated revenue for fiscal 2025.", True, "Dell Technologies Inc."),
    ("点名·Corporation", "Sales to Microsoft Corporation represented 11% of total revenue.",
                        True, "Microsoft Corporation"),
    ("不点名·两家", "Two customers accounted for 22% and 15% of net revenue, respectively, "
                   "in fiscal year 2025.", True, None),
    ("不点名·最大客户", "Sales to our largest customer represented approximately 14.3% of "
                       "total revenue.", True, None),
    ("明确无重大客户", "No customers accounted for 10% or more of our net revenue during "
                      "fiscal 2025.", True, None),
    ("小标题", "Customer Concentration. We depend on a limited number of customers for a "
              "substantial portion of revenue.", True, None),
    ("风险因素", "We have significant customers and the loss of any of them could harm our "
                "business.", True, None),
    ("门槛表述", "Customers that individually represented 10% or more of our net sales are "
                "set forth below.", True, None),
]

# 不得命中的文本：财报里到处是百分比，规则不能见 % 就报
NEGATIVE: list[tuple[str, str]] = [
    ("成本变动", "Cost of revenue increased 12% due to higher component prices."),
    ("员工人数", "We had approximately 164,000 full-time equivalent employees as of year end."),
    ("毛利率", "Gross margin was 46.2% compared with 44.1% in the prior year."),
    ("回购", "We repurchased 2% of our outstanding common stock during the period."),
]


def _load(path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"载入不了 {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_probe():
    return _load(PROBE_PATH, "probe_edgar")


def load_reverse():
    return _load(REVERSE_PATH, "probe_edgar_reverse")


def locate(module, text: str) -> list[str]:
    return [p for p in module.CONCENTRATION_PATTERNS if re.search(p, text, re.I)]


def extract_names(module, text: str) -> list[str]:
    return [e.strip() for e in re.findall(module.NAMED_ENTITY_PATTERN, text)
            if len(e) > 4 and not e.lower().startswith("the compan")]


def main() -> int:
    module = load_probe()
    failures: list[str] = []

    print("── 定位：能不能找到客户集中度披露 ──────────────────────────────────")
    for label, text, should_locate, _ in CASES:
        hits = locate(module, text)
        ok = bool(hits) == should_locate
        if not ok:
            failures.append(f"定位 {label}：期望 {should_locate}，实际命中 {len(hits)} 条规则")
        print(f"  [{'OK' if ok else 'XX'}] {label:<16} 命中 {len(hits)} 条规则")

    print("\n── 点名：披露里有没有指明对方（决定能不能成为边） ────────────────")
    for label, text, _, expected in CASES:
        names = extract_names(module, text)
        if expected is None:
            ok = not names
            detail = "无公司名（线索，不成边）" if ok else f"误抽出 {names}"
        else:
            ok = bool(names) and names[0] == expected
            detail = f"→ {names[0]}" if names else "未抽出"
        if not ok:
            failures.append(f"点名 {label}：期望 {expected!r}，实际 {names!r}")
        print(f"  [{'OK' if ok else 'XX'}] {label:<16} {detail}")

    print("\n── 误报：财报里到处是百分比，不能见 % 就报 ────────────────────────")
    for label, text in NEGATIVE:
        hits = locate(module, text)
        ok = not hits
        if not ok:
            failures.append(f"误报 {label}：不应命中，实际命中 {len(hits)} 条规则")
        print(f"  [{'OK' if ok else 'XX'}] {label:<16} {'无误报' if ok else f'误报 {len(hits)} 条'}")

    print("\n── 反查上下文分类：提到 ≠ 有供应关系 ─────────────────────────────")
    reverse = load_reverse()
    for label, text, expected in CONTEXT_CASES:
        result = reverse.classify_mentions(text, '"Apple Inc."')
        buckets = [k for k, v in result["counts"].items() if v]
        got = buckets[0] if buckets else "none"
        ok = got == expected
        if not ok:
            failures.append(f"分类 {label}：期望 {expected}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] {label:<26} 判为 {got}")

    total = len(CASES) * 2 + len(NEGATIVE) + len(CONTEXT_CASES)
    print("\n" + "─" * 68)
    if failures:
        print(f"失败 {len(failures)}/{total}：")
        for item in failures:
            print(f"  · {item}")
        return 1
    print(f"全部通过（{total} 项断言）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

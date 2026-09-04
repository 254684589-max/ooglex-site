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
import json
import os
import re
import sys

PROBE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "supply-chain", "probe_edgar_relationships.py")
REVERSE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "supply-chain", "probe_edgar_fulltext_reverse.py")
SIC_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "supply-chain", "sic_stages.py")
FORM_SD_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "supply-chain", "form_sd_parse.py")
EXTRACT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "supply-chain", "extract_form_sd.py")
SUPPLIER_PROBE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   "supply-chain", "probe_supplier_lists.py")
NAMES_ZH_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "supply-chain", "smelter_names_zh.py")

# ── SIC → 价值链阶段 ────────────────────────────────────────────────────────
# SIC 码全部取自探针在 Actions 机房实测到的真实值，不是凭印象写的。
# 前三条是这套映射存在的理由：GICS 一级板块把苹果、英伟达、微软都归为「科技」，
# 分不出产业链位置；SIC 能分开。后两条是 33xx 拆分的回归——不拆的话康宁
# （SIC 3357 有色线材拉制）会被误判成上游资源，它做的是玻璃基板与光纤。
SIC_CASES: list[tuple[int, str, str]] = [
    (3571, "苹果 电子计算机整机", "brand-integration"),
    (3674, "英伟达 半导体", "intermediate-manufacturing"),
    (7372, "微软 预装软件", "platform-service"),
    (3312, "钢铁高炉", "upstream-resource"),
    (3357, "康宁 有色线材", "intermediate-manufacturing"),
    (3663, "高通 通信设备", "intermediate-manufacturing"),
    (3559, "泛林 专用机械", "intermediate-manufacturing"),
    (1311, "原油与天然气开采", "upstream-resource"),
    (6022, "州立商业银行", "supporting"),
    (5912, "药品零售", "distribution-service"),
    (2834, "成药制剂", "brand-integration"),
    (3714, "机动车零部件", "intermediate-manufacturing"),
    (3711, "整车制造", "brand-integration"),
]

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


# ── Form SD 冶炼厂清单解析 ─────────────────────────────────────────────────
# 各家申报的表格排版差别很大，夹具按真实排版形状写，列序刻意各不相同。
# 每条夹具都对应一个具体的失败模式，不是凑数的正例。
FORM_SD_FIXTURES: dict[str, str] = {
    # RMI 标准四列，最常见的形状
    "standard-4col": """
<table>
<tr><th>Metal</th><th>Smelter or Refiner Name</th><th>Smelter ID</th><th>Location (Country)</th></tr>
<tr><td>Gold</td><td>Asahi Pretec Corp.</td><td>CID000082</td><td>Japan</td></tr>
<tr><td>Tantalum</td><td>Ningxia Orient Tantalum Industry Co., Ltd.</td><td>CID001277</td><td>China</td></tr>
<tr><td>Tin</td><td>PT Timah Tbk Kundur</td><td>CID001457</td><td>Indonesia</td></tr>
<tr><td>Tungsten</td><td>Wolfram Bergbau und Hutten AG</td><td>CID002044</td><td>Austria</td></tr>
</table>""",
    # 列序完全颠倒 + 编号带空格／连字符 + 国名带逗号从句。
    # 按第几列取值的写法会在这条上全线错位。
    "reordered-spaced-cid": """
<table>
<tr><td>Smelter ID</td><td>Country</td><td>Standard Smelter Names</td><td>Metal</td></tr>
<tr><td>CID 000801</td><td>Korea, Republic of</td><td>LS-NIKKO Copper Inc.</td><td>Gold</td></tr>
<tr><td>CID-002514</td><td>Taiwan, Province of China</td><td>Solar Applied Materials Technology Corp.</td><td>Gold</td></tr>
</table>""",
    # 表里没有矿种列，矿种只写在小标题里
    "mineral-in-heading": """
<p>Tin Smelters</p>
<table><tr><th>Smelter Name</th><th>Smelter ID</th><th>Country</th></tr>
<tr><td>Malaysia Smelting Corporation (MSC)</td><td>CID001105</td><td>Malaysia</td></tr></table>
<p>Tungsten Smelters</p>
<table><tr><th>Smelter Name</th><th>Smelter ID</th><th>Country</th></tr>
<tr><td>Xiamen Tungsten Co., Ltd.</td><td>CID002082</td><td>China</td></tr></table>""",
    # 排版用的嵌套表塞在单元格里。正则切 <tr> 会把外层这条真行切碎。
    "nested-table": """
<table><tr>
<td><table><tr><td>Gold</td></tr></table></td>
<td><table><tr><td>Metalor Technologies SA</td></tr></table></td>
<td>CID001153</td><td>Switzerland</td></tr></table>""",
    # 同一冶炼厂按两种矿种各列一行，必须合并成一条、矿种取并集
    "duplicate-cid": """
<table>
<tr><td>Tin</td><td>Yunnan Tin Company Limited</td><td>CID001908</td><td>China</td></tr>
<tr><td>Tungsten</td><td>Yunnan Tin Company Limited</td><td>CID 001908</td><td>China</td></tr>
</table>""",
    # 国别并在名字里，没有独立国别列
    "country-in-name": """
<table><tr><td>Gold</td><td>Tokuriki Honten Co., Ltd., Japan</td><td>CID001938</td></tr></table>""",
    # 只列名字不列编号：按规则整份不收，但必须计入 droppedNoCid 让代价可见
    "names-without-cid": """
<table>
<tr><th>Smelter or Refiner Name</th><th>Country</th></tr>
<tr><td>Aurubis AG</td><td>Germany</td></tr>
<tr><td>Umicore SA Business Unit Precious Metals Refining</td><td>Belgium</td></tr>
<tr><td>JX Nippon Mining &amp; Metals Co., Ltd.</td><td>Japan</td></tr>
</table>""",
    # 英伟达 2026 年报告的真实形状：Metal | 厂名 | 国别，**全表没有一个 RMI 编号**。
    # 只认编号的规则会把这 279 行整个丢掉。厂名列里还含矿种词（Tantalum Niobium），
    # 宽松的矿种匹配会把厂名当成矿种列吞掉。
    "nvda-no-cid": """
<table>
<tr><th>Metal</th><th>Smelter or Refiner</th><th>Country</th></tr>
<tr><td>Tantalum</td><td>AMG Brasil</td><td>BRAZIL</td></tr>
<tr><td>Tantalum</td><td>Changsha South Tantalum Niobium Co</td><td>CHINA</td></tr>
<tr><td>Tantalum</td><td>D Block Metals, LLC</td><td>UNITED STATES OF AMERICA</td></tr>
<tr><td>Gold</td><td>Global Advanced Metals Aizu</td><td>JAPAN</td></tr>
</table>""",
    # 微软 2026 年报告的真实形状：三列**全是国名**的原产国附录，一家冶炼厂都没有。
    # 早期的「丢弃行」启发式把这 274 行当成漏收的冶炼厂，虚报了规则的代价。
    "country-columns": """
<table>
<tr><td>Andorra</td><td>Italy</td><td>Tanzania</td></tr>
<tr><td>Australia</td><td>Japan</td><td>Thailand</td></tr>
<tr><td>Belgium</td><td>Korea, Republic of</td><td>Uganda</td></tr>
<tr><td>Bolivia</td><td>Malaysia</td><td>United States of America</td></tr>
</table>""",
    # 英特尔 2026 年报告的真实形状：国别 × 矿种矩阵，同样不是冶炼厂名单。
    # 它有国名也有矿种，但没有第三类格子——不能因为「有矿种有国别」就收。
    "country-mineral-matrix": """
<table>
<tr><td>Australia</td><td>Gold</td><td>Tantalum</td><td>Tin</td><td>Tungsten</td></tr>
<tr><td>Bulgaria</td><td>Gold</td></tr>
<tr><td>Burkina Faso</td><td>Gold</td></tr>
<tr><td>Burundi**</td><td>Tantalum</td><td>Tin</td><td>Tungsten</td></tr>
</table>""",
    # 英特尔那份名单的真实形状：每个厂名后面跟一个脚注星号。不去掉就会和别家
    # 名单里的同一家算成两家——正是「按名字合并会把一家拆成几家」的具体形态。
    "footnote-marked": """
<table>
<tr><td>Tungsten</td><td>A.L.M.T. Corp.*</td><td>Japan</td></tr>
<tr><td>Gold</td><td>Agosi AG**</td><td>Germany</td></tr>
<tr><td>Tin</td><td>Alpha Assembly Solutions Inc (1)</td><td>United States of America</td></tr>
</table>""",
    # 微软那份名单的真实形状：按矿种分节，**小标题自己占一整行在表格里面**，
    # 数据行只有厂名与国别。不认表内小标题就会丢掉这 100 家真实冶炼厂。
    "in-table-heading": """
<table>
<tr><td>Gold</td></tr>
<tr><th>Smelter or Refiner Name</th><th>Country</th></tr>
<tr><td>ABC Refinery Pty Ltd.</td><td>Australia</td></tr>
<tr><td>Abington Reldan Metals, LLC</td><td>United States of America</td></tr>
<tr><td>Tin</td></tr>
<tr><td>Aurubis Beerse</td><td>Belgium</td></tr>
</table>""",
    # 叙述正文里矿种与国名满天飞，不得凭空造出冶炼厂
    "narrative-only": """
<p>During the reporting period we sourced gold, tin, tantalum and tungsten from
suppliers located in China, Japan and the United States. We did not identify any
smelter that sourced from a covered country.</p>
<table><tr><th>Metal</th><th>Country</th></tr><tr><td>Gold</td><td>China</td></tr></table>""",
}

# (夹具, 期望条数, 期望丢弃行数, 期望无编号条数, 抽查 {id: (名称, 国别, 矿种集)})
FORM_SD_CASES = [
    ("standard-4col", 4, 0, 0, {"CID000082": ("Asahi Pretec Corp.", "日本", {"金"}),
                                "CID002044": ("Wolfram Bergbau und Hutten AG", "奥地利", {"钨"})}),
    ("reordered-spaced-cid", 2, 0, 0,
     {"CID000801": ("LS-NIKKO Copper Inc.", "韩国", {"金"}),
      "CID002514": ("Solar Applied Materials Technology Corp.", "中国台湾", {"金"})}),
    ("mineral-in-heading", 2, 0, 0,
     {"CID001105": ("Malaysia Smelting Corporation (MSC)", "马来西亚", {"锡"}),
      "CID002082": ("Xiamen Tungsten Co., Ltd.", "中国", {"钨"})}),
    ("nested-table", 1, 0, 0, {"CID001153": ("Metalor Technologies SA", "瑞士", {"金"})}),
    ("duplicate-cid", 1, 0, 0, {"CID001908": ("Yunnan Tin Company Limited", "中国", {"锡", "钨"})}),
    ("country-in-name", 1, 0, 0, {"CID001938": ("Tokuriki Honten Co., Ltd.", "日本", {"金"})}),
    # 无编号但形态完整（矿种 + 厂名 + 国别）：照收，标为 name-only。
    # 厂名里的 Tantalum 不得把厂名列吞成矿种列。
    ("nvda-no-cid", 4, 0, 4,
     {"NAME:amg-brasil": ("AMG Brasil", "巴西", {"钽"}),
      "NAME:changsha-south-tantalum-niobium-co":
          ("Changsha South Tantalum Niobium Co", "中国", {"钽"}),
      "NAME:d-block-metals-llc": ("D Block Metals, LLC", "美国", {"钽"})}),
    # 纯国名附录：一条都不能收，也不能算成「漏收的冶炼厂」
    ("country-columns", 0, 0, 0, {}),
    # 国别 × 矿种矩阵：有国名有矿种但没有厂名列，同样一条都不收
    ("country-mineral-matrix", 0, 0, 0, {}),
    # 脚注星号必须剥掉，否则同一家会被算成两家
    ("footnote-marked", 3, 0, 3,
     {"NAME:a-l-m-t-corp": ("A.L.M.T. Corp.", "日本", {"钨"}),
      "NAME:agosi-ag": ("Agosi AG", "德国", {"金"}),
      "NAME:alpha-assembly-solutions-inc": ("Alpha Assembly Solutions Inc", "美国", {"锡"})}),
    # 表内小标题给出矿种，数据行只有厂名与国别
    ("in-table-heading", 3, 0, 3,
     {"NAME:abc-refinery-pty-ltd": ("ABC Refinery Pty Ltd.", "澳大利亚", {"金"}),
      "NAME:abington-reldan-metals-llc": ("Abington Reldan Metals, LLC", "美国", {"金"}),
      "NAME:aurubis-beerse": ("Aurubis Beerse", "比利时", {"锡"})}),
    # 只有厂名与国别、没有矿种、也没有小标题：无法确认是冶炼厂行，不收但计入丢弃
    ("names-without-cid", 0, 3, 0, {}),
    ("narrative-only", 0, 0, 0, {}),
]


def load_probe():
    return _load(PROBE_PATH, "probe_edgar")


def load_reverse():
    return _load(REVERSE_PATH, "probe_edgar_reverse")


def load_sic():
    return _load(SIC_PATH, "sic_stages")


def locate(module, text: str) -> list[str]:
    return [p for p in module.CONCENTRATION_PATTERNS if re.search(p, text, re.I)]


def extract_names(module, text: str) -> list[str]:
    return [e.strip() for e in re.findall(module.NAMED_ENTITY_PATTERN, text)
            if len(e) > 4 and not e.lower().startswith("the compan")]


def load_module(path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_extractor():
    """载入抽取器模块。它在导入时不发起任何请求，可离线加载。"""
    spec = importlib.util.spec_from_file_location("extract_form_sd", EXTRACT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_form_sd():
    spec = importlib.util.spec_from_file_location("form_sd_parse", FORM_SD_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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

    print("\n── SIC → 价值链阶段：板块级分不开的，行业码要能分开 ───────────────")
    sic = load_sic()
    for code, label, expected in SIC_CASES:
        resolved = sic.resolve(code)
        got = (resolved or {}).get("stage")
        ok = got == expected
        if not ok:
            failures.append(f"SIC {code} {label}：期望 {expected}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] SIC {code}  {label:<18} → {got}")
    # 无法解析时必须返回 None，不得猜一个默认阶段
    for bad in (None, "", 9999, -1, "abc"):
        if sic.resolve(bad) is not None:
            failures.append(f"SIC {bad!r} 无法解析时不得返回阶段")
    print(f"  [{'OK' if all(sic.resolve(b) is None for b in (None, '', 9999, -1, 'abc')) else 'XX'}]"
          f" 无法解析的输入返回 None，不猜默认阶段")

    print("\n── Form SD 冶炼厂清单：列序不固定，真假名单要分得开 ───────────────")
    form_sd = load_form_sd()
    for name, expect_count, expect_dropped, expect_name_only, spot in FORM_SD_CASES:
        result = form_sd.parse_smelters(FORM_SD_FIXTURES[name])
        got = {s["id"]: s for s in result["smelters"]}
        problems = []
        if len(got) != expect_count:
            problems.append(f"条数 {len(got)}≠{expect_count}")
        if result["droppedNoCid"] != expect_dropped:
            problems.append(f"丢弃行 {result['droppedNoCid']}≠{expect_dropped}")
        if result["nameOnly"] != expect_name_only:
            problems.append(f"无编号条目 {result['nameOnly']}≠{expect_name_only}")
        for cid, (want_name, want_country, want_minerals) in spot.items():
            row = got.get(cid)
            if not row:
                problems.append(f"{cid} 未抽出")
                continue
            if row["name"] != want_name:
                problems.append(f"{cid} 名称 {row['name']!r}≠{want_name!r}")
            if row["country"] != want_country:
                problems.append(f"{cid} 国别 {row['country']!r}≠{want_country!r}")
            if set(row["minerals"]) != want_minerals:
                problems.append(f"{cid} 矿种 {set(row['minerals'])}≠{want_minerals}")
        if problems:
            failures.append(f"FormSD {name}：" + "；".join(problems))
        print(f"  [{'OK' if not problems else 'XX'}] {name:<24} "
              f"抽出 {len(got)} 条（无编号 {result['nameOnly']}），"
              f"丢弃 {result['droppedNoCid']} 行"
              + ("" if not problems else "  " + "；".join(problems)))

    # 编号归一化：三种写法必须落到同一个 ID，否则跨申报人合并会把一家拆成三家
    cid_forms = ["CID001908", "CID 001908", "CID-001908", "cid001908"]
    normalised = {form_sd.normalise_cid(f) for f in cid_forms}
    ok = normalised == {"CID001908"}
    if not ok:
        failures.append(f"CID 归一化：{cid_forms} 应全部落到 CID001908，实际 {normalised}")
    print(f"  [{'OK' if ok else 'XX'}] CID 归一化              四种写法 → {sorted(normalised)}")
    # 认不出的国名必须返回 None，不得就近塞一个
    unknown_ok = all(form_sd.match_country(x) == (None, None)
                     for x in ("", "Country", "Various", "Unknown", "N/A", "—"))
    if not unknown_ok:
        failures.append("未知国名必须返回 (None, None)，不得猜")
    print(f"  [{'OK' if unknown_ok else 'XX'}] 未知国名不猜              返回 None")

    # 严格矿种列：整格是矿种词才算，含矿种词的厂名不得被吞成矿种列
    strict = [("Gold", True), ("Tin", True), ("Tin/Tungsten", True), ("Gold and Tin", True),
              ("Changsha South Tantalum Niobium Co", False), ("Gold Refinery Ltd", False),
              ("Tanaka Kikinzoku Kogyo K.K.", False), ("", False)]
    bad = [t for t, want in strict if bool(form_sd.mineral_cell(t)) != want]
    if bad:
        failures.append(f"矿种列严格判定失误：{bad}")
    print(f"  [{'OK' if not bad else 'XX'}] 矿种列严格判定            "
          f"含矿种词的厂名不被吞成矿种列")
    # 名字规范化不得做同义合并——没有编号就无从判断是不是同一家
    slug_ok = (form_sd._slug("Aurubis AG") != form_sd._slug("Aurubis AG, Hamburg")
               and form_sd._slug("AMG Brasil") == form_sd._slug("amg  brasil"))
    if not slug_ok:
        failures.append("名字规范化：大小写空格应归一，但不得把不同写法并成一家")
    print(f"  [{'OK' if slug_ok else 'XX'}] 名字规范化不做同义合并      宁可重复，不可错并")
    # 脚注剥离：只去尾部标记，不动名字本身
    footnotes = [("A.L.M.T. Corp.*", "A.L.M.T. Corp."), ("Agosi AG**", "Agosi AG"),
                 ("Alpha Assembly Solutions Inc (1)", "Alpha Assembly Solutions Inc"),
                 ("Metalor Technologies SA", "Metalor Technologies SA"),
                 ("L.S. Nikko Copper Inc.", "L.S. Nikko Copper Inc.")]
    wrong = [(a, form_sd.clean_name(a)) for a, b in footnotes if form_sd.clean_name(a) != b]
    if wrong:
        failures.append(f"脚注剥离出错：{wrong}")
    print(f"  [{'OK' if not wrong else 'XX'}] 脚注标记剥离              "
          f"尾部 * / ** / (1) 去掉，名字本身不动")

    print("\n── 边文件写盘：契约字段与「不拿坏结果覆盖好数据」 ──────────────")
    # 这几条路径（内容未变不重写、契约字段、体积闸门）只在真实抓取时才会跑到，
    # 出错的代价却是往仓库里写错数据。用合成数据离线跑一遍，不联网。
    extractor = load_extractor()
    import shutil
    import tempfile
    scratch = tempfile.mkdtemp()
    original_out, original_smelters = extractor.OUT_DIR, extractor.SMELTERS_PATH
    try:
        extractor.OUT_DIR = os.path.join(scratch, "edges")
        extractor.SMELTERS_PATH = os.path.join(scratch, "smelters.json")
        os.makedirs(extractor.OUT_DIR)

        def fake(symbol, count, with_cid=True):
            base = f"https://www.sec.gov/Archives/edgar/data/1/{symbol}/"
            return {"symbol": symbol, "cik": 1, "state": "listed",
                    "filing": {"accession": f"000-{symbol}", "filingDate": "2026-05-15",
                               "reportDate": "2025-12-31", "totalSD": 3, "indexUrl": base},
                    "parse": {"url": base + "cmr.htm", "document": "cmr.htm",
                              "rowsScanned": count * 2,
                              "rowsWithCid": count if with_cid else 0,
                              "nameOnly": 0 if with_cid else count, "droppedNoCid": 0,
                              "unique": count, "namedRatio": 1.0, "countryRatio": 1.0,
                              "smelters": [{
                                  "id": f"CID{i:06d}" if with_cid else f"NAME:plant-{i}",
                                  "cid": f"CID{i:06d}" if with_cid else None,
                                  "identifierType": "rmi-cid" if with_cid else "name-only",
                                  "name": f"Plant {i} Co., Ltd.", "countryEn": "japan",
                                  "country": "日本", "minerals": ["金"], "rowIndex": i}
                                  for i in range(count)]}}

        path = os.path.join(extractor.OUT_DIR, "AAA.json")
        first = extractor.write_if_changed(path, extractor.build_edges(fake("AAA", 5), "甲"))
        same = extractor.build_edges(fake("AAA", 5), "甲")
        same["updatedAt"] = "1999-01-01T00:00:00Z"
        rewrote_same = extractor.write_if_changed(path, same)
        changed = extractor.write_if_changed(path, extractor.build_edges(fake("AAA", 6), "甲"))
        with open(path, encoding="utf-8") as handle:
            saved = json.load(handle)
        name_only = extractor.build_edges(fake("BBB", 4, with_cid=False), "乙")
        evidence = saved.get("evidence") or {}

        writes = [
            ("首轮写入", first),
            ("时间戳变但内容同 → 不重写", not rewrote_same),
            ("内容变了 → 重写", changed and len(saved["edges"]) == 6),
            ("文件级 evidence 三要素齐全",
             all(evidence.get(f) for f in ("sourceType", "url", "docDate"))),
            ("出处是可点开的 https", str(evidence.get("url", "")).startswith("https://")),
            ("每条边都有 row 定位",
             all(isinstance(e.get("row"), int) and e["row"] >= 1 for e in saved["edges"])),
            ("标 rmi-cid 的确实带 cid",
             all(e["cid"] for e in saved["edges"] if e["idType"] == "rmi-cid")),
            ("标 name-only 的确实不带 cid",
             all(e["cid"] is None and e["idType"] == "name-only"
                 for e in name_only["edges"])),
            ("contractVersion = 2", saved.get("contractVersion") == 2),
            ("claimComplete 恒为 false", saved["coverage"]["claimComplete"] is False),
            ("体积闸门 30 MB", extractor.MAX_TOTAL_BYTES == 30 * 1024 * 1024),
            ("整轮保留阈值 60%", extractor.MIN_KEEP_RATIO == 0.6),
        ]
        for label, condition in writes:
            if not condition:
                failures.append(f"写盘 {label}")
            print(f"  [{'OK' if condition else 'XX'}] {label}")
    finally:
        extractor.OUT_DIR, extractor.SMELTERS_PATH = original_out, original_smelters
        shutil.rmtree(scratch, ignore_errors=True)

    print("\n── 中文译名：宁可显示英文，也不半译不硬造 ────────────────────────")
    zh = load_module(NAMES_ZH_PATH, "smelter_names_zh")
    zh_cases = [
        # 对照表命中，不限国别
        ("Yunnan Tin Company Limited", "中国", "云南锡业股份有限公司"),
        ("Mitsubishi Materials Corporation", "日本", "三菱综合材料株式会社"),
        # 词表能拼全
        ("Zhuzhou Smelting Group Co., Ltd", "中国", "株洲冶炼集团有限公司"),
        # 含拼音字号：jin 可以是金/进/锦/晋，猜错就是给真公司安错名字 → 不给中文名
        ("Jiangxi Jinxin Nonferrous Co., Ltd.", "中国", None),
        # 非中文语境的企业不组合——直译成中文名等于凭空造名
        ("Advanced Chemical Company", "美国", None),
        ("Industrial Refining Company", "美国", None),
        # 词表认不全 → 整条放弃，绝不半译
        ("Chifeng Dajingzi Tin Industry Co., Ltd.", "中国", "赤峰大井子锡业有限公司"),
        ("Metalor Technologies SA", "瑞士", None),
        (None, "中国", None),
        ("", "中国", None),
    ]
    for name, country, expected in zh_cases:
        got = zh.translate(name, country)
        ok = got == expected
        if not ok:
            failures.append(f"译名 {name!r}({country})：期望 {expected!r}，实际 {got!r}")
        print(f"  [{'OK' if ok else 'XX'}] {str(name)[:40]:<42} → {got or '（英文原文）'}")

    print("\n── 供应商名单探针：打分只排序候选，行为准则不得排在名单前 ────────")
    probe = load_module(SUPPLIER_PROBE_PATH, "probe_supplier_lists")
    rank_cases = [
        ("https://www.apple.com/.../Apple-Supplier-List.pdf",
         "https://www.apple.com/.../Supplier-Code-of-Conduct.pdf",
         "名单应排在行为准则之前——上一轮就是被行为准则 PDF 骗了"),
        ("https://about.nike.com/manufacturing-map.csv",
         "https://about.nike.com/privacy.pdf",
         "工厂地图应排在隐私政策之前"),
        ("https://x.com/supplier-list.xlsx", "https://x.com/brochure.pdf",
         "带 supplier-list 的表格应排在普通 PDF 之前"),
    ]
    for better, worse, why in rank_cases:
        ok = probe.score(better) > probe.score(worse)
        if not ok:
            failures.append(f"打分 {why}：{probe.score(better)} 未高于 {probe.score(worse)}")
        print(f"  [{'OK' if ok else 'XX'}] {why}"
              f"（{probe.score(better)} vs {probe.score(worse)}）")
    # 阈值：只有明确指向名单的地址才算数。首轮把英伟达的《可持续发展报告》
    # 算成了名单——它只是个恰好有文字的 PDF，打分 2 分。
    threshold_cases = [
        ("https://www.cisco.com/c/dam/en_us/about/supply-chain/cisco-supplier-list.pdf",
         True, "思科供应商名单——真名单，必须过线"),
        ("https://images.nvidia.com/NVIDIA-Sustainability-Report-Fiscal-Year-2026.pdf",
         False, "英伟达可持续发展报告——不是名单，必须不过线（首轮就是这里判错的）"),
        ("https://www.intel.com/documents/csr-2025-26-full-report.pdf",
         False, "英特尔 CSR 报告——不是名单，必须不过线"),
        ("https://www.cisco.com/c/dam/en_us/about/supply-chain/smelter-refiner-list.pdf",
         True, "思科冶炼厂名单——是名单，必须过线"),
    ]
    for url, should_pass, why in threshold_cases:
        got = probe.score(url) >= probe.LIST_SCORE
        if got != should_pass:
            failures.append(f"阈值 {why}：打分 {probe.score(url)}，"
                            f"期望{'≥' if should_pass else '<'} {probe.LIST_SCORE}")
        print(f"  [{'OK' if got == should_pass else 'XX'}] {why}（{probe.score(url)} 分）")

    # robots：被 Disallow 的路径必须认出来，不能抓
    robots_ok = (probe.blocked("https://x.com/private/list.pdf", ["/private"]) == "/private"
                 and probe.blocked("https://x.com/public/list.pdf", ["/private"]) is None
                 and probe.blocked("https://x.com/a/b", ["/a/*"]) == "/a/*")
    if not robots_ok:
        failures.append("robots Disallow 判定错误——被禁的路径必须认出来不抓")
    print(f"  [{'OK' if robots_ok else 'XX'}] robots Disallow 的路径不抓")

    # 国名并在名字里的拆分。**拆错砍掉的是公司的身份，不拆只是少一个属性**，
    # 所以宁可不拆。下面前四条是已发布数据里真被砍过的名字，逐条钉死。
    print("\n── 名字里的国名：宁可不拆，也不砍掉名字 ──────────────────────────")
    split_cases = [
        ("KEMET de Mexico", "KEMET de Mexico", None,
         "已发布数据里被砍成「KEMET de」"),
        ("Umicore Precious Metals Thailand", "Umicore Precious Metals Thailand", None,
         "已发布数据里被砍成「Umicore Precious Metals」"),
        ("PT Premium Tin Indonesia", "PT Premium Tin Indonesia", None,
         "已发布数据里被砍成「PT Premium Tin」"),
        ("Bangko Sentral ng Pilipinas (Central Bank of the Philippines)",
         "Bangko Sentral ng Pilipinas (Central Bank of the Philippines)", None,
         "已发布数据里括号被砍掉一半"),
        ("Asahi Pretec Corp. Japan", "Asahi Pretec Corp.", "japan",
         "后缀收尾 + 国名，该拆"),
        ("Tanaka Kikinzoku Kogyo K.K. Japan", "Tanaka Kikinzoku Kogyo K.K.", "japan",
         "带点的后缀也认得出来"),
        ("Dowa Metals & Mining Co., Ltd., Japan", "Dowa Metals & Mining Co., Ltd.",
         "japan", "逗号是约定俗成的分隔符，该拆"),
        ("Metalor Technologies SA - Switzerland", "Metalor Technologies SA",
         "switzerland", "破折号同理"),
        ("Yunnan Tin Company Limited", "Yunnan Tin Company Limited", None,
         "结尾没有国名，不动"),
    ]
    for raw, want_name, want_country, why in split_cases:
        got_name, got_country, _ = load_form_sd()._split_trailing_country(raw)
        ok = got_name == want_name and got_country == want_country
        if not ok:
            failures.append(f"国名拆分 {raw!r}：期望 ({want_name!r}, {want_country!r})，"
                            f"实际 ({got_name!r}, {got_country!r})")
        print(f"  [{'OK' if ok else 'XX'}] {why}")
        print(f"        {raw[:56]:<58} → {got_name[:44]!r}"
              + (f" + {got_country}" if got_country else ""))

    # 申报文档的过滤规则。抽取器用它决定读哪几份，「有申报但没抽到名单」的
    # 探针用同一个函数显示「哪些文件被挡掉了」——两处共用，改坏了两处一起错，
    # 而且探针会开始说假话，所以逐条钉死。
    print("\n── 申报文档过滤：读哪些、跳哪些，两处共用同一套规则 ──────────────")
    skip_cases = [
        ("tm2514567d1_sd.htm", None, "正常的申报正文要读"),
        ("nvda-20250531xsdex101.htm", None, "冲突矿产报告附件要读"),
        ("R2.htm", None, "大写文件名不受影响"),
        ("0001104659-25-064234-index.htm", "文件名以 0 开头", "索引文件跳过"),
        ("Financial_Report.xlsx", "非 HTML", "非 HTML 跳过"),
        ("cmr-2025.pdf", "非 HTML", "PDF 目前跳过——这正是探针要暴露的那一类"),
        ("form-sd-index.html", "文件名含 index", "含 index 的跳过"),
    ]
    for name, expected, why in skip_cases:
        got = extractor.skip_reason(name)
        ok = got == expected
        if not ok:
            failures.append(f"过滤规则 {name!r}：期望 {expected!r}，实际 {got!r}")
        print(f"  [{'OK' if ok else 'XX'}] {why}"
              f"（{name} → {got or '会读'}）")

    total = (len(split_cases) + len(skip_cases) + len(CASES) * 2 + len(NEGATIVE) + len(CONTEXT_CASES) + len(SIC_CASES)
             + len(FORM_SD_CASES) + 6 + len(writes)
             + len(zh_cases) + len(rank_cases) + len(threshold_cases) + 1)
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

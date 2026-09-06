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
import base64
import zlib
from datetime import date

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
EDGAR_INDEX_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "supply-chain", "edgar_index.py")
FOREIGN_FETCH_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  "supply-chain", "fetch_foreign_identity.py")
CHAINS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "supply-chain", "sic_chains.py")
PEERS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "supply-chain", "smelter_peers.py")

# ── SIC → 价值链阶段 ────────────────────────────────────────────────────────
# SIC 码全部取自探针在 Actions 机房实测到的真实值，不是凭印象写的。
# 前三条是这套映射存在的理由：GICS 一级板块把苹果、英伟达、微软都归为「科技」，
# 分不出产业链位置；SIC 能分开。后两条是 33xx 拆分的回归——不拆的话康宁
# （SIC 3357 有色线材拉制）会被误判成上游资源，它做的是玻璃基板与光纤。
SIC_CASES: list[tuple[int, str, str]] = [
    # 板块级分不开的，行业码要能分开
    (3571, "苹果 电子计算机整机", "finished-goods"),
    (3674, "英伟达 半导体", "component"),
    (7372, "微软 预装软件", "technology"),
    (3312, "钢铁高炉", "material-processing"),
    (3357, "康宁 有色线材", "component"),
    (3663, "高通 通信设备", "component"),
    (1311, "原油与天然气开采", "raw-material"),
    (6022, "州立商业银行", "financial"),
    (5912, "药品零售", "distribution"),
    (2834, "成药制剂", "finished-goods"),
    (3714, "机动车零部件", "component"),
    (3711, "整车制造", "finished-goods"),
    # ── 以下是这次把六段扩成十二段时新拆出来的，每条都对应一个会判错的公司 ──
    # 设备商与元器件商不同层：应用材料、泛林供给的是制造商，不是整机厂
    (3559, "泛林 半导体专用设备", "capital-equipment"),
    (3531, "卡特彼勒 工程机械", "capital-equipment"),
    (3570, "IBM 计算机与办公设备", "capital-equipment"),
    # 载客的不是物流。按两位码把 40–47 整段归物流会把这三类当成货运。
    (4512, "达美 客运航空", "end-service"),
    (4400, "皇家加勒比 邮轮", "end-service"),
    (4700, "Booking 在线旅游", "end-service"),
    (4513, "联邦快递 航空货运", "logistics"),
    (4731, "C.H. Robinson 货代", "logistics"),
    (4011, "联合太平洋 铁路", "logistics"),
    # 电力是制造业的投入品，不是像银行那样的外围服务
    (4911, "南方公司 电力", "energy-utility"),
    # 逆向供应链：SCOR 模型的 Return
    (4953, "废物管理公司 废弃物处理", "circular"),
    # 化工要分开：工业化学品是投入品，日化是终端消费品
    (2810, "林德 工业气体", "material-processing"),
    (2840, "宝洁 肥皂洗涤", "finished-goods"),
    # 电信是网络承载，归技术平台
    (4813, "Verizon 电信", "technology"),
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
    # 迪尔 2026 年报告的真实形状：矿种列里带元素符号 —— Gold (Au)。
    # 那份 531KB 的报告里 483 行有 402 行是这个形状，一条都没抽出来：
    # "Gold (Au)" 去掉标点剩 ["gold", "au"]，"au" 不是矿种词，严格匹配一票否决整格。
    # 402 家真冶炼厂卡在括号里的元素符号上。
    "mineral-with-symbol": """
<table>
<tr><th>Metal</th><th>Smelter or Refiner Name</th><th>Country</th></tr>
<tr><td>Gold (Au)</td><td>Al Etihad Gold Refinery DMCC</td><td>UNITED ARAB EMIRATES</td></tr>
<tr><td>Gold (Au)</td><td>L'Orfebre S.A.</td><td>ANDORRA</td></tr>
<tr><td>Tin (Sn)</td><td>Torecom</td><td>KOREA, REPUBLIC OF</td></tr>
<tr><td>Tungsten (W)</td><td>Ta Chen Stainless Pipe Co.</td><td>TAIWAN</td></tr>
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
    # 矿种列带元素符号：照收。厂名里含 "Ta" 的那行不得被当成矿种列吞掉。
    ("mineral-with-symbol", 4, 0, 4,
     {"NAME:al-etihad-gold-refinery-dmcc":
          ("Al Etihad Gold Refinery DMCC", "阿联酋", {"金"}),
      "NAME:l-orfebre-s-a": ("L'Orfebre S.A.", "安道尔", {"金"}),
      "NAME:ta-chen-stainless-pipe-co": ("Ta Chen Stainless Pipe Co.", "中国台湾", {"钨"})}),
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

    # 元素符号。加进来的是 Au/Sn/Ta/W，**只在严格匹配里认**——放进宽松正则的话
    # 正文里每个 "W" 都会被当成钨。两条都要守：该认的认出来，不该吞的不吞。
    print("\n── 矿种列里的元素符号：认得出来，又不能吞掉厂名 ──────────────────")
    fsd = load_form_sd()
    symbol_cases = [
        ("Gold (Au)", {"金"}, "迪尔那 402 行卡住的就是这个形状"),
        ("Tin (Sn)", {"锡"}, "锡"),
        ("Tungsten (W)", {"钨"}, "钨"),
        ("Tantalum (Ta)", {"钽"}, "钽"),
        ("Tungsten (W), Tantalum (Ta), Tin (Sn), Gold (Au)",
         {"锡", "钽", "钨", "金"}, "四种写在一格"),
        ("Ta Chen Stainless Pipe Co.", set(), "厂名里有 Ta，不得当成矿种列"),
        ("Al Etihad Gold Refinery DMCC", set(), "厂名里有 Gold，不得当成矿种列"),
        ("Changsha South Tantalum Niobium Co., Ltd.", set(),
         "厂名里有 Tantalum，不得当成矿种列"),
        ("UNITED ARAB EMIRATES", set(), "国名不是矿种列"),
    ]
    for text, want, why in symbol_cases:
        got = fsd.mineral_cell(text)
        ok = got == want
        if not ok:
            failures.append(f"矿种列 {text!r}：期望 {want}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] {why}"
              f"（{text[:44]} → {sorted(got) or '非矿种列'}）")

    # 国名并在名字里的拆分。**拆错砍掉的是公司的身份，不拆只是少一个属性**，
    # 所以宁可不拆。下面前四条是已发布数据里真被砍过的名字，逐条钉死。
    print("\n── 名字里的国名：国别照认，名字只在有把握时才截 ──────────────────")
    # 这一组前后踩过两次，方向相反，所以两边都要钉住：
    #   太松 —— 见空格就拆，把「KEMET de Mexico」砍成「KEMET de」
    #   太紧 —— 不确定就不拆，连国别一起丢，无编号的行因缺国别被整行弃掉，
    #           六家公司的名单整份消失（实测 88 → 80 家）
    # 正确解：名字保完整 **且** 国别照给。下面前四条两样都断言。
    split_cases = [
        ("KEMET de Mexico", "KEMET de Mexico", "mexico",
         "名字保完整，国别照给（曾被砍成「KEMET de」）"),
        ("Umicore Precious Metals Thailand", "Umicore Precious Metals Thailand",
         "thailand", "名字保完整，国别照给（曾被砍成「Umicore Precious Metals」）"),
        ("PT Premium Tin Indonesia", "PT Premium Tin Indonesia", "indonesia",
         "名字保完整，国别照给（曾被砍成「PT Premium Tin」）"),
        ("Bangko Sentral ng Pilipinas (Central Bank of the Philippines)",
         "Bangko Sentral ng Pilipinas (Central Bank of the Philippines)", "philippines",
         "括号完整，国别照给（曾被砍掉一半）"),
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

    # ── PDF 文本抽取 ────────────────────────────────────────────────────
    # 麦当劳的冲突矿产报告与思科的一级供应商名单都是 PDF，现有规则只收 HTML，
    # 整份看不到。仓库不装新依赖，所以用标准库实现，夹具就地构造、完全离线可复算。
    #
    # 第一版扫了**所有**流，把字体程序也算进内容——CFF/TrueType 的二进制里恰好
    # 会出现 "Tj" 字节，于是从一份 121KB 的真 PDF 里解出 22,853 个字符的乱码，
    # 还报成 verdict=text。改为只从页面的 /Contents 取字后，同一份文件得到
    # 10 页 4,505 字的干净文本。**把结果说多**是这个项目反复踩的方向，钉死它。
    print("\n── PDF 文本抽取：解得开的解，解不开的如实说 ──────────────────────")
    pdf = load_module(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   "supply-chain", "pdf_text.py"), "pdf_text")

    def _pdf(content: bytes, filt: str | None = None) -> bytes:
        """最小但合法的单页 PDF。filt 决定内容流用哪种过滤器。"""
        if filt == "Fl":
            body, f = zlib.compress(content), b"/Filter /FlateDecode "
        elif filt == "A85Fl":
            body = base64.a85encode(zlib.compress(content)) + b"~>"
            f = b"/Filter [/ASCII85Decode /FlateDecode] "
        elif filt == "AHx":
            body, f = content.hex().encode() + b">", b"/Filter /ASCIIHexDecode "
        else:
            body, f = content, b""
        objs = [
            b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R "
            b"/Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< " + f + b"/Length " + str(len(body)).encode()
            + b" >>\nstream\n" + body + b"\nendstream",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ]
        out = b"%PDF-1.5\n"
        for i, o in enumerate(objs, 1):
            out += str(i).encode() + b" 0 obj\n" + o + b"\nendobj\n"
        return out + b"trailer\n<< /Root 1 0 R >>\n%%EOF"

    # 真实冶炼厂行的形状：括号转义、多个 Tj、TJ 字距数组
    SMELTER = (b"BT /F1 12 Tf (Gold \\(Au\\)) Tj 0 -14 Td "
               b"(Al Etihad Gold Refinery DMCC) Tj 0 -14 Td "
               b"[(UNITED) -300 (ARAB) -300 (EMIRATES)] TJ ET")
    pdf_cases = [
        ("未压缩", _pdf(SMELTER), "text", "Al Etihad Gold Refinery DMCC"),
        ("FlateDecode", _pdf(SMELTER, "Fl"), "text", "Al Etihad Gold Refinery DMCC"),
        # 英特尔那三份就是 ASCII85 包一层，旧解析器整份解不开
        ("ASCII85+Flate", _pdf(SMELTER, "A85Fl"), "text", "UNITED ARAB EMIRATES"),
        ("ASCIIHex", _pdf(SMELTER, "AHx"), "text", "Gold (Au)"),
        # 扫描件：解开了流但没有文本操作符。**不得假装有字**
        ("只有图像", _pdf(b"q 100 0 0 100 0 0 cm /Im0 Do Q", "Fl"), "image-only", None),
        ("不是 PDF", b"just some bytes", "not-pdf", None),
    ]
    for label, raw, want_verdict, want_text in pdf_cases:
        got = pdf.pdf_to_text(raw)
        ok = got["verdict"] == want_verdict
        if ok and want_text:
            ok = want_text in got["text"]
        if not ok:
            failures.append(f"PDF {label}：verdict={got['verdict']} "
                            f"text={got['text'][:60]!r}")
        print(f"  [{'OK' if ok else 'XX'}] {label}"
              f"（verdict={got['verdict']}，{got['chars']} 字）")

    # 括号转义与 TJ 字距：字掉了就是这里掉的
    esc = pdf.extract_text(b"BT (a\\(b\\)c) Tj [(for) -300 (the)] TJ ET")[0]
    esc_ok = "a(b)c" in esc and "for the" in esc
    if not esc_ok:
        failures.append(f"PDF 转义与字距：{esc!r}")
    print(f"  [{'OK' if esc_ok else 'XX'}] 括号转义与 TJ 字距（→ {esc!r}）")

    # pdf_text_sample 的返回会被 doc.update() 并进调用方的字典，所以它**不能带
    # 与调用方同名的键**。曾经带了个 kind，把 doc["kind"]="pdf" 覆盖成 "text"，
    # 于是 PDF 的显示分支整个没走、extractable 没设，思科三份明明解出了文字，
    # 结论却报「0/8 家，内容没取到」——靠读 Actions 日志才发现。钉死这个契约。
    print("\n── 探针字段契约：辅助函数不得覆盖调用方的键 ──────────────────────")
    sample = probe.pdf_text_sample(_pdf(SMELTER, "Fl"))
    need = ("extractable", "verdict", "streams", "inflatedStreams",
            "textStreams", "filters", "textSample")
    missing = [k for k in need if k not in sample]
    clash = [k for k in ("kind", "url", "score", "bytes", "contentType") if k in sample]
    contract_ok = not missing and not clash
    if not contract_ok:
        failures.append(f"探针字段契约：缺 {missing}，撞名 {clash}")
    print(f"  [{'OK' if contract_ok else 'XX'}] 显示与判据要的键齐全，且不与调用方撞名"
          f"（缺 {missing or '无'}，撞名 {clash or '无'}）")
    extract_ok = sample["extractable"] is True
    if not extract_ok:
        failures.append(f"探针 extractable：解出文字的 PDF 应为 True，实际 {sample['extractable']!r}")
    print(f"  [{'OK' if extract_ok else 'XX'}] 解出文字的 PDF → extractable=True")
    blind = probe.pdf_text_sample(_pdf(b"q 1 0 0 1 0 0 cm /Im0 Do Q", "Fl"))
    blind_ok = blind["extractable"] is False
    if not blind_ok:
        failures.append("探针 extractable：扫描件不得报 True")
    print(f"  [{'OK' if blind_ok else 'XX'}] 扫描件 → extractable=False，不假装取到了")

    # Form SD 底下是两套互不相干的披露：13p-1 冲突矿产（有冶炼厂名单）与
    # 13q-1 资源开采付款（向各国政府付了多少钱）。把后者算进「申报了但没列名单」
    # 等于暗示「本可以列却没列」，而那套披露里根本没有冶炼厂这个概念。
    print("\n── 披露类型：冲突矿产还是资源开采付款 ────────────────────────────")
    kind_cases = [
        ("<p>Conflict Minerals Report for the reporting period</p>",
         "conflict-minerals", "冲突矿产报告"),
        ("<p>Our smelter and refiner due diligence covered 3TG</p>",
         "conflict-minerals", "提到冶炼厂即为冲突矿产"),
        ("<p>Form SD filed under Rule 13q-1, payments to governments</p>",
         "resource-extraction", "康菲那一类：资源开采付款"),
        ("<p>Extractive Sector Transparency Measures Act (ESTMA) Report</p>",
         "resource-extraction", "纽蒙特那一类：ESTMA"),
        ("<p>Conflict Minerals Report. See also Section 1504.</p>",
         "conflict-minerals", "两类都提时以冲突矿产为准——宁可不摘，不可少报"),
        ("<p>Nothing relevant</p>", "unknown", "都不像就返回 unknown，不猜"),
    ]
    for html, want, why in kind_cases:
        got = load_form_sd().disclosure_kind(html)
        ok = got == want
        if not ok:
            failures.append(f"披露类型 {html[:40]!r}：期望 {want}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] {why}（→ {got}）")

    # 只按用词判会对矿业与能源公司系统性判错——它们的业务词就是 smelter 和
    # refinery。2026-09-05 实测：力拓 formsd2025govpayment.htm、壳牌
    # shel-20251231.htm（表格是「保加利亚能源部 658,383」）都被判成「未列名单」。
    # 结构判据来自 SEC 的要求本身：13q-1 的付款数据必须内联 XBRL 标记，
    # 13p-1 没有这个要求，所以目录里有没有 XBRL 渲染件不受正文用词影响。
    print("\n── 矿业与能源公司：光看用词会判错，得看结构 ──────────────────────")
    _RIO = ("<p>Rio Tinto payments to governments report under Section 1504. "
            "Projects include our aluminium smelter at Kitimat.</p>")
    _SHELL = ("<p>Payments to governments 2025. MINISTRY OF ENERGY BULGARIA 658,383. "
              "Our refinery operations in Germany.</p>")
    # 原来这条写的是「Not a payments to governments report」，本意是测否定，
    # 但子串匹配做不到否定检测——夹具在考一个判据根本没有的能力。
    # 换成真实形状：一份冲突矿产报告不会出现付款披露的用词。
    _SONY = ("<p>Item 1.01 Conflict Minerals Disclosure and Report under Rule 13p-1. "
             "Smelter and refiner list follows.</p>")
    # 力拓那一份第一轮没被拦住：它排在最前的 R4.htm 是张 XBRL 渲染表，通篇数字，
    # 一个特征词都没有。真正写着报的是哪一套的是 Form SD 的条目标题，在另一份
    # 文件里——所以抽取器改为把取到的几份合起来判，判据也改用条目标题。
    _RIO_XBRL_PAGE = ("<p>[2] Payments reported are net of a cash refund. "
                      "IDEA: XBRL DOCUMENT Do Not Remove This Comment</p>")
    _RIO_COVER = ("<p>Item 2.01 Resource Extraction Issuer Disclosure and Report. "
                  "Rio Tinto plc, London SW1Y 4AD, United Kingdom.</p>")
    _TESLA_LIKE = ("<p>Item 1.01 Conflict Minerals Disclosure and Report. "
                   "We describe our due diligence process. No list is provided.</p>")
    title_cases = [
        (_RIO_XBRL_PAGE, True, "unknown",
         "只看那张 XBRL 渲染表：一个特征词都没有，判不出来就说判不出来"),
        (_RIO_XBRL_PAGE + _RIO_COVER, True, "resource-extraction",
         "把几份合起来看，条目标题 2.01 就出现了——力拓这一档由此归位"),
        (_TESLA_LIKE, False, "conflict-minerals",
         "条目标题 1.01：报的是冲突矿产，只是没列名单"),
        (_TESLA_LIKE + _RIO_COVER, False, "conflict-minerals",
         "两个条目标题都在但没有 XBRL：模板本来就印着两节标题，不算数"),
    ]
    for html, xbrl, want, why in title_cases:
        got = load_form_sd().disclosure_kind(html, xbrl_tagged=xbrl)
        ok = got == want
        if not ok:
            failures.append(f"条目标题判据 {why}：期望 {want}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] {why}（→ {got}）")

    xbrl_cases = [
        (_RIO, True, "resource-extraction",
         "力拓：有铝冶炼厂，但这份是 1504 付款报告，XBRL 标记说明它是 13q-1"),
        (_SHELL, True, "resource-extraction", "壳牌：有炼油厂，同上"),
        (_SONY, True, "conflict-minerals",
         "索尼：即使带 XBRL，正文是 13p-1 报告就不能判成资源开采"),
        (_RIO, False, "resource-extraction",
         "正文明写「向各国政府的付款」——这是模板上没有的强特征，不靠 XBRL 也成立"),
    ]
    for html, xbrl, want, why in xbrl_cases:
        got = load_form_sd().disclosure_kind(html, xbrl_tagged=xbrl)
        ok = got == want
        if not ok:
            failures.append(f"披露类型（XBRL={xbrl}）{why}：期望 {want}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] {why}（→ {got}）")

    # XBRL 判据本身：认的是文件名形状，别把普通附件也当成 XBRL 渲染件
    xbrl_name_cases = [
        (["formsd2025govpayment.htm", "R4.htm", "R1.htm"], True, "R4.htm 是 XBRL 渲染件"),
        (["aem-20260601xex2d01.htm", "MetaLinks.json"], True, "MetaLinks.json 同理"),
        (["agi-20251231.htm", "agi-20251231_htm.xml"], True, "_htm.xml 同理"),
        (["a2025conflictmineralsreport.htm", "formsd.htm"], True is False,
         "ASML：纯冲突矿产报告，没有 XBRL 渲染件"),
        (["dp246807_ex0101.htm", "dp246807_sd.htm"], False, "ASE：同上"),
        (["Report.htm", "R.htm"], False, "R 后面没数字的不算"),
        ([], False, "空目录不算"),
    ]
    for names, want, why in xbrl_name_cases:
        got = load_form_sd().filing_is_xbrl_tagged(names)
        ok = got == want
        if not ok:
            failures.append(f"XBRL 判据 {why}：期望 {want}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

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

    # 外国私人发行人探针的纯函数。这个探针要拿 EDGAR 季度全量索引数几万行，
    # 解析错一行不会报错，只会**悄悄少算一家**——所以三个解析函数逐条钉死。
    # master.idx 是管道分隔的，选它而不是定宽的 form.idx 就是因为定宽在长公司名
    # 上会串列；下面第三条负例就是那种会把定宽解析器骗过去的行。
    print("\n── 外国发行人探针：索引解析、季度回溯、归档目录 ─────────────────")
    foreign = _load(EDGAR_INDEX_PATH, "edgar_index")
    index_cases = [
        ("1046179|TAIWAN SEMICONDUCTOR MANUFACTURING CO LTD|20-F|2025-04-17|"
         "edgar/data/1046179/0001046179-25-000012.txt",
         {"cik": 1046179, "form": "20-F", "date": "2025-04-17"},
         "20-F 正常行"),
        ("937966|ASML HOLDING NV|SD|2025-05-28|edgar/data/937966/0000937966-25-000031.txt",
         {"cik": 937966, "form": "SD", "date": "2025-05-28"},
         "SD 正常行"),
        ("320193|APPLE INC.|10-K|2025-11-01|edgar/data/320193/0000320193-25-000123.txt",
         {"cik": 320193, "form": "10-K", "date": "2025-11-01"},
         "公司名里有句点不影响"),
        ("1000229|CORE  MOLDING  TECHNOLOGIES  INC|SD|2025-05-30|"
         "edgar/data/1000229/0001000229-25-000004.txt",
         {"cik": 1000229, "form": "SD", "date": "2025-05-30"},
         "公司名里有连续空格——定宽解析会串列，管道分隔不会"),
        ("CIK|Company Name|Form Type|Date Filed|Filename", None, "表头不当数据行"),
        ("--------------------------------------------------------", None, "分隔线不当数据行"),
        ("", None, "空行不当数据行"),
    ]
    for line, expected, why in index_cases:
        got = foreign.parse_index_line(line)
        if expected is None:
            ok = got is None
        else:
            ok = bool(got) and all(got.get(k) == v for k, v in expected.items())
        if not ok:
            failures.append(f"索引解析 {why}：期望 {expected!r}，实际 {got!r}")
        print(f"  [{'OK' if ok else 'XX'}] {why}"
              f"（→ {got['form'] + ' CIK ' + str(got['cik']) if got else '不是数据行'}）")

    # 季度回溯要跨年。跨错了就会去取一个不存在的季度，然后把「取不到」
    # 误报成「这季度没人申报」——那是个会一路传到结论里的错。
    quarter_cases = [
        (date(2026, 9, 5), 4, [(2026, 3), (2026, 2), (2026, 1), (2025, 4)], "本季度往回数四个，跨年"),
        (date(2026, 1, 15), 3, [(2026, 1), (2025, 4), (2025, 3)], "一月：立刻跨年"),
        (date(2026, 12, 31), 2, [(2026, 4), (2026, 3)], "年末不跨年"),
    ]
    for today, count, expected, why in quarter_cases:
        got = foreign.recent_quarters(today, count)
        ok = got == expected
        if not ok:
            failures.append(f"季度回溯 {why}：期望 {expected}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] {why}"
              f"（{'、'.join(f'{y}Q{q}' for y, q in got)}）")

    dir_cases = [
        (937966, "edgar/data/937966/0000937966-25-000031.txt",
         "https://www.sec.gov/Archives/edgar/data/937966/000093796625000031/",
         "归档路径推出申报目录"),
        (320193, "edgar/data/320193/0000320193-25-000123-index.htm", None,
         "不是 .txt 归档就推不出来，返回 None 而不是拼个错地址"),
    ]
    for cik, path, expected, why in dir_cases:
        got = foreign.accession_dir(cik, path)
        ok = got == expected
        if not ok:
            failures.append(f"归档目录 {why}：期望 {expected!r}，实际 {got!r}")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    # 横轴：SIC → 一级产业链。这张表决定「哪条链上有哪些公司」，判错了整页跟着错，
    # 而且错得很安静——公司还在，只是挂到了别的链上。逐条钉死会判错的那些码。
    print("\n── 横轴：SIC → 一级产业链 ─────────────────────────────────────────")
    chains_mod = _load(CHAINS_PATH, "sic_chains")
    chain_cases = [
        (3674, ["semiconductor"], "英伟达申报码：半导体"),
        (3559, ["semiconductor", "industrial-machinery"],
         "半导体前道设备申报在专用机械 NEC 下，两条链都算"),
        (3533, ["industrial-machinery", "oil-gas"], "油气田机械天然跨两条链"),
        (6324, ["medtech-health", "financial-services"], "医疗保险计划是支付方，也是保险"),
        (3357, ["communications", "electronics-components"],
         "康宁的码：光纤属通信，不能因为字面是「拉丝」就判成采矿"),
        (2911, ["oil-gas", "chemicals"],
         "炼油：区间表最初漏了 2900-2999，六家石油巨头全无归属——覆盖检查抓出来的"),
        (4512, ["logistics-transport", "travel-leisure"],
         "客运航空以载客为主：载客的不是物流，这条此前在纵轴上踩过"),
        (2834, ["pharma-biotech"], "成药"),
        (6798, ["real-estate"], "REIT"),
        (None, None, "没有码就不给链，不硬塞"),
        ("", None, "空码同上"),
        (9999, None, "认不出的码返回 None，页面显示未归类"),
    ]
    for sic, expected, why in chain_cases:
        got = chains_mod.resolve_chains(sic)
        if expected is None:
            ok = got is None
            shown = "未归类"
        else:
            ok = bool(got) and got["chains"] == sorted(
                expected, key=lambda c: chains_mod.CHAIN_INDEX[c])
            shown = "/".join(got["chains"]) if got else "无"
        if not ok:
            failures.append(f"产业链 {why}：期望 {expected}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] {why}（{sic} → {shown}）")

    # 链表本身的自洽：id 不重样、每条链都有中英文名、EXACT/RANGES 里不能出现
    # 表上没有的 id——写错一个 id 不会报错，只会让那条链永远是空的。
    ids = [cid for cid, _, _ in chains_mod.CHAINS]
    chain_self = [
        (len(ids) == len(set(ids)), "链 id 不重复"),
        (all(zh and en for _, zh, en in chains_mod.CHAINS), "每条链都有中英文名"),
        (all(c in chains_mod.CHAIN_INDEX
             for v, _ in chains_mod.EXACT.values() for c in v), "精确表里没有野 id"),
        (all(c in chains_mod.CHAIN_INDEX
             for _, _, v, _ in chains_mod.RANGES for c in v), "区间表里没有野 id"),
    ]
    for ok, why in chain_self:
        if not ok:
            failures.append(f"链表自洽：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    # --extra-ciks 是「先探后建」的口子：拿几家还不在公司池里的公司做 dry-run。
    # 危险的是它被用来写盘——那等于绕过公司池直接发布。守住这道闸。
    print("\n── 临时追加公司只允许 dry-run ────────────────────────────────────")
    import io as _io
    import contextlib as _ctx
    guard_cases = [
        (["x", "--extra-ciks", "TSM:1046179"], 1, "不加 --dry-run 必须拒绝"),
        (["x", "--extra-ciks", "TSM:notanumber", "--dry-run"], 1, "CIK 不是数字要拒绝"),
        (["x", "--extra-ciks", "TSM", "--dry-run"], 1, "少了冒号要拒绝"),
    ]
    for argv, expect, why in guard_cases:
        saved = sys.argv
        sys.argv = argv
        buf = _io.StringIO()
        try:
            with _ctx.redirect_stdout(buf):
                got = extractor.main()
        except SystemExit as exc:                  # noqa: PERF203
            got = exc.code
        finally:
            sys.argv = saved
        ok = got == expect
        if not ok:
            failures.append(f"追加公司闸门 {why}：期望返回 {expect}，实际 {got}")
        print(f"  [{'OK' if ok else 'XX'}] {why}（返回 {got}）")

    # 链间上下游。这张表是**框架**，最大的风险不是写错一条线，而是它被当成
    # 有出处的关系——所以断言分两类：表本身自洽，以及它绝不携带出处字段。
    print("\n── 链间上下游：框架自洽，且不得冒充证据 ─────────────────────────")
    links = chains_mod.chain_links()
    link_pairs = {(l["from"], l["to"]) for l in links}
    ids = [cid for cid, _, _ in chains_mod.CHAINS]
    linked = {l["from"] for l in links} | {l["to"] for l in links}
    link_self = [
        (all(l["from"] in chains_mod.CHAIN_INDEX and l["to"] in chains_mod.CHAIN_INDEX
             for l in links), "两端都是已登记的链"),
        (all(l["from"] != l["to"] for l in links), "没有自己连自己"),
        (len(link_pairs) == len(links), "没有重复的连线"),
        (all(l["basis"] == "framework" for l in links), "每条都自报 framework"),
        (all((l.get("flow") or "").strip() for l in links), "每条都写清流动的是什么"),
        (all(not any(k in l for k in ("sourceType", "url", "docDate"))
             for l in links), "一条都不带出处字段——出处只属于 edges/"),
        (all(c in linked or c in chains_mod.CROSS_CUTTING for c in ids),
         "没有既无连线又没标横跨全链的断头"),
        (all(c in chains_mod.CHAIN_INDEX for c in chains_mod.CROSS_CUTTING),
         "使能链的 id 都在链表里"),
    ]
    for ok, why in link_self:
        if not ok:
            failures.append(f"链间上下游：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    # 闭环：实物链本来是回路，消费后的废弃物回到冶炼与制浆再变成新料。
    # 只画一半（有再生料出来、没有废弃物进去）等于说回收的东西凭空产生。
    loop_cases = [
        (bool(chains_mod.upstream_of("waste-circular")),
         "环保链有上游——废弃物从哪来说得出"),
        (bool(chains_mod.downstream_of("waste-circular")),
         "环保链有下游——再生料去哪说得出"),
        (("waste-circular", "mining-metals") in link_pairs,
         "再生金属回到采矿与金属，闭环合上"),
        (("chemicals", "semiconductor") in link_pairs,
         "化工 → 半导体：电子气体与光刻胶这一跳在"),
        (("industrial-machinery", "semiconductor") in link_pairs,
         "工业机械 → 半导体：设备这一跳在"),
        (("semiconductor", "computing-hardware") in link_pairs,
         "半导体 → 计算硬件：芯片这一跳在"),
        (("mining-metals", "textiles-apparel") not in link_pairs,
         "不连跨好几跳的远关系——那样连出来的是糊成一团的网"),
    ]
    for ok, why in loop_cases:
        if not ok:
            failures.append(f"链间上下游：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    # 链的层次。**这是本轮最容易悄悄出错的一段**：第一版对有环的图直接做最长路径
    # 松弛，算出 241 层、30 条回流边——层数比链数还多十倍，页面照画不会报错。
    # 所以这里钉的不是「算得出层次」，是「算出来的层次讲得通」。
    print("\n── 链的层次：算得出、讲得通、算不出就报错 ─────────────────────────")
    layers = chains_mod.chain_layers()
    lay = layers["layer"]
    depth = layers["depth"]
    cross = chains_mod.CROSS_CUTTING
    layer_self = [
        (0 < depth <= len(chains_mod.CHAINS),
         f"层数 {depth} 不超过链数——第一版算出 241 层就是这么露馅的"),
        (all(c in lay for c, _, _ in chains_mod.CHAINS if c not in cross),
         "每条非使能链都有层次"),
        (not any(c in lay for c in cross), "使能链不参与分层，不硬塞进某一层"),
        # 「不参与分层」和「不逐条连」是**两个不同的判断**，曾经被写成一句
        # 「不逐条连线」——而数据里物流有 3 条入边、金融 1 条、房地产 1 条，
        # 且都是真的投入（石油给物流的是运输燃料）。文案与数据打架，
        # 路径视图还把物流从「石油的下游」里静默丢掉了。
        (any(t in cross for _, t, _ in chains_mod.CHAIN_LINKS),
         "使能链确实带入边——这条断言在的意义是：别再退回「不逐条连线」那句话"),
        (not any(f in cross for f, _, _ in chains_mod.CHAIN_LINKS),
         "使能链没有出边：它向外供给所有链，逐条连会画出 100 多条没信息量的线"),
        (all("其出向不逐条连线" in why or "出向" in why for why in cross.values()),
         "使能链的说明必须点明「不逐条连」说的是**出向**，不能笼统说不连线"),
        (len(layers["back"]) == len(chains_mod.COUNTERFLOW),
         "逆向边数与声明的一致"),
        (all(why.strip() for why in chains_mod.COUNTERFLOW.values()),
         "每条逆向边都写清为什么剪它"),
        (all(pair in {(a, b) for a, b, _ in chains_mod.CHAIN_LINKS}
             for pair in chains_mod.COUNTERFLOW),
         "逆向边都真的在连线表里，没有写错方向的幽灵边"),
    ]
    for ok, why in layer_self:
        if not ok:
            failures.append(f"链的层次：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    # 层次讲不讲得通，只有拿具体的链对比才知道。这几条是行业常识的方向。
    def _lv(cid):
        return lay.get(cid)
    order_cases = [
        (_lv("oil-gas") < _lv("chemicals"), "石油在化工上游"),
        (_lv("chemicals") < _lv("semiconductor"), "化工在半导体上游"),
        (_lv("semiconductor") < _lv("computing-hardware"), "半导体在计算硬件上游"),
        (_lv("computing-hardware") < _lv("software-cloud"), "计算硬件在软件云上游"),
        (_lv("mining-metals") < _lv("semiconductor"), "采矿在半导体上游"),
        (_lv("mining-metals") < _lv("automotive"), "采矿在汽车上游"),
        (_lv("utilities-power") < _lv("computing-hardware"), "电力在数据中心上游"),
        (_lv("textiles-apparel") < _lv("retail-distribution"), "纺织服装在零售上游"),
        # 第一版把采矿排到了半导体下面，就是靠这类对比才看出荒唐
        (_lv("mining-metals") < _lv("industrial-machinery") + 1,
         "采矿不该排在工业机械下游太远"),
    ]
    for ok, why in order_cases:
        if not ok:
            failures.append(f"层次方向：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    # 剪不干净就必须报错，不能悄悄给个错的层次
    print("  [--] 断环不干净时要报错：临时加一条制造新环的连线")
    _saved = list(chains_mod.CHAIN_LINKS)
    try:
        chains_mod.CHAIN_LINKS.append(("retail-distribution", "oil-gas", "临时造的环"))
        raised = False
        try:
            chains_mod.chain_layers()
        except RuntimeError:
            raised = True
        if not raised:
            failures.append("链的层次：制造出环之后仍然算出了层次，没有报错")
        print(f"  [{'OK' if raised else 'XX'}] 有环算不出层次时抛错，不给一个错的层次")
    finally:
        chains_mod.CHAIN_LINKS[:] = _saved

    # 上游重叠：本板块第一条公司 ↔ 公司的关系。它是两份申报名单的交集，
    # 最大的风险是**多算**——把同一条数两遍、或把重叠说成业务关系。
    # 夹具是手搓的小登记表，每条都能用手算出正确答案。
    print("\n── 上游重叠：两份名单的交集，只会少算不会多算 ────────────────────")
    peers_mod = _load(PEERS_PATH, "smelter_peers")
    fixture = {
        # 甲乙丙三家共用；甲乙再共用一家；丙自己独有一家；还有一条没人申报
        "CID000001": {"id": "CID000001", "name": "Alpha Smelter", "country": "日本",
                      "identifierType": "rmi-cid", "minerals": ["锡"],
                      "filers": ["AAA", "BBB", "CCC"]},
        "CID000002": {"id": "CID000002", "name": "Beta Refinery", "country": "德国",
                      "identifierType": "rmi-cid", "minerals": ["金"],
                      "filers": ["AAA", "BBB"]},
        "NAME:gamma": {"id": "NAME:gamma", "name": "Gamma Works", "country": "巴西",
                       "identifierType": "name-only", "minerals": ["钽"],
                       "filers": ["CCC"]},
        "NAME:orphan": {"id": "NAME:orphan", "name": "Orphan Ltd", "country": "美国",
                        "identifierType": "name-only", "minerals": ["钨"], "filers": []},
    }
    got = peers_mod.build_peers(fixture)
    comp = got["companies"]

    def _shared(sym, other):
        for row in comp.get(sym, {}).get("peers", []):
            if row["symbol"] == other:
                return row["shared"]
        return None

    peer_cases = [
        (comp["AAA"]["total"] == 2, "甲名单 2 家（手算）"),
        (comp["CCC"]["total"] == 2, "丙名单 2 家（手算）"),
        (got["pairs"] == 3, "三对：甲乙、甲丙、乙丙"),
        (_shared("AAA", "BBB") == 2, "甲乙共用 2 家"),
        (_shared("AAA", "CCC") == 1, "甲丙只共用 Alpha 一家"),
        (_shared("BBB", "CCC") == 1, "乙丙同上"),
        (_shared("AAA", "BBB") == _shared("BBB", "AAA"), "两边对称"),
        ("DDD" not in comp, "没申报过的公司不出现"),
        (all(r["filerCount"] >= 2 for r in got["concentration"]),
         "集中度榜只收被两家以上共同申报的——一家不构成集中"),
        (got["concentration"][0]["name"] == "Alpha Smelter",
         "集中度第一是被三家申报的 Alpha"),
        (got["concentration"] == sorted(got["concentration"],
                                        key=lambda r: -r["filerCount"]),
         "集中度榜按家数降序"),
        (got["concentrationTotal"] == 2,
         "集中度分母是「被两家以上共同申报」的 2 条（Alpha、Beta），不是全表"),
        (got["smeltersTotal"] == 4, "登记表总数照实给 4 条，含只有一家和无人申报的"),
    ]
    for ok, why in peer_cases:
        if not ok:
            failures.append(f"上游重叠：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    # 重叠数**不可能**超过任何一方的名单长度。这条是「多算」的照妖镜。
    over = []
    for sym, row in comp.items():
        for peer in row["peers"]:
            if peer["shared"] > row["total"] or peer["shared"] > peer["peerTotal"]:
                over.append((sym, peer["symbol"]))
    if over:
        failures.append(f"上游重叠：重叠数超过名单长度 {over}")
    print(f"  [{'OK' if not over else 'XX'}] 重叠数不超过任何一方的名单长度")

    # 语义：关系标签不得把重叠说成供应或合作
    label = peers_mod.RELATION.get("label", "")
    clean = not any(w in label for w in ("供应商", "合作", "客户", "供货"))
    if not clean:
        failures.append(f"上游重叠：关系标签把重叠说过头了——{label!r}")
    print(f"  [{'OK' if clean else 'XX'}] 关系标签没把重叠说成供应或合作")
    has_neg = "不表示" in label
    if not has_neg:
        failures.append("上游重叠：关系标签没写明它不表示业务往来")
    print(f"  [{'OK' if has_neg else 'XX'}] 关系标签写明「不表示两家之间有业务往来」")

    # 外国发行人的主代码选择。**这是撞码事故的唯一防线**：同一家公司有多个代码，
    # 选错不会报错，只会让一家美国公司的节点被一家外国公司悄悄顶掉。
    print("\n── 外国发行人：主代码选得稳，且绝不覆盖标普池 ────────────────────")
    ff = _load(FOREIGN_FETCH_PATH, "fetch_foreign_identity")
    asml = [{"ticker": "ASMLF", "exchange": "OTC"},
            {"ticker": "ASML", "exchange": "Nasdaq"}]
    baba = [{"ticker": "BBAAY", "exchange": "OTC"},
            {"ticker": "BABAF", "exchange": "OTC"},
            {"ticker": "BABA", "exchange": "NYSE"}]
    pick_cases = [
        (ff.pick_primary(asml, set())["ticker"] == "ASML",
         "ASML/ASMLF 选主板那个，不选 OTC 粉单"),
        (ff.pick_primary(baba, set())["ticker"] == "BABA", "三个代码选 NYSE 那个"),
        (ff.pick_primary(list(reversed(asml)), set())["ticker"] == "ASML",
         "换输入顺序结果不变——同一份数据必须永远选出同一个代码"),
        (ff.pick_primary(asml, {"ASML"})["ticker"] == "ASMLF",
         "主代码被占用就退到下一个，不硬抢"),
        (ff.pick_primary(asml, {"ASML", "ASMLF"}) is None,
         "全被占用返回 None——宁可少收一家，也不覆盖既有节点"),
        (ff.exchange_rank("NYSE") < ff.exchange_rank("OTC"), "NYSE 优先于 OTC"),
        (ff.exchange_rank("") > ff.exchange_rank("OTC"), "认不出的交易所排最后"),
    ]
    for ok, why in pick_cases:
        if not ok:
            failures.append(f"外国发行人主代码：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    # 撞码演练：拿真实标普代码当占用集，确认不会被顶掉
    sp_taken = {"AAPL", "NVDA", "MSFT"}
    fake = [{"ticker": "AAPL", "exchange": "NYSE"}, {"ticker": "AAPLX", "exchange": "OTC"}]
    got = ff.pick_primary(fake, sp_taken)
    ok = got and got["ticker"] == "AAPLX"
    if not ok:
        failures.append(f"外国发行人主代码：撞上标普代码时应退让，实际 {got}")
    print(f"  [{'OK' if ok else 'XX'}] 撞上标普代码时退让到备用代码，不覆盖苹果")

    # 付款表不是冶炼厂名单。这条闸门守的是**「说多」的最后一步**：
    # 判据判对了披露类型，可解析器仍从付款表里抠出了几行「冶炼厂」。
    # 艾芬豪那份 ESTMA 实测抽出一家叫「La India」的厂（印度、金）——
    # 那是一行付款记录，不是冶炼厂。
    print("\n── 付款表里抠出来的不是冶炼厂 ───────────────────────────────────")
    _PAY_ROWS = """<html><body>
      <p>Item 2.01 Resource Extraction Issuer Disclosure. ESTMA Report.</p>
      <table>
        <tr><th>Country</th><th>Payee</th><th>Mineral</th><th>Amount</th></tr>
        <tr><td>India</td><td>La India</td><td>Gold</td><td>150,000</td></tr>
        <tr><td>Canada</td><td>Federal Government</td><td>Gold</td><td>947,350,000</td></tr>
      </table></body></html>"""
    pay = load_form_sd()
    pay_parse = pay.parse_smelters(_PAY_ROWS)
    pay_kind = pay.disclosure_evidence(_PAY_ROWS, xbrl_tagged=True)
    pay_cases = [
        (pay_kind["kind"] == "resource-extraction",
         "付款报告判为资源开采付款（强特征 ESTMA）"),
        (pay_parse["rowsWithCid"] == 0,
         "付款表里没有 RMI 编号——这正是抽取器该起疑的地方"),
        (pay_parse["unique"] > 0,
         "解析器确实会从付款表里抠出行来（不假装它不会）"),
    ]
    for ok, why in pay_cases:
        if not ok:
            failures.append(f"付款表：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")
    # 判定成付款披露还不够，此前误发布的边文件必须撤回——不然页面会继续
    # 声称艾芬豪的供应链里有一家名叫「La India」的冶炼厂（那是个矿区）。
    # 撤回的判据必须窄：只撤「抓错了」，绝不撤「没抓到」。
    withdraw = load_extractor().should_withdraw
    withdraw_cases = [
        (withdraw({"state": "resource-extraction", "droppedAsPaymentRows": 2}),
         "判成付款披露、且确实从付款表抠出过行——撤回"),
        (not withdraw({"state": "resource-extraction", "droppedAsPaymentRows": 0}),
         "判成付款披露但本来就没抠出行——没有错数据要撤，不动"),
        (not withdraw({"state": "listed", "droppedAsPaymentRows": 5}),
         "本轮正常抽到名单的不撤"),
        (not withdraw({"state": "filed-no-list"}),
         "有申报无名单不撤——那是披露制度的上限，不是错数据"),
        (not withdraw({"state": "index-failed", "why": "HTTP 500"}),
         "取数失败不撤——删掉就成了拿删数据掩盖抓取失败"),
        (not withdraw({"state": "no-filing"}),
         "本轮查不到申报不撤"),
    ]
    for ok, why in withdraw_cases:
        if not ok:
            failures.append(f"撤回判据：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    print("\n── 供应商名单探针：许可这一问必须答，不能只答技术 ──────────────")
    # 这条探针曾经**只查 robots.txt**，报告一路绿灯、格式解得开、内容读得出，
    # 看着像张准入通行证——而许可这一问从头到尾没人答过。
    # robots 允许抓取 ≠ 许可允许再分发：前者是站长对爬虫的礼貌约定，
    # 后者决定本站能不能把它的内容整理成数据集重新发布。
    sup = load_module(os.path.join(os.path.dirname(EXTRACT_PATH),
                                   "probe_supplier_lists.py"), "probe_supplier_lists")
    lic_cases = [
        (getattr(sup, "LICENSE_CLASS", "") == "PRIV",
         "公司自行发布的文档定为 PRIV"),
        ("不许登记" in getattr(sup, "LICENSE_VERDICT", ""),
         "结论就是「不许登记」，不留模棱两可的措辞"),
        ("书面许可" in getattr(sup, "LICENSE_VERDICT", ""),
         "写明日后要接入的前置条件是拿到书面许可"),
        ("SUPPLY_CHAIN_SOURCES" in getattr(sup, "LICENSE_VERDICT", ""),
         "指向许可文档，读者查得到依据"),
    ]
    for ok, why in lic_cases:
        if not ok:
            failures.append(f"供应商名单探针：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    print("\n── 正文探针：数得准，才谈得上拿它下结论 ────────────────────────")
    # 这条探针的计数被用来判定「洛马／埃森哲／丹纳赫到底有没有名单」，
    # 也被用来判定「PDF 接不接」。**数错了就会得出错的结论**，所以钉住。
    body = load_module(os.path.join(os.path.dirname(EXTRACT_PATH),
                                    "probe_form_sd_body.py"), "probe_form_sd_body")
    _HTML = ("<html><body><h1>Conflict Minerals Report</h1>"
             "<table><tr><td>Gold</td><td>CID001234</td></tr></table>"
             "<script>var x = 'smelter smelter smelter';</script>"
             "<style>.a{content:'refiner'}</style>"
             "<ul><li>One</li><li>Two</li></ul></body></html>")
    tp = body._Text()
    tp.feed(_HTML)
    body_cases = [
        (tp.counts.get("table") == 1 and tp.counts.get("tr") == 1,
         "表格与行数得对"),
        (tp.counts.get("li") == 2,
         "项目符号也数——名单不一定排成表格"),
        ("smelter" not in tp.text(),
         "script 里的字不算正文：否则一段脚本就能把「有名单」的线索刷上去"),
        ("refiner" not in tp.text(),
         "style 里的字同样不算"),
        ("CID001234" in tp.text(),
         "表格里的编号要留在正文里——CID 是判定的决定性线索"),
        (body._HINTS["CID编号"].findall("CID001234 CID 001234 CID-001234")
         == ["CID001234", "CID 001234", "CID-001234"],
         "CID 三种写法都认（各家格式不一）"),
        (not body._HINTS["CID编号"].findall("ACID001234x"),
         "不把词中间的 CID 当编号"),
        (body.skip_reason("formsd2026.pdf") == "非 HTML",
         "PDF 现在仍被抽取器跳过——探针照实标出来，不假装它读了"),
    ]
    for ok, why in body_cases:
        if not ok:
            failures.append(f"正文探针：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    print("\n── 国别：折成真国家，且说清是从哪个字段来的 ──────────────────────")
    region = load_module(os.path.join(os.path.dirname(EXTRACT_PATH), "edgar_region.py"),
                         "edgar_region")
    # 代码表从 EDGAR 自己的配对里长出来：别家申报带了描述，就用它补上这一家。
    code_map = region.build_code_map([
        ("F5", "TAIWAN"), ("F5", "TAIWAN"), ("A6", "Ontario, Canada"),
        ("V8", "Switzerland"), ("XX", ""), ("", "Japan"),
    ])
    _TSMC = {"stateOfIncorporation": "F5",
             "addresses": {"business": {"stateOrCountry": "F5"}}}
    _ALCON = {"stateOfIncorporation": "V8",
              "addresses": {"business": {"stateOrCountry": "TX",
                                         "stateOrCountryDescription": "TX"}}}
    _NOTHING = {"addresses": {"business": {}}}
    region_cases = [
        (region.split_region("Ontario, Canada") == ("Canada", "Ontario"),
         "「Ontario, Canada」折成加拿大＋安大略——46 家加拿大公司不该占 6 行"),
        (region.split_region("Canada (Federal Level)") == ("Canada", None),
         "「Canada (Federal Level)」也是加拿大"),
        (region.split_region("Korea, Republic of") == ("Korea, Republic of", None),
         "「Korea, Republic of」整条保留——按最后一个逗号硬拆会得出一个叫「Republic of」的国家"),
        (region.split_region("Taiwan, Province of China")[0] == "Taiwan, Province of China",
         "ISO 倒装写法不拆"),
        (region.split_region("Israel") == ("Israel", None),
         "本来就是国名的原样返回"),
        # ── 离岸法域识别。EDGAR 用倒装式国名，第一版按自己顺口的说法写表，
        #    63 家 BVI 注册的公司一家都没命中，而两栏数字一模一样看不出来。
        (region.is_offshore("Virgin Islands, British"),
         "EDGAR 的倒装写法要命中——BVI 是这一池的第 4 大注册地，漏了就白改"),
        (region.is_offshore("British Virgin Islands"),
         "正读写法同样命中，两种拼法必须等价"),
        (region.is_offshore("Cayman Islands") and region.is_offshore("Marshall Islands"),
         "开曼与马绍尔（航运注册）"),
        (not region.is_offshore("Korea, Republic of"),
         "倒装归一不能把真国家误判成离岸——Korea, Republic of 是国家"),
        (not region.is_offshore("Luxembourg") and not region.is_offshore("Cyprus"),
         "有真实经济体量的主权国家不进这张表：只在注册地明显只是登记地时才改口径"),
        (not region.is_offshore("") and not region.is_offshore(None),
         "空值不算离岸"),
        (region.operating_location(
            {"addresses": {"business": {"stateOrCountry": "F4",
                                        "stateOrCountryDescription": "China"}}},
            code_map)["country"] == "China",
         "营业地解析：注册在开曼的中国公司，办公室在中国——176 家是这个情况"),
        (region.operating_location(
            {"addresses": {"business": {"stateOrCountry": "TX",
                                        "stateOrCountryDescription": "TX"}}},
            code_map) == {"country": "United States", "region": "TX",
                          "basis": "business-address"},
         "营业地问的是「办公室在哪」，美国州码在这里是有效答案——"
         "与 resolve_country() 拒绝它是两个不同的问题"),
        (region.operating_location(_NOTHING, code_map)["country"] is None,
         "没有地址就返回空，不猜"),
        (region.split_region("") == (None, None),
         "空值返回空，不编造"),
        (region.describe("F5", None, code_map) == "TAIWAN",
         "只有代码没有描述时，查 EDGAR 别处给出的同一代码"),
        (region.describe("ZZ9", None, code_map) is None,
         "代码表里没有、又不是美国州代码——留空不猜"),
        (region.describe("NY", None, code_map) == "NY",
         "美国州代码原样返回，交给上层判定——这一池里它基本是美国办公室，不是国别"),
        (region.describe(None, "DC", code_map) == "DC",
         "描述字段里直接躺着两字母代码时也认出来（壳牌那条 description 就是 'DC'）"),
        (region.resolve_country(
            {"stateOfIncorporation": "", "stateOfIncorporationDescription": "DC",
             "addresses": {"business": {"stateOrCountry": "V8",
                                        "stateOrCountryDescription": "Switzerland"}}},
            code_map)["country"] == "Switzerland",
         "注册地只说到美国某个州时跳过它、换下一个字段，不硬写成美国"),
        (region.resolve_country(
            {"stateOfIncorporationDescription": "DC", "addresses": {"business": {}}},
            code_map)["country"] is None,
         "全部字段都只说到美国某个州就是未归类——把壳牌说成美国公司是错的"),
        (region.resolve_country(
            {"stateOfIncorporationDescription": "DC", "addresses": {"business": {}}},
            code_map)["countryRejected"] == ["state-of-incorporation=DC"],
         "并记下是哪个字段被判定不可用，「为什么没有国别」在数据里查得到"),
        (region.resolve_country(_TSMC, code_map)["country"] == "TAIWAN",
         "台积电：营业地址没有描述，靠代码表补出来（此前这一家国别是空的）"),
        # EDGAR 地址块有两套并行字段。境外公司的国别在 country / countryCode /
        # foreignStateTerritory 里，stateOrCountry 是 None——只读后者的话，
        # 恰恰是台积电、本田、沃达丰这些最典型的外国公司全成了空值。
        (region.address_country({"country": "Taiwan", "countryCode": "F5",
                                 "foreignStateTerritory": "Hsinchu",
                                 "stateOrCountry": None}) == ("Taiwan", "Hsinchu"),
         "境外地址：从 country / foreignStateTerritory 读，不是 stateOrCountry"),
        (region.address_country({"stateOrCountry": "CA",
                                 "stateOrCountryDescription": "California"}) == (None, None),
         "美国境内地址没有 country 字段，这条路返回空、交给原来那套"),
        (region.address_country({}) == (None, None), "空地址块返回空"),
        # country 字段里也会写「省, 国」。第一版这条快路原样返回，
        # 四家加拿大公司当场又按省分行——这一轮开头修掉的 bug 从新代码路径复发。
        (region.address_country({"country": "Ontario, Canada"}) == ("Canada", "Ontario"),
         "country 字段里写着「省, 国」时照样折成加拿大，不绕过 split_region"),
        (region.address_country({"country": "Canada (Federal Level)"}) == ("Canada", None),
         "「Canada (Federal Level)」在这条路上也折成加拿大"),
        (region.address_country({"country": "Ontario, Canada",
                                 "foreignStateTerritory": "ON"}) == ("Canada", "ON"),
         "有 foreignStateTerritory 时用它当下级地区，没有才用逗号前那半"),
        (region.resolve_country(
            {"stateOfIncorporation": "",
             "addresses": {"business": {"country": "Taiwan",
                                        "foreignStateTerritory": "Hsinchu",
                                        "stateOrCountry": None}}},
            code_map)["country"] == "Taiwan",
         "台积电真实形状：注册地为空、境外地址补上——16 家全空就是这么来的"),
        (region.resolve_country(
            {"stateOfIncorporation": "V8",
             "stateOfIncorporationDescription": "Switzerland",
             "addresses": {"business": {"country": None, "stateOrCountry": "TX",
                                        "stateOrCountryDescription": "TX"}}},
            code_map)["country"] == "Switzerland",
         "加了境外字段之后，爱尔康仍然是注册地瑞士优先，没被营业地址盖掉"),
        (region.resolve_country(
            {"stateOfIncorporationDescription": "DC",
             "addresses": {"business": {"country": "United Kingdom"}}},
            code_map)["country"] == "United Kingdom",
         "壳牌：DC 被跳过后落到境外地址的英国，不再是未归类"),
        (region.resolve_country(_ALCON, code_map)["country"] == "Switzerland",
         "爱尔康：注册地瑞士优先于营业地址的 TX——TX 是它的美国办公室，不是国别"),
        (region.resolve_country(_ALCON, code_map)["countryBasis"] == "state-of-incorporation",
         "并记下这个结论取自注册地，页面照实标"),
        (region.resolve_country(_NOTHING, code_map)["country"] is None,
         "什么字段都没有就是未归类——宁可留空，不硬塞一个国家"),
        (region.build_code_map([("a6", "Ontario, Canada")]).get("A6") == "Ontario, Canada",
         "代码大小写归一"),
        (region.build_code_map([("F5", "")]) == {},
         "只有代码没有描述的配对进不了表——那是要补的对象，不是依据"),
    ]
    for ok, why in region_cases:
        if not ok:
            failures.append(f"国别：{why} 不成立")
        print(f"  [{'OK' if ok else 'XX'}] {why}")

    total = (len(pdf_cases) + 4 + len(kind_cases) + len(symbol_cases) + len(split_cases) + len(skip_cases) + len(CASES) * 2 + len(NEGATIVE) + len(CONTEXT_CASES) + len(SIC_CASES)
             + len(FORM_SD_CASES) + 6 + len(writes)
             + len(zh_cases) + len(rank_cases) + len(threshold_cases) + 1
             + len(index_cases) + len(quarter_cases) + len(dir_cases)
             + len(chain_cases) + len(chain_self) + len(guard_cases)
             + len(link_self) + len(loop_cases) + len(layer_self) + len(order_cases) + 1 + len(peer_cases) + 3 + len(pick_cases) + 1 + len(pay_cases) + len(withdraw_cases) + len(region_cases) + len(body_cases) + len(lic_cases)
             + len(xbrl_cases) + len(xbrl_name_cases) + len(title_cases))
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

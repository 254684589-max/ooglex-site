#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成产业链图谱：节点表、价值链阶段口径，以及关系边的索引。

**本脚本不联网、不自己造边。** 节点骨架来自 `apps/companies/sp500.json`
（站内每日更新的标普成分股清单）；关系边由 `extract_form_sd.py` 从 SEC 申报里抽取后
写在 `apps/supply-chain/edges/` 下，本脚本只负责读取、索引与逐条校验。

## 这一层做什么

1. 回答「每家公司处在产业链的哪一段」。SIC 行业码能判的用 SIC，判不了的退回板块级；
   板块横跨多个阶段时不给结论，只给候选集。
2. 把 `edges/` 下各公司的边汇成 `edgeIndex`，并对**每一条**边跑一遍证据契约。

## 边不内联在 nodes.json 里

一家公司的冶炼厂名单动辄几百条。全塞进 nodes.json，总览页为了看六个环节就得下载
几 MB，而它一条边都不需要。改为每家一个文件、公司页按需拉自己那一个；nodes.json
只留索引，索引里带出处链接，不必先下文件就知道有没有边、边从哪来。

## 契约对每一条边生效，不管它存在哪个文件里

边必须携带可核验的原始申报文件（见 `evidence` 契约）。`assert_edge_contract()` 在写盘前
逐条硬校验所有边文件里的所有边，任何一条不合格即中止，不写文件。

模型「知道」台积电给英伟达代工——但没有出处的行业知识不是数据来源。本脚本不含
任何硬编码的公司间关系。

## 板块级口径的诚实处理

GICS 一级板块粒度明显不够：同属「科技」的英伟达（芯片设计，中间制造）与微软
（软件平台，平台服务）产业链位置完全不同；「医疗健康」同样横跨制药生产、器械
制造与医疗服务。这类板块的节点会被标 `stageAmbiguous: true` 并说明原因，
**页面必须显示这个歧义，不得把板块级推断显示成公司级结论。**

歧义节点数由 `health.json` 跟踪，随 SIC 行业码细化与真实边反推逐步下降。
"""
from __future__ import annotations

import importlib.util
import json
import os
from datetime import datetime, timezone

CONTRACT_VERSION = 1
DATASET = "supply-chain-graph"

SOURCE_PATH = "apps/companies/sp500.json"
# SIC 缓存由 fetch_company_identity.py 联网生成。缺失时自动退回板块级口径——
# 一次取数失败不该让整条管道产出空数据或直接失败。
IDENTITY_PATH = "apps/supply-chain/identity.json"
OUT_DIR = "apps/supply-chain"
NODES_PATH = os.path.join(OUT_DIR, "nodes.json")
HEALTH_PATH = os.path.join(OUT_DIR, "health.json")
# 关系边不内联在 nodes.json 里：一家公司的冶炼厂名单动辄几百条，全塞进来会让
# 总览页为了看六个环节而下载几 MB。改为每家一个文件，公司页按需拉自己那一个。
EDGES_DIR = os.path.join(OUT_DIR, "edges")
SMELTERS_PATH = os.path.join(OUT_DIR, "smelters.json")
# 公司两两之间的上游重叠。单独一个文件：只有公司页用得上，
# 总览页不该为了六个环节多下 120KB。
PEERS_PATH = os.path.join(OUT_DIR, "peers.json")
# 第二个公司池：在美上市的外国私人发行人里同时报 Form SD 的那一批。
# 由 fetch_foreign_identity.py 生成；缺失时只出标普那 495 家，不中断构建。
FOREIGN_PATH = os.path.join(OUT_DIR, "foreign.json")
DOMESTIC_PATH = os.path.join(OUT_DIR, "domestic.json")

# ── 价值链阶段定义 ──────────────────────────────────────────────────────────
# 八段实物链 + 四层使能层。chain=True 的在实物流转链条上、按 order 首尾相接；
# chain=False 的横跨整条链，不参与流转（能源是投入、金融是外围服务）。
STAGES = [
    {"id": "raw-material", "label": "资源开采", "labelEn": "Raw Materials",
     "order": 1, "chain": True, "description": "矿产、油气与农林原料的开采"},
    {"id": "material-processing", "label": "材料加工", "labelEn": "Materials Processing",
     "order": 2, "chain": True, "description": "冶炼、化工、炼油与造纸，产出下游的投入品"},
    {"id": "component", "label": "零部件与元器件", "labelEn": "Components",
     "order": 3, "chain": True, "description": "半导体、电子元件与金属结构件"},
    {"id": "capital-equipment", "label": "资本设备", "labelEn": "Capital Equipment",
     "order": 4, "chain": True, "description": "供给制造环节的机械与专用设备"},
    {"id": "finished-goods", "label": "整机与品牌", "labelEn": "Finished Goods & Brands",
     "order": 5, "chain": True, "description": "面向终端市场的整机、成药与消费品牌"},
    {"id": "logistics", "label": "物流与运输", "labelEn": "Logistics & Transport",
     "order": 6, "chain": True, "description": "铁路、货运、空运与货代，链条的连接组织"},
    {"id": "distribution", "label": "分销与零售", "labelEn": "Distribution & Retail",
     "order": 7, "chain": True, "description": "批发与零售渠道"},
    {"id": "end-service", "label": "终端服务", "labelEn": "End Services",
     "order": 8, "chain": True, "description": "医疗、住宿、客运与售后等面向消费者的服务"},
    {"id": "energy-utility", "label": "能源与公用事业", "labelEn": "Energy & Utilities",
     "order": 9, "chain": False, "description": "电力、燃气与水务——是制造业的投入品，不是外围服务"},
    {"id": "technology", "label": "技术与平台", "labelEn": "Technology & Platforms",
     "order": 10, "chain": False, "description": "软件、电信承载与内容平台"},
    {"id": "financial", "label": "金融与专业服务", "labelEn": "Financial & Professional",
     "order": 11, "chain": False, "description": "银行、保险、地产与工程会计等专业服务"},
    {"id": "circular", "label": "循环与废弃物", "labelEn": "Circular & Waste",
     "order": 12, "chain": False, "description": "废弃物处理与材料回收，逆向供应链"},
]
STAGE_IDS = {s["id"] for s in STAGES}

# ── GICS 一级板块 → 价值链阶段的初步映射 ────────────────────────────────────
# 只有板块与阶段一一对应时才给出结论。板块横跨多个阶段时**不给结论**，改为给候选集：
# 「微软 = 中间制造」即使加了歧义标记，也是对一家真实公司的错误断言；
# 「微软 = 待细化（可能：中间制造/品牌整合/平台服务）」才是这份数据实际支持的说法。
# 候选集会随 SIC 行业码或真实上下游边收敛为单一阶段。
SECTOR_STAGE_MAP: dict[str, dict] = {
    "Financials": {"stage": "financial"},
    "Real Estate": {"stage": "financial"},
    "Utilities": {"stage": "energy-utility"},
    "Energy": {
        "candidates": ["raw-material", "material-processing"],
        "reason": "能源板块横跨油气开采与炼制，板块级分不开埃克森与康菲的位置"},
    "Materials": {
        "candidates": ["raw-material", "material-processing", "component"],
        "reason": "原材料板块横跨采矿、冶炼与金属加工件"},
    "Industrials": {
        "candidates": ["capital-equipment", "finished-goods", "logistics"],
        "reason": "工业板块横跨资本设备、整机制造与运输物流，三者在链上位置完全不同"},
    "Information Technology": {
        "candidates": ["component", "capital-equipment", "finished-goods", "technology"],
        "reason": "科技板块同时含半导体（元器件）、半导体设备（资本设备）、"
                  "整机（品牌）与软件（技术平台），同板块的英伟达、应用材料、"
                  "苹果与微软位置完全不同"},
    "Communication Services": {
        "candidates": ["technology", "end-service"],
        "reason": "通信服务横跨网络承载、内容平台与娱乐服务"},
    "Consumer Discretionary": {
        "candidates": ["finished-goods", "distribution", "end-service"],
        "reason": "可选消费横跨整车与耐用品制造、零售分销与消费服务"},
    "Consumer Staples": {
        "candidates": ["finished-goods", "distribution"],
        "reason": "必需消费横跨食品饮料生产与商超分销"},
    "Health Care": {
        "candidates": ["finished-goods", "component", "end-service"],
        "reason": "医疗健康横跨制药与器械（成品）、诊断试剂（投入品）与医疗服务"},
}


def load_sic_resolver():
    """载入 SIC → 阶段映射。模块缺失时返回 None，构建退回板块级口径。"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sic_stages.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("sic_stages", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_region():
    """载入 EDGAR 地理归一模块。

    离岸判定**在构建时现算**，不用 foreign.json 里存着的那个标记。
    理由：那张表改一次，存下来的标记就全过期了，要重新联网取数才能生效——
    而判定规则的修正远比取数频繁。第一版把 BVI 写成 "British Virgin Islands"、
    EDGAR 实际写 "Virgin Islands, British"，63 家一家没命中；修好归一之后
    若还依赖存下来的标记，就得再跑一轮 25 分钟的取数才看得到效果。

    缺失时返回 None：地理汇总退回注册地口径，不中断构建。
    """
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "edgar_region.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("edgar_region", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_chain_resolver():
    """载入 SIC → 一级产业链映射（图的横轴）。缺失时返回 None，节点不带链，
    页面照常显示纵轴——与 SIC 阶段判定同一条退路，不因为缺一张表就中断构建。"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sic_chains.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("sic_chains", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_foreign_pool() -> dict:
    """读外国私人发行人池。没有这个文件就是「还没取过」，不是错误。"""
    try:
        with open(FOREIGN_PATH, encoding="utf-8") as handle:
            return (json.load(handle) or {}).get("companies") or {}
    except (OSError, ValueError):
        return {}


def load_domestic_pool() -> dict:
    """读报 10-K 的美国本土发行人池（标普之外的那批）。缺文件不是错误。"""
    try:
        with open(DOMESTIC_PATH, encoding="utf-8") as handle:
            return (json.load(handle) or {}).get("companies") or {}
    except (OSError, ValueError):
        return {}


def load_peers_builder():
    """载入上游重叠的计算模块。缺失时返回 None，本轮不写 peers.json——
    与 SIC 那两张表同一条退路，不因为缺一个模块就中断构建。"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "smelter_peers.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("smelter_peers", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_smelter_registry() -> dict:
    """读冶炼厂登记表本体（算上游重叠要用它的 filers）。"""
    try:
        with open(SMELTERS_PATH, encoding="utf-8") as handle:
            return (json.load(handle) or {}).get("smelters") or {}
    except (OSError, ValueError):
        return {}


def load_identity() -> dict:
    """读 SIC 缓存。没有就返回空——阶段判定退回板块级，不中断构建。"""
    try:
        with open(IDENTITY_PATH, encoding="utf-8") as handle:
            return (json.load(handle) or {}).get("companies") or {}
    except (OSError, ValueError):
        return {}


def load_edge_files() -> dict[str, dict]:
    """读 edges/ 下每家公司的关系边文件。目录不存在就是「还没有边」，不是错误。"""
    if not os.path.isdir(EDGES_DIR):
        return {}
    loaded: dict[str, dict] = {}
    for name in sorted(os.listdir(EDGES_DIR)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(EDGES_DIR, name)
        try:
            with open(path, encoding="utf-8") as handle:
                payload = json.load(handle)
        except (OSError, ValueError) as exc:
            # 坏文件不能当成「这家没有边」悄悄跳过——那会把故障显示成事实。
            raise SystemExit(f"{path} 读不出来（{exc}），中止构建")
        symbol = payload.get("symbol") or name[:-5]
        if symbol != name[:-5]:
            raise SystemExit(f"{path} 里的 symbol={symbol!r} 与文件名不符，中止")
        loaded[symbol] = payload
    return loaded


def load_form_sd_coverage() -> dict | None:
    """冶炼厂登记表里的覆盖率。没有这个文件就说明抽取器还没跑过。"""
    try:
        with open(SMELTERS_PATH, encoding="utf-8") as handle:
            return (json.load(handle) or {}).get("coverage")
    except (OSError, ValueError):
        return None


# 流向图上直接列出的国别数。其余并入「其他」——不是省略，是把长尾收拢，
# 合计仍等于总边数。列太多的话每条带子细到看不见，反而什么都读不出来。
FLOW_TOP_COUNTRIES = 8


def country_exposure(bundles: dict[str, dict], listed: int) -> list[dict]:
    """按冶炼厂所在国别，算两个**含义完全不同**的数。

    - `edges`：多少条关系跑经该国——图谱里有多少分量落在那里；
    - `filers`：多少家申报人的名单里出现过该国的厂——**暴露面有多宽**。

    这两个数经常排出完全不同的名次，而只印其中一个会把风险读反：
    印度尼西亚按条数排第 4（6.6%），按暴露家数却排第 1（118 家，高于中国的
    107 家）——几乎每一家有名单的公司都沾到印尼的锡。Sankey 画的是
    环节 → 国别的流量，回答不了「多少家公司沾到某国」，所以单列这一份。

    语义与别处一致：**只是「该国的冶炼厂出现在这些公司的名单里」**，
    不是采购关系，也不表示这些公司之间有往来。
    """
    edges: dict[str, int] = {}
    filers: dict[str, set] = {}
    for symbol, bundle in bundles.items():
        for edge in (bundle.get("edges") or []):
            key = edge.get("country") or "未写明"
            edges[key] = edges.get(key, 0) + 1
            filers.setdefault(key, set()).add(symbol)
    rows = [{
        "country": c,
        "edges": edges[c],
        "filerCount": len(filers[c]),
        # 逐家列出，页面可以点开反查——与集中度那块同一套读法。
        "filers": sorted(filers[c]),
        # 占「有名单的公司」的比例。分母不是全池 642 家：没有名单的公司
        # 不可能暴露在任何国别上，混进分母会把每一档都稀释成假的小数。
        "filerShare": round(len(filers[c]) / listed, 4) if listed else 0,
    } for c in edges]
    rows.sort(key=lambda r: (-r["filerCount"], -r["edges"], r["country"]))
    return rows



# 按链切的风险读数各留多少行。页面上这两块本来就折叠，取前 12 行够读，
# 再多每行细到看不清；行数不够时页面照实说「另有 N 行未列出」，不静默截断。
CHAIN_RISK_ROWS = 12


def chain_risk(nodes: list[dict], bundles: dict[str, dict], registry: dict) -> dict:
    """按产业链切一份风险读数：国别暴露 + 上游集中度。

    ## 为什么非切不可

    页面允许筛出某一条产业链。筛完之后环节卡跟着变，而「真实流向 / 上游集中度 /
    国别暴露」这三块此前**一动不动**——读者筛到半导体，环节卡显示 48 家，
    往下滚读到的却是 23 条链合计的「31,320 条关系、72 个国别、128 家分母」。

    **在筛选语境下印全局数字，并且一个字不说，等于把全局风险说成这条链的风险。**
    这是这个板块最该避免的一类错：数字本身没错，错在它回答的不是读者以为的
    那个问题。

    ## 集中度为什么要从登记表重算

    不能拿全局榜单前 30 去按链筛。那样留下的只有「既是全局咽喉、又属于这条链」
    的厂，而**一条链自己的咽喉点很可能根本不在全局前 30 里**——半导体的关键
    冶炼厂未必是被最多公司共同列入的那几家。按链筛全局榜单会漏掉它们，
    还看不出漏了。所以从登记表全量重算，每条链各排各的。

    ## 口径不变

    仍然只是「该冶炼厂／该国的厂出现在这些申报人的名单里」——共同暴露，
    不是采购关系，也不表示这些公司之间有业务往来。分母是**这条链里有名单的
    公司数**，不是这条链的全部公司数：没有名单的公司不可能暴露在任何国别上。
    """
    # stage_flow 定义在本函数之后，Python 到调用时才解析名字，顺序无妨。
    members: dict[str, set] = {}
    for node in nodes:
        if not node.get("edgeCount"):
            continue                            # 没名单的公司进不了任何分母
        for cid in (node.get("chains") or []):
            members.setdefault(cid, set()).add(node["symbol"])

    out: dict[str, dict] = {}
    for cid, symbols in members.items():
        sub_bundles = {s: b for s, b in bundles.items() if s in symbols}
        if not sub_bundles:
            continue
        expo = country_exposure(sub_bundles, len(sub_bundles))
        for row in expo:
            row.pop("filers", None)             # 逐家反查留给全局那一份，按链只报数
        conc = []
        for row in (registry or {}).values():
            hit = sorted({f for f in (row.get("filers") or []) if f} & symbols)
            if len(hit) < 2:                    # 只被一家列入不叫「集中」
                continue
            conc.append({
                "id": row.get("id"),
                "name": row.get("name"),
                "nameZh": row.get("nameZh"),
                "country": row.get("country"),
                "minerals": row.get("minerals") or [],
                "identifierType": row.get("identifierType"),
                "filerCount": len(hit),
                "filers": hit,
            })
        conc.sort(key=lambda r: (-r["filerCount"], str(r["name"] or "")))
        # 这条链自己的「环节 → 国别」流向。全局那份只有 1.75KB，24 条链加起来
        # 约 42KB（gzip 后 4KB），完全划算——上一轮因为没有它，只能在页面上
        # 写「这张图仍是全池口径」，那是照实声明，不是应该长期留着的状态。
        chain_nodes = [n for n in nodes if n["symbol"] in symbols]
        out[cid] = {
            "flow": stage_flow(chain_nodes, sub_bundles),
            "filers": len(sub_bundles),
            "edges": sum(len(b.get("edges") or []) for b in sub_bundles.values()),
            "countries": len(expo),
            "exposure": expo[:CHAIN_RISK_ROWS],
            "exposureTotal": len(expo),
            "concentration": conc[:CHAIN_RISK_ROWS],
            "concentrationTotal": len(conc),
        }
    return out


def stage_flow(nodes: list[dict], bundles: dict[str, dict]) -> dict:
    """环节 → 冶炼厂所在国别的实测流量。

    **这是全站唯一一处「流量」有实测含义的地方。** 图谱里那条价值链
    （上游 → 中间 → 品牌 → 分销）是定义顺序，没有环节到环节的关系数据；
    真正逐条挂着申报出处的，只有「公司 → 冶炼厂」这一层。所以带子的粗细
    只能画这个，别的都是编的。

    在这里预先算好，是因为按国别汇总要读全部边文件；让浏览器为了一张总览图
    去下几十个文件，页面就废了。
    """
    stage_of = {n["symbol"]: n.get("stage") for n in nodes}
    matrix: dict[str, dict[str, int]] = {}
    totals: dict[str, int] = {}
    relations: dict[str, str] = {}
    for symbol, bundle in bundles.items():
        stage = stage_of.get(symbol)
        if not stage:
            continue
        # 语义从边文件里读，不在这里另写一份常量：两处各写一份，抽取器改了
        # 这里就开始说旧话。
        rel = bundle.get("relation") or {}
        if rel.get("id"):
            relations[rel["id"]] = rel.get("label") or ""
        row = matrix.setdefault(stage, {})
        for edge in bundle.get("edges") or []:
            # 国别缺失如实记成「未归类」，不丢掉也不猜——丢掉会让合计对不上，
            # 猜一个国家就是编数据。
            key = edge.get("country") or "未归类"
            row[key] = row.get(key, 0) + 1
            totals[key] = totals.get(key, 0) + 1
    top = [c for c, _ in sorted(totals.items(), key=lambda kv: -kv[1])[:FLOW_TOP_COUNTRIES]]
    flows = []
    for stage, row in matrix.items():
        packed = {c: row.get(c, 0) for c in top}
        rest = sum(row.values()) - sum(packed.values())
        if rest:
            packed["其他"] = rest
        flows.append({"stage": stage, "total": sum(row.values()),
                      "byCountry": {k: v for k, v in packed.items() if v}})
    flows.sort(key=lambda r: -r["total"])
    order = top + (["其他"] if any("其他" in f["byCountry"] for f in flows) else [])
    # 多种关系混在一张图里的话，带子宽度就不是同一件事了，必须拦下。
    if len(relations) > 1:
        raise SystemExit(f"流向图里出现多种关系语义 {sorted(relations)}，"
                         "带子宽度会失去统一含义，中止")
    relation_id = next(iter(relations), None)
    return {
        "relation": relation_id,
        "relationLabel": relations.get(relation_id or "", ""),
        "countries": order,
        "countryTotals": {c: (totals.get(c) if c != "其他"
                              else sum(f["byCountry"].get("其他", 0) for f in flows))
                          for c in order},
        "distinctCountries": len(totals),
        "stages": flows,
        # 没有任何边的环节不会出现在 stages 里，但页面要把它画成 0 条的死头，
        # 所以把「谁一条都没有」也算出来——空缺得画出来，不能只画有数据的部分。
        "stagesWithoutEdges": sorted({n.get("stage") for n in nodes if n.get("stage")}
                                     - set(matrix)),
        "note": ("带子宽度是实测关系条数，不是示意。语义与边文件一致："
                 "该冶炼厂出现在申报人的供应链中——间接、不含份额、不是直接供货。"
                 "只覆盖有冶炼厂名单的公司，其余公司不出现在本图中。"),
    }


def sector_coverage(nodes: list[dict], filing_status: dict[str, str],
                    key: str = "sector", label: str = "sector") -> list[dict]:
    """按某个维度统计覆盖情况，并区分「没抓到」和「本来就不适用」。

    `key` 是分组字段：标普那池按 GICS 板块（sector），外国发行人那池按国别
    （country）——它们没有站内板块分类，全塞进「未分类」等于一个 147 家的
    黑箱，读者看不出任何东西。

    页面上金融 0/70 与科技 34/84 是两种完全不同的 0。前者是 Form SD 的适用范围
    决定的——规则只管产品中含 3TG 的发行人，银行没有产品；后者是这一轮没抓到，
    以后可能补上。混在一起报，读者会把制度上限误读成抓取缺陷。

    这里只统计事实（这家申报了没有、正文列名单没有），不给「该不该申报」下结论：
    某家公司为什么不申报是它自己的判断，本函数无从得知，也不替它回答。
    """
    buckets: dict[str, dict] = {}
    for node in nodes:
        sector = node.get(key) or "未分类"
        row = buckets.setdefault(sector, {
            label: sector,
            "sectorEn": node.get("sectorEn") if key == "sector" else None,
            "companies": 0,
            "withEdges": 0,
            "filedNoList": 0,
            "noFiling": 0,
            "resourceExtraction": 0,
            "failed": 0,
            "unscanned": 0,
        })
        row["companies"] += 1
        if node.get("edgeCount"):
            row["withEdges"] += 1
            continue
        state = filing_status.get(node["symbol"])
        if state == "filed-no-list":
            row["filedNoList"] += 1
        elif state == "no-filing":
            row["noFiling"] += 1
        elif state == "resource-extraction":
            # 申报的是资源开采付款，不是冲突矿产——那套披露里没有冶炼厂这个概念
            row["resourceExtraction"] += 1
        elif state == "failed":
            row["failed"] += 1
        elif state == "listed":
            # 扫描说有名单、但边文件没写成：抽取器与发布路径不一致，属于缺陷，
            # 不能算进「无申报」蒙混过去。
            row["failed"] += 1
        else:
            # 没有逐家状态（抽取器还没跑过带 filingStatus 的版本）。
            # 不猜原因，单列一档。
            row["unscanned"] += 1
    return sorted(buckets.values(), key=lambda r: -r["companies"])


def assert_edge_contract(bundles: dict[str, dict]) -> None:
    """无证据不上图：写盘前硬校验，不靠自觉。

    契约 v2：出处在**文件级**——同一份申报里所有边的出处本就相同，提到文件级之后
    结构上不可能出现某条边指向别的出处或没有出处。每条边则必须有 `row`，
    把核验落到原始文档的具体一行。

    任何一条不合格即中止，不写文件——宁可不发布，也不发布来路不明的公司间关系。
    """
    allowed_confidence = {"disclosed", "inferred"}
    for symbol, bundle in sorted(bundles.items()):
        where = f"edges/{symbol}.json"
        if bundle.get("confidence") not in allowed_confidence:
            raise ValueError(f"{where}：confidence 必须是 {allowed_confidence}，"
                             f"实际 {bundle.get('confidence')!r}")
        if not (bundle.get("relation") or {}).get("label"):
            raise ValueError(f"{where}：缺少 relation.label，边的语义必须随数据发布")
        evidence = bundle.get("evidence")
        if not isinstance(evidence, dict) or not evidence:
            raise ValueError(f"{where}：没有 evidence，拒绝写入")
        for field in ("sourceType", "url", "docDate"):
            if not evidence.get(field):
                raise ValueError(f"{where} evidence：缺少可核验字段 {field}")
        if not str(evidence.get("url")).startswith("https://"):
            raise ValueError(f"{where} evidence：出处必须是可点开的 https 链接")
        for i, edge in enumerate(bundle.get("edges") or []):
            if not edge.get("from"):
                raise ValueError(f"{where} edges[{i}]：缺少 from")
            if not isinstance(edge.get("row"), int) or edge["row"] < 1:
                raise ValueError(f"{where} edges[{i}] {edge.get('from')}：缺少 row 定位")


def load_members() -> tuple[list[dict], dict]:
    with open(SOURCE_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)
    members = payload.get("members") or []
    if not members:
        raise SystemExit(f"{SOURCE_PATH} 里没有成分股，中止（不产出空文件覆盖有效数据）")
    return members, payload


def build_node(member: dict, identity: dict, sic_module, chain_module=None) -> dict:
    sector_en = member.get("sector") if member.get("sector") in SECTOR_STAGE_MAP else member.get("sectorEn")
    mapping = SECTOR_STAGE_MAP.get(sector_en or "")
    node = {
        "id": member.get("symbol"),
        "symbol": member.get("symbol"),
        # 站内公司榜给的名字优先（它对标普成分股本来就多半是中文）；
        # 榜上只有英文的，再查中文名对照表。**两个来源要有明确先后**——
        # 表接上来之前，Uber、Kenvue 这两条一直是孤儿：键没错，只是标普池
        # 根本不查这张表，而孤儿检查如实报了出来。
        "name": (member.get("name") if member.get("name") != member.get("nameEn")
                 else (names_zh.name_for(member.get("nameEn")) or member.get("name"))),
        "nameEn": member.get("nameEn"),
        "sector": member.get("sector"),
        "sectorEn": member.get("sectorEn"),
        "marketCap": member.get("marketCap"),
        "logo": member.get("logo"),
        "listed": True,
        # 边要靠 CIK 锚定实体，第 0 层还没有——如实留空，不猜。
        "cik": None,
        "sic": None,
        "sicDescription": None,
    }
    if not mapping:
        # 板块对不上映射表时如实标未知，不塞默认值。
        node["stage"] = None
        node["stageCandidates"] = []
        node["stageBasis"] = "unknown"
        node["stageAmbiguous"] = True
        node["stageNote"] = f"板块 {member.get('sectorEn')!r} 不在映射表中，未判定阶段"
    elif mapping.get("stage"):
        node["stage"] = mapping["stage"]
        node["stageCandidates"] = [mapping["stage"]]
        node["stageBasis"] = "sector-initial"
        node["stageAmbiguous"] = False
    else:
        # 歧义板块不给结论，只给这份数据实际支持的候选集。
        node["stage"] = None
        node["stageCandidates"] = list(mapping["candidates"])
        node["stageBasis"] = "sector-ambiguous"
        node["stageAmbiguous"] = True
        node["stageNote"] = mapping["reason"]

    apply_identity(node, identity.get(node["symbol"]) or {}, sic_module, chain_module)
    return node


def apply_identity(node: dict, record: dict, sic_module, chain_module=None) -> dict:
    """把 SEC 的 CIK／SIC 落到节点上，并据此判环节与产业链。

    **两个公司池共用这一份。** 标普那侧的 record 来自 identity.json，外国发行人
    那侧来自 foreign.json，字段形状一样（cik / sic / sicDescription）。
    各写一套的话，改了一处另一处就开始按旧规则判——而判定依据那一列会照样显示，
    没有任何东西会报错。
    """
    # ── SIC 升级：板块级判不出来的，用 SEC 行业码再判一次 ──────────────────
    # 只在 SIC 能给出结论时覆盖，且如实记录依据；SIC 判不了就保留板块级结果。
    if record.get("cik"):
        node["cik"] = int(record["cik"])
    if record.get("sic"):
        node["sic"] = int(record["sic"])
        node["sicDescription"] = record.get("sicDescription")
        # 两位大类：把一个环节拆成看得见的构成（「中间制造 142 家」→
        # 仪器仪表 39 / 半导体 31 / …）。只是把 SEC 的码换成中文名，
        # 不改归属；认不出就不写这个字段，页面显示原始码。
        major = sic_module.major_group(record["sic"]) if sic_module else None
        if major:
            node["sicMajor"] = major["code"]
            node["sicMajorLabel"] = major["label"]
            node["sicMajorLabelEn"] = major["labelEn"]
    resolved = sic_module.resolve(record.get("sic")) if sic_module else None
    if resolved:
        node["stage"] = resolved["stage"]
        node["stageCandidates"] = [resolved["stage"]]
        node["stageBasis"] = "sic-refined"
        node["stageAmbiguous"] = False
        node["stageNote"] = f"SIC {resolved['sic']}：{resolved['reason']}"
        node["stageEvidence"] = {
            "sourceType": "sec-submissions-sic",
            "url": f"https://data.sec.gov/submissions/CIK{int(record['cik']):010d}.json"
                   if record.get("cik") else None,
            "sic": resolved["sic"],
            "match": resolved["basis"],
        }

    # ── 横轴：这家公司在哪条产业链上 ────────────────────────────────────
    # 与纵轴同一个输入（申报的 SIC 码）、同一条退路（判不出就不写）。
    # 一家可以在多条链上——SIC 3533 油气田机械既在油气链也在工业机械链，
    # 硬压成一条才是失真。**链是分类，不是边**：同一条链上的两家公司之间
    # 有没有供应关系，只有申报文件说了算。
    chains = chain_module.resolve_chains(record.get("sic")) if chain_module else None
    if chains:
        node["chains"] = chains["chains"]
        node["chainBasis"] = chains["basis"]
        node["chainNote"] = chains["note"]
    else:
        node["chains"] = []
        node["chainBasis"] = "unknown"
    return node


def load_company_names_zh():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "company_names_zh.py")
    spec = importlib.util.spec_from_file_location("company_names_zh", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


names_zh = load_company_names_zh()


def _country_map() -> dict[str, str]:
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "form_sd_parse.py")
    spec = importlib.util.spec_from_file_location("_form_sd_for_nodes", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.COUNTRIES


_COUNTRIES_ZH: dict[str, str] | None = None


def country_zh(name: str | None) -> str | None:
    """SEC 写的国名 → 中文名。表里没有的**原样返回**，不硬塞译名。

    这个站是中文站，国别列一半中文一半英文会很难看；但认不出来时照原文写，
    比按字面猜一个译名强——猜错一个国名就是把一家公司放到别的国家去。
    """
    global _COUNTRIES_ZH
    if not name:
        return None
    if _COUNTRIES_ZH is None:
        _COUNTRIES_ZH = _country_map()
    return _COUNTRIES_ZH.get(name.strip().lower(), name.strip())


def build_foreign_node(record: dict, sic_module, chain_module=None,
                      region_module=None) -> dict:
    """外国私人发行人的节点。

    与标普那侧最大的不同是**没有站内报价**：`marketCap` 与当日涨跌都取不到。
    这里如实留 None，绝不用 0 顶替——0 会被市值加权当成真值算进去，
    等于凭空造一个「市值为零」的公司。环节涨跌的分母也因此不含这批公司，
    构建日志与页面都要把这件事说出来。
    """
    symbol = record.get("symbol")
    # 离岸判定现算，不读 record 里存着的标记——见 load_region() 的注释。
    offshore = bool(region_module.is_offshore(record.get("country"))
                    if region_module else record.get("offshoreIncorporation"))
    node = {
        "id": symbol,
        "symbol": symbol,
        # 中文名只在确有通用叫法时才有（台积电、阿斯麦这类）；
        # 给不出可靠译名的 name 就等于 nameEn，页面照英文原文显示。
        # 半译出来的名字看着像中文名，其实是编的，比英文原文更糟。
        "name": names_zh.name_for(record.get("name")) or record.get("name") or symbol,
        "nameEn": record.get("name") or symbol,
        # 站内板块分类只覆盖标普成分股，这批公司没有，如实留空——
        # 环节与产业链都由 SIC 判，不依赖板块。
        "sector": None,
        "sectorEn": None,
        "marketCap": None,
        "logo": None,
        "listed": True,
        "pool": "sec-foreign-issuer",
        # country 是国家的中文名（页面显示用），countryEn 保留 SEC 的原文，
        # region 是它下面那一级（省／州）。三个分开存，页面要哪个取哪个——
        # 曾经只存一个字段、把「Ontario, Canada」整条当国别，
        # 于是「按国别」的表里加拿大出现了六次。
        "country": country_zh(record.get("country")),
        "countryEn": record.get("country"),
        "region": record.get("region"),
        # 这个国别是从注册地还是营业地址来的。两者偏差方向不同
        # （注册地偏向开曼／泽西这类控股架构，营业地址偏向美国办公室），
        # 页面必须照实标，不能让读者以为它是「公司总部在哪」。
        "countryBasis": record.get("countryBasis"),
        # ── 注册地 ≠ 产业地理 ───────────────────────────────────────────
        # 1,194 家里 415 家注册在开曼／BVI／马绍尔／百慕大这类只做登记的
        # 法域，开曼一家就 340 家，是全池第一大「国家」——而没有一家公司
        # 在那里生产任何东西。实测：这 415 家的营业地址 **100% 定得出位置**，
        # 折回去是中国 176、新加坡 43、香港 37、希腊 19（马绍尔注册的航运）。
        #
        # 所以按地理汇总时用 geoCountry：离岸注册的用营业地，其余不变。
        # **注册地本身照样留着**（country／countryEn），不是改写而是并存——
        # 公司页两个都显示，读者要能看出这家是「注册开曼、经营在中国」。
        #
        # 折完仍落在离岸法域的 51 家不是缺陷：SEC 手上只有那个地址，
        # 说「只知道注册在开曼」是诚实答案，猜一个国家才是编。
        "offshoreIncorporation": offshore,
        "operatingCountry": country_zh(record.get("operatingCountry")),
        "operatingCountryEn": record.get("operatingCountry"),
        "operatingRegion": record.get("operatingRegion"),
        "operatingBasis": record.get("operatingBasis"),
        "geoCountry": country_zh(record.get("operatingCountry")
                                 if offshore and record.get("operatingCountry")
                                 else record.get("country")),
        "exchange": record.get("exchange"),
        "cik": None,
        "sic": None,
        "sicDescription": None,
        "stage": None,
        "stageCandidates": [],
        "stageBasis": "unknown",
        "stageAmbiguous": True,
        "stageNote": "外国私人发行人，站内无板块分类；环节由 SEC 行业码判定",
    }
    apply_identity(node, record, sic_module, chain_module)
    return node


def stage_performance(members: list[dict], nodes: list[dict], source_payload: dict) -> dict:
    """各产业链环节今日表现：把已判定阶段的公司按环节汇总当日涨跌。

    只做汇总，不重算行情——价格与涨跌全部沿用站内 `sp500.json` 已有的值，
    口径、来源与数据日跟着它走，不另建第二套事实来源。

    诚实要求：
    - 阶段未判定（`pending`）的公司不进任何环节，单独计数，**不摊到别处**；
    - 报价过期（`stale`）的不计入均值，单独计数——过期值混进均值会伪造当日表现；
    - 同时给等权与市值加权两个口径并标明，不用其中一个冒充「该环节表现」。
    """
    stage_of = {n["symbol"]: n.get("stage") for n in nodes}
    buckets: dict[str, list[dict]] = {}
    pending = stale = no_quote = 0
    for member in members:
        symbol = member.get("symbol")
        stage = stage_of.get(symbol)
        if not stage:
            pending += 1
            continue
        change = member.get("changePct")
        if change is None:
            no_quote += 1
            continue
        if member.get("stale"):
            stale += 1
            continue
        buckets.setdefault(stage, []).append(
            {"changePct": float(change), "marketCap": float(member.get("marketCap") or 0.0)})

    rows = []
    for stage in STAGES:
        items = buckets.get(stage["id"]) or []
        if not items:
            rows.append({"stage": stage["id"], "label": stage["label"], "companies": 0,
                         "equalWeightPct": None, "capWeightPct": None, "medianPct": None})
            continue
        changes = sorted(item["changePct"] for item in items)
        cap_total = sum(item["marketCap"] for item in items)
        middle = len(changes) // 2
        median = (changes[middle] if len(changes) % 2
                  else (changes[middle - 1] + changes[middle]) / 2)
        rows.append({
            "stage": stage["id"],
            "label": stage["label"],
            "companies": len(items),
            "equalWeightPct": round(sum(changes) / len(changes), 2),
            "capWeightPct": (round(sum(i["changePct"] * i["marketCap"] for i in items) / cap_total, 2)
                             if cap_total > 0 else None),
            "medianPct": round(median, 2),
        })
    return {
        "asOf": source_payload.get("asOf"),
        "source": "站内 apps/companies/sp500.json",
        "method": ("按价值链环节汇总当日涨跌；等权与市值加权并列给出，不互相冒充。"
                   "行情值沿用站内成分股文件，未重算。"),
        "stages": rows,
        "excluded": {
            "stageNotResolved": pending,   # 阶段未判定，不摊入任何环节
            "staleQuote": stale,           # 报价过期，不计入均值
            "noQuote": no_quote,
        },
    }


def build() -> None:
    members, source_payload = load_members()
    identity = load_identity()
    sic_module = load_sic_resolver()
    chain_module = load_chain_resolver()
    region_module = load_region()
    nodes = [build_node(m, identity, sic_module, chain_module)
             for m in members if m.get("symbol")]
    for node in nodes:
        node["pool"] = "sp500"

    # ── 第二个池：外国私人发行人 ──────────────────────────────────────────
    # 公司池此前只有标普 500，半导体链上没有 ASML 和台积电根本画不出来。
    # 代码冲突在取数那一步就跳过了，这里再挡一道：撞码不会报错，只会让一家
    # 美国公司的节点被外国公司悄悄顶掉，而页面上看不出任何异常。
    foreign_pool = load_foreign_pool()
    taken = {n["symbol"] for n in nodes}
    foreign_nodes = []
    dropped_collision = []
    for symbol in sorted(foreign_pool):
        if symbol in taken:
            dropped_collision.append(symbol)
            continue
        taken.add(symbol)
        foreign_nodes.append(
            build_foreign_node(foreign_pool[symbol], sic_module, chain_module,
                               region_module))
    if dropped_collision:
        print(f"[!!] 外国发行人有 {len(dropped_collision)} 个代码与标普池相同，"
              f"已跳过（不覆盖）：{'、'.join(dropped_collision[:10])}")
    nodes.extend(foreign_nodes)

    # ── 第三个池：报 10-K 的美国本土发行人（标普之外）────────────────────
    # 探针实测 SEC 这条路的上限是 6,076 家，此前只收了 1,688 家——差的就是
    # 这一批。**它比按标普成分收许可更干净**：指数成分名单是指数商的专有
    # 数据，10-K 全量是政府公开记录。
    #
    # 与外国发行人那池同一套节点构建：没有站内报价（marketCap 恒为 None，
    # 不是 0）、没有站内板块分类，环节与产业链全由 SIC 判。
    # 撞码同样只跳不覆盖——这一池排在最后，撞了就是它让路。
    domestic_pool = load_domestic_pool()
    domestic_nodes = []
    dropped_domestic = []
    for symbol in sorted(domestic_pool):
        if symbol in taken:
            dropped_domestic.append(symbol)
            continue
        taken.add(symbol)
        node = build_foreign_node(domestic_pool[symbol], sic_module, chain_module,
                                  region_module)
        # 池标识要分开：页面按池说明「为什么没有市值」，两池的理由不同——
        # 外国发行人是站内行情只覆盖标普，本土非成分股是同一个原因，
        # 但读者要能看出这家到底属于哪一批，不能混成一个「非标普」黑箱。
        node["pool"] = "sec-domestic-filer"
        node["stageNote"] = ("报 10-K 的美国本土发行人（非标普成分股），"
                             "站内无板块分类；环节由 SEC 行业码判定")
        domestic_nodes.append(node)
    if dropped_domestic:
        print(f"[!!] 本土发行人有 {len(dropped_domestic)} 个代码与前两池相同，"
              f"已跳过（不覆盖）：{'、'.join(dropped_domestic[:10])}")
    nodes.extend(domestic_nodes)

    # 关系边：抽取器写在 edges/ 下，本脚本只读、只索引、只校验，不自己造边。
    edge_files = load_edge_files()
    all_edges = [e for payload in edge_files.values() for e in (payload.get("edges") or [])]
    assert_edge_contract(edge_files)  # 契约对每个边文件与其每一条边生效

    edge_index: dict[str, dict] = {}
    edges_by_source: dict[str, int] = {}
    for symbol, payload in sorted(edge_files.items()):
        rows = payload.get("edges") or []
        evidence = payload.get("evidence") or {}
        edge_index[symbol] = {
            "file": f"edges/{symbol}.json",
            "count": len(rows),
            "relation": (payload.get("relation") or {}).get("id"),
            "filingDate": evidence.get("filingDate"),
            "url": evidence.get("url"),
        }
        key = evidence.get("sourceType") or "unknown"
        edges_by_source[key] = edges_by_source.get(key, 0) + len(rows)
    node_ids = {n["id"] for n in nodes}
    for node in nodes:
        node["edgeCount"] = edge_index.get(node["id"], {}).get("count", 0)
    orphans = sorted(set(edge_index) - node_ids)
    if orphans:
        # 边文件指向节点表里没有的公司：多半是成分股调整后遗留的旧文件。
        # 留着会让公司页显示一份不再属于任何节点的名单。
        raise SystemExit(f"边文件 {orphans} 不在节点表中，中止（请删除或重跑抽取器）")

    # ── 上游重叠：本板块第一条公司 ↔ 公司的关系 ──────────────────────────
    # 它是两份原始申报的**直接交集**（甲的名单里有 X、乙的名单里也有 X），
    # 不是推断。语义就到这里为止：共同暴露，不是业务往来。
    peers_module = load_peers_builder()
    peers = None
    if peers_module:
        registry = load_smelter_registry()
        if registry:
            peers = peers_module.build_peers(registry)

    form_sd_coverage = load_form_sd_coverage()

    # 逐家申报状态盖到节点上，再按板块汇总。这是为了回答一个具体问题：
    # 「为什么有的公司有数据、有的没有」。金融 0/70、房地产 0/29 不是抓取失败——
    # Form SD 只适用于产品中含 3TG 的发行人，银行和 REIT 没有产品，本来就不申报。
    # 把这件事算出来写进数据，而不是在页面上凭印象断言。
    filing_status = (form_sd_coverage or {}).get("filingStatus") or {}
    for node in nodes:
        state = filing_status.get(node["symbol"])
        if state:
            node["formSdStatus"] = state
    # 两个池分开统计。标普那池按 GICS 板块（读者熟悉的口径，也是缺口成因最能
    # 讲清楚的维度：金融 0/70 是制度上限，科技 34/84 是还没抓到）；外国发行人
    # 那池没有站内板块分类，按国别拆——全塞进「未分类」就是一个 147 家的黑箱。
    # 三个池各按各自最能说清缺口的维度拆。
    #
    # 标普池按 GICS 板块（读者熟悉，也最能讲清成因：金融 0/70 是制度上限）。
    # 外国发行人按经营地。**本土 10-K 申报人这一池两样都没有**——站内公司榜
    # 只收标普成分股，所以它们没有板块；它们又几乎全是美国公司，按国别拆
    # 只会得到一行「美国 4,180 家」。
    #
    # 如果不给它单独一栏，这 4,180 家会掉进标普那栏的「未分类」——
    # 一个比此前担心过的「147 家黑箱」大 28 倍的黑箱。按 SIC 大类拆：
    # 那是它们唯一有的、且本板块全程都在用的分类轴。
    by_sector = sector_coverage(
        [n for n in nodes if n.get("pool") == "sp500"], filing_status)
    foreign_nodes_all = [n for n in nodes if n.get("pool") == "sec-foreign-issuer"]
    domestic_nodes_all = [n for n in nodes if n.get("pool") == "sec-domestic-filer"]
    by_sic_major = sector_coverage(domestic_nodes_all, filing_status,
                                   key="sicMajorLabel", label="sector")
    # 按**经营地**汇总，不按注册地。见节点构建处那段：注册地这一栏的第一名
    # 是开曼群岛 340 家，它回答不了「这条产业链在哪」。
    by_country = sector_coverage(foreign_nodes_all, filing_status,
                                 key="geoCountry", label="sector")
    # 国别是从哪个字段来的，逐档计数。注册地与营业地址偏差方向不同，
    # 页面得照实说是哪一种，不能笼统说成「公司在哪个国家」。
    country_basis: dict[str, int] = {}
    for node in foreign_nodes_all:
        key = node.get("countryBasis") or "unknown"
        country_basis[key] = country_basis.get(key, 0) + 1
    # 中文名覆盖情况。**没有中文名不是缺口**：加拿大初级矿商本来就没有通用
    # 中文名，显示英文原文是正确结果。报这个数是为了让「对照表写错了」露头——
    # 表里有一条却在数据里找不到对应公司，就说明那条键抄错了。
    zh_named = sum(1 for n in foreign_nodes_all if n.get("name") != n.get("nameEn"))
    # 孤儿检查要扫**所有**用这张表的池子。只扫外国发行人的话，接到标普池
    # 上的条目会被误报成孤儿（本轮 Uber、Kenvue 就是这么冒出来的）。
    live_names = ({n.get("nameEn") for n in foreign_nodes_all}
                  | {n.get("nameEn") for n in nodes if n.get("pool") == "sp500"})
    zh_orphans = sorted(k for k in names_zh.NAMES if k not in live_names)
    if zh_orphans:
        print(f"[!!] 中文名对照表里有 {len(zh_orphans)} 条在数据里找不到对应公司"
              f"（键抄错了）：{'、'.join(zh_orphans[:5])}")
    # 边文件还在、但最近一轮扫描没再抽到名单的公司。抽取器**不删有效历史数据**
    # （AGENTS.md：不得删除有效历史数据来掩盖抓取失败），所以文件保留着上一轮的
    # 结果；但覆盖率报的是本轮扫描口径，两个数就会差几家。
    # 差额必须由数据解释，不能留成一个说不清的 1。
    #
    # 判据是「本轮没抽到名单」，不是某一个具体状态。曾经只列 filed-no-list，
    # 结果一批被改判成 13q-1 资源开采付款的公司边文件还在、状态却变成了
    # resource-extraction，差额一家都没进这张表，契约直接拦下发布。
    # 差额的定义只能是「有边 且 本轮状态不是 listed」，包括本轮压根没扫到的。
    stale = sorted(n["symbol"] for n in nodes
                   if n.get("edgeCount") and filing_status.get(n["symbol"]) != "listed")
    flow = stage_flow(nodes, edge_files)
    # 按链切的风险读数。见 chain_risk() 的注释：页面能筛链，风险面板就必须
    # 跟着筛，否则筛选语境下印的是全局数。
    by_chain_risk = chain_risk(nodes, edge_files, registry if peers_module else {})
    exposure = country_exposure(edge_files, len(edge_files))

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    by_stage: dict[str, int] = {}
    for node in nodes:
        key = node.get("stage") or "pending"     # 未判定单独计，不并进任何一段
        by_stage[key] = by_stage.get(key, 0) + 1
    by_basis: dict[str, int] = {}
    for node in nodes:
        key = node.get("stageBasis") or "unknown"
        by_basis[key] = by_basis.get(key, 0) + 1
    # ── 横轴统计 ──────────────────────────────────────────────────────
    # 只统计，不新建归属：家数从节点上已有的 chains 数出来，改不了任何一家的链。
    chain_links = chain_module.chain_links() if chain_module else []
    chain_cross = dict(chain_module.CROSS_CUTTING) if chain_module else {}
    # 层次由连线算出（最长路径），不手工排——手排的话改一条连线，层次就和连线
    # 对不上，而且没人看得出对不上。算不出来时宁可不给层次，不给个错的。
    chain_depth = 0
    chain_layer: dict[str, int] = {}
    if chain_module:
        try:
            layers = chain_module.chain_layers()
            chain_layer = layers["layer"]
            chain_depth = layers["depth"]
        except RuntimeError as exc:
            print(f"[!!] 链的层次算不出来，本轮不写 layer 字段：{exc}")

    chain_rows: list[dict] = []
    if chain_module:
        chain_edges: dict[str, int] = {}
        for node in nodes:
            for cid in node.get("chains") or []:
                chain_edges[cid] = chain_edges.get(cid, 0) + (node.get("edgeCount") or 0)
        counts: dict[str, int] = {}
        for node in nodes:
            for cid in node.get("chains") or []:
                counts[cid] = counts.get(cid, 0) + 1
        for cid, zh, en in chain_module.CHAINS:
            row = {
                "id": cid, "label": zh, "labelEn": en,
                "count": counts.get(cid, 0),
                "edgeCount": chain_edges.get(cid, 0),
            }
            # 使能链不参与分层：它们横跨全链，硬塞进某一层是假的。
            if cid in chain_layer:
                row["layer"] = chain_layer[cid]
            chain_rows.append(row)
    chain_unclassified = sum(1 for n in nodes if not (n.get("chains") or []))
    chain_multi = sum(1 for n in nodes if len(n.get("chains") or []) > 1)

    resolved = sum(1 for n in nodes if n.get("stage"))
    ambiguous = sum(1 for n in nodes if n.get("stageBasis") == "sector-ambiguous")
    unknown = sum(1 for n in nodes if n.get("stageBasis") == "unknown")

    payload = {
        "contractVersion": CONTRACT_VERSION,
        "dataset": DATASET,
        "updatedAt": now,
        "asOf": source_payload.get("asOf"),
        "frequency": "daily",
        "status": "ok",
        "source": "站内 apps/companies/sp500.json",
        "sourceUpstream": source_payload.get("listSource"),
        "note": ("节点与价值链阶段口径。阶段由 GICS 一级板块映射得出，"
                 "属板块级推断。板块横跨多个阶段时不给结论，只给 stageCandidates 候选集——"
                 "「微软=中间制造」即使加歧义标记也是错误断言，"
                 "「微软=待细化（可能：中间制造/品牌整合/平台服务）」才是数据实际支持的说法。"
                 "关系边不内联在本文件里，按公司分文件放在 edges/ 下、由 edgeIndex 索引——"
                 "一家公司的冶炼厂名单动辄几百条，内联会让总览页为看六个环节下载几 MB。"
                 "每条边都必须携带可核验的原始申报文件，写盘前逐条硬校验。"),
        "stages": STAGES,
        # 横轴：一级产业链。counts 在这里算好，页面不必遍历 495 个节点再统计。
        # multi 是「同时在多条链上」的家数——这个数不小，是这套模型的常态而非例外。
        "chains": chain_rows,
        # 链与链之间的上下游。**这是产业结构框架，不是实测的公司间关系**：
        # 「半导体的上游包含化工」与「半导体属于零部件层」同类，是定义不是断言。
        # 与 edgeIndex 指向的那两万条严格分开——那些每条都指名申报人与冶炼厂、
        # 都能点开原始申报。两者在数据、页面、文案三处都不得混为一谈。
        "chainLinks": chain_links,
        "chainCrossCutting": chain_cross,
        # 上游集中度：一家冶炼厂被多少家申报人共同列入。榜单放这里是因为总览页
        # 已经会下 nodes.json，不必为十几行多发一次请求；逐家的重叠在 peers.json。
        "upstreamConcentration": (peers or {}).get("concentration") or [],
        # 逐链一份，键是链 id。页面筛到某条链时用这一份，不筛时用上面那份全局的。
        "chainRisk": by_chain_risk,
        # 按国别的暴露面。edges 与 filerCount 是两个不同的读数，页面两个都印
        # ——只印一个会把风险读反（见 country_exposure 的说明）。
        "countryExposure": exposure,
        "nodes": nodes,
        # 每家一个文件，公司页按需拉。索引里带出处链接，不必先下文件才知道有没有边。
        "edgeIndex": edge_index,
        "stagePerformance": stage_performance(members, nodes, source_payload),
        # 环节 → 冶炼厂国别的实测流量。全站唯一一处带子宽度有实测含义的图，
        # 在这里预算好，页面不必为一张总览图去下几十个边文件。
        "flow": flow,
        "coverage": {
            "claimComplete": False,
            # 横轴覆盖：未归类的家数要露出来，为 0 才说明这张表覆盖到了全部申报码。
            "chainsTotal": len(chain_rows),
            "chainUnclassified": chain_unclassified,
            "chainLinksTotal": len(chain_links),
            "chainDepth": chain_depth,
            # 两个池分开计数。合成一个数会让读者以为 642 家都有市值与当日涨跌，
            # 而外国发行人那批站内没有报价。
            "poolSp500": sum(1 for n in nodes if n.get("pool") == "sp500"),
            "poolForeignIssuer": len(foreign_nodes),
            # 第三池：报 10-K 的美国本土发行人（标普之外）。与前两池分开计数——
            # 三批公司的「为什么没有市值」理由不同，混成一个数就说不清了。
            "poolDomesticFiler": len(domestic_nodes),
            "poolForeignSkippedCollision": len(dropped_collision),
            "nodesWithoutQuote": sum(1 for n in nodes if n.get("marketCap") is None),
            "upstreamPairs": (peers or {}).get("pairs", 0),
            "upstreamConcentrationTotal": (peers or {}).get("concentrationTotal", 0),
            "chainCounterflow": sum(1 for l in chain_links
                                    if l.get("direction") == "counterflow"),
            "chainMulti": chain_multi,
            "nodesTotal": len(nodes),
            "nodesWithEdges": sum(1 for n in nodes if n["edgeCount"]),
            "edgesTotal": len(all_edges),
            "edgesBySource": edges_by_source,
            # 抽取器实测到的申报形态。「有申报无名单」必须与「无申报」分开——
            # Form SD 强制申报、不强制列名单，两者混在一起会把披露制度的上限
            # 说成抓取失败。
            "formSd": form_sd_coverage,
            # 按板块拆开的覆盖情况。缺口的成因写在数据里，页面照实读。
            "bySector": by_sector,
            # 外国发行人按国别。字段名沿用 sector 是为了让页面复用同一套渲染，
            # 但语义是国别——页面上必须写清楚，不能让读者以为这是板块。
            "byCountry": by_country,
            # 第三池按 SIC 大类。键名沿用 sector（与另两栏同一套渲染），
            # 语义是行业大类——页面必须写清，不能让读者以为是 GICS 板块。
            "bySicMajor": by_sic_major,
            # 上面那一栏的国别各自来自哪个 SEC 字段。页面照这个数说话。
            "countryBasis": country_basis,
            # 中文名：有通用译名的家数、对照表总条数、以及对不上号的条目。
            # orphans 非空就是对照表写错了，契约会拦。
            "foreignNameZh": {
                "named": zh_named,
                "glossary": len(names_zh.NAMES),
                "orphans": zh_orphans,
            },
            # 见上：边来自更早的扫描，本轮未复现。列出代码，读者可自己核对。
            "edgesFromEarlierScan": stale,
            # 按实际 stageBasis 分组。曾经把所有已判定的都记成 sector-initial，
            # 等于把 SIC 升级的功劳记在板块级口径头上、低报了数据质量的真实来源。
            "stageByBasis": by_basis,
            "stageResolvedNodes": resolved,
            "stageAmbiguousNodes": ambiguous,
            "note": ("本图谱只收录有公开出处的关系，不是完整供应链。"
                     + ("当前尚无关系边。" if not all_edges else
                        f"当前 {len(all_edges)} 条边全部来自 Form SD 冲突矿产申报，"
                        f"语义是「该冶炼厂出现在申报人的供应链中」——间接、不含份额、"
                        f"不含层级，不等于直接供货关系。")),
        },
        "dataQuality": {
            "contractVersion": CONTRACT_VERSION,
            "status": "ok",
            "total": len(nodes),
            "byStage": by_stage,
            "resolvedStage": resolved,
            "ambiguousStage": ambiguous,
            "unknownStage": unknown,
        },
    }

    health = {
        "contractVersion": CONTRACT_VERSION,
        "dataset": DATASET,
        "generatedAt": now,
        # 歧义不是故障：这是板块级数据的真实上限，如实报告即可。
        # 只有板块对不上映射表（unknown）才是需要修的问题。
        "status": "healthy" if unknown == 0 else "degraded",
        "historyStatus": "migrated",     # 首次建立，无历史可追溯
        "lastAttemptAt": now,
        "lastSuccessfulAt": now,
        "consecutiveFailures": 0,
        "failureReason": None,
        "coverage": {
            "expectedNodes": len(members),
            "publishedNodes": len(nodes),
            "stageResolvedPct": round(100.0 * resolved / len(nodes), 1) if nodes else 0.0,
            "stageAmbiguousPct": round(100.0 * ambiguous / len(nodes), 1) if nodes else 0.0,
            "edges": len(all_edges),
            "companiesWithEdges": len(edge_index),
        },
        "sources": ([{
            "id": "form-sd-smelters",
            "name": "SEC EDGAR Form SD 冲突矿产申报",
            "role": "edges",
            "status": "healthy",
            "mode": "filing",
            "frequency": "annual",
            "asOf": None,
            "upstream": {"dataset": "supply-chain-edges", "path": EDGES_DIR},
        }] if edge_index else []) + [{
            "id": "sp500-members",
            "name": "站内标普500成分股清单",
            "role": "upstream",
            "status": "healthy",
            "mode": "market",
            "frequency": "daily",
            "asOf": source_payload.get("asOf"),
            "upstream": {"dataset": "companies", "path": SOURCE_PATH},
        }],
        "note": ("构建脚本本身不发起外部请求，只读站内上游文件与抽取器产出的边文件。"
                 "stageAmbiguousPct 随 SIC 行业码细化与真实边反推逐步下降。"),
    }

    os.makedirs(OUT_DIR, exist_ok=True)
    for path, data in ((NODES_PATH, payload), (HEALTH_PATH, health)):
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")

    print(f"节点 {len(nodes)} 个 → {NODES_PATH}")
    print(f"  阶段分布：{by_stage}")
    print(f"  已判定阶段 {resolved}（{health['coverage']['stageResolvedPct']}%）；"
          f"仅给候选集 {ambiguous}；板块未登记 {unknown}")
    print(f"  口径来源：{by_basis}")
    print(f"  关系边 {len(all_edges)} 条，来自 {len(edge_index)} 家公司的边文件"
          f"（契约已逐条校验）")
    if edges_by_source:
        print(f"  边的出处：{edges_by_source}")
    if foreign_nodes:
        print(f"  外国私人发行人 {len(foreign_nodes)} 家已入池"
              f"（站内无报价，不参与环节涨跌与市值合计）")
    if chain_rows:
        print(f"  横轴：{len(chain_rows)} 条一级产业链，链间上下游 {len(chain_links)} 条"
              f"（框架，非实测关系）；{len(chain_cross)} 条标为横跨全链")
        if chain_depth:
            print(f"  层次：{chain_depth} 层（由连线算出），"
                  f"逆向边 {sum(1 for l in chain_links if l.get('direction') == 'counterflow')} 条")
    # peers.json 单独写盘。没算出来就不写，也不删旧的——与「不拿坏结果覆盖好数据」
    # 同一条规矩。
    if peers:
        peers_payload = {
            "contractVersion": CONTRACT_VERSION,
            "dataset": "supply-chain-peers",
            "updatedAt": now,
            "relation": peers_module.RELATION,
            "note": ("两家申报人的冶炼厂名单里出现了同一批冶炼厂，由两份原始申报的"
                     "交集得出，不含任何推断。**不表示两家之间有业务往来**，"
                     "表示的是上游冶炼环节的共同暴露。"
                     "只有名字的冶炼厂按规范化名字合并，同一家厂写法不同会被算成两条，"
                     "因此本口径**只会少算不会多算**。"),
            "coverage": {
                "companies": len(peers["companies"]),
                "pairs": peers["pairs"],
                "maxPeersPerCompany": peers["maxPeers"],
                "maxSharedPerCompany": peers["maxShared"],
                "understatesOverlap": True,
            },
            "companies": peers["companies"],
        }
        with open(PEERS_PATH, "w", encoding="utf-8") as handle:
            json.dump(peers_payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
        print(f"  上游重叠：{len(peers['companies'])} 家申报人、{peers['pairs']} 对"
              f" → {PEERS_PATH}")
        top = (peers.get("concentration") or [])[:1]
        if top:
            print(f"  上游集中度最高：{top[0]['name']}（{top[0]['filerCount']} 家共同申报）"
                  f"，榜单取前 {len(peers['concentration'])}/{peers['concentrationTotal']}")

    if form_sd_coverage:
        print(f"  Form SD：有名单 {form_sd_coverage.get('companiesWithList')} 家 · "
              f"有申报无名单 {form_sd_coverage.get('companiesFiledNoList')} 家 · "
              f"无申报 {form_sd_coverage.get('companiesNoFiling')} 家")
    perf = payload["stagePerformance"]
    active = [r for r in perf["stages"] if r["companies"]]
    print(f"  环节表现：{len(active)} 个环节有报价；"
          f"未判定阶段 {perf['excluded']['stageNotResolved']} 家不摊入、"
          f"过期报价 {perf['excluded']['staleQuote']} 家不计入均值")
    for row in active:
        print(f"    {row['label']:<6} {row['companies']:>3} 家  "
              f"等权 {row['equalWeightPct']:>6}%  市值加权 {row['capWeightPct']:>6}%  "
              f"中位 {row['medianPct']:>6}%")
    print(f"健康 → {HEALTH_PATH}  status={health['status']}")


if __name__ == "__main__":
    build()

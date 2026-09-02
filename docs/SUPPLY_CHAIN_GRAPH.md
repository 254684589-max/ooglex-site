# 全球产业链图谱：架构与证据规范

> 状态：**第 0 层已落地**（495 节点，0 关系边）
> 入口：`/apps/supply-chain/`　中文名称：全球产业链　英文名称：Global Supply Chain
> 姊妹文档：`docs/SUPPLY_CHAIN_SOURCES.md`（物流通道层的来源与许可）

## 1. 目标与诚实边界

**目标**：以标普 500 成分股为骨架，呈现每家公司在全球产业链中的位置，并可下钻查看
单家公司的上下游关系网——点开苹果看它的供应商链条，点开英伟达看它的。

**边界必须一开始就说清楚**：完整、准确的公司级全球供应链关系数据**不存在免费版本**。
做这门生意的是 Bloomberg SPLC、FactSet Supply Chain Relationships、S&P Capital IQ /
Panjiva、LSEG、Sayari、Interos，年费以万美元计。

因此本板块交付的**不是「完整产业链」，而是「可证据化的产业链子集」**：每一条关系都
来自公开申报文件或企业自披露，都能点开核验。页面必须显示覆盖率，**永远不得宣称完整**。

这不是能力不足的托词，而是产品定位：**一张 500 条有出处的边，价值高于 5000 条来路
不明的边**。后者在金融语境下是负资产。

## 2. 最高优先级规则：无证据不上图

模型「知道」台积电给英伟达代工、富士康组装 iPhone。**但没有出处的行业知识不是数据
来源**。把这类记忆写进 `data.json` 就是对真实企业断言未经证实的商业关系——违反
`AGENTS.md` 关于数据真实性的规定，也是本板块唯一不可挽回的错误类型。

因此：

1. **每条边必须携带非空 `evidence[]`**，否则不得写入发布文件。这由生成脚本硬校验，
   不是靠自觉。
2. **`evidence` 必须可点开核验**：原始文件 URL、文件日期、在文件中的定位。
3. **`confidence` 只有两档**：`disclosed`（申报或自披露原文写明）与 `inferred`
   （由规则从公开数据推导，必须写明推导方法）。**不得混用，不得把 inferred 显示成
   已确认关系。**
4. **模型生成的文本不得作为任何一条边的 evidence。** 文本摘要只能描述已有的边，
   不能创造边。

## 3. 免费的一手证据源

| 证据类型 | 来源 | 能得到什么 | 可规模化 |
|---|---|---|---|
| 客户集中度披露 | SEC EDGAR 10-K（ASC 280 强制披露占营收 10% 以上的客户） | 「X 公司 22% 营收来自苹果」——**反向即得苹果的重要供应商** | 是，全体美股上市公司 |
| 企业自披露供应商名单 | 苹果年度供应商名单等 | 直接的供应商清单，含工厂位置 | 否，仅少数公司 |
| 冲突矿产 Form SD | SEC 强制申报冶炼厂／精炼厂清单 | 通向**上游矿产**那一段 | 部分，数百家制造业公司 |
| 子公司清单 Exhibit 21 | 10-K 附件 | 集团内部结构 | 是 |

EDGAR 全部为美国政府公有领域作品，**零许可风险、零费用**，与 `SUPPLY_CHAIN_SOURCES.md`
「只用政府作品口径」是同一条纪律。SEC 要求声明身份的 User-Agent 并限速每秒 10 次，
本仓库脚本远低于该上限，联系方式从环境变量读取，不硬编码个人邮箱。

### 3.1 定位命中 ≠ 能抽出边

大量公司只写「一家客户占营收 22%」而**不写是谁**。这类段落是线索，不是边。
`scripts/supply-chain/probe_edgar_relationships.py` 因此把「命中披露段落数」与
「其中点名了对方的段落数」**分开报告**——后者才决定实际能拿到多少条边。

## 4. 数据模型

```jsonc
// 节点：公司。骨架来自站内已日更的 apps/companies/sp500.json，不另建事实来源。
{
  "id": "AAPL",                    // 上市公司用代码；非上市供应商用规范化名称
  "cik": 320193,                   // SEC 实体标识，来自 EDGAR，边的锚点
  "sic": 3571, "sicDescription": "Electronic Computers",
  "stage": "brand-integration",    // 价值链阶段，见第 5 节
  "stageBasis": "sector-initial",  // ← 口径来源，初步口径必须自报家门
  "listed": true
}

// 边：关系。没有 evidence 就不发布，由生成脚本硬校验。
{
  "from": "AVGO", "to": "AAPL",
  "type": "supplier",              // supplier / customer / smelter / subsidiary
  "confidence": "disclosed",       // disclosed | inferred，不得混用
  "evidence": [{
    "sourceType": "sec-10k-customer-concentration",
    "url": "https://www.sec.gov/Archives/edgar/data/.../avgo-20251102.htm",
    "docDate": "2025-12-12",
    "locator": "Item 1A. Risk Factors，客户集中度段落",
    "quote": "One customer ... accounted for approximately 20% of our net revenue"
  }]
}

// 覆盖率：与数据同级发布，页面必须显示，不得省略。
{
  "coverage": {
    "claimComplete": false,        // 永远为 false
    "nodesTotal": 495, "nodesWithEdges": 0,
    "edgesBySource": { "sec-10k-customer-concentration": 0, "apple-supplier-list": 0 },
    "note": "本图谱只收录有公开出处的关系，不是完整供应链"
  }
}
```

逐条数据仍沿用全站 `dataMeta` 契约（`mode`/`status`/`source`/`asOf`/`updatedAt`/
`frequency`/`note`），不新造字段。

## 5. 价值链阶段：初步口径与后续校正

按方案 C：**先用板块级初步口径上线并明确标注，第 2 层真实关系边完成后用实际上下游校正。**

| 阶段 | 含义 |
|---|---|
| `upstream-resource` | 上游资源：能源、原材料开采与初加工 |
| `intermediate-manufacturing` | 中间制造：零部件、设备、资本品 |
| `brand-integration` | 品牌整合：面向终端的品牌与系统集成 |
| `distribution-service` | 分销服务：零售、物流、终端服务 |
| `platform-service` | 平台服务：软件、互联网、通信平台 |
| `supporting` | 支持性行业：金融、地产、公用事业，不在实物链上 |

**初步口径的诚实要求**：当前只有 GICS 一级板块（11 类）可用，粒度明显偏粗——同属
「科技」的英伟达与微软，产业链位置完全不同。因此：

- 每个节点带 `stageBasis` 标明口径来源：`sector-initial`（板块与阶段一一对应，已判定）／
  `sector-ambiguous`（板块横跨多段，只给候选集）／`sic-refined`（SIC 行业码细化）／
  `edge-derived`（真实上下游边反推）／`unknown`（板块不在映射表内）；
- 页面必须显示当前口径级别，**不得把板块级推断显示成公司级结论**；
- 第 2 层完成后逐节点升级 `stageBasis`，升级过程可见、可回退。

### 5.1 歧义板块不给结论，只给候选集

第 0 层首版曾给每个节点一个单一阶段并附 `stageAmbiguous` 标记。实测输出后否决了这个做法：
**苹果、英伟达、微软会同时被标成「中间制造」**——对微软和苹果都是错的。加了歧义标记也不行，
页面上出现「微软 = 中间制造」就是对一家真实公司的错误断言，与仓库「不用默认值静默覆盖
有效数据」的规则冲突。

现行做法：板块与阶段一一对应时才给 `stage`；横跨多段时 `stage` 为 `null`，改给
`stageCandidates` 候选集。

| 展示 | 是否可接受 |
|---|---|
| 微软 = 中间制造（附歧义标记） | ❌ 对真实公司的错误断言 |
| 微软 = 待细化（可能：中间制造／品牌整合／平台服务） | ✅ 数据实际支持的说法 |

代价是首版只有 **182/495（36.8%）** 节点有确定阶段，其余 313 个只给候选集。这个比例
本身就是有用的信息——它精确地量化了「板块级分类不足以定位产业链位置」，并会随 SIC
行业码与真实边落地而上升。`health.json` 的 `stageResolvedPct` 跟踪这条曲线。

## 6. 可复用的既有资产

| 需要的能力 | 复用对象 |
|---|---|
| 495 家标普成分股节点（代码·中文名·板块·市值·logo·日更行情） | `apps/companies/sp500.json` |
| 非美上市公司（供应商侧大量在此） | `apps/companies/data.json` |
| 关系图渲染原语 | `apps/finance-terminal/finance-terminal-globe.mjs` 已导出 `projectPoint()`／`greatCirclePoint()` |
| 树图／气泡布局 | `apps/heatmap/heatmap-layout.mjs`、`bubble-layout.mjs` |
| 健康契约 | `scripts/market_source_health.py` 的 `DATASET_SPECS` |
| 工作流治理 | `.github/workflows/commodities.yml` |

**独有差异化**：站内已有 500 家公司的日更行情。图谱 + 行情 = 「英伟达产业链今日表现」、
「苹果供应商链条平均涨跌」。这个组合是站内数据的独家复用。

## 7. 推进路线

| 层 | 内容 | 验收标准 | 状态 |
|---|---|---|---|
| 0 | 节点表 + 价值链阶段初步口径 | 495 节点齐全，`stageBasis` 逐节点标注，零新增数据源 | **已落地** |
| 1 | 企业自披露供应商名单（苹果） | 首张完整产业链图，每条边可点开核验 | 未开始 |
| 2 | EDGAR 10-K 客户集中度全量抽取 | 数百条带出处的真边，覆盖率如实披露 | 探测中 |
| 3 | Form SD 冶炼厂清单 | 接到上游矿产 | 未开始 |
| 4 | 图谱可视化 | 分层产业链图／关系网，三档宽度可用 | 未开始 |
| 5 | 叠加站内日更行情 | 产业链今日表现，不重算已有行情口径 | 未开始 |

## 8. 已建立的质量防线

- `scripts/validate_supply_chain_extraction.py`——离线校验抽取规则的定位、点名与误报，
  22 项断言。用例全部来自开发中的真实失败：单层限定词漏掉唯一会点名客户的句式；
  裸 `Co` 后缀把小标题 `Customer Concentration` 误抽成公司名；后缀不按长度排序时
  `Corp` 把 `Microsoft Corporation` 截断。抽取规则一旦退化，后果是**边指向错的公司**，
  比没有数据严重得多，因此这条防线先于抽取器存在。
- `scripts/supply-chain/probe_edgar_relationships.py`——实测 CIK 解析率、SIC 可得性、
  真 10-K 的规则命中率与点名率、全量运行耗时估算。**不实测就写抽取器是在赌。**
- `scripts/validate_supply_chain_graph.py`——发布侧契约校验，与生成脚本里的
  `assert_edge_contract()` 构成两道防线，针对同一件事：模型「知道」的行业关系不是数据
  来源。已用注入违规的方式实测拦截能力：无证据的边、证据缺 URL、非 https 出处、
  `confidence` 越界、板块级推断冒充公司级结论、宣称完整、空文件覆盖——7 项全部拦下，
  未改动的真实文件无误报。

## 9. 官方参考资料

- [SEC EDGAR 全文检索](https://www.sec.gov/edgar/search/)
- [SEC EDGAR API 与访问礼仪](https://www.sec.gov/os/accessing-edgar-data)
- [ASC 280 分部报告与重大客户披露](https://www.fasb.org/)
- [苹果供应商责任与年度供应商名单](https://www.apple.com/supplier-responsibility/)

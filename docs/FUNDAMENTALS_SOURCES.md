# 基本面数据源：待你决定的那一步

这是 B 档的第一项，也是整个 B 档的闸门：**接上基本面字段（PE / PB / ROE / 营收
增速 / 股息）就一次解锁 FA、EE、RV、EQS 一整族功能**；不接，这一族就一项也做不了。

代码我可以写。**选哪个源不是代码问题，是许可决定，而许可决定在你手上。** 下面把
需要你拍板的东西列清楚，拍完之后的接线是机械活。

---

## 一、为什么这份文档停在这里，而不是直接接一个源

两个硬约束，都复核过：

**1. 这个开发容器没有外网。** 实测：

```
https://api.stlouisfed.org/fred/series                 → 000
https://query1.finance.yahoo.com/v8/finance/chart/AAPL → 000
https://www.sec.gov/files/company_tickers.json         → 000
https://stockanalysis.com                              → 000
```

现有管道跑在 GitHub Actions 里，那边有网。所以我能写抓取脚本，**但没法在本地看到
任何源真实返回什么** —— 字段名、嵌套结构、限流行为、空值表示法，全都只能靠猜，
而猜错的代价是管道上线后静默写出脏数据。

**2. 仓库自己的许可治理要求人来签字。** `apps/finance-terminal/market-source-readiness.json`
里有这么两个字段：

```json
"selection": { "decidedOn": "2026-08-25", "decidedBy": "project-owner" }
```

还有 `scripts/finance_terminal_market_licenses.py` 这个专门的许可契约在守着。
**这是仓库明确写下的「源的选择由项目所有者决定」**，不是我该替你填的。

**所以这份文档不写任何我没核实过的条款。** 我不会凭记忆写「某某源免费可商用」——
条款会变，写错的后果是真的。下面给的是**核查清单**，不是结论。

---

## 二、接上之后能解锁什么

| 功能 | 对应彭博 | 需要的字段 | 现在为什么做不了 |
|---|---|---|---|
| 财务分析 | FA / GF | 营收、净利、毛利率、资产负债、现金流 | 站内公司数据只有价格、市值、收益率 |
| 盈利预测 | EE | 分析师一致预期、预期修正 | 无来源 |
| 相对估值 | RV / EQRP | PE、PB、PS、EV/EBITDA | 无来源 |
| 条件选股 | EQS / SCRN | 上面任意字段 + 阈值 | 无可筛的字段 |
| 股息 | DVD | 每股股息、除息日、连续增长年数 | 无来源 |

registry 里 `SCRN`（条件选股）现在挂的卡点就是这一条：
「站内公司数据只有价格、市值与收益率，没有财务报表字段」。

---

## 三、站内既有的两条先例（这是你衡量新源的标尺）

**先例 A —— 价格数据走 Yahoo v8/chart。** `scripts/companies/build_companies.py`
的文件头写着：「数据源 Yahoo Finance（免密钥，与本仓库 asset-tracker 同款
v8/chart 接口，机房可达）」。450 家公司的价格、市值、收益率、日线与月线历史，
都是这条路来的。

**先例 B —— 两项基准走 TradingView 免费嵌入。** 登记在册的策略是
`free-embedded-proxy`，`cost: free`、`credentialsRequired: false`、
`attributionRequired: true`、`exportAllowed: false`，并明确
「不抓取、导出或再分发 TradingView 原始数据」。

**你已经声明过的立场**（`useCase` 段，新源必须对着它核）：

```
operatorType            individual-hobbyist
commercial              false
advertising             false
subscriptions           false
domain                  ooglex.com
displayPurpose          personal-financial-research
publicApiRedistribution false
costPolicy              free-only
```

---

## 四、需要你决定的：照登记表的字段逐项

选定一个源之后，`market-source-readiness.json` 要新增一段，字段是现成的。
**每一项都需要你去源站的当前条款里确认**，我无法从这个环境代你核实：

| 登记字段 | 要确认什么 | 你的答案 |
|---|---|---|
| `cost` | 是否真的免费；免费额度之外是否收费 | ☐ |
| `credentialsRequired` | 是否需要 API key / 注册 | ☐ |
| `attributionRequired` | 是否必须署名；署在哪、怎么写 | ☐ |
| `commercial` | 条款是否允许你这种用途（非商业、个人研究、公开站点） | ☐ |
| `exportAllowed` | 是否允许把数据落盘存进仓库（**这一条最关键**，见下） | ☐ |
| `publicApiRedistribution` | 站点公开 JSON 是否算再分发 | ☐ |
| `documentationUrl` / `dataFaqUrl` | 条款与文档的稳定链接 | ☐ |
| `decidedBy` / `decidedOn` | 你签字与日期 | ☐ |

### `exportAllowed` 为什么最关键

本站是**纯静态站**：所有数据以 JSON 落盘进仓库、由 GitHub Pages 公开提供。
这意味着任何基本面数据一旦接入，就是**被存储并公开分发**的。

TradingView 那条先例走的是「嵌入展示、不落盘」，正因为
`exportAllowed: false`。**基本面字段做不到只嵌不落** —— 要算 PE 排序、要筛选、
要画同业对比，就必须落盘。

所以：**如果一个源不允许存储与再分发，它对本站就不可用**，哪怕它免费。
这一条会筛掉相当一部分候选。

---

## 五、候选方向（只给核查要点，不给我没核实的条款）

按「本站需要落盘」这个前提，候选大致分三类。**每一类的条款都要你去核**：

**第一类：官方一手披露。** SEC 的公司财报结构化数据属于美国政府公开信息。
要核：具体数据集的使用条款、访问频率要求（SEC 对自动化访问有明确的
User-Agent 与速率要求）、以及**你要不要承担把原始报表字段加工成 PE/PB 的工作量**
（一手披露给的是报表项，不是比率，比率要自己算 —— 这反而更干净，口径由你定）。

**第二类：已在用的源的其他端点。** 价格已经走 Yahoo v8/chart。要核的是：
它承载基本面的端点是否与 v8/chart 属同一条款、是否允许落盘与再分发。
**注意这是最需要谨慎的一类** —— 「价格能用」不自动等于「基本面也能用、还能存」。

**第三类：明确面向开发者的免费 API。** 这类通常条款清楚、有免费额度，
但要核：免费档的字段覆盖与调用上限是否够 450 家 × 每日一次，
以及免费档是否允许公开再分发。

我刻意不在这里替它们打分 —— 没有网络核实条款的打分是假的。

---

## 六、选定之后：接线是机械的

不管选哪个源，接口形状不变。我会按仓库既有约定写：

```
scripts/fundamentals/build_fundamentals.py     取数 → apps/companies/fundamentals.json
scripts/fundamentals/adapter_<源名>.py         只有这个文件与源耦合
.github/workflows/fundamentals.yml             每日跑一次，提交回仓库
scripts/validate_fundamentals.py               契约：字段齐备、口径标注、缺值声明
```

适配器只需实现一个函数：

```python
def fetch(symbols: list[str]) -> dict[str, dict]:
    """返回 {symbol: {pe, pb, ps, roe, revenueGrowth, dividendYield, asOf, ...}}。
    取不到的字段返回 None，不要返回 0 —— 0 是一个有意义的值，None 才是「没有」。
    整体取数失败时抛异常，让上层保留上次的 JSON，不要写半份数据。"""
```

换源 = 换一个 adapter 文件，其余不动。

---

## 七、无论选哪个源，这三条都不会变

这三条来自 `AGENTS.md`，不随源的选择改变：

1. **每个字段必须带 source / asOf / frequency / status。** 基本面是季度数据，
   最长滞后可能几个月 —— 页面上必须写明是哪一期的报表，不能让人当成当前值读。
2. **取不到就写「无来源」，绝不用占位数字。** PE 取不到就是取不到，写 0 或写
   行业平均都是在说假话。
3. **不得用零值或脏数据覆盖已有的好数据。** 现有管道都有这个保护
   （`build_companies.py` 里写着「有效报价过少或榜首市值离谱时，保留上次不覆盖」），
   基本面管道照同一个规矩写。

---

## 八、现在的状态

- **A 档七个包全部做完并上线**，用的全是站内已有数据，没有新增任何外部依赖。
- **B 档卡在这一步**，卡点是许可决定 + 本地无法核实条款，不是工作量。
- 你把第四节那张表填了（或者直接说「用哪个源」），我就写 adapter、管道、
  工作流与契约，跑完校验合并上线。

### 我本来想先搭个空壳页，想清楚之后决定不做

第一版草稿里我写了「可以先把 RV（相对估值）页做出来，估值比率那几列标成
『站内无来源』」。**收回这个提议**，两个理由：

1. **仓库自己的规矩就是不这么干。** `docs/TERMINAL.md` 写着：
   「缺数据源就写缺哪一条，**不先画空壳**」。registry 里 `SCRN` 现在挂着卡点
   「站内公司数据只有价格、市值与收益率，没有财务报表字段」—— 那一行就是这件事
   现在最诚实的表达形式，比一个八列有五列写着「无来源」的页面强。
2. **剩下那几列是重复的。** 去掉估值比率之后，RV 页能给的就是市值、价格、
   区间收益、板块、国别的同业对比 —— 这些**证券描述页 12) 收益与同业已经有了**，
   而且是在有报价头上下文的地方给的。再开一页等于复制。

所以 B 档就停在你拍板这一步，不用空壳占位。等源定了，adapter 一写，
列就是真的。

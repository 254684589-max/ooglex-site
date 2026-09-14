# 基本面数据源

> **2026-09-14 更新：源已定 —— SEC EDGAR XBRL。** 你把选择权交给我，我选了它，
> 理由与仍需你确认的事项记在 `apps/companies/fundamentals-source.json`，
> 管道、契约与工作流已经写好上线。下面第一到七节是当时的分析（保留，它解释了
> 为什么会这么选）；**最新状态看第八节。**

# 原分析：待决定的那一步

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

## 八、现在的状态：源已定，管道已上线，等你跑第一次

**选的是 SEC EDGAR XBRL。** 四条理由（详见 `fundamentals-source.json` 的
`selection.rationale`）：

1. **美国政府的公开披露系统** —— 它存在的目的就是向公众分发这些数字。这让我不必
   去解释某家私营公司的当前条款，而条款解释正是这个无外网环境里我最不该代你做的
   判断。
2. **一手数据** —— 数字来自公司自己递交的报表，不是厂商加工过的编纂成果，
   所以不涉及「再分发别人的产品」。
3. **比率由本站按写明的公式现算** —— 一手披露给的是报表项，PE/PB/ROE 全是我们
   自己算的，口径可复算。这比抄一个别人算好的 PE 干净，因为别人的口径你未必知道。
4. **SEC 的访问要求是工程约束，不是法律条款** —— 声明 User-Agent、限速。两条都
   实现了（限速取 ~6.7 次/秒，低于 SEC 公布的 10 次/秒上限，留余量）。

**否决了什么、为什么**（也记在册）：行情站的基本面端点（「价格能用」不自动等于
「基本面也能用、还能落盘再分发」，要断定必须读它当前条款，而我核实不了）；
第三方免费基本面 API（同样无法核实，且它们是自己加工过的编纂成果）。

### 已经交付的

```
scripts/fundamentals/adapter_sec.py        唯一与源耦合的文件
scripts/fundamentals/build_fundamentals.py 算比率 + 三道保护闸
scripts/validate_fundamentals.py           契约（选源记录 + 数据两部分）
.github/workflows/fundamentals.yml         只有 workflow_dispatch，但受完整治理
apps/companies/fundamentals-source.json    选源与许可记录
```

治理与其余十三条行情管道同一套（`market_workflow_governance.py` + 它的契约）：独立并发锁、
只接受分支引用、生成前用远端 `FETCH_HEAD` 快进、路径守卫暂存、无变化不提交、推送被拒时
rebase 重试、诊断留 14 天。**可写范围只有 `apps/companies/fundamentals.json` 一个文件** ——
它与公司榜共用 `apps/companies/` 目录，但公司榜的 `data.json`、`sp500.json`、历史分片与
标志图一个都动不了，反过来公司榜也动不了这个文件。手动触发不是治理的例外：会推回仓库的
管道就得受同一套守卫。

### 三件需要你做的事

1. **设一个仓库变量 `SEC_CONTACT`。** 直接开
   `https://github.com/<owner>/<repo>/settings/variables/actions`，**别靠侧边栏点** ——
   `Secrets and variables` 下面的 Actions / Agents / Codespaces / Dependabot 是**四个
   互不相通的变量仓库**，长得一模一样。只有 **Actions** 那一个工作流读得到；Agents
   那个是给 Copilot 编码代理用的（页面标题会写 `Agents secrets and variables`，
   或者 `for the Copilot cloud agent`，看到这两句就是走错了）。
   然后在那一页填 **下半部分「Repository variables」那一栏**（不是上半部分的
   「Environment variables」—— 本工作流没声明 `environment:`，读的是 `vars.SEC_CONTACT`，
   只认仓库级变量）。值填你愿意对 SEC 公开的联系邮箱。**它是明文变量而不是 Secret，
   因为这个值本来就要发给 SEC、不是密钥**；有协作者权限的人都看得到，所以要是不想
   暴露主邮箱就换一个收技术通知的地址，SEC 不校验是哪个。SEC 要求自动化访问在
   User-Agent 里声明联系方式 —— **那是你的个人信息，我没有把它写进仓库**，
   也不会替你发给第三方服务。没设这个变量脚本会直接失败并说明，不会用默认值去撞
   SEC 的限流策略。
2. **手动跑一次 Fundamentals 工作流，看日志与产出的 JSON。** 我**刻意没有把它加进
   `scheduler.yml` 的每日轮转** —— 这条管道的第一次真实运行谁都没看过（我这边没有
   外网，验证不了 SEC 的返回结构）。确认数据对了，再决定要不要进轮转。
3. **顺手核一下** `fundamentals-source.json` 里 `verification.ownerShouldConfirm`
   那两条：SEC 当前公布的访问政策是否与我实现的限速一致。

### 关于「未核实」这件事，我把它写进了数据里

`verification.status` 明确写成 **`reasoned-not-fetched`** —— 上面那些条款判断是
依据「这是美国政府公开披露系统」这一性质**推定**的，不是逐条读过当前条款页得出的，
因为这个容器没有外网。契约里有一条专门盯着这个字段：**谁把它改成 `verified`，
校验就失败**，除非真的去核过并同步更新记录。

### 第一次真实运行踩到的坑（记下来，换源时同样适用）

第三次触发才过了 `SEC_CONTACT` 这一关，然后崩在
`UnicodeDecodeError: 'utf-8' codec can't decode byte 0x8b in position 1`。

`0x8b` 在第 1 位就是 gzip 的魔数。原因是请求头里发了
`Accept-Encoding: gzip, deflate` 却没写解压 —— **`urllib` 不像 `requests`
那样自动解压**。**发了一个自己没实现的头，就是在要求对方给你处理不了的东西。**

这次失败反而证明最关键的一环是通的：**SEC 真的返回了 200 和真实数据**，
User-Agent 格式被接受、没被限流、没有 403。卡的只是本地解码。

两条修法都选了「不猜」的那个：只声明 `gzip`（deflate 有 zlib 包装与裸流两种，
要猜；gzip 只有一种），并且除了读 `Content-Encoding` **再嗅一次魔数**（过代理时
头可能被剥掉而正文仍是压缩的）。

**更该记住的是第二个问题**：`UnicodeDecodeError` 不是 `AdapterError`，
所以它绕过了「保留上一份 JSON 不覆盖」那条保护路径，直接崩掉。
**上层只捕获 `AdapterError`，适配器就必须把一切失败都收敛成 `AdapterError`** ——
漏一个异常型，保护闸就形同不存在。换源时这条比 gzip 那条更要紧。

闸门原因现在一律用 `::error::` 打出来：只写 stderr 的话，GitHub 运行摘要里
只剩「Process completed with exit code 1」，等于把原因藏起来。

这类 bug 在没有外网的开发容器里对所有校验器都是隐形的，所以
`validate_fundamentals.py` 里加了**用桩替换 `urlopen`** 的离线契约把它钉住。

### 第四次跑通了，但数据是坏的 —— 换源时这三条最容易再犯

管道成功、自动提交了 249 KB 的 `fundamentals.json`。**然后核数字，发现基本不能用。**

| 现象 | 真因 | 教训 |
|---|---|---|
| PB 中位数 `4.6e-09` | 站内 `marketCap` 是**十亿美元**，SEC 是原始美元，**而这件事没写在任何 JSON 里** | 跨两个数据源做除法，先把两边的单位各自找出证据（这里的证据是 `build_companies.py` 里的 `round(cap_usd / 1e9, 1)`），然后**把假设写成断言** |
| PE 一家都没有 | frames 的单位串把 `/` 写成 `-per-`，该是 `USD-per-shares`；写成 `USD/shares` 会把 URL 路径切断 → 全 404 | 标签取不到时不要只记日志继续 —— 那等于静默降级 |
| PS/ROE/净利率只有 13–17 家 | 「撞上第一个有覆盖的期间就停」，9 月被只覆盖 12 家的 `CY2026` 劫持，跳过了覆盖几百家的 `CY2025` | 选期间要**按覆盖面挑最好的**，并设下限；**同类标签必须共用一期**，否则利润率是两个年度拼的 |

**但最该反省的不是这三条，是闸门。** 原来的三道闸问的是「取到没有」「覆盖率塌没塌」
「至少有一个比率」—— **没有一道问「这些数字像不像真的」**。所以一份 PB 全错 9 个
数量级、PE 全空的文件顺利通过了：`withRatio` 的计数被唯一算对的 `debtToAssets`
和一堆 1e-9 的假 PB 凑够了。

第四层闸门因此是：**逐项覆盖下限** + **中位数合理区间** + **PE 全空单独点名**。
区间给得很宽，它拦的是「单位错了/口径错了」这种整体性偏离，不替读者判断某家公司
贵不贵。契约复用 build 里同一套常量与函数，**不抄第二份**。

那份坏数据已删除 —— 还没有页面读它，但留着更糟：将来某次坏运行被闸门拒绝时会走
「保留上一份」，保留的就是这份错数据。**宁可没有，不要有一份错的当基线。**

### 前端已接上（2026-09-14）

第五次运行产出可用数据后建的两处，**都没有另造新表**：

- **`screen.html`** —— `SCRN` 条件选股与 `RV` 相对估值是同一张表的两种用法
  （筛选是加阈值，相对估值是和同业中位比），四个分页：条件选股 / 同业对比 /
  板块分布 / 覆盖面与口径。实测 436 家、PE 10–25 且净利率≥15 筛出 54 家、
  再加板块=金融剩 21 家。
- **证券页 `15) 财务报表`** —— 那一格菜单里本来就是**置灰预留**的，数据到了就
  点亮它，而不是另加一页。含报表原始项、六项比率与板块中位对比、两个日期。
  `16) 信用评级`、`17) 现金流表`、`18) 期权链` 仍无来源，**继续置灰**。

两页都把这几件事摆在明面上：两个日期（报表期末 + 价格日期）、PB 与 ROE 的
分母不是同一个数、分母非正不给比率、缺值是 `null` 不是 0、池子不是全市场、
板块中位不是行业标准值、以及**仍然没有**的东西（现金流、评级、股息、前瞻）。

还有一个区别值得单独说：**有 CIK 但 us-gaap 下无数据**（外国私人发行人按 IFRS
递交 20-F），与「SEC 无此申报人」不是一回事，页面分开写，不含糊成一句「没数据」。

### 原先记的「前端还没接」

`fundamentals.json` 还不存在（管道没跑过），所以 FA / RV / EQS 那几页**一个都没
建**。这是刻意的：仓库规矩是「缺数据源就写缺哪一条，不先画空壳」。数据一旦跑出来
是真的，页面我再建 —— 那时候列里是真数字，不是一片「无来源」。

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

# 财务桑基

公开路径：`/apps/financial-sankey/`

中文页面。输入美股代码，点一次「生成」，同时画出最近一个报告期的三张桑基图：利润表、资产负债表、现金流量表。研究用，不是投资建议，也不是行情。空代码、查无此代码、以及 SEC 或网络失败都会给出中文说明；SEC 读不到时可以点「重试」。

## 数据从哪来

只用美国证监会公开数据：

- 代码表：<https://www.sec.gov/files/company_tickers.json>
- 公司 XBRL：<https://data.sec.gov/api/xbrl/companyfacts/CIK##########.json>

没有 API key，也不抓 Sankify、FinGraphicx、Bloomberg 或其他付费站。

SEC 公平访问要求请求带能识别应用的 User-Agent。浏览器里的 `fetch` 不能改 User-Agent，而且 `data.sec.gov` 的响应没有 `Access-Control-Allow-Origin`。主站 `www.ooglex.com` 是 Cloudflare 灰云上的 GitHub Pages（响应头 `server: GitHub.com`，地址落在 `185.199.108-111.153`），流量不经过 Cloudflare，所以不能在 `www` 的路径上挂 Worker。

页面按这个顺序取 companyfacts：

1. **同源路径** `/apps/financial-sankey/companyfacts/CIK##########.json`。Worker 认识这条路径。当前灰云下 GitHub Pages 会返回 404，页面随即试下一条。以后如果把 `www` 接到边缘，并只把这条路径交给 Worker，页面不用再改。
2. **边缘代理** `https://sec-facts.ooglex.com/companyfacts/CIK##########.json`。这是 Cloudflare Worker `workers/sec-companyfacts/`，做法与现有的 `pro-api.ooglex.com` 相同：在已有 Cloudflare 账号上建自定义域名，不改 `www` 的 DNS。Worker 回写 CORS，浏览器才能读到响应。地址写在 `proxy.json` 的 `companyfacts`；设成空字符串就关掉边缘这一跳。
3. 仍然尝试浏览器直连 SEC。哪天接口允许跨域，同一套 JSON 会直接出图。代理返回 429 时不再直连，避免连打 SEC。
4. 上面都失败时，NVDA 和 MSFT 使用 `snapshots/` 里的摘录。摘录是 2026-10-21 从 companyfacts 裁下来的真实 us-gaap 科目，`demo` 为 `false`，不是模拟数。页面会写摘录时间。
5. 其他代码可以点「打开本地 JSON」。文件只在浏览器里解析，不上传。

Worker 合并进 `main` 后，由 `.github/workflows/deploy-sec-companyfacts.yml` 部署。部署完成前，`sec-facts.ooglex.com` 还不会解析，没有摘录的代码会停在中文失败说明。

`tickers.json` 是 SEC 代码表的精简副本（代码、CIK、公司名）。`extract_snapshot.py` 用来重新裁摘录：它只请求上面两个公开地址。

## 代理怎么限制

Worker 只转发 `data.sec.gov/api/xbrl/companyfacts/CIK` 加 10 位数字再加 `.json`。别的路径、查询参数里的 URL、以及跳转到其他主机的响应都不会转给浏览器。

- **User-Agent**：`Ooglex financial-sankey (https://www.ooglex.com/apps/financial-sankey/; <联系方式>)`。联系方式优先用仓库变量 `SEC_CONTACT`（与基本面、产业链相同，部署时写入 Worker Secret，不进 Git）。没设变量时用站点 URL，不在仓库里写邮箱。
- **频率**：每个 IP 每分钟最多 20 次、每天最多 120 次。真正打到 SEC 的新请求，每个 Worker 隔离实例至少间隔 1 秒，并且每分钟不超过 20 次。这是实例内计数，不是全机房精确配额。
- **缓存**：成功的 companyfacts 在边缘缓存 6 小时。同一 CIK 的重复打开不会反复打 SEC。这是披露数据，不是实时行情；页面不会按秒刷新，也不会把缓存标成实时。
- **来源白名单**：浏览器请求必须来自 `https://www.ooglex.com` 或 `https://ooglex.com`（本地 `127.0.0.1` / `localhost` 仅供验收）。没有 `Origin` 的直接请求仍受上面的频率限制。

健康检查是 `GET /health`，不访问 SEC。

## 图怎么读

条带宽度按美元。绿色是流入，红色是流出，蓝色是小计，金色是轧差。名称和金额同时写在表里，不靠颜色单独表达。

利润表会先看是不是工商企业的毛利结构（营业收入、营业成本、研发费用）。对不上时，再看银行（利息收入、利息支出、净利息收入、非利息收支、信贷拨备）和保险（已赚保费、净投资收益、保单给付与费用）。资产负债表和现金流量表仍用通用科目，例如经营、投资、筹资现金。对不上的差额标成「轧差」或「未映射」，公式写在明细里。可能重叠的科目宁可不画，也不重复加总。

默认是最新年报（10-K，若只有 20-F 则用 20-F）。「最新季报」用最近一份 10-Q 里约一个季度的利润表和期末资产负债表。季报现金流量在 XBRL 里经常是年初至本季末，页面会单独写明，不能和单季利润表直接比较。

## 做不到的事

- 银行利润表按净利息、非利息收支和信贷拨备来画；保险利润表按已赚保费、净投资收益和给付费用来画。两边都还要有税前利润、所得税和正的净利润，才能出图。
- 没有毛利、也不像银行或保险的利润表，会说明数据已经取到、当前结构还画不成，并在明细里列出已识别科目。这和没取到 companyfacts 不是同一件事。
- 净利润为负、所得税为收益时，利润表不画，避免条带方向和金额相反。已识别科目仍留在表里。
- 资产负债表和现金流量表仍是通用映射。银行的资产负债科目很多对不上，轧差可能比较大。
- 资产负债表上的抵销项（综合亏损、库存股）从相邻条带里扣掉，原值留在表里。
- 没有把页面放进「最新消息」顶栏。那一排是五个新闻栏目，并且按手机宽度排过；这里是单独的研究页。
- 在把 `www` 改成橙云之前，同源那一条在生产上是 404。真正让浏览器读到任意代码的，是 `sec-facts.ooglex.com`。橙云会让整个主站改走 Cloudflare，这次没有改 DNS。
- companyfacts 原文可能有几十 MB。手机上解析会慢一些；失败时仍是中文说明，不是白屏。

数字对应的是申报文件里的 XBRL，可能和新闻稿里的四舍五入口径不同。

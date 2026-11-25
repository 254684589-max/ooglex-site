# V63 | SEC 官方基金总回报数据试点

2026-11-25，复用 V60 的总回报口径和 V61 的 PIT 禁止放行规则。公开网页核对成功，原始 XML 字节尚未下载验证；不宣称已经建成历史数据库。

## 免费来源核验

- SEC FAQ https://www.sec.gov/about/webmaster-frequently-asked-questions ：公开 EDGAR 申报及政府内容可以免费访问、再利用。自动访问须遵循 https://www.sec.gov/about/developer-resources 的公平访问要求；不将发行商网站的独立许可自动套用到其他内容。
- GLD https://www.spdrgoldshares.com/usa/gld/ 提供历史 XLSX 入口；SEC 10-K https://www.sec.gov/Archives/edgar/data/1222333/000143774926038190/gld20260930_10k.htm Financial Highlights 提供年度 NAV 总回报和市价总回报。两种收益不可混用。
- SPY https://www.ssga.com/us/en/intermediary/etfs/state-street-spdr-sp-500-etf-trust-spy 提供 NAV 历史与分配入口；SEC 财务报告 https://www.sec.gov/Archives/edgar/data/884394/000119312526247066/d75559dn30d.htm 提供 NAV 与买卖报价收益比较，不能把滚动年度收益拼成月度历史。
- TLT https://www.ishares.com/us/products/239454/ishares-20-year-treasury-bond-etf 提供净值、分配及下载入口。两份已阅读的 N-PORT 原始申报提供 Item B.5 的连续两个三月窗口。Series S000004360，Class C000012090，申报期末 2026-02-28、2026-05-31。
  - https://www.sec.gov/Archives/edgar/data/1100663/000207169126008193/xslFormNPORT-P_X01/primary_doc.xml
  - https://www.sec.gov/Archives/edgar/data/1100663/000207169126016714/xslFormNPORT-P_X01/primary_doc.xml

网页核对得 TLT 两份申报的 Month 1/2/3 百分数分别为 -2.528092/-0.083174/4.526658 与 -4.147675/-0.861366/0.507649。六个月属于基金申报总回报，不能代表扣除个人税费及买卖滑点的可投资收益；原始发布时钟及修订链未认证。不作为网站实时行情或评分。GLD、SPY、TLT 发行商文件的自动采集及公开发布许可仍需按具体文件核查。

## 实现与操作

新增离线 TLT SEC XML 导入器：明确登记两份申报；核对基金 series、class、报告期；检查 XML 大小、实体、缺失/非法数值、重复月份；按月份保留百分数和来源，记录本地原始字节 SHA256（并不证明独立来源认证）；输出只允许在网站仓库外。

从上述申报页手工保存原始 primary_doc.xml（非展示 HTML），各自保存为 feb.xml 和 may.xml。在仓库根目录执行：

    python3 -m scripts.asset_compass_sec_returns_v63 --feb-xml /path/feb.xml --may-xml /path/may.xml --output /tmp/ooglex-tlt-v63.json

自动化测试只使用合成 XML，不联网、不采集、不开通付费服务。执行：

    python3 -m unittest discover -s tests -p 'test_asset_compass_sec_returns_v63.py' -v

后续：从 SEC 申报索引批量登记多年的 TLT 窗口并核对原始文件、修订及月度连续性；GLD/SPY 另寻非重叠月度收益或获准 NAV/分配数据。六资产正式评分、PIT、样本外认证均保留 0；没有修改生产数据、网站或部署。

# V97–V103 | 真实数据缺失修复及申报时间证据

V90–V96 实际运行 run 45575126574/job 139071058731：原81月与新增127月基金回报、四季度观测仍采集成功，六特征FRED解析失败（空字符串float转换）。修复仅将明确的空字符串/点视为缺失，零仍有效，缺列拒绝。测试覆盖三种边界；实际六特征重新计算待CI。BLS run 45575126732/job 139071059055：46/46报告，112项统计，27份完整目标统计，46份头部时间匹配，35项非农修订、3份重发标志。仍19份不完整，不冒充独立PIT。

新增SEC官方申报历史 https://www.sec.gov/search-filings/edgar-application-programming-interfaces ，按CIK0001100663的近期及有日期范围的历史分片检索28份目标申报（TLT16、IVV11、IVV修订1）。验证文件名、列长度、accession、报告期、NPORT-P/A身份、UTC时钟及时间顺序，与原XML SHA256匹配。只允许固定SEC主机，1秒间隔、30分片上限、拒绝重定向，403/429停止，无付费服务。接受时间不是历史公开发布时间；不能把报告期结束当成可用时间。未取得真实metadata前不宣称28/28成功。输出仅研究元数据，原始基金收益不发布。独立PIT与正式资产评分仍关闭。

黄金GLD官网明确提供历史XLSX（https://www.spdrgoldshares.com/usa/gld/），文件含可能受限基准字段，条款 https://www.spdrgoldshares.com/terms-and-conditions/ 对LBMA数据限制用途及披露。IBIT官网 https://www.ishares.com/us/products/333011/ishares-bitcoin-trust-etf/ 提供Excel数据入口，基金2024-01成立。未核实工作簿字段/可用历史范围和商业衍生使用授权，暂不下载、不转售、不冒充月度回报。两者保留此前SEC季度证据，GLD年度证据。即使IBIT取得全部月度历史也不能自然达到正式审计的五年样本条件；可另行研究更久的现货价格代理，但必须显式隔离。

正式评分仍缺独立PIT、许可、足够OOS样本及投资者成本对账。未购买数据、未部署。
# Ooglex 全球资产罗盘 V13｜BEA 核心PCE和联储 H.4.1

## 实际接入

- **BEA 核心PCE（剔除食品和能源）**：FRED 公开 CSV 序列 `PCEPILFE`；数据原始统计机构为美国经济分析局 BEA，官方说明：https://www.bea.gov/index.php/help/faq/518；FRED 页面：https://fred.stlouisfed.org/series/PCEPILFE
- **美联储资产负债表总资产**：FRED 公开 CSV 序列 `WALCL`；原始统计机构为美联储，属于 H.4.1 周度报告，原始页面：https://www.federalreserve.gov/releases/h41/；FRED 页面：https://fred.stlouisfed.org/series/WALCL
- **纽约联储未来12个月衰退模型**：官方资料 https://www.newyorkfed.org/research/capital_markets/ycfaq.html 提供月度模型资料，尚未完成官方原始文件格式、日期列和预测月份的程序化验收，所以注册状态不改变，不显示模型概率。

两项新数值来源是 FRED 对官方统计数据的镜像（不是直接访问 BEA 和美联储网站）。首次访问或数据更新失败时，自动化 CI 报错，页面显示「暂无数据」，不会添加示例数值。

## 字段与口径

| 快照路径 | 字段 | 单位 | 新鲜度 |
|---|---|---|---|
| `bea.core_pce` | `observation_period`, `value`, 可选 `yoy_percent` | 指数，% | 月度4个月以内 |
| `fed_h41.total_assets` | `observation_date`, `value_millions_usd` | 百万美元 | 周度21天以内 |

核心PCE同比按当月与上年同月指数计算；缺少任一真实基期不估计。不发布未经验证的全年化增长率。H.4.1 的总资产规模不等于金融体系净流动性，也不是所有政策利率变化的同义词。

## 数据安全与约束

- FRED 历史 CSV 可能包含官方后续修订值，`release_timestamp_verified=false`，不能当作历史首次发布时点的交易信号。
- 两个新序列接入 `scripts/archive_asset_compass_observations.py` 的首次观测档案，首见时间与官方发布时间分开。
- FRED 页面公开可获取，不自动代表无限制商用再分发许可。对第三方公开展示许可需继续遵循数据使用政策。
- 六资产综合评分仍锁定，未建立合格六因子历史验证前不发布利多利空分数。

## 下一阶段

解析并验证纽约联储月度官方 XLS / XLSX 下载，明确 **模型预测目标月比观察月晚12个月**；以及补充美联储准备金、隔夜逆回购、TGA 等流动性组件，以免仅凭资产负债表总规模判断实际流动性。

# Ooglex 全球资产罗盘｜V42 美国财政部真实历史趋势图

## 为什么这样实施
此前 V39–V41 的六资产解释只有当期宏观观测，用户无法看到利率变化的时间序列。本阶段采用仓库**既有**的 `scripts/build_asset_compass_history.py`，从美国财政部官方CSV按同日配对2年、10年名义国债与10年TIPS实际收益率，派生通胀补偿及10Y−2Y期限利差。先做**真实金融数据图表**，不增加新闻稿或云端审计工具。

不能把当前重新下载的历史财政部观测冒充各日期的首发版本，也不能用这些最新修订观测直接声称已完成 historical PIT 回测。

## 产品交付
- `/macro/overview.html` 在核心收益率卡片后增加历史趋势区，默认10年名义利率近一年，支持切换10年TIPS实际收益率、10年通胀补偿、10Y−2Y利差与近三个月/一年/全部时间。图表采用原生响应式SVG，屏幕阅读器有图表标签；最近8条原始观测可展开查看。
- `macro/treasury-trends.js` **只读取网站发布的** `/data/asset-compass-treasury-history.json`。数据文件缺失、失败或质量不合格时不画线，直白显示“历史趋势尚不可用”。不将样例行情写入页面。
- `scripts/validate_asset_compass_treasury_trends_v42.py` 强制核查美国财政部 HTTPS 来源、名义/TIPS双系列、时间排序与观测期无未来、原始差值与派生值一致、至少100个实际配对观测，以及禁止PIT认证声明。
- `.github/workflows/asset-compass-treasury-trends-v42.yml` 新增**独立真实历史数据发布任务**：合并至 `main` 触发一次，支持手动运行，之后每周一 UTC 04:15 维护；下载官方原始CSV→验证→只提交经过核验的静态JSON→从远程main再次读回验证。此任务与原有14指标日度采集流水线相互独立；生成的数据文件本身不触发循环抓取。
- 原有14项宏观指标、六资产解释、0–100正式评分关闭、历史回测准入和投资提醒保持不变。收益率趋势只解释利率市场观测的时间序列。

## 数据来源与口径
美国财政部：<https://home.treasury.gov/resource-center/data-chart-center/interest-rates>。名义与实际收益率取同日收盘观测。通胀补偿=10Y名义−10Y实际（TIPS）；10Y−2Y利差=10Y名义−2Y名义。通胀补偿还受通胀风险与TIPS流动性溢价影响，不是纯通胀预期；长期债券收益率变动不等于投资者可实现总回报。

数据文件若正常生成，一般包含过去约5年多的财政部日度观测。具体开始/结束时间、记录数量取决于**实际成功下载结果**，不事先预填。首次真实下载未完成前，页面会保留数据缺失提示，而不是显示伪造曲线。

## 验收
```bash
python3 -m unittest discover -s tests -p 'test_asset_compass_treasury_trends_v42.py' -v
node --check macro/treasury-trends.js
node tests/smoke_asset_compass_trends_v42.cjs
```

提交后以 GitHub `Asset Compass Research V18–V42 Gates` 为离线测试结果，**以独立的 `Asset Compass V42 Official Treasury Trend Observations` 工作流及已提交的 `data/asset-compass-treasury-history.json` 为真实抓取完成的证据**。二者必须分开核实。

已验证评分的独立宏观因子来源仍不足，正式评分及收益率历史回测继续关闭。

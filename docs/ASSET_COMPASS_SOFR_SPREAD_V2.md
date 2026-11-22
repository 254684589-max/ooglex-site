# SOFR互换利差历史归档 V2（2026-11-22）

## 范围
本阶段升级 `/macro/swap-spreads.html` 为六期限指示性OIS互换利差日频研究页，保留其他站内页面原URL不变。

## 数据
- 美国国债：U.S. Treasury Daily Par Yield Curve XML；平价收益率、单位百分比，观测日期为美国交易日。
- 互换端：CheckMySwap公开API中的美元SOFR OIS曲线；由DTCC公开交易报告聚合的指示性市场估值，并非交易商可执行报价。只接纳 `close` 与 `close-thin` 方法；后者为稀疏成交收盘窗口。
- 六期限：2/3/5/7/10/30年；同一交易日、完整六期限方可形成一条记录。
- 公式：`spreadBp = (swap_percent - treasury_percent) * 100`。
- 同一天不允许更改已归档的记录（源站可能修订，需要独立人工审计）；前一天或早于现有最后日期的快照不能倒填。
- 不进行时间插值、不伪造历史走势、不把指示性估值标为交易可执行报价。
- `macro/swap-spreads-history.json` 初始只有2026-11-20一条日期记录，因此时间序列明确显示样本不足。

## 自动运行
工作流 `.github/workflows/asset-compass-sofr-spreads.yml` 预定周二至周六 UTC 03:35，且只在main运行；通过测试后请求两数据源，如果没有相同交易日或其中任何必要期限缺失，脚本失败并保留原文件。全程无API密钥与额外依赖，工作流只暂存该JSON。手动触发同样仅允许main。

## 验收标准
- 运行 `python -m unittest discover -s tests -p test_swap_spreads_history.py -v`。
- 运行 `python -m py_compile scripts/update_swap_spreads.py`。
- 运行 `node --check macro/swap-spreads-history.js`。
- 检查360/768/1280像素页面布局，且页面无法载入、空数据、过期、单日历史时标注清楚。
- 先在PR里审查和测试，再合并部署。

## 发布
未部署。本阶段仅作为独立Pull Request提交；未执行生产合并或修改密钥、域名与数据库。

## 已知限制
- 免费公开接口可能变更或限制再发布；商业使用前应复核使用条款。
- 观测是指示性OIS市场估值，与利率互换交易商报价及其他合成互换曲线不能直接混用。
- 历史回填需要独立许可、元数据和源文件审计；不会从现有单条记录推断历史分位数。
- 资金成本/融资、互换与国债支付与折现约定不一致时，这不是逐笔可复制的交易Swap Spread。

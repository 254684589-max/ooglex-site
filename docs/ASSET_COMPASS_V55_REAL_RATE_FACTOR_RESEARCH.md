# Ooglex 全球资产罗盘 V55｜真实国债历史利率标准化与六资产方向研究

## 核心目标
V54 已真实产出六资产评分就绪矩阵，发现4组有宏观观测、2组完全缺数据、0组能够直接打分。本阶段不制造新的空评分框架，而是使用主分支已有 **1,472条美国财政部 2021-01-04至2026-11-20 日度历史记录**，真正执行滚动变化/标准化，呈现研究候选与仍缺的证据。

**重要：这些1472条为目前可取得的、可能已经修订后的历史观察值，非存档首发历史版本，且不代表当时投资者可获取的数据。** V55不会让研究候选变成正式收益预测或0–100分。

## 已实现的数据计算
- 来源：`data/asset-compass-treasury-history.json`；真实原始来源优先美国财政部，失败时使用明确标注的美联储H.15/FRED镜像。复用V42全部来源、日期顺序、名义/实际收益率、代数恒等式及时效校验；伪造PIT或无授权数据不通过。
- 5列历史研究指标：10年名义收益率、2年名义收益率、10年实际收益率、10年通胀补偿（派生）、10Y−2Y期限利差（派生）。
- 对每列从最新日起向前21条**有效观察**计算收益率变化（百分点乘100，单位bp），和此前252个21期变化组成的**滚动历史参考分布**对比，计算 `z = (current_change - historical_mean) / historical_std`。当前候选不包含在其参考均值/方差中。标准差为零或历史记录不足：不返回Z值。
- `tanh(z/2)` 仅将变化强度压缩进[-1,1]以便研究，**不是概率、历史有效信号或模型校准函数**。历史参考的21期变化彼此重叠；不能当作252个独立事件或可投资回测样本。
- 所有原始系列与派生系列分别打标，不能把10Y名义收益率、实际收益率、通胀补偿当成3个独立模型投票。

## 六资产的研究假设，严格禁止自认证
| 资产 | 利率研究假设 | 是否实际计算当前候选 | 正式0–100评分 |
| --- | --- | --- | --- |
| 黄金 | 实际收益率提高可能增加持有成本；反向响应是假设 | 是，有效源时显示 | null |
| 美国长期国债 | 名义10年收益率提高可能压低存量长债价格；反向响应是假设 | 是，有效源时显示 | null |
| 美股 | 利率影响依赖盈利、风险偏好及市场估值 | 未擅自判断方向 | null |
| 美元 | 缺少跨币种利差与资金流 | 未擅自判断方向 | null |
| 比特币 | 利率与风险偏好的关系非稳定单向 | 未擅自判断方向 | null |
| 原油 | 供需和库存远不能仅靠利率替代 | 未擅自判断方向 | null |

在 `scripts/build_asset_compass_rate_shocks_v55.py` 中，只有黄金/长期国债会得到带明确 `verified:false` 的研究输入。程序会**把该研究输入真实传入当前 `score_one()`**，验证其返回 `score:null`、历史校准及样本外未通过。其他四资产不填零或猜方向。所有结果显示在网站总览新增V55面板，报告与当前宏观快照生成时间不符则拒绝展示。前端不能绕过任何正式评分门禁。

## 自动化
- `scripts/build_asset_compass_rate_shocks_v55.py`：直接处理现有真实数据，保存公开研究报告 `data/asset-compass-rate-shocks-v55.json`。
- `.github/workflows/asset-compass-treasury-trends-v42.yml`：每周刷新历史国债来源后同步生成V55报告，并对已持久提交的远端报告实施“0分数、非PIT、截止日期匹配”验证。
- `.github/workflows/macro-treasury.yml`：每次完成正式宏观快照后生成V55报告，确保研究报告与快照源时间一致，提交并远端比对。
- `.github/workflows/deploy_protected_pages.yml`：部署产物重新生成V55、检查非PIT、确认所有资产正式分数null。
- `.github/workflows/asset-compass-research-gates.yml`：V18–V55研究门禁与真实利率标准化、网站JS冒烟测试。
- `tests/test_asset_compass_rate_shocks_v55.py`：15项专项测试，真实历史计算、前21期变化校验、历史样本、PIT造假、错序、派生恒等式、时效、源格式、数据缺失、波动率为零、评分锁。
- `tests/smoke_asset_compass_rate_shocks_v55.cjs`：7项网站实际JS测试，真实报告、资产结果、超期拒绝及伪造权限阻断。

## 仍未完成与 V56
1. **正式评分依然全部锁定**：缺少可信的历史首次可得时间和修订版本、完整风险/信用、六资产专属数据、资产可投资总收益、各资产经济方向的严格样本外校准。
2. 利率Z值仅是描述性宏观变化，其意义不是“黄金下月会跌/涨”。
3. 正式需要通过私有、核证版 `asset_compass_pit_standardize.py` 和真实首次发布可得性，进入独立信号研究与多周期滚动验证。**不要把V55研究候选翻转成`verified:true`。**
4. V54受保护域名验收的V11清单404：已查明构建工件本身含 `asset-compass-deploy-v11.json`，而www.ooglex.com的在线地址没有。V55增加部署传播重试与精准错误提示，但如果GitHub Pages同时启用了**默认分支发布**和**GitHub Actions自建部署**，连接器不能修改Pages设置。需由仓库管理员在 GitHub `Settings → Pages → Build and deployment → Source` 中选择 `GitHub Actions` 并确认唯一发布源，重新验收真实生产域名。**仅修改模型脚本无法证明该404已经解决**。

## 检查
```bash
python3 -m unittest discover -s tests -p 'test_asset_compass_rate_shocks_v55.py' -v
python3 -m scripts.build_asset_compass_rate_shocks_v55
node tests/smoke_asset_compass_rate_shocks_v55.cjs
```

本阶段只输出可复核的真实宏观描述性研究、不输出交易信号、不发布未经证明的策略收益。

# Ooglex 全球资产罗盘｜V40 上线记录与前端数据验收

## 经核实的 GitHub 生产部署状态
V39 合并提交 `bc19ae4560fa62290ab5fb9d9dc64eb2d8de740b`。在 GitHub Actions 仓库实际运行记录中，下列部署均已标记 **completed/success**：

- `Deploy Protected Ooglex Pages` 运行 `45032274157`（对应主分支 V39 合并提交）
- `pages build and deployment` 运行 `45032273822`（对应同一提交）
- PR 上 `Ooglex Macro Unit Tests` 运行 `45032176758` 成功
- PR 上 `Asset Compass Research V18-V39 Gates` 运行 `45032176753` 成功

但外部网页读取工具直接访问 `https://www.ooglex.com/macro/overview.html`、`/macro/compass-pages.js`、`/data/asset-scores.json` 均不可达；**不可把 GitHub Pages deploy success 等同于用户设备上的可访问/可渲染成功**。具体 DNS、站点权限和浏览器控制台需在实际生产环境核验。

## V40 前端收口
1. 保留真实14项指标的搜索和类别筛选，以及六资产原有0–100评分门禁，不加入任何示意行情或虚构宏观分数。
2. 改进日/月日期验证：拒绝溢出日期 `2026-02-30`、零月份或第13个月等无效观测日期；拒绝不在0–100%的失业率和纽约联储研究模型概率。绝不能将无效值显示为可用数据。
3. 为每个来源增加固定的**官方机构入口链接**，不把采集账本里历史引用过的2025年财政部URL当作2026年的实时来源链接。
4. 明确区分72小时未更新的**整体快照延迟**与各指标自己的日/周/月观测周期。即使快照延迟，仍允许显示观测期符合规则的月度数据，但明确告警；不能声称来源已经完成新一轮采集。
5. `tests/smoke_asset_compass_frontend_v40.cjs` 直接在 Node VM 运行真实 `macro/compass-pages.js`，用极小DOM测试替代空泛的静态字符串测试，验证14行表、六资产卡片、搜索、筛选、来源链接、无效/过期数据隐藏、评分关闭。继续保留V39静态校验与原有研究门禁。

## 实际验收指标
```bash
node --check macro/compass-pages.js
node tests/smoke_asset_compass_frontend_v40.cjs
python3 -m unittest discover -s tests -p 'test_macro_compass_frontend_v39.py' -v
```

运行 `Asset Compass Research V18–V40 Gates` 后，核查 CI 是否真正成功。合并后检查 GitHub 两个生产部署工作流、main 的前端文件以及网站实际URL。后两项如当前工具权限不足应保留待人工或浏览器验收，不伪造HTTP响应和真实浏览器截图。

## 下一步
优先完成上线可达性（若生产页面仍无法访问，检查DNS、GitHub Pages保护层和部署工作流），随后可加入真正的因子解释/指标选择交互；正式历史回测、资产0–100评分及交易预警仍须独立认证，继续关闭。

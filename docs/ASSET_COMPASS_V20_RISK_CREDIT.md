# Ooglex 全球资产罗盘 V20 · 风险与信用因子来源准入

## 范围和来源
| 系列 | 归属方 | 参考链接 | 单位 | 状态 |
|---|---|---|---|---|
| VIXCLS | Cboe | https://fred.stlouisfed.org/series/VIXCLS | index | 候选，待授权 |
| BAMLC0A0CM | ICE Data Indices, LLC | https://fred.stlouisfed.org/series/BAMLC0A0CM | percent | 候选，待授权 |
| BAMLH0A0HYM2 | ICE Data Indices, LLC | https://fred.stlouisfed.org/series/BAMLH0A0HYM2 | percent | 候选，待授权 |

FRED 仅是传播/整理来源；不能把 FRED 的可访问性解释为第三方版权数据可以放在公开的 Ooglex 网站或商用。ICE 数据、Cboe VIX 数据的可公开展示、缓存、再分发、商业用途必须由权利人条款或合同单独确认。

## 技术交付
- `scripts/asset_compass_risk_credit_v20.py`：无网络请求、无模拟数据，**仅私有研究**。读取操作人员事先合法获得的真实 CSV + 外置许可核验声明，确认真实来源、单位、频率、时间及发布标识后，调用 V9 不可篡改的宏观版本入库逻辑。
- `tests/test_asset_compass_risk_credit_v20.py`：6项合成测试覆盖无许可、禁止公用、伪造网址、单位错误、无效值、未来发布时间及按时点查询。
- 不向网站发布原始第三方序列或标准化因子，不接生产评分、不自动预警。

## 私有 CSV 必需列
```csv
series_id,source,frequency,units,observation_date,available_at,value,source_release_id,source_url
```
注意：`available_at` 必须是有真实证据的发布/修订时刻，不能用今天下载数据的时间倒推历史首次发布时刻。`source_release_id` 必须来自可追溯真实版本，并非任意自编号。

## 私有权限核验 JSON 的结构示例
仅作为字段示例，**不是授权书，也不表示已获得权利**：
```json
{
  "series": {
    "VIXCLS": {
      "approved_for_private_research": false,
      "approved_for_public_redistribution": false,
      "authority": "",
      "evidence_reference": "",
      "reviewed_at": ""
    }
  }
}
```
仅当核对真实合同或许可后才能将私有研究布尔值设为 true，且填写审查人、可核验证据编号和带时区的审查日期。此声明是操作方内部确认，工具无法自行验证合同法律效力。

## 执行（文件必须放在仓库外）
```bash
python3 -m unittest tests.test_asset_compass_risk_credit_v20 -v
python3 -m scripts.asset_compass_risk_credit_v20 --db /tmp/asset-compass-vintages.sqlite --csv /tmp/authorized-risk-credit.csv --permission /tmp/confirmed-rights.json
```

## 阶段验收与限制
- 权利授权未明确或历史发布日期无证据：不导入、不公开、不计分。
- 私有研究数据归档成功不代表覆盖率、质量、独立性或预测能力通过。
- V18/V19/V20 形成依赖链；必须逐阶段完成测试、审核后合并。
- 后续需要建设合法数据供应、真实 vintage 归档、公开展示许可审查与模型验证，不能因为完成了代码就宣称实际 VIX / OAS 已经上线。

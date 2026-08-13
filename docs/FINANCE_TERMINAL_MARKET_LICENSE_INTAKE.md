# 金融终端精确原标的授权询价包

> 状态：询价材料已准备，尚未对外提交
>
> 决定日期：2026-08-13
>
> 适用域名：`ooglex.com`

## 1. 已确认的产品范围

Ooglex稳定V1继续使用精确原标的，不采用ETF或期货代理：

| 页面资产 | 精确目标 | 权利人/数据方 | 申请范围 | 当前状态 |
|---|---|---|---|---|
| 标普500 | `SPX`价格指数 | S&P Dow Jones Indices | 日终或延迟、公开网页展示 | 材料已准备，未提交 |
| 纳斯达克100 | `NDX`价格指数 | Nasdaq | 日终或延迟、公开网页展示 | 材料已准备，未提交 |
| 道琼斯工业平均指数 | `DJIA`价格指数 | S&P Dow Jones Indices | 日终或延迟、公开网页展示 | 材料已准备，未提交 |
| 黄金 | LBMA Gold Price PM，USD/金衡盎司 | ICE Benchmark Administration | 伦敦午夜后延迟、公开网页展示 | 材料已准备，未提交 |

统一使用场景：个人爱好者运营、无广告、无订阅、无其他商业收入，只在一个公开域名展示研究页面；不提供对外行情API、不连接交易执行、不发行或定价金融产品。

任何报价、合同、付款、自动续费或用途扩大都必须由项目所有者逐项确认。GitHub授权、API访问权或网页可见性均不等于数据公开展示许可。

## 2. 官方询价路径

| 询价组 | 覆盖标的 | 官方入口 | 联系方式 | 预期交付 |
|---|---|---|---|---|
| S&P DJI | SPX、DJIA | [Data & Index Licensing](https://www.spglobal.com/spdji/en/about-us/data-index-licensing/) | `index_services@spglobal.com` | S&P DJI文件/API或其指定授权数据商 |
| Nasdaq | NDX | [GIDS](https://www.nasdaq.com/solutions/global-indexes/data/gids)与[Global Data价格/联系页](https://www.nasdaqtrader.com/Trader.aspx?id=DPGlobaldata) | `DataSales@nasdaq.com` | GIDS云接口或其指定授权数据商 |
| ICE IBA | LBMA Gold Price PM | [LBMA Precious Metals](https://www.ice.com/iba/lbma-precious-metals)与[LBMA许可说明](https://www.lbma.org.uk/prices-and-data/lbma-gold-price/lbma-gold-price) | `iba-licensing@theice.com` | IBA或授权再分发商的延迟基准数据 |

询价时必须要求供应商书面确认：允许在`ooglex.com`向未登录公众展示；允许显示当前值、上一观测值、百分比变化、最多8个最近观测点、来源名称、数据日和更新时间；是否要求商标文字、免责声明、延迟标签、用户计数或定期报告。

## 3. S&P DJI询价文本

主题：`Non-commercial delayed web display license inquiry — SPX and DJIA`

```text
Hello S&P Dow Jones Indices Commercial Services,

I operate Ooglex (https://ooglex.com) as an individual, non-commercial personal financial research website. The site has no advertising, subscriptions, paid products, trading execution, or public data API.

I would like a quote and written permission to display end-of-day or delayed values for the S&P 500 Price Index (SPX) and Dow Jones Industrial Average (DJIA) on one public webpage. The display would include the latest value, prior observation, percentage change, observation date, update time, source attribution, and up to eight recent daily observations.

Please confirm the lowest applicable license for this limited public-web use, approved delivery options, required attribution/disclaimers, reporting obligations, annual fees, setup fees, renewal terms, and whether a non-commercial individual tier or waiver is available.

The data will not be redistributed through an API, used for trading execution, or used to create or value a financial product.

Regards,
[legal name]
[country/region]
[contact email]
```

## 4. Nasdaq询价文本

主题：`Non-commercial delayed web display license inquiry — Nasdaq-100 NDX`

```text
Hello Nasdaq Global Data Products,

I operate Ooglex (https://ooglex.com) as an individual, non-commercial personal financial research website. The site has no advertising, subscriptions, paid products, trading execution, or public data API.

I would like a quote and written permission to display end-of-day or delayed values for the Nasdaq-100 Price Index (NDX) on one public webpage. The display would include the latest value, prior observation, percentage change, observation date, update time, source attribution, and up to eight recent daily observations.

Please confirm the lowest applicable display license, whether GIDS Cloud or an authorized vendor is appropriate, required agreements and system approval, attribution/disclaimer requirements, reporting obligations, annual and setup fees, renewal terms, and whether a non-commercial individual tier or waiver is available.

The data will not be redistributed through an API, used for trading execution, or used to create or value a financial product.

Regards,
[legal name]
[country/region]
[contact email]
```

## 5. ICE IBA询价文本

主题：`Non-commercial delayed web display license inquiry — LBMA Gold Price PM`

```text
Hello ICE Benchmark Administration Licensing,

I operate Ooglex (https://ooglex.com) as an individual, non-commercial personal financial research website. The site has no advertising, subscriptions, paid products, trading execution, or public data API.

I would like a quote and written permission to display the delayed LBMA Gold Price PM in USD per troy ounce after midnight London time on one public webpage. The display would include the latest benchmark value, prior observation, percentage change, observation date, update time, source attribution, and up to eight recent daily observations.

Please confirm the lowest applicable delayed redistribution/display license, approved delivery options, required attribution/disclaimers, user-count or reporting obligations, annual and setup fees, renewal terms, and whether a non-commercial individual tier or waiver is available.

The data will not be redistributed through an API, used for trading execution, or used to create or value a financial product.

Regards,
[legal name]
[country/region]
[contact email]
```

## 6. 提交与入库规则

提交前仍需由项目所有者在邮件或供应商表单中填写真实法定姓名、居住国家/地区和联系邮箱；这些个人信息不得提交到公开Git仓库。

每次提交后，仅把以下非敏感审计信息写入`market-source-readiness.json`：

- `procurement.status`改为`submitted`；
- `submittedAt`使用带时区的UTC ISO 8601时间；
- `inquiryReference`记录供应商工单号或去敏后的邮件引用；
- 不保存邮件正文、姓名、邮箱、电话、合同原件或付款资料。

收到报价后改为`quoted`，但仍保持`authorization.status: blocked`。只有取得书面公开展示许可、完成法律和费用确认后，才能登记可审计授权编号并进入真实数据接入；授权前四张卡继续显示`DEMO`。

## 7. 授权后工程验收

1. 先确认供应商允许的传输方式、频率、缓存、历史窗口和公开展示字段。
2. 密钥只进入GitHub Actions Secret或Cloudflare Secret，不进入前端、仓库和日志。
3. 每个来源独立实现成功、空值、字段变化、过期、限流、授权失败和同标的旧值保留测试。
4. 页面显示精确来源、数据日、更新时间、单位、日终/延迟标签和规定的免责声明。
5. 黄金卡片正式接入时改名为“LBMA Gold Price PM”，不得继续把该基准标为通用`XAU/USD`现货。
6. 每项接入独立提交，只推完整开发分支；不合并`main`、不发布、不部署。

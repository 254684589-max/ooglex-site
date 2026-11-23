"use strict";
const ASSETS={gold:"黄金",us_equities:"美股",us_long_bonds:"美国长期国债",usd:"美元",bitcoin:"比特币",oil:"原油"};
const FACTORS={rates:"利率与货币政策",inflation:"通胀",growth:"经济增长与就业",liquidity:"美元与流动性",risk:"市场风险与信用",asset_specific:"资金流与估值"};
const DATA="../data/asset-scores.json";
const CONFIG="./model-config.json";
const PRICE="../data/asset-compass-price-audit.json";
const READY="../data/asset-compass-history-readiness.json";
const OBSERVATIONS="../data/asset-compass-factor-observations.json";
const SCORING_READINESS="../data/asset-compass-scoring-readiness-v54.json";
const RATE_SHOCKS_V55="../data/asset-compass-rate-shocks-v55.json";
const OFFICIAL_SOURCES_V56="../data/asset-compass-new-sources-v56.json";
const ASSET_SPECIFIC_V57="../data/asset-compass-asset-specific-v57.json";
const $=q=>document.querySelector(q);
const el=(tag,cls,content)=>{const node=document.createElement(tag);if(cls)node.className=cls;if(content!==undefined)node.textContent=String(content);return node};
const isNumber=n=>typeof n==="number"&&Number.isFinite(n);
function card(title,value,detail){const node=el("article","card"),h=el("div","label",title),b=el("div","big",value),p=el("p","muted",detail);node.append(h,b,p);return node}
async function getJSON(path){const result=await fetch(path,{cache:"no-store"});if(!result.ok)throw Error("未发布："+path);return result.json()}
async function optional(path){try{return await getJSON(path)}catch{return null}}
function isoDay(day,age){if(!/^\d{4}-\d{2}-\d{2}$/.test(day||""))return false;const dt=Date.parse(day+"T00:00:00Z");return Number.isFinite(dt)&&new Date(dt).toISOString().slice(0,10)===day&&Date.now()>=dt&&Date.now()-dt<=age*86400000}
function isoMonth(month,age){if(!/^\d{4}-\d{2}$/.test(month||""))return false;const [y,m]=month.split("-").map(Number);if(y<1900||m<1||m>12)return false;const now=new Date();const n=(now.getUTCFullYear()-y)*12+now.getUTCMonth()+1-m;return n>=0&&n<=age}
function usableScore(a){return a?.status==="calibrated"&&isNumber(a.score)&&a.score>=0&&a.score<=100&&a.validation?.historical_calibration_passed===true&&a.validation?.out_of_sample_passed===true}
function scoreText(a){return usableScore(a)?a.score.toFixed(1)+"/100":"— / 100"}
// Current-observation registry. These are 14 SOURCE series, not 14 independent
// factor signals. Break-even inflation and 10Y-2Y are derived from Treasury.
const OVERVIEW_INDICATORS=[
 {id:"treasury.us10y",name:"10年期名义国债收益率",group:"利率",source:"美国财政部",cadence:"daily",unit:"%",precision:2,value:d=>d.rates?.us10y,period:d=>d.observation_date},
 {id:"treasury.real10y",name:"10年期TIPS实际收益率",group:"利率",source:"美国财政部",cadence:"daily",unit:"%",precision:2,value:d=>d.rates?.real10y,period:d=>d.observation_date},
 {id:"treasury.us2y",name:"2年期国债收益率",group:"利率",source:"美国财政部",cadence:"daily",unit:"%",precision:2,value:d=>d.rates?.us2y,period:d=>d.observation_date},
 {id:"nyfed.effr",name:"有效联邦基金利率 EFFR",group:"利率",source:"纽约联储",cadence:"daily",unit:"%",precision:2,value:d=>d.nyfed?.effr_percent,period:d=>d.nyfed?.observation_date},
 {id:"bls.cpi",name:"CPI价格指数",group:"通胀",source:"美国劳工统计局",cadence:"monthly",unit:"指数",precision:3,value:d=>d.bls?.series?.cpi?.value,period:d=>d.bls?.series?.cpi?.period},
 {id:"bls.core_cpi",name:"核心CPI价格指数",group:"通胀",source:"美国劳工统计局",cadence:"monthly",unit:"指数",precision:3,value:d=>d.bls?.series?.core_cpi?.value,period:d=>d.bls?.series?.core_cpi?.period},
 {id:"bls.unemployment",name:"失业率",group:"就业",source:"美国劳工统计局",cadence:"monthly",unit:"%",precision:1,value:d=>d.bls?.series?.unemployment?.value,period:d=>d.bls?.series?.unemployment?.period},
 {id:"bls.payroll",name:"非农就业月增量",group:"就业",source:"美国劳工统计局",cadence:"monthly",unit:"千人",precision:0,value:d=>d.bls?.series?.payroll?.monthly_change_thousands,period:d=>d.bls?.series?.payroll?.period},
 {id:"bea.core_pce",name:"核心PCE同比",group:"通胀",source:"BEA（经FRED）",cadence:"monthly",unit:"%",precision:2,value:d=>d.bea?.core_pce?.yoy_percent,period:d=>d.bea?.core_pce?.observation_period},
 {id:"fed_h41.total_assets",name:"美联储H.4.1总资产",group:"流动性",source:"美联储（经FRED）",cadence:"weekly",unit:"百万美元",precision:0,value:d=>d.fed_h41?.total_assets?.value_millions_usd,period:d=>d.fed_h41?.total_assets?.observation_date},
 {id:"liquidity.reserves",name:"银行准备金",group:"流动性",source:"美联储（经FRED）",cadence:"weekly",unit:"百万美元",precision:0,value:d=>d.liquidity?.reserves?.unit==="millions_usd"?d.liquidity.reserves.value:null,period:d=>d.liquidity?.reserves?.observation_date},
 {id:"liquidity.tga",name:"财政部一般账户 TGA",group:"流动性",source:"美联储（经FRED）",cadence:"weekly",unit:"百万美元",precision:0,value:d=>d.liquidity?.tga?.unit==="millions_usd"?d.liquidity.tga.value:null,period:d=>d.liquidity?.tga?.observation_date},
 {id:"liquidity.overnight_rrp",name:"隔夜逆回购余额",group:"流动性",source:"纽约联储（经FRED）",cadence:"daily",unit:"十亿美元",precision:3,value:d=>d.liquidity?.overnight_rrp?.unit==="billions_usd"?d.liquidity.overnight_rrp.value:null,period:d=>d.liquidity?.overnight_rrp?.observation_date},
 {id:"nyfed_recession.probability",name:"收益率曲线模型：12个月后衰退概率",group:"模型",source:"纽约联储研究模型",cadence:"monthly",unit:"%",precision:2,value:d=>{const m=d.nyfed_recession_model||{};if(m.official_forecast!==false||!/^\d{4}-\d{2}$/.test(m.observation_period||"")||!/^\d{4}-\d{2}$/.test(m.target_period||""))return null;const [y,n]=m.observation_period.split("-").map(Number),[ty,tn]=m.target_period.split("-").map(Number);return (ty*12+tn)-(y*12+n)===12?m.probability_percent:null},period:d=>d.nyfed_recession_model?.observation_period}
];
// V48: research-source independence taxonomy, not causal or predictive
// certification. Every entry maps to a V39 canonical observation series.
const INDICATOR_DEPENDENCE={
 "treasury.us10y":{family:"国债收益率",relation:"名义期限锚",note:"与实际收益率、通胀补偿存在同期限代数恒等式"},
 "treasury.real10y":{family:"国债收益率",relation:"实际期限锚",note:"与名义收益率、通胀补偿存在同期限代数恒等式"},
 "treasury.us2y":{family:"国债收益率",relation:"短端期限锚",note:"10Y−2Y期限利差依赖此值及10年名义收益率"},
 "nyfed.effr":{family:"政策及货币市场",relation:"独立系列，尚未认证独立预测信息",note:"与短端国债利率或货币政策背景可能高度相关，不能重复视作独立投票"},
 "bls.cpi":{family:"通胀",relation:"独立系列，尚未认证独立预测信息",note:"与核心CPI共享调查来源和部分价格样本"},
 "bls.core_cpi":{family:"通胀",relation:"独立系列，尚未认证独立预测信息",note:"CPI剔除食品能源的口径，与总体CPI非相互独立"},
 "bls.unemployment":{family:"劳动力市场",relation:"独立系列，尚未认证独立预测信息",note:"失业率来自家庭调查，非农来自企业调查；经济周期相关但不是代数重复"},
 "bls.payroll":{family:"劳动力市场",relation:"独立系列，尚未认证独立预测信息",note:"就业增长和失业率来自不同调查但共享宏观周期"},
 "bea.core_pce":{family:"通胀",relation:"独立系列，尚未认证独立预测信息",note:"与CPI有共用价格资料，不等于CPI，但不能假定完全独立"},
 "fed_h41.total_assets":{family:"美联储资产负债表",relation:"共同会计体系，不能独立计票",note:"与准备金、财政部TGA等余额存在资产负债表会计联系，并非简单相加独立信号"},
 "liquidity.reserves":{family:"美联储资产负债表",relation:"共同会计体系，不能独立计票",note:"准备金为美联储负债端项目，非美联储资产的另一项独立政策投票"},
 "liquidity.tga":{family:"美联储资产负债表",relation:"共同会计体系，不能独立计票",note:"财政部在联储的存款与准备金共同受到资产负债表操作影响"},
 "liquidity.overnight_rrp":{family:"美联储资产负债表",relation:"共同会计体系，不能独立计票",note:"隔夜逆回购余额与准备金存在资金配置联系，且来源频率、单位不同"},
 "nyfed_recession.probability":{family:"期限结构研究模型",relation:"模型输出，非独立原始指标",note:"纽约联储模型基于收益率曲线，不能再作为独立于期限利差的证据"}
};
const EXACT_IDENTITIES=[
 {label:"10年名义收益率 = 10年TIPS实际收益率 + 10年通胀补偿",
  inputs:["treasury.us10y","treasury.real10y"],derived:"treasury.breakeven10y"},
 {label:"10Y−2Y期限利差 = 10年名义收益率 − 2年名义收益率",
  inputs:["treasury.us10y","treasury.us2y"],derived:"treasury.spread10y2y"}
];
function independenceAudit(rows){
 const validRows=Array.isArray(rows)?rows:[];
 const coverage=OVERVIEW_INDICATORS.every(x=>Object.hasOwn(INDICATOR_DEPENDENCE,x.id))&&
  Object.keys(INDICATOR_DEPENDENCE).length===OVERVIEW_INDICATORS.length;
 if(!coverage)throw Error("V48 indicator dependency registry incomplete");
 const entries=OVERVIEW_INDICATORS.map(def=>{
  const observation=validRows.find(r=>r.id===def.id);
  return {id:def.id,name:def.name,source:def.source,cadence:def.cadence,
   family:INDICATOR_DEPENDENCE[def.id].family,
   relation:INDICATOR_DEPENDENCE[def.id].relation,
   note:INDICATOR_DEPENDENCE[def.id].note,
   current:observation?.value!==null&&Number.isFinite(observation?.value)};
 });
 return {entries,sourceSeries:entries.length,derivedDefinitions:EXACT_IDENTITIES.length,
  reportingFamilies:new Set(entries.map(x=>x.family)).size,
  // These must remain false until independent PIT and out-of-sample evidence exists.
  independentSignalsCertified:false,validatedForScoring:false};
}
function renderIndependenceAudit(rows){
 const panel=$("#indicator-independence");
 if(!panel)return;
 panel.replaceChildren();
 const audit=independenceAudit(rows);
 const intro=el("p","muted","审计覆盖 "+audit.sourceSeries+" 条已接入源系列、"+
  audit.derivedDefinitions+" 条代数派生公式和 "+audit.reportingFamilies+
  " 个研究主题分组。研究主题分组不是独立因子数量，来自同一机构或不同机构也不能据此认证预测独立性。");
 const identities=el("div","audit-identities");
 for(const item of EXACT_IDENTITIES){
  const p=el("p","",item.label+"；派生指标 "+item.derived+" 只能由同日原始数据计算，不新增独立观测源或重复投票。");
  identities.append(p);
 }
 const wrap=el("div","table-wrap"),table=el("table");
 const header=el("tr");
 for(const text of ["14项源指标","研究主题","频率","依赖及重复风险","数据状态"]){
  const th=el("th","",text);th.scope="col";header.append(th);
 }
 const thead=el("thead");thead.append(header);table.append(thead);
 const body=el("tbody");
 for(const item of audit.entries){
  const tr=el("tr");tr.title=item.note;
  for(const v of [item.name,item.family,item.cadence,item.relation,item.current?"当前可用":"缺失或过期"]){
   tr.append(el("td","",v));
  }
  body.append(tr);
 }
 table.append(body);wrap.append(table);
 const foot=el("p","insights-warning",
  "独立性审计结论：0项预测独立性认证。来源计数≠独立信号数。高相关不等于严格代数重复；同一会计体系不意味着数值相等。缺少逐日历史发布可得性和样本外验证，不能解锁六资产评分、历史策略收益和自动预警。");
 panel.append(intro,identities,wrap,foot);
}

// V49 factor evidence qualification: these are gates, NOT certified investment signals.
// A website first-seen timestamp is not a publisher's as-of release timestamp.
const QUALIFICATION_MIN_PERIODS={daily:252,weekly:104,monthly:36};
function factorQualification(rows,readiness,report){
 const validHistory=readiness?.schema_version===1&&
  readiness?.report_type==="asset_compass_history_readiness"&&
  readiness?.validated_for_live_scoring===false&&
  readiness?.eligible_for_point_in_time_backtest===false;
 const validReport=report?.schema_version===1&&
  report?.report_type==="asset_compass_factor_observations"&&
  report?.validated_for_live_scoring===false&&report?.factor_signals_calibrated===false&&
  report?.asset_specific_contributions_available===false;
 const byId=new Map((Array.isArray(rows)?rows:[]).map(r=>[r.id,r]));
 const reportObservations=validReport?Object.values(report.groups||{}).flatMap(g=>Array.isArray(g.observations)?g.observations:[]):[];
 const entries=OVERVIEW_INDICATORS.map(def=>{
  const row=byId.get(def.id),series=validHistory?readiness.series?.[def.id]:null;
  const periods=Number.isSafeInteger(series?.distinct_observation_periods)&&series.distinct_observation_periods>=0?
   series.distinct_observation_periods:null;
  const versions=Number.isSafeInteger(series?.archived_versions)&&series.archived_versions>=0?
   series.archived_versions:null;
  const observed=row?.state==="可用"&&isNumber(row?.value);
  const minimum=QUALIFICATION_MIN_PERIODS[def.cadence];
  const historyLength=periods!==null&&periods>=minimum;
  // Merely archiving a revised value is NEVER evidence of official release-time provenance.
  const releaseVerified=false;
  const revisionTraceVerified=false;
  // Shared lineage (V48) has been described, NOT statistically de-duplicated
  // with original PIT evidence or tested for incremental predictive information.
  const independentEvidence=false;
  const oosVerified=false;
  const reportMatch=reportObservations.some(r=>r&&r.validated_historical_release_time===true&&
    r.qualifies_as_model_factor_signal===true);
  return {id:def.id,name:def.name,cadence:def.cadence,
   observed,periods,versions,minimum,historyLength,releaseVerified,
   revisionTraceVerified,independentEvidence,oosVerified,
   // The current V49 report does not authorize any score even when a data
   // series eventually meets the minimum historical coverage gate.
   qualified:false,reportMatch};
 });
 return {entries,archivedTotal:validHistory&&Number.isSafeInteger(readiness.archived_observations)?
   readiness.archived_observations:null,
  historyVerified:validHistory,reportVerified:validReport,
  sourceMismatchCount:validHistory&&Number.isInteger(readiness.treasury_source_year_mismatch_rows)?
   readiness.treasury_source_year_mismatch_rows:null,
  certifiedSignalCount:0,scoringEnabled:false};
}
function renderFactorQualification(rows,readiness,report){
 const target=$("#factor-qualification");
 if(!target)return;
 target.replaceChildren();
 const audit=factorQualification(rows,readiness,report);
 const headline=el("p","muted","V49准入规则：先确认真实观测，再逐项检查历史样本覆盖、官方首发可得时间、修订追踪、重复信息增量检验及样本外验证。"+
  "历史覆盖研究下限：日频252、周频104、月频36个不同观测期；达到下限本身不等于合格。");
 const summary=el("p","label","证据记录："+
  (audit.archivedTotal===null?"首次归档报告未核实":audit.archivedTotal+"条网站首次归档记录")+
  "；已认证独立预测信号："+audit.certifiedSignalCount+
  "；正式评分：未启用。"+
  (audit.sourceMismatchCount===null?"":(" 已归档的财政部来源年份异常记录："+audit.sourceMismatchCount+"（需修复及原始版本核证）。")));
 const wrap=el("div","table-wrap"),table=el("table"),head=el("thead"),tr=el("tr");
 for(const label of ["源指标","当前观测","历史覆盖/下限","官方首发时间","修订追踪","信息独立增量","样本外验证","模型准入"]){
  const th=el("th","",label);th.scope="col";tr.append(th);
 }
 head.append(tr);table.append(head);
 const body=el("tbody");
 for(const item of audit.entries){
  const row=el("tr");
  const values=[item.name,item.observed?"有当前有效值":"缺失或过期",
   (item.periods===null?"未核实":item.periods)+"/"+item.minimum+"期",
   "未核实","未核实","未认证","未通过",
   item.qualified?"已准入":"仅研究 · 不可评分"];
  values.forEach(v=>row.append(el("td","",v)));
  body.append(row);
 }
 table.append(body);wrap.append(table);
 const note=el("p","insights-warning",
  "网站首次观察记录不代表官方首次发布日期；同一序列有多个归档版本不代表修订全历史可追溯。"+
  "V48的来源重叠审计和V47相关性也不能替代逐点PIT增量信息验证。"+
  "当前缺少合格历史首发版本、修订溯源与样本外资产总回报检验，14项源系列均不得解锁评分、回测收益或自动投资预警。");
 target.append(headline,summary,wrap,note);
}

// Stable primary publisher references; never use the legacy 2025 Treasury
// citation attached to the 2026 value as a live series source link.
const OFFICIAL_SOURCES={
 "treasury.":"https://home.treasury.gov/resource-center/data-chart-center/interest-rates",
 "bls.":"https://www.bls.gov/developers/",
 "bea.":"https://www.bea.gov/data/personal-consumption-expenditures-price-index",
 "fed_h41.":"https://www.federalreserve.gov/releases/h41/",
 "liquidity.":"https://fred.stlouisfed.org/",
 "nyfed.effr":"https://www.newyorkfed.org/markets/reference-rates/effr",
 "nyfed_recession.":"https://www.newyorkfed.org/research/capital_markets/ycfaq.html"
};
function sourceReference(id){
 const key=Object.keys(OFFICIAL_SOURCES).find(prefix=>id.startsWith(prefix));
 return key?OFFICIAL_SOURCES[key]:null
}
const ASSET_CONTEXT={
 gold:"观察实际利率、通胀补偿和美元条件。方向与因子贡献尚未校准。",
 us_equities:"观察利率、就业增长和流动性；不能直接推断指数涨跌。",
 us_long_bonds:"观察期限结构、通胀与货币政策；价格和总回报不同。",
 usd:"观察美国利率和相对货币政策；缺少海外相对利差信号。",
 bitcoin:"观察金融条件与风险偏好；暂无合格资产专属因子。",
 oil:"观察需求增长、通胀与供给；暂无合格库存和供需因子。"
};
// V41 contextual explanations reference observation values only. They are not
// calibrated factor signals, forward returns or buy/sell recommendations.
const ASSET_INSIGHTS={
 gold:{name:"黄金",items:[
  ["treasury.real10y","实际利率代表持有无息黄金的机会成本背景；影响还取决于风险偏好与美元。"],
  ["treasury.breakeven10y","期限通胀补偿包含风险和流动性溢价；不等于纯粹的通胀预期。"],
  ["bea.core_pce","核心PCE反映通胀环境，不能仅凭其绝对值预测金价。"],
  ["nyfed.effr","短端融资利率影响资金条件；不是黄金价格的独立交易信号。"]
 ]},
 us_equities:{name:"美股",items:[
  ["treasury.us10y","长端国债利率影响折现率；对股价的影响同时取决于盈利预期。"],
  ["bls.payroll","就业月增量可描述经济活动，但没有基期和盈利数据不能推导股市方向。"],
  ["bls.unemployment","失业率反映劳动力市场状况，与估值、政策预期共同作用。"],
  ["bea.core_pce","核心PCE是通胀约束之一，单期数据并不构成股市择时信号。"]
 ]},
 us_long_bonds:{name:"美国长期国债",items:[
  ["treasury.us10y","长期债券价格通常与市场要求的收益率反向变化；持有到期与ETF净值不同。"],
  ["treasury.real10y","TIPS实际利率反映长期实际贴现条件；并非完整债券总回报。"],
  ["treasury.breakeven10y","通胀补偿分解名义收益率的背景，包含期限风险和流动性因素。"],
  ["treasury.spread10y2y","10Y−2Y利差是期限结构观测，不等于衰退必然发生。"]
 ]},
 usd:{name:"美元",items:[
  ["nyfed.effr","美国有效政策利率反映美元短期融资环境；汇率仍需比较海外利率。"],
  ["treasury.us2y","美国两年期收益率反映近期政策定价；相对利差与风险情绪尚缺失。"],
  ["treasury.us10y","美国长端收益率是资本流动的背景指标，不能单独预测美元指数。"],
  ["bea.core_pce","通胀可能影响政策预期，但绝对水平不能直接转为美元多空信号。"]
 ]},
 bitcoin:{name:"比特币",items:[
  ["nyfed.effr","短期资金价格是加密资产流动性环境的一部分，影响并不稳定。"],
  ["liquidity.reserves","银行准备金是金融体系流动性组件，不可直接等同于加密市场可用资金。"],
  ["treasury.real10y","实际贴现率是风险资产定价背景，但不能直接推导比特币回报。"],
  ["nyfed_recession.probability","纽约联储模型衡量12个月后某个月的衰退概率，不是对比特币的预测。"]
 ]},
 oil:{name:"原油",items:[
  ["bls.payroll","就业月增量可作为需求景气背景，无法替代实际原油消费统计。"],
  ["bls.unemployment","劳动力市场数据有助于观察美国需求，但未覆盖全球供需。"],
  ["bea.core_pce","核心PCE剔除食品与能源，属于货币政策背景，不能用它估算油价。"],
  ["treasury.us10y","长端利率是经济周期及资金成本观测；缺少库存、OPEC供给和期货结构。"]
 ]}
};
function derivedContextObservation(id,observations){
 const byId=new Map(observations.map(x=>[x.id,x]));
 const nominal=byId.get("treasury.us10y"),secondary=byId.get(
  id==="treasury.breakeven10y"?"treasury.real10y":"treasury.us2y");
 if(!nominal||!secondary||nominal.value===null||secondary.value===null||
    nominal.period!==secondary.period)return null;
 return {id,name:id==="treasury.breakeven10y"?"10年期通胀补偿（派生）":"10Y−2Y利差（派生）",
    value:nominal.value-secondary.value,unit:"百分点",precision:2,
    period:nominal.period,source:"美国财政部同日收益率差值",
    state:"可用",derived:true};
}
function renderAssetInsights(assetId,observations){
 const target=$("#asset-insights"),def=ASSET_INSIGHTS[assetId];
 if(!target||!def)return;
 const byId=new Map(observations.map(x=>[x.id,x]));
 const heading=el("h3","insights-title",def.name+" · 相关宏观观测");
 const note=el("p","muted","以下是当前观测值与宏观经济含义，不代表方向预测、独立因子评分或资产收益预期。");
 const list=el("div","insights-list");
 for(const [indicatorId,explanation] of def.items){
  const obs=byId.get(indicatorId)||
     (indicatorId.startsWith("treasury.")?derivedContextObservation(indicatorId,observations):null);
  const row=el("article","insights-item"),label=el("div","label",obs?.name||indicatorId);
  const value=obs?.value===null||!obs?"数据缺失或过期":
   obs.value.toLocaleString("zh-CN",{minimumFractionDigits:obs.precision,
      maximumFractionDigits:obs.precision})+" "+obs.unit;
  const amount=el("div","insights-value",value);
  const meta=el("div","label","观测期："+(obs?.period||"未知")+" · "+(obs?.source||"暂无来源")+
      (obs?.derived?" · 同日代数派生，非独立来源":""));
  const expl=el("p","muted",explanation);
  row.append(label,amount,meta,expl);list.append(row);
 }
 const warning=el("p","insights-warning","尚缺少完整风险信用、估值与资金流等独立信号，不能把这些指标简单相加为0–100分。");
 target.replaceChildren(heading,note,list,warning);
}
function renderAssetSelection(assetId,rows){
 const valid=Object.hasOwn(ASSET_INSIGHTS,assetId)?assetId:"gold";
 for(const b of document.querySelectorAll("[data-insight-asset]")){
  const selected=b.dataset.insightAsset===valid;
  b.setAttribute("aria-pressed",selected?"true":"false");
 }
 renderAssetInsights(valid,rows);
}

function observationCurrent(def,period){
 return def.cadence==="monthly"?isoMonth(period,4):isoDay(period,def.cadence==="weekly"?21:11)
}
function overviewObservations(data){
 const valid=data?.schema_version===1&&data?.scoring?.calibration_verified===false&&data?.scoring?.out_of_sample_verified===false;
 return OVERVIEW_INDICATORS.map(def=>{
  const period=valid?def.period(data):null;
  const value=valid?def.value(data):null;
  const inRange=def.id==="nyfed_recession.probability"?(isNumber(value)&&value>=0&&value<=100):
    def.id==="bls.unemployment"?(isNumber(value)&&value>=0&&value<=100):
    def.id==="bls.payroll"?(isNumber(value)):
    (isNumber(value)&&value>=0);
  const present=inRange&&observationCurrent(def,period);
  return {id:def.id,name:def.name,group:def.group,source:def.source,
   period:period||"—",unit:def.unit,value:present?value:null,
   precision:def.precision,state:present?"可用":"缺失或过期"};
 });
}
function headline(data){
 const grid=$("#headline");if(!grid)return;
 const valid=data?.schema_version===1&&data?.scoring?.calibration_verified===false;
 const values=[["10年期名义收益率",data?.rates?.us10y,"%"],
               ["10年期实际收益率",data?.rates?.real10y,"%"],
               ["10Y−2Y期限利差",data?.rates?.spread10y2y,"百分点"]];
 const fresh=valid&&isoDay(data?.observation_date,11);
 grid.replaceChildren(...values.map(([title,v,unit])=>
  card(title,fresh&&isNumber(v)?v.toFixed(2)+unit:"暂无有效数据",
       "美国财政部 · 观测日："+(data?.observation_date||"缺失"))));
}


// V55 genuine, latest-revised historical rate shocks: never scoring inputs.


function renderAssetSpecificV57(report,v56){
 const target=$("#asset-specific-v57");if(!target)return;
 target.replaceChildren();
 const reject=(msg)=>target.replaceChildren(el("p","insights-warning",msg));
 if(!report||report.schema_version!==1||
  report.report_type!=="asset_compass_v57_authentic_asset_specific_source_research"||
  report.status!=="research_only_no_model_promotion"||
  report.validated_for_live_scoring!==false||
  report.eligible_for_point_in_time_backtest!==false||
  report.approved_asset_scores!==0||report.first_publication_vintages_certified!==0||
  report.independent_model_factor_qualified_count!==0||
  !report.sources||!report.assets||Object.keys(report.assets).length!==6||
  !v56||report.v56_observed_at!==v56.generated_at||
  report.v56_oil_source_date!==v56.sources?.oil_inventory?.latest_observation_date){
  reject("V57资产专属官方报告未发布、已过期或不匹配原油源历史。正式六资产评分保持关闭。");return;
 }
 const gold=report.sources.cftc_gold,bond=report.sources.treasury_30y;
 if(!gold||gold.series_id!=="CFTC_COMEX_GOLD_MANAGED_MONEY_FUTURES_ONLY"||
   !bond||bond.series_id!=="TREASURY_30Y_BOND_AUCTION_BID_TO_COVER"||
   !/^[a-f0-9]{64}$/.test(gold.source_sha256||"")||
   !/^[a-f0-9]{64}$/.test(bond.source_sha256||"")||
   !Number.isSafeInteger(gold.observation_count)||gold.observation_count<105||
   !Number.isSafeInteger(bond.auction_count)||bond.auction_count<37||
   gold.reference_count!==104||bond.reference_count!==36||
   gold.report_date_is_publication_time!==false||
   bond.auction_date_is_publication_time!==false||
   gold.signal_verified!==false||bond.signal_verified!==false||
   !isNumber(gold.latest_managed_money_net_percent_oi)||
   !isNumber(gold.latest_managed_money_net_contracts)||
   !isNumber(bond.latest_bid_to_cover_ratio)||
   (gold.research_z_score!==null&&!isNumber(gold.research_z_score))||
   (bond.research_z_score!==null&&!isNumber(bond.research_z_score))||
   Object.values(report.assets).some(a=>a.score!==null||
     a.verified_asset_specific_model_signal!==false||
     a.historic_as_published_vintages_certified!==false||
     a.historical_calibration_passed!==false||
     a.out_of_sample_validation_passed!==false)){
  reject("V57来源、历史标准化或者正式评分安全标志未通过审计，拒绝展示数据。");return;
 }
 target.append(el("p","muted","来源观测：黄金CFTC持仓、长期国债30年期拍卖、原油EIA库存。其余三种资产专属数据尚缺；合格方向信号仍为0/6，正式0–100评分全部未开放。"));
 const specs=[
   {name:"黄金 · CFTC管理资金净持仓",date:gold.latest_observation_date,level:gold.latest_managed_money_net_contracts.toLocaleString("en-US")+" 张合约",z:gold.research_z_score,source:"CFTC·周二仓位",fresh:gold.fresh_for_research===true&&isoDay(gold.latest_observation_date,18)},
   {name:"美国长期国债 · 30年拍卖投标倍数",date:bond.latest_auction_date,level:bond.latest_bid_to_cover_ratio.toFixed(2)+" 倍",z:bond.research_z_score,source:"财政部·单次拍卖",fresh:bond.fresh_for_research===true&&isoDay(bond.latest_auction_date,75)},
   {name:"原油 · EIA商业库存",date:v56.sources.oil_inventory.latest_observation_date,level:v56.sources.oil_inventory.latest_level.toLocaleString("en-US")+" 千桶",z:v56.sources.oil_inventory.research_z_score,source:"EIA·周频存量",fresh:v56.sources.oil_inventory.current_observation_fresh===true&&isoDay(v56.sources.oil_inventory.latest_observation_date,21)}
 ];
 if(specs.some(x=>x.z!==null&&!isNumber(x.z))){
  reject("V57组合来源数值异常，不展示历史计算。");return;
 }
 const table=el("table"),head=el("thead"),tr=el("tr");
 for(const label of ["资产专属观测","观测日","实际数值","描述性Z值","观测可用性"]){
  const th=el("th","",label);th.scope="col";tr.append(th);
 }
 head.append(tr);table.append(head);const body=el("tbody");
 for(const src of specs){
  const row=el("tr");
  for(const value of [src.name,src.date,src.level,
   src.z===null?"无有效方差":src.z.toFixed(2),src.fresh?"近期观测（未校准）":"过期或未验证"]){
   row.append(el("td","",value));
  }
  body.append(row);
 }
 table.append(body);const wrap=el("div","table-wrap");wrap.append(table);target.append(wrap);
 const missing=Object.keys(ASSETS).filter(id=>!report.assets[id]?.asset_specific_research_source_available).map(id=>ASSETS[id]);
 target.append(el("p","muted","仍缺专属数据："+(missing.join("、")||"无")+"。有来源仅代表可分析原始观察值，不代表资产方向经过历史回测。"));
 const links=el("p","muted","官方原始资料：");
 const g=el("a","","CFTC Commitments of Traders");g.href="https://www.cftc.gov/MarketReports/CommitmentsofTraders/index.htm";
 const b=el("a","","美国财政部拍卖记录");b.href="https://fiscaldata.treasury.gov/datasets/treasury-securities-auctions-data/";
 links.append(g,el("span",""," · "),b);target.append(links);
 target.append(el("p","insights-warning","CFTC净持仓不是黄金ETF资金流；财政部投标倍数不是长期债券总回报；观测日不等于首次公开发布时间，禁止作为已验证评分输入。"));
}

function renderOfficialSourcesV56(report){
 const target=$("#new-sources-v56");if(!target)return;
 target.replaceChildren();
 const fail=(msg)=>target.replaceChildren(el("p","insights-warning",msg));
 if(!report||report.schema_version!==1||
    report.report_type!=="asset_compass_v56_official_risk_and_oil_research"||
    !["research_only_two_official_sources_current","research_only_one_or_more_sources_stale"].includes(report.status)||
    report.approved_asset_scores!==0||report.validated_for_live_scoring!==false||
    report.eligible_for_point_in_time_backtest!==false||
    report.independent_scoring_factor_groups_qualified!==0||
    report.source_vintages_qualified!==0||
    report.groups_with_any_observation_across_v54_and_v56!==6||
    !report.sources||!report.assets||Object.keys(report.assets).length!==6){
  fail("V56 官方数据尚未发布或未经完整来源/评分安全验证。风险与原油研究暂不展示，0–100正式评分仍不可用。");return;
 }
 const nfci=report.sources.nfci,oil=report.sources.oil_inventory;
 const checks=[[nfci,"NFCI","risk"],[oil,"WCESTUS1","asset_specific"]];
 for(const [v,sid,group] of checks){
  if(!v||v.series_id!==sid||v.group!==group||
     !/^([0-9a-f]{64})$/.test(v.source_raw_sha256||"")||
     !isNumber(v.latest_level)||!isNumber(v.latest_week_delta)||
     !Number.isSafeInteger(v.observation_count)||v.observation_count<112||
     v.reference_104week_count!==104||
     v.first_publication_vintages_verified!==false||
     v.independent_scoring_signal_qualified!==false||
     v.out_of_sample_calibration_passed!==false||
     !Array.isArray(v.recent_observations)||!v.recent_observations.length||
     (v.research_z_score!==null&&!isNumber(v.research_z_score))){
   fail("V56 来源身份、数值、历史覆盖或PIT/评分门禁不一致，拒绝展示。");return;
  }
 }
 if(Object.values(report.assets).some(a=>a.score!==null||
    a.research_price_direction_signal!==null||
    a.validated_for_live_scoring!==false||
    a.independent_model_signal_coverage_pct!==0)){
   fail("V56 含未经授权的资产分数或交易信号，拒绝展示。");return;
 }
 target.append(el("p","muted",
  "V56新增两个可追溯官方观察系列：风险信用研究组有NFCI；原油资产专属研究组有EIA库存。"+
  "结合旧版源观察，六个因子组已有数据入口，但仅原油取得本次资产专属数据；独立合格评分因子仍为0。"));
 const table=el("table"),head=el("thead"),tr=el("tr");
 for(const name of ["官方指标","最新周观测","实际观测值","与前周变化","研究标准化Z","状态"]){
  const th=el("th","",name);th.scope="col";tr.append(th);
 }
 head.append(tr);table.append(head);const body=el("tbody");
 const items=[
  {s:nfci,name:"芝加哥联储NFCI",unit:"指数点",digits:3,delta:3},
  {s:oil,name:"EIA商业原油库存（不含SPR）",unit:"千桶",digits:0,delta:0},
 ];
 for(const {s:source,name,unit,digits,delta} of items){
  const fresh=isoDay(source.latest_observation_date,21)&&source.current_observation_fresh===true;
  const r=el("tr");
  const values=[name,source.latest_observation_date,
   source.latest_level.toFixed(digits)+" "+unit,
   source.latest_week_delta.toFixed(delta)+" "+unit,
   source.research_z_score===null?"缺乏有效基准":source.research_z_score.toFixed(2),
   fresh?"观察有效，未校准":"过期或未验证"];
  for(const value of values)r.append(el("td","",value));body.append(r);
 }
 table.append(body);const wrap=el("div","table-wrap");wrap.append(table);target.append(wrap);
 target.append(el("p","muted",
  "NFCI正值通常代表金融条件较历史平均偏紧，负值较宽松；其内含利率与信用指标，不能与旧因子重复投票。"+
  "原油库存是千桶存量，库存增加不等于油价必跌。库存周末日期不等于官方发布时刻，历史修订链未认证。"));
 const sources=el("p","muted","官方数据：");
 const l1=el("a","","芝加哥联储 NFCI，经FRED");l1.href="https://fred.stlouisfed.org/series/NFCI";
 const l2=el("a","","美国能源信息署 EIA WCESTUS1");l2.href="https://www.eia.gov/dnav/pet/hist/LeafHandler.ashx?f=W&n=PET&s=WCESTUS1";
 sources.append(l1,el("span",""," · "),l2);target.append(sources);
 target.append(el("p","insights-warning",
  "上述真实数据是研究观察，不是ICE高收益债OAS、六资产价格预测、历史PIT合格信号或正式0–100分。"));
}

function renderRateShocksV55(report,data){
 const target=$("#rate-shocks-v55");
 if(!target)return;
 target.replaceChildren();
 const invalid=!report||report.schema_version!==1||
  report.report_type!=="asset_compass_v55_real_treasury_rate_shock_research"||
  report.status!=="research_only_latest_revised_rate_shocks"||
  report.validated_for_live_scoring!==false||
  report.eligible_for_point_in_time_backtest!==false||
  report.historical_first_publication_vintages_verified!==false||
  report.asset_direction_signs_empirically_calibrated!==false||
  report.official_0_to_100_scores_published!==0||
  report.asset_hypothesis_count!==2||report.source_snapshot_generated_at!==data?.generated_at||
  !report.shock_features||!report.assets||Object.keys(report.assets).length!==6||
  !Number.isSafeInteger(report.source_observation_count)||report.source_observation_count<274;
 if(invalid){
  target.append(el("p","insights-warning",
   "V55 真实利率研究报告缺失或与当前宏观快照不一致；不显示过时或未审核的方向假设，正式资产评分仍未开放。"));
  return;
 }
 const fresh=isoDay(report.source_end_date,11);
 target.append(el("p","muted",
  "历史来源："+report.source+"；"+report.source_observation_count+
  "个真实观测；区间 "+report.source_start_date+" 至 "+report.source_end_date+
  "；数据时效："+(fresh?"未超出11日展示门槛":"已超过11日，不能视作当前研究信号")+
  "。计算使用21个观测期变动及252期基准；不是首次发布PIT版本。"));
 const titles={us10y:"10年名义收益率",us2y:"2年名义收益率",
  real10y:"10年实际收益率",breakeven10y:"10年通胀补偿（派生）",
  spread10y2y:"10Y−2Y利差（派生）"};
 const table=el("table"),head=el("thead"),tr=el("tr");
 for(const v of ["真实历史指标","21期变化","滚动标准化Z","数据角色"]){
  const th=el("th","",v);th.scope="col";tr.append(th);
 }
 head.append(tr);table.append(head);const body=el("tbody");
 for(const [key,name] of Object.entries(titles)){
  const item=report.shock_features[key];
  if(!item||item.historical_pit_verified!==false||
     item.qualified_independent_model_signal!==false||
     !isNumber(item.period_change_basis_points)||
     !Number.isSafeInteger(item.prior_baseline_period_count)||
     item.prior_baseline_period_count<252||
     (item.research_z_score!==null&&!isNumber(item.research_z_score))){
   target.replaceChildren(el("p","insights-warning","V55历史利率字段未通过完整性校验，不展示研究数字。"));return;
  }
  const row=el("tr");
  const type=key==="breakeven10y"||key==="spread10y2y"?"代数派生（非独立票）":"收益率系列（尚未认证独立性）";
  for(const v of [name,item.period_change_basis_points.toFixed(2)+" bp",
    item.research_z_score===null?"缺少有效方差":item.research_z_score.toFixed(2),type])row.append(el("td","",v));
  body.append(row);
 }
 table.append(body);const wrap=el("div","table-wrap");wrap.append(table);target.append(wrap);
 const another=el("div","table-wrap"),assetTable=el("table"),ahead=el("thead"),arow=el("tr");
 for(const h of ["资产","经济机制假设","当前标准化压力候选","正式评分"]){
  const th=el("th","",h);th.scope="col";arow.append(th);
 }
 ahead.append(arow);assetTable.append(ahead);const abody=el("tbody");
 for(const [id,name] of Object.entries(ASSETS)){
  const a=report.assets[id];
  if(!a||a.official_score!==null||a.eligible_for_live_scoring!==false||
     a.historical_calibration_passed!==false||a.out_of_sample_validation_passed!==false||
     (a.rate_pressure_candidate!==null&&
      (!isNumber(a.rate_pressure_candidate)||Math.abs(a.rate_pressure_candidate)>1||
       a.candidate_scoring_entry?.verified!==false))){
   target.replaceChildren(el("p","insights-warning","V55资产压力假设报告未通过防误用校验。"));return;
  }
  const phrase=a.research_hypothesis||"缺乏足够经济与历史证据，不推断方向";
  const candidate=fresh&&isNumber(a.rate_pressure_candidate)?
    a.rate_pressure_candidate.toFixed(3)+"（未校准）":"不提供";
  const row=el("tr");
  for(const value of [name,phrase,candidate,"— / 100"])row.append(el("td","",value));
  abody.append(row);
 }
 assetTable.append(abody);another.append(assetTable);target.append(another);
 target.append(el("p","insights-warning",
  "Z值与候选压力是描述性研究量，不是上涨概率、资产收益预测、PIT交易信号或正式0–100分。"));
}

function renderScoringReadiness(report,data,observations){
 const target=$("#scoring-readiness-v54");
 if(!target)return;
 target.replaceChildren();
 if(!report||report.schema_version!==1||report.report_type!=="asset_compass_v54_scoring_readiness"||
    report.status!=="research_only_no_authorized_scores"||report.validated_for_live_scoring!==false||
    report.independently_qualified_factor_groups!==0||report.asset_count!==6||report.factor_group_count!==6||
    report.source_pit_qualified_count!==0||
    report.source_snapshot_generated_at!==data?.generated_at||
    report.source_observations_generated_at!==observations?.generated_at||
    !report.assets||!report.groups){
  target.append(el("p","insights-warning","V54 评分就绪报告缺失、格式异常或与当前宏观快照不匹配；不能沿用旧数据声称因子覆盖。六资产正式评分仍未开放。"));
  return;
 }
 const groups=Object.keys(FACTORS);
 const groupNames=groups.map(g=>report.groups[g]?.label);
 if(groupNames.some(x=>typeof x!=="string")||
    Object.keys(report.assets).length!==Object.keys(ASSETS).length||
    Object.values(report.assets).some(a=>a.status!=="unavailable"||a.score!==null||
       a.qualified_model_signal_coverage_pct!==0||a.validated_for_live_scoring!==false)){
  target.append(el("p","insights-warning","评分就绪报告存在未经授权的资产得分或缺失的因子组；拒绝展示此报告。"));
  return;
 }
 target.append(el("p","muted",
  "六资产已取得正式评分：0/6；有实际宏观观测的因子组 "+
  report.groups_with_source_observations+"/6，尚无数据的因子组 "+
  report.groups_without_source_observations+"/6；独立合格的模型因子组 0/6。"+
  "实际宏观观测≠已验证的资产方向信号；所有分数仍关闭。"));
 const wrap=el("div","table-wrap"),table=el("table"),head=el("thead"),tr=el("tr");
 for(const label of ["资产","有宏观观测的权重（仅研究）","合格信号覆盖","缺少原始数据的因子组","正式分数"]){
  const cell=el("th","",label);cell.scope="col";tr.append(cell);
 }
 head.append(tr);table.append(head);
 const body=el("tbody");
 for(const [id,name] of Object.entries(ASSETS)){
  const info=report.assets[id];
  if(!info||!Array.isArray(info.missing_source_groups)||
     !isNumber(info.source_observation_weight_pct_research_only)||
     info.source_observation_weight_pct_research_only<0||
     info.source_observation_weight_pct_research_only>100){
   target.replaceChildren(el("p","insights-warning","六资产评分就绪数据未通过一致性审查。"));return;
  }
  const missing=info.missing_source_groups.map(g=>FACTORS[g]||g).join("、")||"无（仍待信号校准）";
  const row=el("tr");
  for(const value of [name,info.source_observation_weight_pct_research_only+"%（非评分覆盖）",
   "0%",missing,"— / 100"])row.append(el("td","",value));
  body.append(row);
 }
 table.append(body);wrap.append(table);target.append(wrap);
 target.append(el("p","muted",
  "现存历史归档 "+report.website_archived_first_seen_records+
  " 条，财政部旧来源年份待纠正 "+report.treasury_source_year_mismatch_records+
  " 条；官方历史首发时点、因子方向校准及样本外验证均未通过。"+
  "研究用观测权重不是得分，也不是投资建议。"));
}

function overview(data,readiness,qualifications,scoringReadiness,rateShocks,newSources,assetSpecific){
 const snapshotValid=data?.schema_version===1&&data?.assets&&typeof data?.scoring?.calibration_verified==="boolean"&&typeof data?.scoring?.out_of_sample_verified==="boolean";
 const approved=snapshotValid?data:null;
 const rows=overviewObservations(approved);
 renderIndependenceAudit(rows);
 renderFactorQualification(rows,readiness,qualifications);
 renderScoringReadiness(scoringReadiness,approved,qualifications);
 renderRateShocksV55(rateShocks,approved);
 renderOfficialSourcesV56(newSources);
 renderAssetSpecificV57(assetSpecific,newSources);
 const usable=rows.filter(x=>x.state==="可用").length;
 const snapshotTime=approved?.generated_at?Date.parse(approved.generated_at):NaN;
 const age=Date.now()-snapshotTime;
 const snapshotOk=Number.isFinite(snapshotTime)&&age>=0;
 const delayed=!snapshotOk||age>72*3600*1000;
 const status=$("#source-status");
 if(status)status.textContent=!approved?"数据未通过快照和评分锁定校验；暂停展示数值。":
   "官方数据快照："+(snapshotOk?new Date(snapshotTime).toLocaleString("zh-CN",{timeZone:"Asia/Shanghai",hour12:false})+"（北京时间）":"时间无效")+
   "；14项必需指标中 "+usable+" 项仍在各自可用期限内。"+
   (delayed?" 注意：数据快照超过72小时未更新或生成时间异常。下方各指标按自身观测期单独判定，可能包含仍有效的月度值；请检查采集任务。":" 当前快照可供研究浏览。")+
   " 不代表实时行情或已验证资产预测。";
 headline(approved);
 const validReady=readiness?.schema_version===1&&readiness.report_type==="asset_compass_history_readiness"&&readiness.validated_for_live_scoring===false;
 const summary=$("#overview-kpis");
 if(summary)summary.replaceChildren(
  card("当前有效宏观指标",usable+" / 14","14项必需源；缺失、过期均不填零"),
  card("正式评分状态","尚未启用","六因子仍需历史校准及样本外验证"),
  card("首次观测归档",validReady&&Number.isInteger(readiness.archived_observations)?readiness.archived_observations+" 条":"未核实","记录版本数，不等于交易日或官方首次发布次数")
 );
 const body=$("#macro-table-body");
 const input=$("#indicator-search"),filter=$("#indicator-filter"),count=$("#indicator-count");
 function draw(){
  if(!body)return;
  const search=(input?.value||"").trim().toLocaleLowerCase();
  const group=filter?.value||"all";
  const shown=rows.filter(r=>(group==="all"||r.group===group)
     &&(!search||(r.name+" "+r.source+" "+r.id).toLocaleLowerCase().includes(search)));
  body.replaceChildren(...shown.map(r=>{
   const tr=el("tr");
   const value=r.value===null?"—":r.value.toLocaleString("zh-CN",{minimumFractionDigits:r.precision,maximumFractionDigits:r.precision})+" "+r.unit;
   [r.name,value,r.period,r.source,r.state].forEach((v,i)=>{
    const td=el("td","",v);
    if(i===3){
     const url=sourceReference(r.id);
     if(url){const a=el("a","source-link",v);a.href=url;a.target="_blank";a.rel="noopener noreferrer";td.append(a)}
     else td.textContent=v;
    }
    if(i===4)td.className=r.value===null?"data-unavailable":"data-ready";
    tr.append(td);
   });
   return tr;
  }));
  if(count)count.textContent="显示 "+shown.length+" / 14 项 · "+
    shown.filter(x=>x.value!==null).length+" 项当前可用";
  if(!shown.length)body.replaceChildren(el("tr","",undefined));
  if(!shown.length){const td=el("td","", "没有符合条件的指标");td.colSpan=5;body.firstChild.append(td)}
 }
 if(input)input.addEventListener("input",draw);
 if(filter)filter.addEventListener("change",draw);
 draw();
 const assets=$("#asset-grid");
 if(assets)assets.replaceChildren(...Object.entries(ASSETS).map(([id,name])=>{
  const a=approved?.assets?.[id]||{};
  const gated=approved?.scoring?.calibration_verified===true&&approved?.scoring?.out_of_sample_verified===true&&usableScore(a);
  const node=card(name,gated?scoreText(a):"— / 100",ASSET_CONTEXT[id]);
  node.append(el("div","label","状态："+(gated?"已通过评分验证":"评分未校准 · 不做利多利空预测")));
  const inspect=el("button","insights-select","查看宏观依据");
  inspect.type="button";inspect.dataset.insightAsset=id;
  inspect.setAttribute("aria-pressed","false");
  inspect.setAttribute("aria-controls","asset-insights");
  inspect.addEventListener("click",()=>renderAssetSelection(id,rows));
  node.append(inspect);
  // Separate user action connects the V41 asset explanation to V43 Treasury
  // history. Do not silently infer future returns from the selected yields.
  const trend=el("button","asset-trend-focus","查看关联利率趋势");
  trend.type="button";
  trend.dataset.trendAsset=id;
  trend.addEventListener("click",()=>{
   renderAssetSelection(id,rows);
   if(typeof window!=="undefined"&&typeof window.ooglexTreasuryFocus==="function")
    window.ooglexTreasuryFocus(id);
  });
  node.append(trend);
  const links=el("div","asset-links");
  const detail=el("a","","查看因子权重");detail.href="./attribution.html";
  const history=el("a","","查看回测准备度");history.href="./research.html";
  links.append(detail,history);node.append(links);return node;
 }));
 if(assets&&$("#asset-insights"))renderAssetSelection("gold",rows);
 const archive=$("#history-status");
 if(archive)archive.textContent="CPI、PCE等当前数值可能包含后续修订；首次观测归档不是官方原始发布版本。"+
  "盈亏平衡通胀补偿、实际利率与名义利率相关，不能当作独立投票；"+
  "美联储资产、准备金和逆回购存在频率与单位差异，不直接合成买卖信号。"+
  "正式评分、回测收益率和预警均未启用。";
}
function overviewFailure(){overview(null,null)}
function attribution(config,data){const target=$("#factor-table");if(!config||!Array.isArray(config.factor_order)||!config.weights){target.replaceChildren(el("p","empty","无法读取六因子权重配置。"));return}const table=el("table"),head=el("thead"),tr=el("tr");["资产",...config.factor_order.map(x=>FACTORS[x]||x),"合计"].forEach(x=>tr.append(el("th","",x)));head.append(tr);const body=el("tbody");Object.entries(ASSETS).forEach(([id,name])=>{const weights=config.weights[id];if(!Array.isArray(weights)||weights.length!==6)return;const row=el("tr");row.append(el("td","",name));weights.forEach(v=>row.append(el("td","",isNumber(v)?v+"%":"—")));row.append(el("td","",weights.every(isNumber)?weights.reduce((a,b)=>a+b,0)+"%":"—"));body.append(row)});table.append(head,body);target.replaceChildren(table);
const factors=$("#factor-cards");const names=config.factor_order||[];factors.replaceChildren(...names.map((name)=>{const relevant=(config.indicator_registry||[]).filter(x=>x.group===name),ready=relevant.filter(x=>x.status==="implemented");const node=card(FACTORS[name]||name,"—","可用指标定义："+ready.length+"/"+relevant.length+"；未计算经历史校准的资产专属信号。");node.append(el("div","label","当前值不等于因子得分，未启用收益预测。"));return node}));
const reasons=$("#attribution-status");reasons.textContent="权重来自模型配置（未校准的V1初始研究参数）。指标接入状态不代表独立信号覆盖；名义利率、实际利率和盈亏平衡通胀之间有数学关联，不应重复计分。"}
function renderFactorObservations(report){
 const root=$("#factor-observations"),status=$("#factor-observation-status");
 if(!root||!status)return;
 if(!report||report.schema_version!==1||report.report_type!=="asset_compass_factor_observations"||report.validated_for_live_scoring!==false||report.factor_signals_calibrated!==false||report.asset_specific_contributions_available!==false){
  root.replaceChildren(card("因子观测","暂无可核验的报告","尚未取得符合格式的真实宏观研究明细。"));
  status.textContent="因子数据尚未通过报告校验；不可据此推断资产走势。";return
 }
 const keys=["rates","inflation","growth","liquidity","risk","asset_specific"];
 root.replaceChildren(...keys.map(id=>{
  const group=report.groups?.[id]||{};
  const items=Array.isArray(group.observations)?group.observations:[];
  const box=el("article","card"),name=el("div","label",group.label||FACTORS[id]||id);
  const n=el("div","big",items.length+" 项观测");
  const hint=el("p","muted",items.length?"均仅为当期公开研究观测，未校准因子方向。":"缺少合格数据，不能视为中性因子。");
  box.append(name,n,hint);
  for(const item of items){
   if(!item||item.validated_historical_release_time!==false||item.qualifies_as_model_factor_signal!==false||!isNumber(item.value))continue;
   const section=el("div","key");
   const heading=el("div","",item.label||item.id||"未命名观测");
   heading.style.fontWeight="600";
   const detail=el("div","","观测："+item.value.toLocaleString("zh-CN",{maximumFractionDigits:6})+" "+(item.unit||"")+" · "+(item.observation_period||"日期未知"));
   const source=el("div","",item.source||"来源未说明");
   section.append(heading,detail,source);
   if(item.formula)section.append(el("div","",item.formula));
   box.append(section);
  }
  return box
 }));
 status.textContent="报告生成于："+(report.generated_at||"未知")+"；仅有原始观测和代数关系，没有经过历史验证的六因子信号，也不构成六资产因子贡献。";
}
function research(price,readiness){const out=$("#price-grid");if(!price||price.report_type!=="price_coverage_audit"||price.validated_for_live_scoring!==false){out.replaceChildren(el("p","empty","历史价格覆盖报告尚未发布或无效。"));}else{out.replaceChildren(...Object.entries(ASSETS).map(([id,name])=>{const a=price.assets?.[id]||{};const n=isNumber(a.observation_count)?a.observation_count:0;const node=card(name,n+" 条价格观测","来源代理："+(a.symbol||"未记录")+" · "+(a.last_observation||"暂无有效日期"));node.append(el("div","label","非可投资总回报；未通过回测准入。"));return node}))}
const block=$("#archive-data");if(readiness&&readiness.report_type==="asset_compass_history_readiness"&&readiness.validated_for_live_scoring===false){const count=readiness.archived_observations;block.replaceChildren(card("首次归档观测数",Number.isInteger(count)?count:"暂无数据","记录网站首次看到数值的时间，不代表官方最初发布时间。"));const list=$("#blockers");list.replaceChildren(...(readiness.blockers||[]).map(x=>el("li","",x)));}else{block.replaceChildren(card("首次归档状态","未发布","没有可核实的正式历史归档进度，不能把CI测试样本当作生产历史。"));$("#blockers").replaceChildren(el("li","","官方首发版本、统一总回报、独立样本外模型验收尚未通过。"))}$("#research-status").textContent="暂不公布历史命中率、资金曲线、最大回撤或资产预警阈值。数据来源及模型尚未达到可验证标准。";}
async function run(){const page=document.body.dataset.page;if(page==="overview"){const [data,readiness,qualifications,scoringReadiness,rateShocks,newSources,assetSpecific]=await Promise.all([optional(DATA),optional(READY),optional(OBSERVATIONS),optional(SCORING_READINESS),optional(RATE_SHOCKS_V55),optional(OFFICIAL_SOURCES_V56),optional(ASSET_SPECIFIC_V57)]);overview(data,readiness,qualifications,scoringReadiness,rateShocks,newSources,assetSpecific);return}if(page==="attribution"){const [config,data,observations]=await Promise.all([optional(CONFIG),optional(DATA),optional(OBSERVATIONS)]);attribution(config,data);renderFactorObservations(observations);return}if(page==="research"){const [price,readiness]=await Promise.all([optional(PRICE),optional(READY)]);research(price,readiness);return}}
run().catch(()=>{const node=$("#source-status")||$("#attribution-status")||$("#research-status");if(node)node.textContent="数据读取暂不可用；不会以示例数值代替真实数据。"});

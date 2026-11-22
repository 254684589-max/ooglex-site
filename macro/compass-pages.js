"use strict";
const ASSETS={gold:"黄金",us_equities:"美股",us_long_bonds:"美国长期国债",usd:"美元",bitcoin:"比特币",oil:"原油"};
const FACTORS={rates:"利率与货币政策",inflation:"通胀",growth:"经济增长与就业",liquidity:"美元与流动性",risk:"市场风险与信用",asset_specific:"资金流与估值"};
const DATA="../data/asset-scores.json";
const CONFIG="./model-config.json";
const PRICE="../data/asset-compass-price-audit.json";
const READY="../data/asset-compass-history-readiness.json";
const OBSERVATIONS="../data/asset-compass-factor-observations.json";
const $=q=>document.querySelector(q);
const el=(tag,cls,content)=>{const node=document.createElement(tag);if(cls)node.className=cls;if(content!==undefined)node.textContent=String(content);return node};
const isNumber=n=>typeof n==="number"&&Number.isFinite(n);
function card(title,value,detail){const node=el("article","card"),h=el("div","label",title),b=el("div","big",value),p=el("p","muted",detail);node.append(h,b,p);return node}
async function getJSON(path){const result=await fetch(path,{cache:"no-store"});if(!result.ok)throw Error("未发布："+path);return result.json()}
async function optional(path){try{return await getJSON(path)}catch{return null}}
function isoDay(day,age){if(!/^\d{4}-\d{2}-\d{2}$/.test(day||""))return false;const dt=Date.parse(day+"T00:00:00Z");return Number.isFinite(dt)&&Date.now()>=dt&&Date.now()-dt<=age*86400000}
function isoMonth(month,age){if(!/^\d{4}-\d{2}$/.test(month||""))return false;const [y,m]=month.split("-").map(Number);const now=new Date();const n=(now.getUTCFullYear()-y)*12+now.getUTCMonth()+1-m;return n>=0&&n<=age}
function usableScore(a){return a&&a.status!=="unavailable"&&isNumber(a.score)&&a.score>=0&&a.score<=100&&a.validation?.historical_calibration_passed===true&&a.validation?.out_of_sample_passed===true}
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
 {id:"nyfed_recession.probability",name:"收益率曲线模型：12个月后衰退概率",group:"模型",source:"纽约联储研究模型",cadence:"monthly",unit:"%",precision:2,value:d=>{const m=d.nyfed_recession_model||{};if(m.official_forecast!==false||!/^\\d{4}-\\d{2}$/.test(m.observation_period||"")||!/^\\d{4}-\\d{2}$/.test(m.target_period||""))return null;const [y,n]=m.observation_period.split("-").map(Number),[ty,tn]=m.target_period.split("-").map(Number);return (ty*12+tn)-(y*12+n)===12?m.probability_percent:null},period:d=>d.nyfed_recession_model?.observation_period}
];
const ASSET_CONTEXT={
 gold:"观察实际利率、通胀补偿和美元条件。方向与因子贡献尚未校准。",
 us_equities:"观察利率、就业增长和流动性；不能直接推断指数涨跌。",
 us_long_bonds:"观察期限结构、通胀与货币政策；价格和总回报不同。",
 usd:"观察美国利率和相对货币政策；缺少海外相对利差信号。",
 bitcoin:"观察金融条件与风险偏好；暂无合格资产专属因子。",
 oil:"观察需求增长、通胀与供给；暂无合格库存和供需因子。"
};
function observationCurrent(def,period){
 return def.cadence==="monthly"?isoMonth(period,4):isoDay(period,def.cadence==="weekly"?21:11)
}
function overviewObservations(data){
 const valid=data?.schema_version===1&&data?.scoring?.calibration_verified===false&&data?.scoring?.out_of_sample_verified===false;
 return OVERVIEW_INDICATORS.map(def=>{
  const period=valid?def.period(data):null;
  const value=valid?def.value(data):null;
  const present=isNumber(value)&&observationCurrent(def,period);
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
function overview(data,readiness){
 const snapshotValid=data?.schema_version===1&&data?.assets&&data?.scoring?.calibration_verified===false&&data?.scoring?.out_of_sample_verified===false;
 const approved=snapshotValid?data:null;
 const rows=overviewObservations(approved);
 const usable=rows.filter(x=>x.state==="可用").length;
 const snapshotTime=approved?.generated_at?Date.parse(approved.generated_at):NaN;
 const age=Date.now()-snapshotTime;
 const snapshotOk=Number.isFinite(snapshotTime)&&age>=0;
 const delayed=!snapshotOk||age>72*3600*1000;
 const status=$("#source-status");
 if(status)status.textContent=!approved?"数据未通过快照和评分锁定校验；暂停展示数值。":
   "官方数据快照："+(snapshotOk?new Date(snapshotTime).toLocaleString("zh-CN",{timeZone:"Asia/Shanghai",hour12:false})+"（北京时间）":"时间无效")+
   "；14项必需指标中 "+usable+" 项仍在各自可用期限内。"+
   (delayed?" 数据快照已过期或生成时间异常，请检查采集任务。":" 当前快照可供研究浏览。")+
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
  const links=el("div","asset-links");
  const detail=el("a","","查看因子权重");detail.href="./attribution.html";
  const history=el("a","","查看回测准备度");history.href="./research.html";
  links.append(detail,history);node.append(links);return node;
 }));
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
async function run(){const page=document.body.dataset.page;if(page==="overview"){const [data,readiness]=await Promise.all([optional(DATA),optional(READY)]);overview(data,readiness);return}if(page==="attribution"){const [config,data,observations]=await Promise.all([optional(CONFIG),optional(DATA),optional(OBSERVATIONS)]);attribution(config,data);renderFactorObservations(observations);return}if(page==="research"){const [price,readiness]=await Promise.all([optional(PRICE),optional(READY)]);research(price,readiness);return}}
run().catch(()=>{const node=$("#source-status")||$("#attribution-status")||$("#research-status");if(node)node.textContent="数据读取暂不可用；不会以示例数值代替真实数据。"});

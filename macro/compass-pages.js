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
function headline(data){const r=data?.rates||{},fresh=isoDay(data?.observation_date,11);const cards=[["10年期名义国债",r.us10y],["10年期实际利率",r.real10y],["10Y−2Y利差",r.spread10y2y]];const list=$("#headline");if(!list)return;list.replaceChildren(...cards.map(([title,value])=>card(title,fresh&&isNumber(value)?value.toFixed(2)+"%":"暂无有效数据","美国财政部 · 观测日："+(data?.observation_date||"缺失"))))}
function overview(data){headline(data);const assets=$("#asset-grid");const source=data?.assets||{};assets.replaceChildren(...Object.entries(ASSETS).map(([id,name])=>{const a=source[id]||{},node=card(name,scoreText(a),"六因子正式评分 · 历史校准与样本外验证未通过时不展示。");node.append(el("div","label","权重覆盖报告："+(isNumber(a.coverage_pct)?a.coverage_pct+"%":"未提供")));return node}));const note=$("#source-status");note.textContent=data?.schema_version===1?"观测快照："+(data.observation_date||"未知")+"；仅展示官方观测，不自动生成利多利空。":"数据不可用：未取得经过核验的官方快照。"}
function overviewFailure(){overview(null)}
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
async function run(){const page=document.body.dataset.page;if(page==="overview"){const data=await optional(DATA);overview(data);return}if(page==="attribution"){const [config,data,observations]=await Promise.all([optional(CONFIG),optional(DATA),optional(OBSERVATIONS)]);attribution(config,data);renderFactorObservations(observations);return}if(page==="research"){const [price,readiness]=await Promise.all([optional(PRICE),optional(READY)]);research(price,readiness);return}}
run().catch(()=>{const node=$("#source-status")||$("#attribution-status")||$("#research-status");if(node)node.textContent="数据读取暂不可用；不会以示例数值代替真实数据。"});

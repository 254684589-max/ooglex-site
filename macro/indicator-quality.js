"use strict";
/* Ooglex V6 — evidence checks. Research priorities A-D are not quality grades. */
(()=>{
 const $=id=>document.getElementById(id);
 const checks=[
  ["source","权威来源与可追溯性","财政部历史来源和官方URL符合审计要求"],
  ["snapshot","最新观测与日期有效性","最新宏观快照必须具有可信生成时间及合理的新鲜度"],
  ["coverage","历史覆盖","研究数据须覆盖足够跨度；仅说明覆盖，不赋予预测资格"],
  ["archive","不可变归档一致性","财政部来源年份不得存在已知错配"],
  ["vintage","历史首次发布版本（PIT）","不得用事后修订历史替代当时可获得的数据"],
  ["returns","资产收益口径与授权","资产总回报及公开衍生使用许可需要审计通过"],
  ["oos","样本外与跨周期验证","模型须完成可复核的跨经济周期样本外检验"]
 ];
 const isTime=s=>typeof s==="string"&&Number.isFinite(Date.parse(s));
 const isDay=s=>typeof s==="string"&&/^\d{4}-\d{2}-\d{2}$/.test(s)&&Number.isFinite(Date.parse(s+"T00:00:00Z"))&&new Date(s+"T00:00:00Z").toISOString().slice(0,10)===s;
 const age=s=>isDay(s)?(Date.now()-Date.parse(s+"T00:00:00Z"))/86400000:Infinity;
 const td=(row,value)=>{const el=document.createElement("td");el.textContent=String(value);row.append(el);return el};
 function record(k,passed,reason){return {key:k,passed:passed===true,reason}}
 function audit(data){
  const {score,history,ready,config}=data;
  const trusted=history.dataset==="treasury_historical_daily_observations"&&
    ["U.S. Department of the Treasury","Federal Reserve Board H.15 via FRED"].includes(history.source)&&
    Array.isArray(history.source_urls)&&history.source_urls.length>0;
  const source=record("source",trusted,"官方来源及完整历史结构通过现有TREASURY_TRENDS校验");
  const snapshotTime=isTime(score.generated_at)&&Date.parse(score.generated_at)<=Date.now()+3600000;
  const snapshot=record("snapshot",snapshotTime&&age(score.observation_date)>=0&&age(score.observation_date)<=7,"最新快照："+(score.observation_date||"未知")+"；生成时间："+(score.generated_at||"未知")+"；门槛7个自然日");
  const count=history.observation_count||0,first=history.start_date,last=history.end_date;
  const span=isDay(first)&&isDay(last)?(Date.parse(last+"T00:00:00Z")-Date.parse(first+"T00:00:00Z"))/86400000:0;
  const coverage=record("coverage",count>=500&&span>=730,"财政部历史："+count+"个真实配对观测日；"+first+"至"+last+"；仅历史覆盖，非PIT数据");
  const archive=record("archive",Number.isInteger(ready.treasury_source_year_mismatch_rows)&&ready.treasury_source_year_mismatch_rows===0,"不可变归档的来源年份错配："+(ready.treasury_source_year_mismatch_rows??"未知")+"条");
  const vintage=record("vintage",history.original_release_vintages_available===true&&history.not_valid_for_point_in_time_backtest===false&&ready.eligible_for_point_in_time_backtest===true,"历史首次发布版本："+(history.original_release_vintages_available===true?"已声明具备":"未具备")+"；归档PIT准入："+String(ready.eligible_for_point_in_time_backtest));
  const returns=record("returns",false,"未取得可核验的资产总回报序列及公开衍生数据授权；禁止推断资产收益准入");
  const guard=config.guardrails||{};
  const oos=record("oos",false,"研究配置要求历史校准及样本外验证；当前缺少独立可验证的通过报告");
  const out=[source,snapshot,coverage,archive,vintage,returns,oos];
  const gating=ready.validated_for_live_scoring===true&&
    score.status!=="partial_data_no_full_score"&&
    !!guard.require_historical_calibration&&!!guard.require_out_of_sample_validation&&
    Object.values(score.assets||{}).every(x=>x?.validation?.historical_calibration_passed===true&&x?.validation?.out_of_sample_passed===true);
  return {checks:out,eligible:gating&&out.every(x=>x.passed),total:out.filter(x=>x.passed).length};
 }
 function present(result,data){
  const body=$("quality-rows");body.replaceChildren();
  for(const def of checks){const c=result.checks.find(x=>x.key===def[0]);const tr=document.createElement("tr");
   td(tr,def[1]);const st=td(tr,c.passed?"证据满足":"未通过／待核验");st.className=c.passed?"q-pass":"q-block";td(tr,c.reason);body.append(tr)}
  const head=$("quality-summary");head.textContent="证据检查："+result.total+" / "+checks.length+"项满足条件 · 正式资产评分："+(result.eligible?"准入条件满足（仍须独立复核）":"未获准入，保持关闭")+"。这是审计项通过数，不是数据准确率或投资评分。";
  $("quality-gate").textContent=result.eligible?"已满足当前自动检查；上线正式评分仍需审批。":"阻断：PIT版本、归档一致性、收益及授权口径、跨周期样本外验证等未全部通过。";
  $("quality-time").textContent="审计时点：浏览器读取时；输入：asset-scores.json、asset-compass-treasury-history.json、asset-compass-history-readiness.json、model-config.json；历史数据抓取："+data.history.retrieved_at+"。检查结果不写回模型，不提升A/B/C/D等级。";
  const rows=$("quality-asset-rows");rows.replaceChildren();const assets={gold:"黄金",us_equities:"美股",us_long_bonds:"美国长期国债",usd:"美元",bitcoin:"比特币",oil:"原油"};
  for(const [key,name] of Object.entries(assets)){const item=data.score.assets?.[key];const tr=document.createElement("tr");td(tr,name);td(tr,item?.status==="unavailable"?"关闭":"待人工复核");td(tr,Array.isArray(item?.blocked_by)&&item.blocked_by.length?item.blocked_by.join("、"):"尚无可审计的独立通过证据");rows.append(tr)}
 }
 async function init(){if(!$("quality-summary"))return;try{
  if(typeof TREASURY_TRENDS==="undefined"||typeof TREASURY_TRENDS.validate!=="function")throw Error("基础历史数据校验模块缺失");
  const names=["../data/asset-scores.json","../data/asset-compass-treasury-history.json","../data/asset-compass-history-readiness.json","./model-config.json"];
  const responses=await Promise.all(names.map(n=>fetch(n,{cache:"no-store"})));
  for(let i=0;i<responses.length;i++)if(!responses[i].ok)throw Error("审计数据缺失 HTTP "+responses[i].status+" ("+names[i]+")");
  const [score,rawHistory,ready,config]=await Promise.all(responses.map(r=>r.json()));
  const history=TREASURY_TRENDS.validate(rawHistory);
  if(score.schema_version!==1||ready.schema_version!==1||config.schema_version!==1||
   ready.report_type!=="asset_compass_history_readiness"||!score.assets||!config.guardrails)throw Error("审计输入结构不一致");
  const data={score,history,ready,config};
  present(audit(data),data);
 }catch(err){$("quality-summary").textContent="审计失败（fail closed）："+err.message+"。不得据此解锁评分。";$("quality-gate").textContent="未获准入";$("quality-rows").replaceChildren();$("quality-asset-rows").replaceChildren()}}
 if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init,{once:true});else init();
})();
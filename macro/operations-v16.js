"use strict";
/* V16 Ooglex retrieval-to-retrieval Treasury observations, NOT original vintage history. */
(()=>{
const status=document.getElementById("v16-status");
const body=document.getElementById("v16-comparison-rows");
if(!status||!body)return;
async function run(){
 try{
  const response=await fetch("../data/asset-compass-treasury-v16-report.json",{cache:"no-store"});
  if(!response.ok)throw new Error("尚无已发布的V16对比证据（HTTP "+response.status+"）");
  const d=await response.json();
  const series=["treasury.us2y","treasury.us10y","treasury.real10y"];
  if(d?.schema_version!==1||d.report_type!=="asset_compass_v16_retrieval_comparison"||
     !["first_capture","new_year","same_year"].includes(d.baseline_state)||
     d.historical_official_revisions_verified!==false||
     d.historical_original_publication_timestamp_verified!==false||
     d.eligible_for_point_in_time_backtest!==false||
     d.validated_for_live_scoring!==false||
     !d.by_series||series.some(k=>!d.by_series[k]||
        !["new_observation_periods","changed_value_periods","no_longer_in_response_periods","current_observation_periods"]
         .every(key=>Number.isInteger(d.by_series[k][key])&&d.by_series[k][key]>=0))){
     throw Error("报告缺少核验证据或安全门禁异常");
  }
  body.replaceChildren();
  const names={"treasury.us2y":"美国2Y名义收益率","treasury.us10y":"美国10Y名义收益率","treasury.real10y":"美国10Y实际收益率"};
  for(const key of series){
   const line=d.by_series[key];
   const tr=document.createElement("tr");
   const values=[names[key],line.current_observation_periods,line.new_observation_periods,line.changed_value_periods,line.no_longer_in_response_periods,(line.changed_dates||[]).slice(0,5).join("、")||"—"];
   for(const value of values){const td=document.createElement("td");td.textContent=String(value);tr.append(td)}
   body.append(tr);
  }
  const baseline=d.baseline_state==="same_year"?"已有同年度上次真实抓取基准":"首次取证或跨年建立新基准，不能推断上一版本差异";
  status.textContent="最新采集："+d.checked_at+"（UTC） · 基准："+baseline+" · 观察到的数值变化："+d.total_observed_value_changes+"处。所有变化仅表示两次本站抓取间的差异，不代表官方修订发布日期；PIT准入与资产评分均关闭。";
 }catch(e){status.textContent="V16 差异审计未验证："+e.message+"。不显示推测修订。";body.replaceChildren()}
}
void run();
})();
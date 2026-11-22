"use strict";
/* V17 Treasury quote sampling ≠ official first website publication time. */
(()=>{
const status=document.getElementById("v17-status"),body=document.getElementById("v17-rows");
if(!status||!body)return;
async function load(){
 try{
  const response=await fetch("../data/asset-compass-treasury-release-evidence-v17.json",{cache:"no-store"});
  if(!response.ok)throw Error("HTTP "+response.status);
  const d=await response.json();
  if(d?.schema_version!==1||d.report_type!=="asset_compass_v17_treasury_publication_evidence"||
     !Array.isArray(d.series)||d.series.length!==3||
     d.independently_verified_original_publication_timestamps!==0||
     d.quotation_timestamp_is_publication_timestamp!==false||
     d.eligible_for_point_in_time_backtest!==false||d.validated_for_live_scoring!==false||
     d.series.some(x=>x.official_quote_sampling_approx_local_time!=="15:30"||
       x.official_quote_timezone!=="America/New_York"||x.publication_timestamp_utc!==null||
       x.historical_first_release_vintage_verified!==false))throw Error("报告结构或PIT安全门禁无效");
  const title={"treasury.us2y":"美国2年期名义收益率","treasury.us10y":"美国10年期名义收益率","treasury.real10y":"美国10年期实际收益率"};
  body.replaceChildren();
  for(const item of d.series){
   const tr=document.createElement("tr");
   for(const val of [title[item.series_id]||item.series_id,"交易日约15:30（纽约时间）","未独立核实","未核实","禁止PIT回测"]){
     const td=document.createElement("td");td.textContent=val;tr.append(td);
   }body.append(tr);
  }
  status.textContent="已核对官方曲线方法说明和V15/V16抓取证据。3项收益率均有官方报价采样时间说明，但尚无经过独立验证的每日首次公布时间或原始修订版本；不能据此解锁模型。";
 }catch(e){status.textContent="V17官方发布时间证据未通过："+e.message+"。PIT回测与资产评分保持关闭。";body.replaceChildren()}
}
void load();
})();
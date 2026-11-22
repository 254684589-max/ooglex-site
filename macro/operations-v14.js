"use strict";
/* V14 source-evidence inventory. Never grants PIT backtest or public scoring. */
(()=>{
const status=document.getElementById("ops-v14-status");
const body=document.getElementById("ops-v14-rows");
if(!status||!body)return;
const names={
"source_original_release_timestamp_verified":"原始发布时间",
"provider_vintage_asof_value_verified":"当时可见的修订版本",
"original_release_artifact_integrity_verified":"官方原始文件完整性",
"redistribution_rights_approved":"数据授权",
"historical_investable_asset_returns_verified":"可投资资产总回报"
};
function cell(tr,value){const td=document.createElement("td");td.textContent=String(value);tr.append(td)}
async function render(){
 try{
  const resp=await fetch("../data/asset-compass-pit-readiness-v14.json",{cache:"no-store"});
  if(!resp.ok)throw Error("HTTP "+resp.status);
  const x=await resp.json();
  if(x?.report_type!=="asset_compass_v14_pit_evidence_gaps"||
     x.schema_version!==1||x.required_series!==14||
     !Array.isArray(x.series)||x.series.length!==14||
     x.independently_qualified_pit_series!==0||
     x.validated_for_live_scoring!==false||
     x.eligible_for_point_in_time_backtest!==false||
     x.private_vintage_database_exported!==false||
     x.series.some(v=>v.independently_qualified_for_pit!==false||!Array.isArray(v.evidence_gaps))){
      throw Error("审计结构或安全门禁未通过");
  }
  body.replaceChildren();
  for(const row of x.series){
   const tr=document.createElement("tr");
   cell(tr,row.series_id);
   cell(tr,"P"+row.priority_tier);
   cell(tr,row.first_seen_distinct_periods+"个观测期");
   cell(tr,row.evidence_gaps.map(k=>names[k]||k).join("、")||"需独立复核");
   cell(tr,"未获准入");
   body.append(tr);
  }
  status.textContent="已覆盖 "+x.first_seen_covered_series+"/14 项first-seen序列；独立PIT核证 "+x.independently_qualified_pit_series+"/14。正式评分与PIT回测保持关闭。发现资源地址仅用于寻找原始文件，不代表已取得或获准使用。";
 }catch(e){status.textContent="V14资料无法独立核验："+e.message+"。禁止启用正式评分。";body.replaceChildren()}
}
void render();
})();
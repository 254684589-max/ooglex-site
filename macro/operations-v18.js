"use strict";
/* V18 First confirmed Ooglex public HTTP fetch != Treasury first publication */
(()=>{
const status=document.getElementById("v18-status"),body=document.getElementById("v18-rows");
if(!status||!body)return;
async function init(){
 try{
  const response=await fetch("../data/asset-compass-treasury-v18-fetch-readiness.json",{cache:"no-store"});
  if(!response.ok)throw Error("HTTP "+response.status);
  const d=await response.json();
  if(d?.schema_version!==1||d.report_type!=="asset_compass_v18_fetch_witness_summary"||
     d.tracked_curves!==2||!Array.isArray(d.first_successful_ooglex_fetches)||
     d.first_successful_ooglex_fetches.length!==2||
     d.official_first_publication_verified!==false||
     d.historical_vintage_asof_verified!==false||
     d.eligible_for_point_in_time_backtest!==false||
     d.validated_for_live_scoring!==false||
     d.first_successful_ooglex_fetches.some(x=>!["nominal","real"].includes(x.curve_type)||
       !Number.isFinite(Date.parse(x.first_ooglex_verified_fetch_at))||
       !/^[a-f0-9]{64}$/.test(x.sha256)))throw Error("V18证据结构或准入阻断状态异常");
  body.replaceChildren();
  for(const x of d.first_successful_ooglex_fetches){
    const tr=document.createElement("tr");
    const cells=[x.curve_type==="nominal"?"2Y/10Y名义收益率CSV":"10Y实际收益率CSV",
      x.first_ooglex_verified_fetch_at,x.sha256.slice(0,20)+"…",
      x.changed_bytes_since_previous_fetch===null?"首次基准":x.changed_bytes_since_previous_fetch?"发现文件字节变化":"与前次字节相同",
      "原始发布时间未知"];
    for(const cell of cells){const td=document.createElement("td");td.textContent=cell;tr.append(td)}
    body.append(tr);
  }
  status.textContent="V18已记录"+d.tracked_curves+"个财政部CSV来源的本站首次成功公开获取证据；时间"+d.verified_no_later_than+"（UTC，不晚于该时刻可获取）。该记录不代表财政部第一次发布，亦不倒填历史PIT资格。";
 }catch(e){status.textContent="V18首次成功获取证据尚未核证："+e.message+"。PIT回测和正式资产评分保持关闭。";body.replaceChildren()}
}
void init();
})();
"use strict";
/* V15 official Treasury source receipts: downloaded-now evidence, not PIT proof. */
(()=>{
const $=id=>document.getElementById(id);
const headline=$("v15-headline"),body=$("v15-receipts");
if(!headline||!body)return;
async function init(){
 try{
  const r=await fetch("../data/asset-compass-treasury-source-evidence-v15.json",{cache:"no-store"});
  if(!r.ok)throw Error("HTTP "+r.status);
  const d=await r.json();
  if(d?.schema_version!==1||d.report_type!=="asset_compass_v15_treasury_raw_source_evidence"||
    !Array.isArray(d.source_receipts)||d.source_receipts.length!==2||
    d.original_publication_time_verified!==false||
    d.original_release_vintages_verified!==false||
    d.eligible_for_point_in_time_backtest!==false||
    d.validated_for_live_scoring!==false||
    !d.source_receipts.every(v=>/^https:\/\/home\.treasury\.gov\//.test(v.source_url)&&/^[a-f0-9]{64}$/.test(v.sha256)))throw Error("证据结构或安全门禁不符合要求");
  body.replaceChildren();
  const values=d.latest_matched_observation||{};
  for(const item of d.source_receipts){
   const tr=document.createElement("tr");
   const entries=[item.type==="nominal"?"美国2Y/10Y名义收益率":"美国10Y实际收益率",
     item.observation_rows+"条",item.earliest_observation_date+"—"+item.latest_observation_date,
     item.sha256.slice(0,16)+"…",
     item.retrieved_at];
   for(const entry of entries){const td=document.createElement("td");td.textContent=entry;tr.append(td)}
   body.append(tr);
  }
  headline.textContent="已取得"+d.year+"年度财政部原始CSV抓取摘要；配对"+d.matched_three_series_observation_days+"个交易日。最新配对日 "+(values.date||"未知")+"。此报告仅证明抓取时文件内容与来源，不证明当时首次发布的时间或历史修订版本。";
 }catch(e){headline.textContent="V15原始来源证据尚未验证："+e.message+"。PIT回测与正式资产评分仍关闭。";body.replaceChildren()}
}
void init();
})();
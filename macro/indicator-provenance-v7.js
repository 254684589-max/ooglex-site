"use strict";
/* V7 immutable Treasury source provenance monitor. No synthetic pass states. */
(()=>{
 const summary=document.getElementById("v7-summary");
 const rows=document.getElementById("v7-rows");
 if(!summary||!rows)return;
 function line(label,value){const tr=document.createElement("tr");for(const t of [label,value]){const td=document.createElement("td");td.textContent=String(t);tr.append(td)}rows.append(tr)}
 async function init(){
  try{
   const r=await fetch("../data/asset-compass-provenance-v7.json",{cache:"no-store"});
   if(!r.ok)throw new Error("尚无已发布V7审计报告（HTTP "+r.status+"）");
   const d=await r.json();
   if(d?.schema_version!==1||d.report_type!=="asset_compass_v7_treasury_provenance"||
      d.validated_for_live_scoring!==false||d.legacy_rows_are_valid_evidence!==false||
      !Number.isInteger(d.unexpected_mismatch_rows)||!Number.isInteger(d.legacy_quarantined_rows)||
      typeof d.ledger_sha256!=="string"||!/^[a-f0-9]{64}$/.test(d.ledger_sha256)||
      !Array.isArray(d.legacy_anomalies))throw new Error("审计报告结构或安全门禁无效");
   rows.replaceChildren();
   line("已隔离的历史异常",d.legacy_quarantined_rows+"条（不计作可信来源）");
   line("新增或未识别来源异常",d.unexpected_mismatch_rows+"条");
   line("符合来源检查的财政部归档记录",d.treasury_valid_source_rows+"条");
   line("归档哈希前12位",d.ledger_sha256.slice(0,12));
   line("审计报告生成时间（UTC）",d.generated_at);
   summary.textContent=d.integrity_gate_passed===true&&d.unexpected_mismatch_rows===0?
    "来源审计通过（仅归档一致性）：历史错误被保留并隔离。PIT版本、资产回测和正式评分仍未通过。":
    "来源审计存在异常：新错配或已知历史异常清单不一致；正式评分保持关闭。";
  }catch(e){summary.textContent="V7报告尚未验证："+e.message+"。等待独立归档流水线生成并提交，不以旧版本或假数据替代。";rows.replaceChildren()}
 }
 void init();
})();
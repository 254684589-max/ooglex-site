(() => {
"use strict";
const el=id=>document.getElementById(id);
const status={"new_report":"新增已核验日报","new_version":"新增修订版本","unchanged":"文件未变","not_available":"未取得文件","network_error":"网络错误","schema_or_validation_error":"结构或核验失败"};
function render(d){
 if(d?.schema_version!==1||d.source!=="tradeweb_sbsef_dmdr"||d.publication_enabled!==false||d.admitted_par_spreads!==0||!d.reports||typeof d.reports!=="object"||Array.isArray(d.reports))throw Error("ledger");
 const days=Object.keys(d.reports).sort();
 for(const day of days){
  const versions=d.reports[day];
  if(!/^\d{4}-\d{2}-\d{2}$/.test(day)||!Array.isArray(versions)||!versions.length||versions.some(v=>v.admitted_par_spreads!==0||v.verified_reference_entities!==0||!Number.isInteger(v.candidate_issuer_count)||v.candidate_issuer_count<0||v.candidate_issuer_count>100))throw Error("version");
 }
 el("cds-audit-days").textContent=String(days.length);
 el("cds-audit-versions").textContent=String(days.reduce((n,day)=>n+d.reports[day].length,0));
 el("cds-audit-latest").textContent=days.at(-1)||"—";
 const attempts=d.last_run?.attempts||{};
 const values=Object.values(attempts);
 const success=values.filter(v=>["new_report","new_version","unchanged"].includes(v)).length;
 el("cds-audit-status").textContent=d.last_run?"最近采集尝试（UTC）："+d.last_run.attempted_at+" · "+success+" / "+values.length+" 个日期取得有效文件；正式行情发布关闭。":"自动采集账本尚无运行记录；正式行情发布关闭。";
 const body=el("cds-audit-table");body.replaceChildren();
 for(const day of Object.keys(attempts).sort().reverse()){
  const tr=document.createElement("tr"),v=attempts[day],rows=d.reports[day];
  for(const value of [day,status[v]||(/^http_error_\d{3}$/.test(v)?"HTTP 请求失败":"未知状态"),rows?.length?String(rows.at(-1).candidate_issuer_count):"—"]){
   const td=document.createElement("td");td.textContent=value;tr.append(td);
  }
  body.append(tr);
 }
}
fetch("./nasdaq100-cds-audit.json",{cache:"no-cache"}).then(r=>{if(!r.ok)throw Error("HTTP");return r.json();}).then(render).catch(()=>{el("cds-audit-status").textContent="自动审计账本读取或验证失败；不显示数据。";for(const id of ["cds-audit-days","cds-audit-versions","cds-audit-latest"])el(id).textContent="—";el("cds-audit-table").replaceChildren();});
})();

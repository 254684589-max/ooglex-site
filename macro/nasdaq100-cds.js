(() => {
"use strict";
const byId = id => document.getElementById(id);
const dash = "—";
const showError = () => {byId("cds-status").textContent="研究名单读取或校验失败；不显示报价。";byId("cds-table").replaceChildren();};
function validate(data) {
 if (data.schema_version !== 1 || data.publication?.enabled !== false || !Array.isArray(data.issuers)) throw Error("closed gate required");
 const rows = data.issuers;
 const symbols = rows.flatMap(r => r.tickers);
 if (rows.length !== 100 || symbols.length !== 101 || new Set(symbols).size !== symbols.length || new Set(rows.map(r=>r.issuer_id)).size !== rows.length) throw Error("invalid universe");
 for (const r of rows) {
  if (typeof r.name !== "string" || !r.name || typeof r.issuer_id !== "string" || !r.tickers.every(t=>/^[A-Z]+$/.test(t)) || r.reference_entity_id !== null || r.mapping_status !== "unverified" || r.quote !== null || !Array.isArray(r.history) || r.history.length) throw Error("V1 prohibits unapproved data");
 }
 if (!Array.isArray(data.sources) || data.sources.some(s=>s.public_display!==false)) throw Error("unapproved source");
 return rows;
}
function cell(tr, value) {const td=document.createElement("td");td.textContent=value;tr.append(td);}
function init(data) {
 const rows=validate(data).sort((a,b)=>a.tickers[0].localeCompare(b.tickers[0]));
 byId("cds-status").textContent="研究名单可用；正式报价发布门禁关闭。数据授权及参考实体尚未核验。";
 byId("cds-universe").textContent=rows.length+" / "+rows.flatMap(r=>r.tickers).length;
 byId("cds-date").textContent="交叉检查日期："+data.universe.membership_as_of;
 byId("cds-mapped").textContent="0 / "+rows.length;
 byId("cds-covered").textContent="0 / "+rows.length;
 const search=byId("cds-search"), body=byId("cds-table"), select=byId("cds-issuer");
 for(const r of rows){const option=document.createElement("option");option.value=r.issuer_id;option.textContent=r.tickers.join(" / ")+" · "+r.name;select.append(option);}
 function render(){
  const q=search.value.trim().toLowerCase();const found=rows.filter(r=>(r.name+" "+r.tickers.join(" ")).toLowerCase().includes(q));
  const fragment=document.createDocumentFragment();
  for(const r of found){const tr=document.createElement("tr");const td=document.createElement("td");const btn=document.createElement("button");btn.type="button";btn.textContent=r.name;btn.addEventListener("click",()=>{select.value=r.issuer_id;detail();byId("cds-detail-title").scrollIntoView({block:"start"});});td.append(btn);tr.append(td);cell(tr,r.tickers.join(" / "));for(let i=0;i<4;i++)cell(tr,dash);cell(tr,"待核验 · 未发布");fragment.append(tr);}
  if(!found.length){const tr=document.createElement("tr"),td=document.createElement("td");td.colSpan=7;td.textContent="没有匹配企业";tr.append(td);fragment.append(tr);}
  body.replaceChildren(fragment);byId("cds-count").textContent=found.length+" / "+rows.length+" 家";
 }
 function detail(){const r=rows.find(x=>x.issuer_id===select.value);byId("cds-detail").textContent=r?r.name+"（"+r.tickers.join(" / ")+"）：参考实体待核验，尚无准入历史观测；不展示虚构曲线。":"尚无准入历史观测。不会生成模拟曲线。";}
 search.addEventListener("input",render);select.addEventListener("change",detail);render();
}
fetch("./nasdaq100-cds.json",{cache:"no-cache"}).then(r=>{if(!r.ok)throw Error("HTTP "+r.status);return r.json();}).then(init).catch(showError);
})();

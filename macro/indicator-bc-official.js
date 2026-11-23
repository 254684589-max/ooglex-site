"use strict";
/* Eight officially originated B/C macro series. FRED mirrors source agencies.
   Neither series values nor last observed dates imply original release vintages. */
(()=>{
const summary=document.getElementById("bc-summary");
const tbody=document.getElementById("bc-rows");
const select=document.getElementById("bc-history-series");
const svg=document.getElementById("bc-history-svg");
const caption=document.getElementById("bc-history-caption");
if(!summary||!tbody||!select||!svg||!caption)return;
const seriesNames=[
"美国实际GDP增长率","美元广义贸易加权指数","美国工业生产指数","美国住房开工","美国零售销售",
"美国初请失业金人数","美国10Y－3M国债利差","5Y5Y远期通胀补偿","WTI原油现货价格"];
const unitMap={percent_annualized_qoq:"% · 季环比年化",index:"指数点",millions_usd_sa:"百万美元 · 季调",
 persons_sa:"人 · 季调",thousands_units_saar:"千套 · 季调年率",percentage_points:"百分点",percent:"%",usd_per_barrel:"美元/桶"};
const grace={quarterly:160,monthly:95,weekly:20,daily:16};
const ns="http://www.w3.org/2000/svg";
let data={};
function point(type,attrs){const n=document.createElementNS(ns,type);for(const [k,v] of Object.entries(attrs))n.setAttribute(k,String(v));return n}
function cell(row,value){const td=document.createElement("td");td.textContent=String(value);row.append(td);return td}
function chart(){
 svg.replaceChildren();
 const name=select.value,item=data[name];
 if(!item){caption.textContent="尚无可核验历史序列。";return}
 const rows=(item.observations||[]).filter(x=>typeof x.value==="number"&&Number.isFinite(x.value)&&/^\d{4}-\d{2}-\d{2}$/.test(x.date));
 if(rows.length<2){caption.textContent="有效历史点不足。";return}
 const vals=rows.map(x=>x.value),min=Math.min(...vals),max=Math.max(...vals),range=Math.max(max-min,0.001);
 const width=900,height=240,l=65,r=25,t=20,b=40;
 const x=i=>l+(width-l-r)*i/(rows.length-1),y=v=>t+(max+range*.12-v)/(range*1.24)*(height-t-b);
 for(let i=0;i<=4;i++){
  const val=min+range*i/4,yy=y(val);
  svg.append(point("line",{x1:l,x2:width-r,y1:yy,y2:yy,stroke:"#33455b"}));
  const label=point("text",{x:l-10,y:yy+4,fill:"#a9bdd5","text-anchor":"end","font-size":12});
  label.textContent=val.toFixed(2);svg.append(label);
 }
 svg.append(point("polyline",{points:rows.map((v,i)=>x(i).toFixed(1)+","+y(v.value).toFixed(1)).join(" "),fill:"none",stroke:"#7ac1ff","stroke-width":2.4}));
 for(const [at,pos,align] of [[0,l,"start"],[rows.length-1,width-r,"end"]]){
  const label=point("text",{x:pos,y:height-9,"text-anchor":align,fill:"#a9bdd5","font-size":12});
  label.textContent=rows[at].date;svg.append(label);
 }
 caption.textContent=name+" · "+rows.length+"个观测日/期 · "+rows[rows.length-1].date+
 " · 最新数值 "+rows[rows.length-1].value.toLocaleString("en-US",{maximumFractionDigits:3})+
 " "+(unitMap[item.unit]||item.unit)+
 "。仅为当前下载可见的历史版本，不是严格PIT回测数据。";
}
select.addEventListener("change",chart);
(async()=>{
try{
 const resp=await fetch("../data/asset-compass-bc-official-v1.json",{cache:"no-store"});
 if(!resp.ok)throw Error("HTTP "+resp.status);
 const d=await resp.json();
 if(d?.schema_version!==1||d.report_type!=="asset_compass_bc_official_observations_v1"||
    d.validated_for_live_scoring!==false||d.historical_pit_certified!==false||
    d.redistribution_rights_independently_approved!==false||
    !d.series||typeof d.series!=="object"||
    d.requested_series_count!==9||d.accepted_series_count!==Object.keys(d.series).length||
    Object.keys(d.series).some(k=>!seriesNames.includes(k)))throw Error("数据口径、安全门禁或来源清单不匹配");
 data=d.series;
 tbody.replaceChildren();select.replaceChildren();
 const missing=d.failed_sources||{};
 for(const name of seriesNames){
  const item=data[name],tr=document.createElement("tr");
  cell(tr,name);
  cell(tr,item?item.latest_value.toLocaleString("en-US",{maximumFractionDigits:3})+" "+(unitMap[item.unit]||item.unit):"—");
  cell(tr,item?item.observation_period:"—");
  const recent=item&&Date.parse(item.observation_period+"T00:00:00Z")<=Date.now()&&
      (Date.now()-Date.parse(item.observation_period+"T00:00:00Z"))/86400000<=grace[item.frequency];
  cell(tr,item?(recent?"来源观测可用":"观测过期"):"采集未核实");
  const td=document.createElement("td");
  if(item){
    const a=document.createElement("a");a.href=item.source_url;a.target="_blank";a.rel="noopener noreferrer";a.textContent=item.original_agency+" · FRED镜像";td.append(a);
    const option=document.createElement("option");option.value=name;option.textContent=name;select.append(option);
  }else td.textContent=missing[name]?.status||"尚未接入";
  tr.append(td);tbody.append(tr);
 }
 summary.textContent="B/C公开来源数据：成功核验 "+d.accepted_series_count+"/9，未核验 "+Object.keys(missing).length+
 " 项。8项均来自机构原始统计经FRED公开镜像；未声称历史首次发布时间，未接入ICE授权行情，也不生成资产投资评分。";
 chart();
}catch(err){summary.textContent="B/C数据尚未核验："+err.message+"。目录和A级数据仍可独立使用。";tbody.replaceChildren();caption.textContent="暂无可核验的B/C走势图。";}
})();
})();

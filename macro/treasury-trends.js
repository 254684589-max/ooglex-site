"use strict";
/* V42 historical *observations* chart. Never infer PIT publication timestamp
   or calibrated asset signals from downloaded Treasury historical CSV data. */
const TREASURY_TRENDS=(function(){
 const SOURCE="../data/asset-compass-treasury-history.json";
 const FIELDS={
  us10y:{name:"10年期名义收益率",unit:"%"},
  real10y:{name:"10年期TIPS实际收益率",unit:"%"},
  breakeven10y:{name:"10年期通胀补偿",unit:"百分点"},
  spread10y2y:{name:"10Y−2Y期限利差",unit:"百分点"}
 };
 const NS="http://www.w3.org/2000/svg",MIN_DATE="1997-01-01";
 const $=id=>document.getElementById(id);
 const el=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n};
 function svg(tag,attributes={},text){
  const n=document.createElementNS(NS,tag);
  for(const [key,value] of Object.entries(attributes))n.setAttribute(key,String(value));
  if(text!==undefined)n.textContent=String(text);
  return n;
 }
 function validDay(d){
  if(!/^\d{4}-\d{2}-\d{2}$/.test(d||""))return false;
  const t=Date.parse(d+"T00:00:00Z");
  return Number.isFinite(t)&&new Date(t).toISOString().slice(0,10)===d&&d>=MIN_DATE&&t<=Date.now();
 }
 function validate(d){
  if(!d||d.schema_version!==1||d.dataset!=="treasury_historical_daily_observations"||
    !["U.S. Department of the Treasury","Federal Reserve Board H.15 via FRED"].includes(d.source)||
    d.original_release_vintages_available!==false||
    d.not_valid_for_point_in_time_backtest!==true||
    !Array.isArray(d.observations)||d.observations.length<2||d.observations.length>10000||
    d.observation_count!==d.observations.length||
    !Array.isArray(d.source_urls)||!d.source_urls.length||d.source_urls.length>40)
   throw new Error("历史数据结构、来源或PIT限制不符合要求");
  const retrieved=Date.parse(d.retrieved_at);
  if(!Number.isFinite(retrieved)||retrieved>Date.now())throw new Error("历史数据抓取时间无效");
  const kinds=new Set();
  for(const raw of d.source_urls){
   let u;
   try{u=new URL(raw)}catch{throw new Error("历史官方来源URL无效")}
   const year=u.searchParams.get("field_tdr_date_value"),kind=u.searchParams.get("type");
   if(u.protocol!=="https:"||u.username||u.password)
    throw new Error("历史来源必须使用可信HTTPS");
   if(d.source==="U.S. Department of the Treasury"){
    if(u.hostname!=="home.treasury.gov"||!/^[0-9]{4}$/.test(year||"")||
      !u.pathname.includes("/"+year+"/all")||
      !["daily_treasury_yield_curve","daily_treasury_real_yield_curve"].includes(kind))
      throw new Error("历史来源不是财政部官方CSV");
    kinds.add(kind);
   }else{
    const id=u.searchParams.get("id");
    if(u.hostname!=="fred.stlouisfed.org"||u.pathname!=="/graph/fredgraph.csv"||
      !["DGS10","DGS2","DFII10"].includes(id)||
      !u.searchParams.has("cosd")||!u.searchParams.has("coed"))
      throw new Error("历史来源不是美联储H.15经FRED镜像");
    kinds.add(id);
   }
  }
  if(d.source==="U.S. Department of the Treasury"&&kinds.size!==2)
   throw new Error("缺少财政部名义或实际收益率来源");
  if(d.source==="Federal Reserve Board H.15 via FRED"&&
     (kinds.size!==3||!["DGS10","DGS2","DFII10"].every(x=>kinds.has(x))||
     JSON.stringify(d.source_series_ids)!=='["DGS10","DGS2","DFII10"]'))
   throw new Error("H.15必须包含DGS10、DGS2和DFII10");
  let last="";
  const keys=["us10y","us2y","real10y","breakeven10y","spread10y2y"];
  for(const row of d.observations){
   if(!row||!validDay(row.date)||row.date<=last||
       keys.some(key=>typeof row[key]!=="number"||!Number.isFinite(row[key])||row[key]<=-15||row[key]>=30))
    throw new Error("历史观测的日期、顺序或收益率不合法");
   if(Math.abs(row.us10y-row.real10y-row.breakeven10y)>0.0011||
      Math.abs(row.us10y-row.us2y-row.spread10y2y)>0.0011)
    throw new Error("历史代数派生指标不一致");
   last=row.date;
  }
  if(d.start_date!==d.observations[0].date||d.end_date!==last)
   throw new Error("历史观测起止日期不一致");
  return d;
 }
 function selectWindow(data,range){
  const rows=data.observations;
  if(range==="all")return rows;
  const latest=Date.parse(rows[rows.length-1].date+"T00:00:00Z");
  const cutoff=latest-(range==="3m"?92:366)*86400000;
  return rows.filter(row=>Date.parse(row.date+"T00:00:00Z")>=cutoff);
 }
 function clear(node){node.replaceChildren()}
 const ASSET_CURVE_FOCUS={
  gold:["real10y","breakeven10y"],
  us_equities:["us10y","real10y"],
  us_long_bonds:["us10y","real10y"],
  usd:["us10y","spread10y2y"],
  bitcoin:["real10y","us10y"],
  oil:["breakeven10y","us10y"]
 };
 let readyData=null;
 function plot(data,key,range,compareKey){
  const chart=$("treasury-trend-svg"),status=$("treasury-trend-status"),
   meta=$("treasury-trend-meta"),body=$("treasury-trend-table"),
   legend=$("treasury-trend-legend"),difference=$("treasury-trend-difference");
  if(!chart||!status||!meta||!body)return;
  clear(chart);clear(body);
  if(legend)clear(legend);
  if(difference)difference.textContent="";
  key=Object.hasOwn(FIELDS,key)?key:"us10y";
  compareKey=Object.hasOwn(FIELDS,compareKey)&&compareKey!==key?compareKey:null;
  const all=selectWindow(data,range);
  if(all.length<2){
   status.textContent="所选期间有效观测不足，无法绘制真实历史趋势。";
   meta.textContent="未使用估算值或填充值。";return;
  }
  const width=720,height=300,left=62,right=20,top=24,bottom=45;
  // The source already has exact-date paired nominal and TIPS observations.
  // Never forward-fill or align two unrelated observation timestamps.
  const values=all.flatMap(r=>compareKey?[r[key],r[compareKey]]:[r[key]]);
  const rawMin=Math.min(...values),rawMax=Math.max(...values);
  const margin=Math.max((rawMax-rawMin)*0.1,0.08);
  const ymin=rawMin-margin,ymax=rawMax+margin;
  const x=i=>left+i/(all.length-1)*(width-left-right);
  const y=v=>top+(ymax-v)/(ymax-ymin)*(height-top-bottom);
  chart.setAttribute("viewBox","0 0 720 300");
  chart.setAttribute("role","img");
  chart.setAttribute("aria-label",FIELDS[key].name+(compareKey?"与"+FIELDS[compareKey].name+"双曲线对比":"")+
   "："+all[0].date+"至"+all[all.length-1].date+"的同日匹配历史收益率观测（"+data.source+"）");
  for(let i=0;i<5;i++){
   const value=ymin+(ymax-ymin)*i/4,yy=y(value);
   chart.append(svg("line",{x1:left,y1:yy,x2:width-right,y2:yy,class:"trend-gridline"}));
   chart.append(svg("text",{x:left-8,y:yy+4,"text-anchor":"end",class:"trend-axis-label"},value.toFixed(2)));
  }
  function curve(field,cls){
   const d=all.map((r,i)=>(i?"L":"M")+x(i).toFixed(2)+" "+y(r[field]).toFixed(2)).join(" ");
   chart.append(svg("path",{d,class:cls,fill:"none"}));
   chart.append(svg("circle",{cx:x(all.length-1),cy:y(all[all.length-1][field]),r:4,
    class:cls==="trend-line"?"trend-last-point":"trend-compare-point"}));
  }
  curve(key,"trend-line");
  if(compareKey)curve(compareKey,"trend-compare-line");
  chart.append(svg("text",{x:left,y:height-12,class:"trend-axis-label"},all[0].date));
  chart.append(svg("text",{x:width-right,y:height-12,"text-anchor":"end",class:"trend-axis-label"},all[all.length-1].date));
  const last=all[all.length-1],unit=FIELDS[key].unit;
  status.textContent=FIELDS[key].name+"：最新 "+last[key].toFixed(2)+" "+unit+
   (compareKey?"；"+FIELDS[compareKey].name+"："+last[compareKey].toFixed(2)+" "+FIELDS[compareKey].unit:"")+
   " · "+last.date+" · "+all.length+" 个匹配观测日（所有曲线按同日配对）";
  meta.textContent="来源："+(data.source==="U.S. Department of the Treasury"?
    "美国财政部名义国债与TIPS实际收益率官方CSV":"美国联邦储备委员会H.15日度国债收益率（经圣路易斯联储FRED镜像）")+"；"+
   "数据读取时间："+data.retrieved_at+"；"+
   "历史回溯观测不是历史首发版本，不能直接用于当年可得信息回测。";
  if(legend){
   legend.append(el("span","● "+FIELDS[key].name));
   if(compareKey)legend.append(el("span","● "+FIELDS[compareKey].name));
  }
  // Only the nominal minus real *same-tenor* pair has the breakeven
  // interpretation; never name an arbitrary difference "inflation".
  if(difference&&compareKey&&new Set([key,compareKey]).size===2&&
     [key,compareKey].every(id=>id==="us10y"||id==="real10y")){
   const spread=last.us10y-last.real10y;
   difference.textContent="同日10年期通胀补偿："+spread.toFixed(2)+"个百分点（"+
    (spread*100).toFixed(0)+" bp）。计算口径：10年名义−10年TIPS实际收益率；包含风险及流动性溢价，非纯粹通胀预期。";
  }
  for(const item of all.slice(-8).reverse()){
   const tr=el("tr");
   for(const value of [item.date,item[key].toFixed(3)+" "+unit,
    compareKey?item[compareKey].toFixed(3)+" "+FIELDS[compareKey].unit:"—"]){
    const td=el("td",value);tr.append(td);
   }
   body.append(tr);
  }
 }
 function focusAsset(assetId){
  const choice=ASSET_CURVE_FOCUS[assetId];
  const main=$("treasury-trend-series"),compare=$("treasury-trend-compare"),
   range=$("treasury-trend-range");
  if(!choice||!main||!compare||!range)return false;
  main.value=choice[0];compare.value=choice[1];
  if(readyData)plot(readyData,main.value,range.value,compare.value);
  const section=$("treasury-trend-panel");
  if(section&&typeof section.scrollIntoView==="function")
   section.scrollIntoView({behavior:"smooth",block:"start"});
  return true;
 }
 async function init(){
  const series=$("treasury-trend-series"),compare=$("treasury-trend-compare"),
   range=$("treasury-trend-range"),status=$("treasury-trend-status");
  if(!series||!range||!status)return;
  let documentData;
  try{
   const response=await fetch(SOURCE,{cache:"no-store"});
   if(!response.ok)throw new Error("未发布历史观测JSON（HTTP "+response.status+"）");
   documentData=validate(await response.json());
  }catch(e){
   status.textContent="历史趋势尚不可用："+e.message+"。不会用模拟曲线替代真实数据。";
   return;
  }
  readyData=documentData;
  const update=()=>plot(documentData,FIELDS[series.value]?series.value:"us10y",
   ["3m","1y","all"].includes(range.value)?range.value:"1y",compare?.value||"none");
  series.addEventListener("change",update);
  if(compare)compare.addEventListener("change",update);
  range.addEventListener("change",update);
  if(typeof window!=="undefined")window.ooglexTreasuryFocus=focusAsset;
  update();
 }
 return {validate,selectWindow,plot,init,focusAsset,FIELDS,ASSET_CURVE_FOCUS};
})();
if(document.body.dataset.page==="overview")void TREASURY_TRENDS.init();

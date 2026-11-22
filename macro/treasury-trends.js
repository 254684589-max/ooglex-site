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
  const rows=Array.isArray(data?.observations)?data.observations:[];
  if(!rows.length)return [];
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
 // V44: exact historical observations, not forward-filled dates, returns or
 // investment performance. 1 percentage point = 100 basis points.
 function compareDates(rows,startDate,endDate,key,compareKey){
  if(!Array.isArray(rows)||!Object.hasOwn(FIELDS,key))return null;
  const byDate=new Map(rows.map(row=>[row.date,row]));
  const first=byDate.get(startDate),last=byDate.get(endDate);
  if(!first||!last||startDate>endDate)return null;
  const secondary=Object.hasOwn(FIELDS,compareKey)&&compareKey!==key?compareKey:null;
  const changes=[key,secondary].filter(Boolean).map(id=>{
   const start=first[id],end=last[id];
   if(!Number.isFinite(start)||!Number.isFinite(end))return null;
   const percentagePoints=end-start;
   return {id,start,end,percentagePoints,basisPoints:Math.round(percentagePoints*100)};
  });
  return changes.every(Boolean)?{startDate,endDate,changes}:null;
 }
 function renderDateComparison(rows,key,compareKey,previousStart,previousEnd){
  const start=$("treasury-compare-start"),end=$("treasury-compare-end"),
   output=$("treasury-compare-result");
  if(!start||!end||!output)return;
  const available=rows.map(r=>r.date);
  start.replaceChildren(...available.map(day=>{
   const option=el("option",day);option.value=day;return option;
  }));
  end.replaceChildren(...available.map(day=>{
   const option=el("option",day);option.value=day;return option;
  }));
  start.value=available.includes(previousStart)?previousStart:available[0];
  end.value=available.includes(previousEnd)?previousEnd:available[available.length-1];
  const update=()=>{
   const report=compareDates(rows,start.value,end.value,key,compareKey);
   if(!report){output.textContent="请选择起点不晚于终点的两个真实观测日期。";return}
   output.textContent=report.startDate+" → "+report.endDate+"（仅观察收益率变化） "+
    report.changes.map(change=>FIELDS[change.id].name+"："+
     change.start.toFixed(3)+" → "+change.end.toFixed(3)+" "+FIELDS[change.id].unit+
     "，变化 "+(change.percentagePoints>=0?"+":"")+change.percentagePoints.toFixed(3)+
     "个百分点（"+(change.basisPoints>=0?"+":"")+change.basisPoints+" bp）").join("；")+
    "。非资产价格回报，不代表回测收益。";
  };
  start.onchange=update;end.onchange=update;
  update();
 }
 function renderProbe(row,key,compareKey){
  const display=$("treasury-trend-probe");
  if(!display)return;
  if(!row){display.textContent="移动鼠标或触摸图表查看某日真实观测；也可在下方选择两个日期比较。";return}
  display.textContent=row.date+" · "+FIELDS[key].name+"："+row[key].toFixed(3)+
   " "+FIELDS[key].unit+(compareKey?" · "+FIELDS[compareKey].name+"："+
   row[compareKey].toFixed(3)+" "+FIELDS[compareKey].unit:"")+
   "（官方历史观测，非PIT首发值）";
 }
 function nearestPlotObservation(rows,relativeX){
  if(!Array.isArray(rows)||!rows.length||!Number.isFinite(relativeX))return null;
  const clamped=Math.max(0,Math.min(1,relativeX));
  return rows[Math.round(clamped*(rows.length-1))];
 }
 // V45: descriptive statistics of actual paired observations, not a model score.
 // All windows end on the last *available observation*, never on an assumed trade date.
 const STAT_WINDOWS={"3m":92,"6m":183,"1y":366};
 function periodStatistics(rows,field,window){
  if(!Array.isArray(rows)||!Object.hasOwn(FIELDS,field)||!Object.hasOwn(STAT_WINDOWS,window)||rows.length<2)
   return null;
  const final=rows[rows.length-1];
  if(!final||typeof final.date!=="string"||!validDay(final.date))return null;
  const cutoff=Date.parse(final.date+"T00:00:00Z")-STAT_WINDOWS[window]*86400000;
  const selected=rows.filter(r=>r&&validDay(r.date)&&
   Date.parse(r.date+"T00:00:00Z")>=cutoff&&r.date<=final.date&&
   typeof r[field]==="number"&&Number.isFinite(r[field]));
  if(selected.length<2)return null;
  const ordered=selected.every((r,i)=>i===0||selected[i-1].date<r.date);
  if(!ordered)return null;
  const first=selected[0],last=selected[selected.length-1];
  let low=first,high=first,sum=0;
  for(const item of selected){
   sum+=item[field];
   if(item[field]<low[field])low=item;
   if(item[field]>high[field])high=item;
  }
  const change=last[field]-first[field],span=high[field]-low[field];
  return {id:field,window,startDate:first.date,endDate:last.date,
   sampleCount:selected.length,latest:last[field],minimum:low[field],
   maximum:high[field],minimumDate:low.date,maximumDate:high.date,
   average:sum/selected.length,changePercentagePoints:change,
   changeBasisPoints:Math.round(change*100),
   // This is the *location within the observed yield range*, NOT an
   // investment rating, historical percentile or a 0–100 asset score.
   rangePosition:span>0?(last[field]-low[field])/span:null};
 }
 function renderPeriodStatistics(data,key,compareKey){
  const panel=$("treasury-period-statistics");
  if(!panel)return;
  panel.replaceChildren();
  if(!data||!Array.isArray(data.observations)||data.observations.length<2){
   panel.append(el("p","统计暂不可用：缺少经过核验的真实历史观测。"));return;
  }
  const intro=el("p","区间锚定于最新可取得的观测日；最高、最低与均值基于实际有记录的日期，不填补节假日。当前值位置仅是区间高低点内的相对位置，不是百分位、资产评分或涨跌预测。");
  intro.className="muted";
  panel.append(intro);
  const fields=[key,compareKey].filter((id,i,arr)=>Object.hasOwn(FIELDS,id)&&arr.indexOf(id)===i);
  const grid=el("div");grid.className="treasury-stat-grid";
  for(const id of fields){
   const item=el("article");item.className="treasury-stat-series";
   const head=el("h3",FIELDS[id].name);item.append(head);
   const table=el("table");
   const thead=el("thead"),hr=el("tr");
   for(const col of ["窗口","观测数","最低及日期","最高及日期","算术均值","最新值","首末变化","当前区间位置"]){
    const th=el("th",col);th.scope="col";hr.append(th);
   }
   thead.append(hr);table.append(thead);
   const tbody=el("tbody");
   for(const win of ["3m","6m","1y"]){
    const stats=periodStatistics(data.observations,id,win);
    const row=el("tr");
    const cells=!stats?[win,"不足2项实际观测","—","—","—","—","—","—"]:[
     win,stats.sampleCount+"天",stats.minimum.toFixed(3)+"（"+stats.minimumDate+"）",
     stats.maximum.toFixed(3)+"（"+stats.maximumDate+"）",
     stats.average.toFixed(3),stats.latest.toFixed(3),
     (stats.changeBasisPoints>=0?"+":"")+stats.changeBasisPoints+" bp",
     stats.rangePosition===null?"区间无变化":
     (stats.rangePosition*100).toFixed(1)+"%（低点→高点）"
    ];
    cells.forEach(value=>row.append(el("td",value)));
    tbody.append(row);
   }
   table.append(tbody);
   const wrap=el("div");wrap.className="table-wrap";wrap.append(table);
   item.append(wrap);grid.append(item);
  }
  panel.append(grid);
 }
 // V46 in-sample descriptive statistics. The latest observation is included
 // in its own empirical midrank; this is not an ex-ante PIT signal.
 function quantile(sorted,p){
  if(!sorted.length||p<0||p>1)return null;
  const index=(sorted.length-1)*p,lo=Math.floor(index),hi=Math.ceil(index);
  return sorted[lo]+(sorted[hi]-sorted[lo])*(index-lo);
 }
 const DISTRIBUTION_BINS=[
  {label:"≤ −20 bp",accept:x=>x<=-20},
  {label:"(−20, −10] bp",accept:x=>x>-20&&x<=-10},
  {label:"(−10, −5] bp",accept:x=>x>-10&&x<=-5},
  {label:"(−5, +5) bp",accept:x=>x>-5&&x<5},
  {label:"[+5, +10) bp",accept:x=>x>=5&&x<10},
  {label:"[+10, +20) bp",accept:x=>x>=10&&x<20},
  {label:"≥ +20 bp",accept:x=>x>=20}
 ];
 function rateDistribution(rows,field){
  if(!Array.isArray(rows)||!Object.hasOwn(FIELDS,field)||rows.length<3)return null;
  let last="";
  for(const row of rows){
   if(!row||!validDay(row.date)||row.date<=last||
    typeof row[field]!=="number"||!Number.isFinite(row[field]))return null;
   last=row.date;
  }
  const values=rows.map(r=>r[field]),latest=values[values.length-1];
  const ordered=values.slice().sort((a,b)=>a-b),n=values.length;
  const lower=ordered.filter(v=>v<latest).length;
  const equal=ordered.filter(v=>v===latest).length;
  const percentile=100*(lower+0.5*equal)/n;
  const moves=[];
  for(let i=1;i<rows.length;i++){
   // Consecutive *observed* dates, not necessarily successive calendar days.
   const changeBp=(rows[i][field]-rows[i-1][field])*100;
   moves.push({previousDate:rows[i-1].date,date:rows[i].date,
    changeBp,absoluteBp:Math.abs(changeBp)});
  }
  const absolute=moves.map(m=>m.absoluteBp).sort((a,b)=>a-b);
  const cutoff=quantile(absolute,0.95),latestMove=moves[moves.length-1];
  const counts=DISTRIBUTION_BINS.map(b=>moves.filter(m=>b.accept(m.changeBp)).length);
  const flagged=moves.filter(m=>m.absoluteBp>=cutoff);
  const largest=moves.slice().sort((a,b)=>b.absoluteBp-a.absoluteBp||
    a.date.localeCompare(b.date)).slice(0,5);
  return {id:field,startDate:rows[0].date,endDate:rows[n-1].date,
   levelCount:n,changeCount:moves.length,latest,percentile,
   lowerCount:lower,equalCount:equal,
   p10:quantile(ordered,0.1),median:quantile(ordered,0.5),p90:quantile(ordered,0.9),
   cutoff95AbsBp:cutoff,flaggedCount:flagged.length,
   latestMove,latestFlagged:latestMove.absoluteBp>=cutoff,
   bins:DISTRIBUTION_BINS.map((b,i)=>({label:b.label,count:counts[i]})),
   largest};
 }
 function renderRateDistribution(rows,key,compareKey){
  const panel=$("treasury-rate-distribution");
  if(!panel)return;
  panel.replaceChildren();
  if(!rows||rows.length<3){
   panel.append(el("p","历史分布暂不可用：至少需要3个真实同日配对观测值。"));return;
  }
  const info=el("p","统计为所选图表范围内的历史样本描述：收益率经验分位采用“低于最新值的样本 + 相等样本的一半”计算；单日变化指相邻实际观测日的差，非日历日填值。异常阈值为本样本绝对变化的95%分位（含当前日），不构成实时预警、资产评分或预测。");
  info.className="muted";panel.append(info);
  const fields=[key,compareKey].filter((id,i,a)=>Object.hasOwn(FIELDS,id)&&a.indexOf(id)===i);
  const grid=el("div");grid.className="treasury-distribution-grid";
  for(const id of fields){
   const stats=rateDistribution(rows,id);
   const item=el("article");item.className="treasury-distribution-card";
   item.append(el("h4",FIELDS[id].name));
   if(!stats){item.append(el("p","有效样本不足或存在无效观测，统计不发布。"));grid.append(item);continue}
   const summary=el("p","历史区间："+stats.startDate+" 至 "+stats.endDate+
    " · 收益率观测 "+stats.levelCount+"日 · 变化样本 "+stats.changeCount+"次");
   summary.className="label";item.append(summary);
   const kpis=el("div");kpis.className="treasury-distribution-kpis";
   for(const [label,value] of [
    ["当前收益率经验分位",stats.percentile.toFixed(1)+"%"],
    ["P10 / 中位 / P90",stats.p10.toFixed(3)+" / "+stats.median.toFixed(3)+" / "+stats.p90.toFixed(3)],
    ["单次变动绝对值P95",stats.cutoff95AbsBp.toFixed(1)+" bp"],
    ["最新一次观测间变动",(stats.latestMove.changeBp>=0?"+":"")+stats.latestMove.changeBp.toFixed(1)+" bp"],
    ["最新变动是否达到样本P95阈值",stats.latestFlagged?"是（样本内）":"否（样本内）"],
    ["达到阈值的样本次数",stats.flaggedCount+" / "+stats.changeCount]
   ]){
    const cell=el("div");cell.className="treasury-distribution-kpi";
    const l=el("span",label);l.className="label";const v=el("strong",value);
    cell.append(l,v);kpis.append(cell);
   }
   item.append(kpis);
   item.append(el("h5","单次观测间变化分布（bp）"));
   const bars=el("div");bars.className="treasury-distribution-bars";
   const max=Math.max(...stats.bins.map(b=>b.count),1);
   for(const bin of stats.bins){
    const line=el("div");line.className="treasury-distribution-bin";
    const name=el("span",bin.label),bar=el("div");bar.className="treasury-distribution-track";
    const fill=el("span");fill.className="treasury-distribution-fill";
    fill.style.width=(bin.count/max*100).toFixed(1)+"%";
    bar.append(fill);
    line.append(name,bar,el("span",String(bin.count)));bars.append(line);
   }
   item.append(bars);
   item.append(el("h5","绝对变化最大的5个观测间变动"));
   const table=el("table");const head=el("thead"),tr=el("tr");
   for(const title of ["上一观测日","本次观测日","变动（bp）"]){
    const th=el("th",title);th.scope="col";tr.append(th);
   }
   head.append(tr);table.append(head);
   const body=el("tbody");
   for(const move of stats.largest){
    const row=el("tr");
    for(const val of [move.previousDate,move.date,
      (move.changeBp>=0?"+":"")+move.changeBp.toFixed(1)]){
     row.append(el("td",val));
    }
    body.append(row);
   }
   table.append(body);const wrap=el("div");wrap.className="table-wrap";wrap.append(table);
   item.append(wrap);grid.append(item);
  }
  panel.append(grid);
 }
 function plot(data,key,range,compareKey){
  const chart=$("treasury-trend-svg"),status=$("treasury-trend-status"),
   meta=$("treasury-trend-meta"),body=$("treasury-trend-table"),
   legend=$("treasury-trend-legend"),difference=$("treasury-trend-difference");
  if(!chart||!status||!meta||!body)return;
  clear(chart);clear(body);
  if(legend)clear(legend);
  if(difference)difference.textContent="";
  const probe=$("treasury-trend-probe"),start=$("treasury-compare-start"),
    end=$("treasury-compare-end"),comparison=$("treasury-compare-result");
  const previousStart=start?.value,previousEnd=end?.value;
  chart.onpointermove=null;chart.onpointerleave=null;
  if(probe)probe.textContent="";
  if(comparison)comparison.textContent="";
  if(start)start.replaceChildren();
  if(end)end.replaceChildren();
  key=Object.hasOwn(FIELDS,key)?key:"us10y";
  compareKey=Object.hasOwn(FIELDS,compareKey)&&compareKey!==key?compareKey:null;
  const all=selectWindow(data,range);
  if(all.length<2){
   status.textContent="所选期间有效观测不足，无法绘制真实历史趋势。";
   meta.textContent="未使用估算值或填充值。";
   if(probe)probe.textContent="未取得足够真实历史观测，无法定位或比较。";
   if(comparison)comparison.textContent="无可比较的实际观测日期。";
   renderPeriodStatistics(null,key,compareKey);
   renderRateDistribution(null,key,compareKey);
   return;
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
  // Use the V43 equal-spaced observation x axis, not fabricated weekend days.
  // Pointer coordinates come from the rendered SVG bounds; no network fetches.
  chart.onpointermove=event=>{
   if(typeof chart.getBoundingClientRect!=="function")return;
   const bounds=chart.getBoundingClientRect();
   if(!bounds||!Number.isFinite(bounds.width)||bounds.width<=0)return;
   const viewX=(event.clientX-bounds.left)/bounds.width*width;
   const ratio=(viewX-left)/(width-left-right);
   renderProbe(nearestPlotObservation(all,ratio),key,compareKey);
  };
  chart.onpointerleave=()=>renderProbe(null,key,compareKey);
  chart.onfocus=()=>renderProbe(all[all.length-1],key,compareKey);
  if(typeof chart.setAttribute==="function")chart.setAttribute("tabindex","0");
  renderProbe(null,key,compareKey);
  renderDateComparison(all,key,compareKey,previousStart,previousEnd);
  renderPeriodStatistics(data,key,compareKey);
  renderRateDistribution(all,key,compareKey);
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
 return {validate,selectWindow,plot,init,focusAsset,compareDates,nearestPlotObservation,periodStatistics,renderPeriodStatistics,rateDistribution,renderRateDistribution,FIELDS,ASSET_CURVE_FOCUS};
})();
if(document.body.dataset.page==="overview")void TREASURY_TRENDS.init();

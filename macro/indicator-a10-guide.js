"use strict";
/* A10 research handbook. Curves are actual Treasury historical observations,
   not original release-time vintages and NOT investable security returns. */
(()=>{
const grid=document.getElementById("a10-guide");
const status=document.getElementById("a10-history-status");
const svg=document.getElementById("a10-history-svg");
const select=document.getElementById("a10-history-series");
const windowSelect=document.getElementById("a10-history-window");
if(!grid||!status||!svg||!select||!windowSelect)return;
const entries=[
 ["美国10年期实际收益率","日度/交易日","%","美国财政部 TIPS","美国10年期通胀保值国债实际到期收益率的曲线估算；对黄金机会成本与长期估值敏感。","实际收益率并非已实现投资回报；TIPS期限与流动性会影响比较。","real10y"],
 ["美国10年期国债收益率","日度/交易日","%","美国财政部","长期名义贴现率、抵押品收益率与美元资产估值参考。","市场收益率变化不等于债券总回报；需留意期限溢价。","us10y"],
 ["美国2年期国债收益率","日度/交易日","%","美国财政部","对短期货币政策路径较敏感的名义到期收益率。","不是未来两年联邦基金利率的精确平均预测。","us2y"],
 ["10Y－2Y期限利差","日度/交易日","百分点","财政部同日数值计算","10年期减2年期名义收益率，观察收益率曲线斜率及周期变化。","负利差不能被单独等同于确定的衰退事件。","spread10y2y"],
 ["10年盈亏平衡通胀率","日度/交易日","百分点","财政部名义与TIPS收益率差","名义10年收益率减10年实际收益率，反映市场要求的通胀补偿。","含流动性及通胀风险溢价，不等于纯粹预期通胀。","breakeven10y"],
 ["SOFR及SOFR远期曲线","SOFR交易日；远期曲线另定","%","纽约联储／合规衍生品数据","隔夜SOFR反映有担保隔夜融资成本；SOFR期货或互换远期曲线反映衍生品隐含路径。","官方隔夜SOFR已接入；远期利率与交易所合约报价尚未完成。",null],
 ["美国国债远期收益率曲线","报价日；依赖期限结构方法","%","财政部期限结构／市场推导","根据同日的不同期限现货和零息曲线推算未来起始期限的隐含收益率。","不可直接拿10年期现货收益率冒充10年远期收益率。",null],
 ["联邦基金目标利率及FOMC指引","FOMC会议变化；EFFR交易日","%","美联储／纽约联储","目标区间代表政策目标，FOMC声明、SEP与点阵图是不同的信息层。","当前仅展示EFFR接口所报告目标区间；FOMC官方前瞻文本/SEP未完成统一接入。",null],
 ["高收益债OAS信用利差","交易日（以提供方发布为准）","百分点","ICE BofA／FRED","期权调整后的高收益信用利差，用于观察企业信用风险与金融条件。","须核对使用许可、指数成分及供应商数据定义；未认证前不填数值。",null],
 ["美国非农就业与失业率","月度","千人/月，%","美国劳工统计局 BLS","非农就业月增量反映就业新增岗位估计，失业率来自家庭调查；两者口径不同。","两项来自不同调查且均可能修订，不可将月增量当作就业人数存量。",null],
];
const ns="http://www.w3.org/2000/svg";
for(const [name,freq,unit,src,meaning,caveat] of entries){
  const card=document.createElement("article");card.className="a10-guide-card";
  const h=document.createElement("h3");h.textContent=name;card.append(h);
  for(const [label,val] of [["更新频率",freq],["单位",unit],["来源",src],["研究意义",meaning],["注意事项",caveat]]){
    const p=document.createElement("p");const strong=document.createElement("strong");strong.textContent=label+"：";p.append(strong,document.createTextNode(val));card.append(p);
  }
  const link=document.createElement("a");link.href="./indicator-lab.html";link.textContent="进入历史研究档案";card.append(link);grid.append(card);
}
let rows=[];
function draw(){
  while(svg.firstChild)svg.removeChild(svg.firstChild);
  const field=select.value,period=windowSelect.value;
  const all=rows.filter(x=>typeof x[field]==="number"&&Number.isFinite(x[field])&&/^\d{4}-\d{2}-\d{2}$/.test(x.date));
  if(!all.length){status.textContent="这条收益率序列暂无可核实的历史观测。";return;}
  const last=Date.parse(all[all.length-1].date+"T00:00:00Z"),days=period==="1y"?366:period==="2y"?732:Infinity;
  const series=all.filter(x=>period==="all"||last-Date.parse(x.date+"T00:00:00Z")<=days*86400000);
  if(series.length<2){status.textContent="有效历史观测点不足，不绘图。";return;}
  const width=900,height=260,pad={l:60,r:20,t:18,b:38};
  const values=series.map(x=>x[field]),low=Math.min(...values),high=Math.max(...values);
  const span=Math.max(high-low,0.02),min=low-span*.12,max=high+span*.12;
  const x=i=>pad.l+(width-pad.l-pad.r)*(i/(series.length-1));
  const y=v=>pad.t+(max-v)/(max-min)*(height-pad.t-pad.b);
  function node(name,attrs){const n=document.createElementNS(ns,name);for(const [k,v] of Object.entries(attrs))n.setAttribute(k,String(v));return n;}
  for(let i=0;i<=4;i++){
    const v=min+(max-min)*i/4,yy=y(v);
    svg.append(node("line",{x1:pad.l,x2:width-pad.r,y1:yy,y2:yy,stroke:"#314258","stroke-width":1}));
    const label=node("text",{x:pad.l-10,y:yy+4,"text-anchor":"end",fill:"#abc1d9","font-size":12});
    label.textContent=v.toFixed(2);svg.append(label);
  }
  const points=series.map((r,i)=>x(i).toFixed(1)+","+y(r[field]).toFixed(1)).join(" ");
  svg.append(node("polyline",{points,fill:"none",stroke:"#69baff","stroke-width":2.5,"stroke-linecap":"round","stroke-linejoin":"round"}));
  const first=node("text",{x:pad.l,y:height-9,fill:"#abc1d9","font-size":12});first.textContent=series[0].date;svg.append(first);
  const end=node("text",{x:width-pad.r,y:height-9,"text-anchor":"end",fill:"#abc1d9","font-size":12});end.textContent=series[series.length-1].date;svg.append(end);
  const lastValue=values[values.length-1];
  status.textContent=entries.find(x=>x[6]===field)?.[0]+"｜"+series.length+"个已记录观测｜最新 "+series[series.length-1].date+"："+lastValue.toFixed(3)+(field==="spread10y2y"||field==="breakeven10y"?" 个百分点":"%")+"。当前下载可见历史版本，不具备原始PIT资格。";
}
select.addEventListener("change",draw);windowSelect.addEventListener("change",draw);
(async()=>{
 try{
  const resp=await fetch("../data/asset-compass-treasury-history.json",{cache:"no-store"});
  if(!resp.ok)throw Error("HTTP "+resp.status);
  const d=await resp.json();
  if(d?.schema_version!==1||d.dataset!=="treasury_historical_daily_observations"||
     d.original_release_vintages_available!==false||d.not_valid_for_point_in_time_backtest!==true||
     !Array.isArray(d.observations)||d.observations.length<2)throw Error("历史数据类型或PIT门禁不匹配");
  rows=d.observations.filter(x=>x&&typeof x.date==="string").sort((a,b)=>a.date.localeCompare(b.date));
  draw();
 }catch(e){status.textContent="无法验证官方历史数据："+e.message+"；不绘制推测曲线。";}
})();
})();

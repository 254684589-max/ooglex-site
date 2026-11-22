"use strict";
(()=>{
 const $=id=>document.getElementById(id),root=$("spread-monitor"),sel=$("monitor-tenor"),status=$("monitor-status");
 if(!root||!sel||!status||!window.OoglexSwapMonitor)return;
 const fmt=v=>v===null?"无数据":(v<0?"−":"+")+Math.abs(v).toFixed(2)+" bp";
 const label={widening:"利差扩大",tightening:"利差收窄",unchanged:"无变化",insufficient:"样本不足"};
 function render(data){
   const obs=data.observations;
   const draw=()=>{
     const r=window.OoglexSwapMonitor.analyze(obs,Number(sel.value));
     const values=[
       ["最近已归档变化",fmt(r.deltaBp),r.previousAsOf?"比较基准日："+r.previousAsOf:"没有前一个真实观测日"],
       ["方向",label[r.direction]||"暂无","观察变化，不代表政策或资产价格预测"],
       ["经验异常识别",r.classification==="unusual_observed_change"?"异常变动（研究提示）":
          r.classification==="normal_observed_change"?"未达到异常阈值":"未启用",
         r.thresholdBp===null?"至少需30个先前变动与45天跨度":"异常门槛："+r.thresholdBp+" bp；参考变动样本："+r.baseline.count]
     ];
     root.replaceChildren(...values.map(([name,value,note])=>{
       const el=document.createElement("article");el.className="card";
       for(const [text,style] of [[name,"minor"],[value,"big"],[note,"minor"]]){
         const div=document.createElement("div");div.className=style;div.textContent=text;el.append(div);
       }return el;
     }));
     status.textContent=r.status==="stale"?
       "过期数据：最近观测日 "+r.asOf+"，不发布新的异常判断。":
       "数据日："+r.asOf+"；总归档："+r.count+"个交易日；"+
       (r.classification==="descriptive_only"?"尚不满足异常阈值统计样本要求。":
       r.classification==="unusual_observed_change"?"统计性异常变动，仅作研究提示。":"无足够证据发布风险预警。");
   };
   sel.addEventListener("change",draw);draw();
 }
 fetch("./swap-spreads-history.json",{cache:"no-store"}).then(r=>{if(!r.ok)throw Error("HTTP "+r.status);return r.json()})
 .then(d=>{
   if(d.schemaVersion!==2||d.demo!==false||!Array.isArray(d.observations))throw Error("数据契约无效");
   render(d);
 }).catch(e=>{status.textContent="监测不可用："+e.message+"。不显示猜测性风险指标。";root.replaceChildren();});
})();
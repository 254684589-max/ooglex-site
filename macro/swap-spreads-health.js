"use strict";
(()=>{
  const target=document.getElementById("sofr-run-health");
  if(!target)return;
  function show(message){target.textContent=message;}
  function isRealDate(s){if(typeof s!=="string"||!/^\d{4}-\d{2}-\d{2}$/.test(s))return false;const d=new Date(s+"T00:00:00Z");return Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===s;}
  fetch("./swap-spreads-health.json",{cache:"no-store"}).then(r=>{
    if(r.status===404)throw Error("尚无正式日更成功记录（状态文件尚未生成）");
    if(!r.ok)throw Error("无法读取采集状态（HTTP "+r.status+"）");
    return r.json();
  }).then(d=>{
    if(!d||d.schemaVersion!==1||d.type!=="sofr-last-successful-ingestion"||
       d.status!=="successful"||!["new_observation","no_new_observation"].includes(d.runResult)||
       !isRealDate(d.lastDataAsOf)||typeof d.lastSuccessAt!=="string"||
       !Number.isFinite(Date.parse(d.lastSuccessAt))||!Number.isInteger(d.observations)||
       d.observations<1)throw Error("采集状态文件未通过校验");
    const age=(Date.now()-Date.parse(d.lastSuccessAt))/86400000;
    if(age<-.1)throw Error("采集状态时间异常");
    const old=age>3;
    show("正式日更最近一次成功："+d.lastSuccessAt.replace("T"," ").slice(0,16)+" UTC"+
         "｜数据日期："+d.lastDataAsOf+"｜真实观测数："+d.observations+
         "｜结果："+(d.runResult==="new_observation"?"新增交易日":"当次无新交易日")+
         (old?"｜超过3天未记录新一次成功，需检查GitHub Actions。":"｜非实时成交报价。")+
         "｜注意：仅记录最近一次成功，不能证明之后没有失败。");
  }).catch(e=>show("正式日更状态：未验证。"+e.message+"；不代表历史行情已更新。"));
})();
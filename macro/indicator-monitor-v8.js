"use strict";
/* V8 operational monitor UI: only displays a published, validated report. */
(()=>{
const $=id=>document.getElementById(id);
const status=$("v8-status"),rows=$("v8-rows");
if(!status||!rows)return;
function add(name,value){const tr=document.createElement("tr");for(const text of [name,value]){const td=document.createElement("td");td.textContent=String(text);tr.append(td)}rows.append(tr)}
async function load(){
try{
const response=await fetch("../data/asset-compass-monitor-v8.json",{cache:"no-store"});
if(!response.ok)throw Error("监控报告暂未发布（HTTP "+response.status+"）");
const d=await response.json();
if(d?.schema_version!==1||d.report_type!=="asset_compass_monitor_v8"||
!["healthy","alert"].includes(d.operational_status)||
!Array.isArray(d.issues)||!Number.isInteger(d.consecutive_alert_runs)||
d.consecutive_alert_runs<0||d.validated_for_live_scoring!==false||
d.point_in_time_backtest_eligible!==false||!Number.isFinite(Date.parse(d.checked_at)))
throw Error("报告结构或模型安全门禁未通过");
const hours=(Date.now()-Date.parse(d.checked_at))/3600000;
if(hours<-.5)throw Error("监控报告生成时间异常");
rows.replaceChildren();
add("监控运行状态",d.operational_status==="healthy"?"运行检查通过":"发现运行异常");
add("连续异常检查次数",d.consecutive_alert_runs);
add("告警级别",d.alert_severity);
add("最近检查时间（UTC）",d.checked_at);
add("检查异常数量",d.issues.length);
for(const i of d.issues){if(typeof i.code==="string"&&typeof i.detail==="string")add("异常："+i.code,i.detail)}
if(hours>36){status.textContent="监控报告已过期（超过36小时），不能确认当前系统健康。正式资产评分仍关闭。";status.className="v8-warn"}
else if(d.operational_status==="healthy"){status.textContent="最近一次运行检查通过，但不代表历史首发版本、资产评分或回测已通过认证。";status.className="v8-ok"}
else{status.textContent="存在运行异常，请在GitHub Actions查看失败任务和详细日志。正式资产评分保持关闭。";status.className="v8-warn"}
}catch(e){rows.replaceChildren();status.textContent="尚未获得可验证的V8监控结果："+e.message+"。评分保持关闭。";status.className="v8-warn"}
}
void load();
})();
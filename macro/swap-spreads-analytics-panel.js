"use strict";
(() => {
  const api=window.OoglexSpreadAnalytics;
  const $=id=>document.getElementById(id);
  const status=$("analytics-status"),panel=$("analytics-kpis"),select=$("analytics-tenor");
  if (!api || !status || !panel || !select) return;
  const fmt=v=>v===null?"样本不足":(v<0?"−":"+")+Math.abs(v).toFixed(2)+" bp";
  const box=(name,value,detail)=>{
    const outer=document.createElement("article"),label=document.createElement("div"),
      number=document.createElement("div"),caption=document.createElement("div");
    outer.className="card";label.className="minor";number.className="big";caption.className="minor";
    label.textContent=name;number.textContent=value;caption.textContent=detail;
    outer.append(label,number,caption);return outer;
  };
  function show(history) {
    const series=api.normalize(history);
    const draw=()=>{
      const years=Number(select.value),r=api.analyze(history,years);
      if(r.status!=="ok"){panel.replaceChildren(box("历史统计","暂无数据","没有完整观测"));return;}
      panel.replaceChildren(
        box("最新利差",fmt(r.latest),"数据日期："+r.asOf),
        box("上一个已归档观测日",fmt(r.changes.one),"变化量；并非保证前一交易日"),
        box("前5个已归档观测日",fmt(r.changes.five),"需要至少6个有效日期"),
        box("前20个已归档观测日",fmt(r.changes.twenty),"需要至少21个有效日期"),
        box("历史经验分位",r.percentile===null?"样本不足":r.percentile.toFixed(2)+"%",
          r.percentile===null?"至少60个先前样本且跨度≥90天":
            "相对于先前"+r.previousCount+"条真实观测的经验百分位"),
        box("历史参考范围",r.observedRange?fmt(r.observedRange.min)+" ～ "+fmt(r.observedRange.max):"样本不足",
          "仅当至少20条先前记录可用")
      );
      const curve=api.relativeCurve(history,10,2);
      $("analytics-2s10s").textContent=curve.status==="ok"?fmt(curve.valueBp):"暂无数据";
      $("analytics-curve-change").textContent=curve.deltaFromPreviousBp===null?
        "暂无可比较的前一个匹配日期，不计算变化量。":
        "相对于前一个已归档匹配日："+fmt(curve.deltaFromPreviousBp)+"（不是国债2Y/10Y期限利差）";
      status.textContent="已归档："+series.length+"个真实匹配日期；统计窗口最多252个先前观察值。样本不连续时只比较已观测日期，不补插值。";
      $("analytics-disclosure").textContent="经验分位数 = 先前观察值中不高于最新利差的数量 / 先前观察值总数 × 100%。至少60个先前观察且跨越90个日历日才显示。该统计不是风险概率、交易信号或同业通用估值评分。";
    };
    select.addEventListener("change",draw);
    draw();
  }
  fetch("./swap-spreads-history.json",{cache:"no-store"})
    .then(response=>{if(!response.ok)throw Error("HTTP "+response.status);return response.json()})
    .then(data=>{
      if(data.demo!==false || data.schemaVersion!==2 || !Array.isArray(data.observations))throw Error("历史文件不符合数据契约");
      show(data.observations);
    })
    .catch(err=>{
      panel.replaceChildren(box("分析不可用","—","未计算任何分位数"));
      status.textContent="统计数据无法验证："+err.message+"。不发布不可靠的历史分位数。";
    });
})();

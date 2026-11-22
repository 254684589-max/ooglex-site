"use strict";
(() => {
  const YEARS = [2, 3, 5, 7, 10, 30];
  const NS = "http://www.w3.org/2000/svg";
  const $ = id => document.getElementById(id);
  const status = $("status");
  const fmt = v => (v < 0 ? "−" : "+") + Math.abs(v).toFixed(2) + " bp";
  const isDate = s => /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s + "T00:00:00Z"));
  function el(svg, tag, props, text) {
    const e = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(props)) e.setAttribute(k, String(v));
    if (text !== undefined) e.textContent = text;
    svg.append(e);
    return e;
  }
  function validate(data) {
    if (!data || data.schemaVersion !== 2 || data.demo !== false || !Array.isArray(data.observations))
      throw new Error("数据契约不符合要求");
    const dates = new Set();
    for (const record of data.observations) {
      if (!isDate(record.asOf) || dates.has(record.asOf) || !Array.isArray(record.tenors) || record.tenors.length !== 6)
        throw new Error("历史日期或期限不合法");
      dates.add(record.asOf);
      if (record.tenors.map(row => row.years).join(",") !== YEARS.join(","))
        throw new Error("缺失指定期限");
      for (const r of record.tenors) {
        if (![r.swap, r.treasury, r.spreadBp].every(v => typeof v === "number" && Number.isFinite(v)) || r.swap <= 0 || r.treasury <= 0
          || !["close", "close-thin"].includes(r.method) || Math.abs((r.swap - r.treasury) * 100 - r.spreadBp) > 0.011)
          throw new Error("利差公式或数据来源方法验证失败");
      }
    }
    return data.observations.slice().sort((a, b) => a.asOf.localeCompare(b.asOf));
  }
  function axes(svg, min, max, bounds, ticks, xLabel) {
    const {left, right, top, bottom} = bounds;
    const y = v => bottom - (v - min) / (max - min) * (bottom - top);
    for (let i = 0; i <= ticks; i++) {
      const v = min + (max - min) * i / ticks;
      const yy = y(v);
      el(svg, "line", {x1:left,y1:yy,x2:right,y2:yy,stroke:"#34465a","stroke-width":1});
      el(svg, "text", {x:left-12,y:yy+4,"text-anchor":"end"},v.toFixed(0));
    }
    el(svg,"text",{x:22,y:18},"bp");
    el(svg,"text",{x:right,y:bottom+33,"text-anchor":"end"},xLabel);
    return y;
  }
  function renderCurve(record) {
    const svg = $("term");
    svg.replaceChildren();
    const points = record.tenors, values = points.map(r => r.spreadBp);
    const min = Math.floor((Math.min(...values)-8)/10)*10;
    const max = Math.max(0,Math.ceil((Math.max(...values)+8)/10)*10);
    const b = {left:70,right:840,top:32,bottom:285};
    const y = axes(svg,min,max,b,5,"期限");
    const x = r => b.left + (r.years-2)/28*(b.right-b.left);
    el(svg,"polyline",{points:points.map(r=>x(r)+","+y(r.spreadBp)).join(" "),fill:"none",stroke:"#77baff","stroke-width":3,"stroke-linejoin":"round"});
    for(const r of points){
      el(svg,"circle",{cx:x(r),cy:y(r.spreadBp),r:5,fill:"#77baff"});
      el(svg,"text",{x:x(r),y:y(r.spreadBp)-13,"text-anchor":"middle"},fmt(r.spreadBp));
      el(svg,"text",{x:x(r),y:b.bottom+21,"text-anchor":"middle"},r.years+"Y");
    }
    $("term-desc").textContent = record.asOf + " 横截面，6个实际期限观测，数值为指示性利差（bp）。";
  }
  function renderHistory(observations, years) {
    const svg = $("history");
    svg.replaceChildren();
    const values = observations.map(record=>({date:record.asOf,spreadBp:record.tenors.find(r=>r.years===years).spreadBp}));
    if (values.length < 2) {
      el(svg,"text",{x:450,y:145,"text-anchor":"middle"},"仅有 "+values.length+" 个匹配日期，暂不绘制虚假历史趋势");
      $("history-desc").textContent = "历史观测："+values.length+" 个日期。至少积累两个真实交易日才可连接历史折线。";
      return;
    }
    const b={left:80,right:836,top:30,bottom:262};
    const low=Math.min(...values.map(v=>v.spreadBp)),high=Math.max(...values.map(v=>v.spreadBp));
    const pad=Math.max(5,(high-low)*0.15);
    const y=axes(svg,Math.floor((low-pad)/5)*5,Math.ceil((high+pad)/5)*5,b,5,"交易日");
    const x=i=>b.left+i/(values.length-1)*(b.right-b.left);
    el(svg,"polyline",{points:values.map((v,i)=>x(i)+","+y(v.spreadBp)).join(" "),fill:"none",stroke:"#74c8b7","stroke-width":3});
    const ticks=[0,Math.floor((values.length-1)/2),values.length-1];
    for(const i of new Set(ticks)){
      el(svg,"circle",{cx:x(i),cy:y(values[i].spreadBp),r:4,fill:"#74c8b7"});
      el(svg,"text",{x:x(i),y:b.bottom+20,"text-anchor":"middle"},values[i].date.slice(5));
    }
    $("history-desc").textContent=years+"年期 · "+values.length+" 个有据可查的匹配交易日；"+values[0].date+" 至 "+values[values.length-1].date+"。未插值或补造缺失日。";
  }
  function render(data) {
    const observations=validate(data);
    if(!observations.length){status.textContent="尚无完整、日期匹配的正式观测；已停用图表。";return}
    const latest=observations[observations.length-1];
    const age=(Date.now()-Date.parse(latest.asOf+"T00:00:00Z"))/86400000;
    const stale=age>7;
    status.textContent=(stale?"历史数据已过期":"最近有效观测")+
      "｜数据日："+latest.asOf+"｜频率：日频参考｜来源：CheckMySwap（DTCC指示性OIS曲线）+ 美国财政部"+
      "｜历史匹配交易日："+observations.length+"｜"+(stale?"超过7个自然日，切勿作为当前报价。":"非实时可执行报价。")+
      "｜数据生成："+(data.updatedAt||"未知");
    for(const years of [2,10,30])$("k"+years).textContent=fmt(latest.tenors.find(r=>r.years===years).spreadBp);
    const body=$("rows");
    body.replaceChildren();
    for(const r of latest.tenors){
      const tr=document.createElement("tr");
      for(const text of [r.years+"年",r.swap.toFixed(4),r.treasury.toFixed(2),fmt(r.spreadBp),r.method]){
        const td=document.createElement("td");td.textContent=text;tr.append(td);
      }
      body.append(tr);
    }
    renderCurve(latest);
    const selector=$("tenor-select");
    selector.addEventListener("change",()=>renderHistory(observations,Number(selector.value)));
    renderHistory(observations,Number(selector.value));
  }
  fetch("./swap-spreads-history.json",{cache:"no-store"})
    .then(r=>{if(!r.ok)throw new Error("HTTP "+r.status);return r.json()})
    .then(render).catch(err=>{status.textContent="数据不可用： "+err.message+"。已停用计算展示，未用旧行情冒充实时。";});
})();

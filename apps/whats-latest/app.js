/* Ooglex 最新消息 · What’s-the-Latest-inspired briefing layout
 * 数据来源、抓取与自动更新逻辑保持不变；这里只负责展示。
 */
(function(){
  "use strict";
  var DATA=null, active="all";
  var $=function(id){return document.getElementById(id);};

  function esc(s){
    return String(s==null?"":s).replace(/[&<>"]/g,function(c){
      return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c];
    });
  }
  function isNum(v){return v!==null&&v!==undefined&&!isNaN(v);}
  function relTime(pub){
    if(!isNum(pub))return "";
    var diff=Date.now()/1000-Number(pub);
    if(diff<0)return "刚刚";
    if(diff<3600)return Math.max(1,Math.floor(diff/60))+"分钟前";
    if(diff<86400)return Math.floor(diff/3600)+"小时前";
    if(diff<2592000)return Math.floor(diff/86400)+"天前";
    return "";
  }
  function dateText(iso){
    if(!iso)return "—";
    var d=new Date(iso+"T00:00:00");
    if(isNaN(d.getTime()))return iso;
    return ["周日","周一","周二","周三","周四","周五","周六"][d.getDay()]+" · "+iso+" · Ooglex";
  }
  function fmtPrice(m){
    if(!isNum(m.price))return "—";
    var p=Number(m.price),dec=p>=1000?0:2;
    var s=p.toLocaleString("en-US",{minimumFractionDigits:dec,maximumFractionDigits:dec});
    return (m.fmt==="usd"?"$":"")+s;
  }
  function pctClass(v){return !isNum(v)?"flat":Number(v)>0?"up":Number(v)<0?"down":"flat";}
  function pctText(v){
    if(!isNum(v))return "—";
    v=Number(v);
    return (v>0?"▲":v<0?"▼":"•")+Math.abs(v).toFixed(2)+"%";
  }
  function catByKey(key){
    return (DATA.categories||[]).filter(function(c){return c.key===key;})[0]||null;
  }
  function allItems(){
    var out=[];
    (DATA.categories||[]).forEach(function(c){
      (c.items||[]).forEach(function(it){
        out.push(Object.assign({category:c.name,categoryKey:c.key},it));
      });
    });
    return out;
  }

  function activeItems(){
    if(active==="all")return allItems();
    var c=catByKey(active);
    return c?(c.items||[]).map(function(it){
      return Object.assign({category:c.name,categoryKey:c.key},it);
    }):[];
  }

  function activeLead(){
    if(active==="all")return DATA.lead||DATA.highlight||{};
    var items=activeItems().slice().sort(function(a,b){
      return Number(b.published||0)-Number(a.published||0);
    });
    return items[0]||{};
  }

  function renderActiveView(){
    renderHero();
    renderTrending();
    renderSignals();
    renderWires();
    renderCards();
    renderRail();
    renderRundown();
  }

  function renderHeader(){
    $("date-line").textContent=dateText(DATA.asOf);
    $("edition-date").textContent=(DATA.asOf||"—")+" · latest";
    var upd=DATA.updatedAt?new Date(DATA.updatedAt):null;
    if(upd&&!isNaN(upd.getTime())){
      var mins=Math.max(0,Math.round((Date.now()-upd.getTime())/60000));
      $("freshness").textContent=mins<60?"更新于 "+Math.max(1,mins)+" 分钟前":"更新于 "+Math.floor(mins/60)+" 小时前";
    }else $("freshness").textContent="自动更新";
  }

  function renderTabs(){
    var box=$("category-tabs");
    var defs=[{key:"all",name:"概览"}].concat((DATA.categories||[]).map(function(c){
      var map={politics:"政策",world:"国际",markets:"市场",tech:"AI/Tech",law:"监管",risk:"风险"};
      return {key:c.key,name:map[c.key]||c.name};
    }));
    box.innerHTML="";
    defs.forEach(function(t){
      var b=document.createElement("button");
      b.type="button";b.textContent=t.name;
      if(t.key===active)b.className="on";
      b.onclick=function(){
        active=t.key;
        box.querySelectorAll("button").forEach(function(x){x.classList.remove("on");});
        b.classList.add("on");
        renderActiveView();
      };
      box.appendChild(b);
    });
  }

  function renderHero(){
    var h=activeLead();
    $("hero-link").href=h.link||"#";
    $("hero-title").textContent=h.brief||h.title||"今日全球新闻简报";
    var activeCat=active==="all"?(h.category||"概览"):((catByKey(active)||{}).name||h.category||"");
    $("hero-meta").textContent=[h.source||"",DATA.asOf||"",activeCat].filter(Boolean).join(" · ");
    $("lead-title").textContent=h.title||h.brief||"今日主线";
    $("why-box").innerHTML="<b>WHY IT MATTERS</b>"+esc(h.why||"这条信息是当前简报中的核心主线，值得进一步核实原文与后续发展。");
    $("lead-source").innerHTML=esc(h.source||"来源未知")+(relTime(h.published)?" · "+esc(relTime(h.published)):"")+
      (h.link?" · <a href='"+esc(h.link)+"' target='_blank' rel='noopener'>阅读原文 →</a>":"");
  }

  function renderTrending(){
    var box=$("trending"),items=[];
    if(active==="all"){
      (DATA.signals||[]).forEach(function(s){items.push({label:s.label+(s.trend?" "+s.trend:""),hot:true});});
      (DATA.wires||[]).slice(0,5).forEach(function(it){if(it.topic)items.push({label:it.topic,hot:false});});
    }else{
      activeItems().slice(0,8).forEach(function(it){
        items.push({label:it.topic||it.category||"要闻",hot:false});
      });
    }
    var seen={};
    items=items.filter(function(x){if(seen[x.label])return false;seen[x.label]=1;return true;}).slice(0,8);
    box.innerHTML="<span class='trend-label'>TRENDING NOW</span>"+items.map(function(x){
      return "<span class='trend-chip"+(x.hot?" hot":"")+"'>"+esc(x.label)+"</span>";
    }).join("");
  }

  function renderGalaxy(){
    var cols=["#9d6bd8","#e06167","#67ca83","#d96ea8","#ca69d7","#63c7a3","#c765da","#5f9fda"];
    var cats=DATA.categories||[];
    $("galaxy-bars").innerHTML=(cats.length?cats:[{},{},{},{},{}]).map(function(c,i){
      var n=(c.items||[]).length||1;
      return "<span title='"+esc(c.name||"cluster")+"' style='background:"+cols[i%cols.length]+";flex:"+Math.max(1,n)+"'></span>";
    }).join("");
  }

  function wireHtml(it){
    return "<a class='wire' href='"+esc(it.link||"#")+"' target='_blank' rel='noopener'>"+
      "<div class='wire-topic'>"+esc(it.topic||it.category||"NEWS")+"</div>"+
      "<div class='wire-title'>"+esc(it.brief||it.title||"")+"</div>"+
      "<div class='wire-meta'>"+esc(it.source||"来源未知")+(relTime(it.published)?" · "+esc(relTime(it.published)):"")+"</div></a>";
  }
  function renderWires(){
    var list=active==="all"?(DATA.wires||[]).slice(0,6):activeItems().slice(1,7);
    if(!list.length&&active!=="all")list=activeItems().slice(0,6);
    $("wire-list").innerHTML=list.map(wireHtml).join("");
  }

  function cardHtml(it){
    return "<a class='brief-card' href='"+esc(it.link||"#")+"' target='_blank' rel='noopener'>"+
      "<div class='c-topic'>"+esc(it.topic||it.category||"BRIEF")+"</div>"+
      "<div class='c-title'>"+esc(it.brief||it.title||"")+"</div>"+
      "<div class='c-meta'>"+esc(it.source||"来源未知")+(relTime(it.published)?" · "+esc(relTime(it.published)):"")+"</div></a>";
  }
  function renderCards(){
    var items=active==="all"?(DATA.alsoNoted||[]).concat((DATA.watch||[])).slice(0,6):
      ((catByKey(active)||{}).items||[]).slice(0,6);
    if(!items.length)items=allItems().slice(0,6);
    $("brief-cards").innerHTML=items.map(cardHtml).join("");
  }

  function railItem(it){
    return "<a class='rail-item' href='"+esc(it.link||"#")+"' target='_blank' rel='noopener'>"+
      "<div class='ri-topic'>"+esc(it.topic||it.category||"BRIEF")+"</div>"+
      "<div class='ri-title'>"+esc(it.brief||it.title||"")+"</div>"+
      "<div class='ri-meta'>"+esc(it.source||"来源未知")+(relTime(it.published)?" · "+esc(relTime(it.published)):"")+"</div></a>";
  }
  function renderRail(){
    var selected=activeItems();
    if(active==="all"){
      $("rail-watch").innerHTML=(DATA.watch||[]).slice(0,4).map(railItem).join("");
      $("rail-noted").innerHTML=(DATA.alsoNoted||[]).slice(0,4).map(railItem).join("");
    }else{
      $("rail-watch").innerHTML=selected.slice(0,4).map(railItem).join("");
      $("rail-noted").innerHTML=selected.slice(4,8).map(railItem).join("");
    }
    var mk=DATA.markets||[];
    $("market-list").innerHTML=mk.length?mk.map(function(m){
      return "<div class='quote'><span>"+esc(m.name)+"</span><span class='quote-val'>"+fmtPrice(m)+
        "<small class='"+pctClass(m.changePct)+"'>"+pctText(m.changePct)+"</small></span></div>";
    }).join(""):"<div class='rail-copy'>暂无市场数据</div>";
  }

  function renderSignals(){
    var signals;
    if(active==="all"){
      signals=DATA.signals||[];
      $("signal-row").innerHTML=signals.map(function(s){
        var cls=s.trend==="↑"?" up":s.trend==="↓"?" down":"";
        return "<span class='signal"+cls+"'>"+esc(s.label||"")+(s.trend?" "+esc(s.trend):"")+"</span>";
      }).join("");
    }else{
      var seen={};
      signals=activeItems().map(function(it){return it.topic||it.category||"要闻";})
        .filter(function(x){if(seen[x])return false;seen[x]=1;return true;}).slice(0,6);
      $("signal-row").innerHTML=signals.map(function(label){
        return "<span class='signal'>"+esc(label)+"</span>";
      }).join("");
    }
  }

  function rdHtml(it){
    return "<a class='rd-item' href='"+esc(it.link||"#")+"' target='_blank' rel='noopener'>"+
      "<span class='rd-dot'></span><span><div class='rd-title'><b>"+esc(it.topic||it.category||"要闻")+"</b>"+
      esc(it.brief||it.title||"")+"</div><div class='rd-meta'>"+esc(it.source||"来源未知")+
      (relTime(it.published)?" · "+esc(relTime(it.published)):"")+" · 阅读原文 →</div></span></a>";
  }
  function renderRundown(){
    var items,name;
    if(active==="all"){items=allItems();name="全部主题";}
    else{var c=catByKey(active);items=(c&&c.items)||[];name=c?c.name:"当前分类";}
    items=items.slice().sort(function(a,b){return Number(b.published||0)-Number(a.published||0);});
    $("rundown-sub").textContent=name+" · "+items.length+" 条";
    $("rundown-list").innerHTML=items.map(rdHtml).join("");
  }

  function renderFooter(){
    var html="数据来源 <b>"+esc(DATA.source||"—")+"</b>";
    if(DATA.sourcePool&&DATA.sourcePool.length)html+="<br>新闻源："+DATA.sourcePool.map(esc).join(" · ");
    if(DATA.note)html+="<br>"+esc(DATA.note);
    $("sources").innerHTML=html;
  }

  function boot(data){
    DATA=data;
    renderHeader();renderTabs();renderGalaxy();renderActiveView();renderFooter();
  }

  fetch("data.json?t="+Date.now())
    .then(function(r){if(!r.ok)throw new Error("HTTP "+r.status);return r.json();})
    .then(boot)
    .catch(function(e){
      $("lead-title").textContent="数据加载失败";
      $("why-box").innerHTML="<b>ERROR</b>"+esc(e.message);
      $("rundown-list").innerHTML="";
    });
})();
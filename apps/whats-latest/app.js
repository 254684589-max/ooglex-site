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

  var SOURCE_ZH={
    "Reuters":"路透社",
    "Bloomberg":"彭博社",
    "Financial Times":"英国《金融时报》",
    "The Wall Street Journal":"《华尔街日报》",
    "BBC":"英国广播公司",
    "CNBC":"美国消费者新闻与商业频道",
    "CNN":"美国有线电视新闻网",
    "NBC News":"美国全国广播公司新闻",
    "CBS News":"美国哥伦比亚广播公司新闻",
    "ABC News":"美国广播公司新闻",
    "The New York Times":"《纽约时报》",
    "The Guardian":"英国《卫报》",
    "South China Morning Post":"《南华早报》",
    "The Hill":"《国会山报》",
    "Fox News":"福克斯新闻",
    "TechCrunch":"科技博客",
    "Semafor":"塞马福新闻",
    "The Japan Times":"《日本时报》",
    "Axios":"阿克西奥斯新闻",
    "WIRED":"《连线》杂志",
    "Euronews":"欧洲新闻台",
    "Associated Press":"美联社",
    "POLITICO":"《政客》",
    "Finextra":"金融科技资讯网",
    "Ooglex rules":"Ooglex 规则"
  };
  var SOURCE_LEVEL={
    "Reuters":"high","Bloomberg":"high","Financial Times":"high","The Wall Street Journal":"high",
    "BBC":"high","Associated Press":"high","The New York Times":"high",
    "CNBC":"medium","CNN":"medium","NBC News":"medium","CBS News":"medium","ABC News":"medium",
    "The Guardian":"medium","Axios":"medium","POLITICO":"medium","Euronews":"medium","The Japan Times":"medium",
    "South China Morning Post":"low","The Hill":"low","Fox News":"low","TechCrunch":"low",
    "Semafor":"low","WIRED":"low","Finextra":"low"
  };
  var SOURCE_LEVEL_META={
    high:{label:"高",order:0,title:"高等级新闻源"},
    medium:{label:"中",order:1,title:"中等级新闻源"},
    low:{label:"低",order:2,title:"低等级新闻源"}
  };
  function sourceZh(src){return SOURCE_ZH[src]||"其他新闻源";}
  function sourceLevel(src){return SOURCE_LEVEL[src]||"low";}
  function sourceLevelMeta(src){return SOURCE_LEVEL_META[sourceLevel(src)];}
  function hasHan(s){return /[\u3400-\u9fff]/.test(String(s||""));}
  function categoryZh(it){
    var map={politics:"政策政治",world:"国际地缘",markets:"市场经济",tech:"人工智能科技",law:"法律监管",risk:"风险"};
    return map[(it&&it.categoryKey)||""]||(it&&hasHan(it.category)?it.category:"新闻");
  }
  function showTitle(it){
    it=it||{};
    if(hasHan(it.titleZh))return it.titleZh;
    if(hasHan(it.briefZh))return it.briefZh;
    if(hasHan(it.title))return it.title;
    if(hasHan(it.brief))return it.brief;
    return categoryZh(it)+"：最新进展";
  }
  function showBrief(it){
    it=it||{};
    if(hasHan(it.briefZh))return it.briefZh;
    if(hasHan(it.brief))return it.brief;
    return showTitle(it);
  }
  function showSource(it){
    it=it||{};
    if(hasHan(it.sourceZh))return it.sourceZh;
    return sourceZh(it.source||"");
  }
  function riskEntitiesZh(title){
    var t=String(title||""),out=[];
    [
      [/\\bU\\.S\\.\\b|\\bUS\\b|United States/i,"美国"],
      [/Ukraine|Kyiv|Zelensky/i,"乌克兰"],
      [/Russia|Moscow|Putin/i,"俄罗斯"],
      [/Iran|Tehran/i,"伊朗"],
      [/Israel|Jerusalem/i,"以色列"],
      [/Sudan/i,"苏丹"],
      [/Saudi|Riyadh/i,"沙特阿拉伯"],
      [/Yemen/i,"也门"],
      [/Syria/i,"叙利亚"],
      [/Lebanon/i,"黎巴嫩"],
      [/NATO/i,"北约"],
      [/United Nations|\\bU\\.N\\.\\b/i,"联合国"]
    ].forEach(function(x){if(x[0].test(t)&&out.indexOf(x[1])<0)out.push(x[1]);});
    return out.slice(0,3);
  }
  function riskEventTypeZh(title,stream){
    var t=String(title||"");
    if(/wheat|grain|food price|agricultur/i.test(t))return "战争延续与粮食成本压力";
    if(/ceasefire|talks|meet|negotiat|peace plan/i.test(t))return "停火与谈判进展";
    if(/missile|drone|attack|strike|explosion|bomb/i.test(t))return "军事打击与安全升级";
    if(/sanction|blockade|visa/i.test(t))return "制裁、限制与外交措施";
    if(/oil|gas|tanker|pipeline|shipping|freight|vessel|LNG/i.test(t))return "能源与运输风险";
    if(/credit|bond|debt|bank|liquidity|default|bankruptcy/i.test(t))return "信用与流动性风险";
    if(/cyber|ransomware|hack|malware|data breach/i.test(t))return "网络攻击与数据安全风险";
    if(/supply chain|shortage|logistics|bottleneck|port disruption/i.test(t))return "供应链与物流中断";
    if(/war|conflict|invasion|military|troops|army/i.test(t))return "战争与军事行动";
    return (stream||"风险事件")+"最新进展";
  }
  function riskImpactZh(stream){
    var map={
      "地缘冲突":"重点观察冲突是否继续升级，以及是否向能源、运输、商品价格和市场风险偏好传导。",
      "市场信用":"重点观察信用利差、融资条件、银行与债券市场是否出现进一步压力。",
      "能源运输":"重点观察供应、航运通道、运价与能源价格是否出现持续扰动。",
      "网络安全":"重点观察关键基础设施、企业系统和数据安全是否受到进一步影响。",
      "供应链":"重点观察物流、交付周期与成本压力是否向更多行业扩散。"
    };
    return map[stream]||"重点观察事件是否升级、扩散，并形成跨市场或跨行业传导。";
  }
  function riskHeadlineZh(it){
    var entities=riskEntitiesZh(it.title||"");
    var type=riskEventTypeZh(it.title||"",it.riskStreamName||it.topic||"");
    return (entities.length?entities.join("、")+"：":"")+type;
  }
  function riskNarrativeZh(it){
    var src=sourceZh(it.source||"");
    var stream=it.riskStreamName||it.topic||"风险";
    var entities=riskEntitiesZh(it.title||"");
    var type=riskEventTypeZh(it.title||"",stream);
    var first=src+"报道显示，"+(entities.length?entities.join("、")+"相关的":"")+type+"成为当前风险监测重点。";
    var second="该消息已归入“"+stream+"”风险流。"+riskImpactZh(stream);
    return first+" "+second;
  }
  function renderRiskSourceLevels(items){
    var box=$("risk-source-levels"); if(!box)return;
    var groups={high:[],medium:[],low:[]},seen={};
    (items||[]).forEach(function(it){
      var src=it.source||"";
      if(!src||seen[src])return;
      seen[src]=1;
      groups[sourceLevel(src)].push(sourceZh(src));
    });
    box.innerHTML=["high","medium","low"].map(function(k){
      var meta=SOURCE_LEVEL_META[k],arr=groups[k];
      return "<div class='risk-source-tier'><div class='risk-source-tier-head'><span class='risk-source-tier-name'>"+
        meta.title+"</span><span class='risk-source-badge "+k+"'>"+meta.label+"</span></div>"+
        "<div class='risk-source-tier-list'>"+esc(arr.length?arr.join(" · "):"当前无样本")+"</div></div>";
    }).join("");
  }

  function setRiskMode(on){
    var ids=["cover"];
    ids.forEach(function(id){var el=$(id);if(el)el.style.display=on?"none":"";});
    var galaxy=document.querySelector(".galaxy");
    var main=document.querySelector(".main-grid");
    if(galaxy)galaxy.style.display=on?"none":"";
    if(main)main.style.display=on?"none":"";
    var desk=$("risk-desk");
    if(desk)desk.classList.toggle("show",!!on);
  }

  function riskClass(level){
    if(level==="数据不足")return "insufficient";
    if(level==="高")return "high";
    if(level==="中高")return "medium-high";
    if(level==="中")return "medium";
    return "low";
  }

  function renderRiskDesk(){
    var a=DATA.riskAnalysis||{};
    var riskCat=catByKey("risk")||{items:[]};
    var items=(riskCat.items||[]).slice().sort(function(x,y){
      var ax=sourceLevelMeta(x.source||"").order, ay=sourceLevelMeta(y.source||"").order;
      if(ax!==ay)return ax-ay;
      return Number(y.published||0)-Number(x.published||0);
    });
    var lead=items[0]||a.lead||{};
    var level=a.level||"数据不足";
    var status=a.status||"等待样本";
    var cov=a.coverage||{};
    var reliable=!!a.reliable;
    $("risk-meta").innerHTML=
      "<span class='risk-level "+riskClass(level)+"'><span class='dot'></span>风险等级："+esc(level)+"</span>"+
      "<span>威胁状态："+esc(status)+"</span>"+
      "<span>监测事件："+esc(cov.sampleCount!=null?cov.sampleCount:items.length)+" 条</span>"+
      "<span>新闻源："+esc(cov.sourceCount!=null?cov.sourceCount:"—")+" 家</span>"+
      "<span>风险流："+esc(cov.streamCount!=null?cov.streamCount:"—")+" / 5</span>"+
      "<span>"+esc(DATA.asOf||"")+"</span>"+
      "<div class='risk-quality'>"+
        "<span class='"+(reliable?"ok":"warn")+"'>"+(reliable?"样本门槛已满足":"样本门槛未满足")+"</span>"+
        "<span>要求 ≥ "+esc(cov.minItems||8)+" 条</span>"+
        "<span>≥ "+esc(cov.minSources||3)+" 家媒体</span>"+
        "<span>≥ "+esc(cov.minStreams||3)+" 个风险流</span>"+
      "</div>";

    var leadMeta=sourceLevelMeta(lead.source||"");
    $("risk-focus").innerHTML=
      "<div class='risk-kicker'>当前焦点</div>"+
      "<h3>"+esc(riskHeadlineZh(lead)||"暂无核心风险事件")+"</h3>"+
      "<div class='risk-event-meta'><span class='risk-source-badge "+sourceLevel(lead.source||"")+"'>"+leadMeta.label+"</span>"+
      "<span>新闻源："+esc(sourceZh(lead.source||""))+"</span>"+
      (relTime(lead.published)?"<span>· "+esc(relTime(lead.published))+"</span>":"")+"</div>"+
      "<p>"+esc(riskNarrativeZh(lead))+"</p>"+
      "<div class='risk-why'><b>影响研判</b>"+esc(lead.why||a.why||riskImpactZh(lead.riskStreamName||lead.topic||""))+"</div>";

    var grouped={high:[],medium:[],low:[]};
    items.slice(0,12).forEach(function(it){grouped[sourceLevel(it.source||"")].push(it);});
    $("risk-events").innerHTML=["high","medium","low"].map(function(k){
      if(!grouped[k].length)return "";
      var meta=SOURCE_LEVEL_META[k];
      return "<div class='risk-level-group'><div class='risk-level-group-title'><span class='risk-source-badge "+k+"'>"+meta.label+"</span><span>"+meta.title+"</span></div>"+
        grouped[k].map(function(it){
          return "<a class='risk-event' href='"+esc(it.link||"#")+"' target='_blank' rel='noopener'>"+
            "<span class='bullet'></span><span>"+
            "<div class='risk-event-meta'><span class='risk-source-badge "+k+"'>"+meta.label+"</span><span>新闻源："+esc(sourceZh(it.source||""))+"</span>"+
            (relTime(it.published)?"<span>· "+esc(relTime(it.published))+"</span>":"")+"<span>· 查看原文 →</span></div>"+
            "<div class='risk-event-title'>"+esc(riskHeadlineZh(it))+"</div>"+
            "<div class='risk-event-copy'>"+esc(riskNarrativeZh(it))+"</div>"+
            "</span></a>";
        }).join("")+"</div>";
    }).join("")||"<div class='risk-note'>当前没有新的风险事件。</div>";

    var follow=a.followUp||[];
    if(!follow.length)follow=items.slice(0,3);
    $("risk-followup").innerHTML=follow.map(function(it){
      return "<div class='risk-event'><span class='bullet'></span><span><div class='risk-event-title'>"+
        esc(it.text||riskHeadlineZh(it)||"持续监测")+"</div>"+
        (it.source?"<div class='risk-event-meta'>新闻源："+esc(sourceZh(it.source))+"</div>":"")+"</span></div>";
    }).join("");

    renderRiskSourceLevels(items);

    var dims=(a.dimensions||[]).slice().sort(function(x,y){return Number(y.score||0)-Number(x.score||0);});
    $("risk-dimensions").innerHTML=dims.map(function(d){
      var pct=Math.max(8,Math.min(100,Number(d.score||0)));
      return "<div class='risk-dimension'><div class='risk-dimension-row'><span class='risk-dimension-name'>"+esc(d.name||"风险")+
        "</span><span class='risk-dimension-state'>"+esc(d.state||"观察")+"</span></div>"+
        "<div class='risk-dimension-bar'><span style='width:"+pct+"%'></span></div></div>";
    }).join("");
  }

  function renderActiveView(){
    var riskMode=active==="risk";
    setRiskMode(riskMode);
    if(riskMode){
      renderRiskDesk();
      renderRundown();
      return;
    }
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
    $("edition-date").textContent=(DATA.asOf||"—")+" · 最新";
    var upd=DATA.updatedAt?new Date(DATA.updatedAt):null;
    if(upd&&!isNaN(upd.getTime())){
      var mins=Math.max(0,Math.round((Date.now()-upd.getTime())/60000));
      $("freshness").textContent=mins<60?"更新于 "+Math.max(1,mins)+" 分钟前":"更新于 "+Math.floor(mins/60)+" 小时前";
    }else $("freshness").textContent="自动更新";
  }

  function renderTabs(){
    var box=$("category-tabs");
    var defs=[{key:"all",name:"概览"}].concat((DATA.categories||[]).map(function(c){
      var map={politics:"政策",world:"国际",markets:"市场",tech:"人工智能",law:"监管",risk:"风险"};
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
    $("hero-title").textContent=showBrief(h)||"今日全球新闻简报";
    var activeCat=active==="all"?(h.category||"概览"):((catByKey(active)||{}).name||h.category||"");
    $("hero-meta").textContent=[showSource(h),DATA.asOf||"",activeCat].filter(Boolean).join(" · ");
    $("lead-title").textContent=showTitle(h)||"今日主线";
    $("why-box").innerHTML="<b>影响解读</b>"+esc(h.whyZh||h.why||"这条信息是当前简报中的核心主线，值得进一步核实原文与后续发展。");
    $("lead-source").innerHTML=esc(showSource(h)||"来源未知")+(relTime(h.published)?" · "+esc(relTime(h.published)):"")+
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
    box.innerHTML="<span class='trend-label'>今日热点</span>"+items.map(function(x){
      return "<span class='trend-chip"+(x.hot?" hot":"")+"'>"+esc(x.label)+"</span>";
    }).join("");
  }

  function renderGalaxy(){
    var cols=["#9d6bd8","#e06167","#67ca83","#d96ea8","#ca69d7","#63c7a3","#c765da","#5f9fda"];
    var cats=DATA.categories||[];
    $("galaxy-bars").innerHTML=(cats.length?cats:[{},{},{},{},{}]).map(function(c,i){
      var n=(c.items||[]).length||1;
      return "<span title='"+esc(c.name||"新闻分组")+"' style='background:"+cols[i%cols.length]+";flex:"+Math.max(1,n)+"'></span>";
    }).join("");
  }

  function wireHtml(it){
    return "<a class='wire' href='"+esc(it.link||"#")+"' target='_blank' rel='noopener'>"+
      "<div class='wire-topic'>"+esc(hasHan(it.topic)?it.topic:categoryZh(it))+"</div>"+
      "<div class='wire-title'>"+esc(showBrief(it))+"</div>"+
      "<div class='wire-meta'>"+esc(showSource(it)||"来源未知")+(relTime(it.published)?" · "+esc(relTime(it.published)):"")+"</div></a>";
  }
  function renderWires(){
    var list=active==="all"?(DATA.wires||[]).slice(0,6):activeItems().slice(1,7);
    if(!list.length&&active!=="all")list=activeItems().slice(0,6);
    $("wire-list").innerHTML=list.map(wireHtml).join("");
  }

  function cardHtml(it){
    return "<a class='brief-card' href='"+esc(it.link||"#")+"' target='_blank' rel='noopener'>"+
      "<div class='c-topic'>"+esc(hasHan(it.topic)?it.topic:categoryZh(it))+"</div>"+
      "<div class='c-title'>"+esc(showBrief(it))+"</div>"+
      "<div class='c-meta'>"+esc(showSource(it)||"来源未知")+(relTime(it.published)?" · "+esc(relTime(it.published)):"")+"</div></a>";
  }
  function renderCards(){
    var items=active==="all"?(DATA.alsoNoted||[]).concat((DATA.watch||[])).slice(0,6):
      ((catByKey(active)||{}).items||[]).slice(0,6);
    if(!items.length)items=allItems().slice(0,6);
    $("brief-cards").innerHTML=items.map(cardHtml).join("");
  }

  function railItem(it){
    return "<a class='rail-item' href='"+esc(it.link||"#")+"' target='_blank' rel='noopener'>"+
      "<div class='ri-topic'>"+esc(hasHan(it.topic)?it.topic:categoryZh(it))+"</div>"+
      "<div class='ri-title'>"+esc(showBrief(it))+"</div>"+
      "<div class='ri-meta'>"+esc(showSource(it)||"来源未知")+(relTime(it.published)?" · "+esc(relTime(it.published)):"")+"</div></a>";
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
      "<span class='rd-dot'></span><span><div class='rd-title'><b>"+esc(hasHan(it.topic)?it.topic:categoryZh(it))+"</b>"+
      esc(showBrief(it))+"</div><div class='rd-meta'>"+esc(showSource(it)||"来源未知")+
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
    var html="数据来源 <b>谷歌新闻聚合 · 雅虎财经</b>";
    if(DATA.sourcePool&&DATA.sourcePool.length)html+="<br>新闻源："+DATA.sourcePool.map(function(x){return esc(sourceZh(x));}).join(" · ");
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
      $("why-box").innerHTML="<b>加载错误</b>"+esc(e.message);
      $("rundown-list").innerHTML="";
    });
})();
/* 投研日看板：只渲染同目录 data.json。外部文字一律 textContent。
   Brief 芯片取 brief.header 开头的 Brief-NN，不写死期号。
   雷达正式入选只看 items；archive 是二级存档，不计入 N。
   芯片「雷达 N」在 radar.selected 为数字时用该值。 */
(function () {
  "use strict";

  var ALLOWED = {
    "https://www.ooglex.com/apps/news-brief/": true,
    "https://www.ooglex.com/apps/news-radar/": true
  };
  var STATUS = { ok: "正常", partial: "部分缺失", stale: "已过期", error: "失败" };
  var FREQUENCY = {
    realtime: "实时",
    delayed: "延迟",
    daily: "日频",
    weekly: "周频",
    monthly: "月频",
    quarterly: "季频",
    annual: "年频"
  };

  var dateline = document.getElementById("dateline");
  var edition = document.getElementById("edition");
  var board = document.getElementById("board");
  var banner = document.getElementById("banner");
  var foot = document.getElementById("foot-meta");

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function clear(node) {
    while (node && node.firstChild) node.removeChild(node.firstChild);
  }

  function text(value) {
    return typeof value === "string" ? value.trim() : "";
  }

  function allowedLink(url) {
    return ALLOWED[text(url)] ? text(url) : "";
  }

  function addChip(label, value) {
    var chip = el("span", "chip");
    chip.appendChild(el("strong", "", label));
    chip.appendChild(document.createTextNode(" " + value));
    edition.appendChild(chip);
  }

  function linkEl(href, label) {
    var safe = allowedLink(href);
    if (!safe) return el("span", "", text(label) || "链接未提供");
    var a = document.createElement("a");
    a.href = safe;
    a.textContent = text(label) || safe;
    return a;
  }

  function showFailure(message) {
    clear(board);
    clear(edition);
    dateline.textContent = "来源与更新时间暂时不可用";
    if (banner) banner.textContent = "投研汇总暂时无法加载 · 非正式产品";
    board.appendChild(el("p", "banner error", message));
    foot.textContent = "研究用／非投资建议";
  }

  function section(id, heading) {
    var sec = el("section", "block");
    sec.id = id;
    sec.appendChild(el("h2", "", heading || "（未提供标题）"));
    return sec;
  }

  function briefToken(header) {
    var match = text(header).match(/^Brief-\d+/);
    return match ? match[0] : "";
  }

  function briefRadarSynced(data) {
    var asOf = text(data.asOf);
    var header = text(data.brief && data.brief.header);
    if (!asOf || !briefToken(header) || header.indexOf(asOf) === -1) return false;
    var marker = text(data.note) + "\n" + text(data.source);
    if (marker.indexOf("已同步") === -1 && marker.indexOf("早更同步") === -1) return false;
    var radar = data.radar;
    return !!radar && (typeof radar.selected === "number" || Array.isArray(radar.items));
  }

  function renderBrief(data) {
    var brief = data.brief || {};
    var token = briefToken(brief.header);
    var fallback = token ? ("区块 A · Brief 最新（" + token + "）") : "区块 A · Brief 最新";
    var sec = section("brief", text(brief.heading) || fallback);
    sec.appendChild(el("p", "block-kicker", text(brief.header) || "（表头未提供）"));
    var items = Array.isArray(brief.items) ? brief.items : [];
    if (!items.length) {
      sec.appendChild(el("p", "empty-title", "本期简报标题未提供。"));
      return sec;
    }
    var list = document.createElement("ol");
    list.className = "title-list";
    items.forEach(function (item) {
      var li = document.createElement("li");
      var title = text(item);
      if (!title) {
        li.textContent = "（空标题）";
      } else {
        li.appendChild(linkEl(brief.link, title));
      }
      list.appendChild(li);
    });
    sec.appendChild(list);
    var more = el("p", "more");
    more.appendChild(linkEl(brief.link, text(brief.linkLabel) || "打开全球新闻扫描简报概览"));
    sec.appendChild(more);
    return sec;
  }

  function renderRadar(data) {
    var radar = data.radar || {};
    var sec = section("radar", text(radar.heading) || "区块 B · 雷达最新（Day-05）");
    (Array.isArray(radar.lines) ? radar.lines : []).forEach(function (line) {
      if (text(line)) sec.appendChild(el("p", "fact", text(line)));
    });

    var formal = Array.isArray(radar.items) ? radar.items.filter(function (item) {
      return text(item);
    }) : [];
    var declared = typeof radar.selected === "number" ? radar.selected : formal.length;
    var shown = formal.length;

    var hero = el("div", "count-hero");
    hero.appendChild(el("p", "count-kicker", "正式入选"));
    hero.appendChild(el("p", "count-num", String(shown)));
    hero.appendChild(el("p", "count-caption", shown === 0
      ? (text(radar.empty) || "合格空报 · 正式入选 0")
      : ("正式入选 " + shown + " 条")));
    sec.appendChild(hero);

    if (!shown) {
      var empty = el("div", "empty-panel");
      empty.appendChild(el("p", "empty-title", text(radar.empty) || "合格空报 · 正式入选 0"));
      sec.appendChild(empty);
    } else {
      var list = document.createElement("ol");
      list.className = "title-list";
      formal.forEach(function (item) {
        var li = document.createElement("li");
        li.textContent = text(item);
        list.appendChild(li);
      });
      sec.appendChild(list);
    }

    if (declared !== shown) {
      sec.appendChild(el("p", "warn", "文件标注的正式入选 N（" + declared + "）与列出的正式条目（" + shown + "）不一致。页面以列出的条目为准，不把二级存档算进 N。"));
    }

    var archive = Array.isArray(radar.archive) ? radar.archive : [];
    var details = document.createElement("details");
    details.className = "archive";
    var summary = document.createElement("summary");
    summary.textContent = text(radar.archiveLabel) || "二级存档（不计入 N）";
    details.appendChild(summary);
    var body = el("div", "archive-body");
    if (text(radar.archiveNote)) body.appendChild(el("p", "archive-note", text(radar.archiveNote)));
    if (!archive.length) {
      body.appendChild(el("p", "empty-reason", "本轮没有二级存档。"));
    } else {
      var ul = document.createElement("ul");
      ul.className = "archive-list";
      archive.forEach(function (item) {
        ul.appendChild(el("li", "", text(item) || "（空条目）"));
      });
      body.appendChild(ul);
    }
    details.appendChild(body);
    sec.appendChild(details);

    var more = el("p", "more");
    more.appendChild(linkEl(radar.link, text(radar.linkLabel) || "打开雷达专区"));
    sec.appendChild(more);
    return sec;
  }

  function renderWsj(data) {
    var wsj = data.wsj || {};
    var sec = section("wsj", text(wsj.heading) || "区块 C · WSJ 日更一页");
    sec.appendChild(el("p", "block-kicker", text(wsj.title) || "（标题未提供）"));
    if (text(wsj.boundary)) sec.appendChild(el("p", "boundary", text(wsj.boundary)));
    sec.appendChild(el("h3", "", text(wsj.conclusionsHeading) || "核心结论（≤6）"));
    var conclusions = Array.isArray(wsj.conclusions) ? wsj.conclusions : [];
    if (!conclusions.length) {
      sec.appendChild(el("p", "empty-reason", "核心结论未提供。"));
    } else {
      var ol = document.createElement("ol");
      ol.className = "prose-list";
      conclusions.forEach(function (line) {
        ol.appendChild(el("li", "", text(line) || "（空行）"));
      });
      sec.appendChild(ol);
    }
    sec.appendChild(el("h3", "", text(wsj.flagsHeading) || "监测红旗（演示）"));
    var flags = Array.isArray(wsj.flags) ? wsj.flags : [];
    if (!flags.length) {
      sec.appendChild(el("p", "empty-reason", "监测红旗未提供。"));
    } else {
      var ul = document.createElement("ul");
      ul.className = "prose-list";
      flags.forEach(function (line) {
        ul.appendChild(el("li", "", text(line) || "（空行）"));
      });
      sec.appendChild(ul);
    }
    return sec;
  }

  function renderS2(data) {
    var s2 = data.s2 || {};
    var sec = section("s2", text(s2.heading) || "区块 D · S2 待办列表");
    var columns = Array.isArray(s2.columns) ? s2.columns : [];
    var rows = Array.isArray(s2.rows) ? s2.rows : [];
    if (!columns.length || !rows.length) {
      sec.appendChild(el("p", "empty-title", "S2 待办表未提供。"));
    } else {
      var wrap = el("div", "table-wrap");
      var table = document.createElement("table");
      var caption = document.createElement("caption");
      caption.textContent = "S2 待办列表";
      table.appendChild(caption);
      var thead = document.createElement("thead");
      var headRow = document.createElement("tr");
      columns.forEach(function (column) {
        var th = document.createElement("th");
        th.scope = "col";
        th.textContent = column == null ? "" : String(column);
        headRow.appendChild(th);
      });
      thead.appendChild(headRow);
      table.appendChild(thead);
      var tbody = document.createElement("tbody");
      rows.forEach(function (row) {
        var tr = document.createElement("tr");
        var cells = Array.isArray(row) ? row : [];
        columns.forEach(function (column, index) {
          var td = document.createElement("td");
          td.setAttribute("data-label", column == null ? "" : String(column));
          var value = cells[index];
          td.textContent = value == null || value === "" ? "—" : String(value);
          tr.appendChild(td);
        });
        tbody.appendChild(tr);
      });
      table.appendChild(tbody);
      wrap.appendChild(table);
      sec.appendChild(wrap);
    }
    if (text(s2.note)) sec.appendChild(el("p", "note", text(s2.note)));
    return sec;
  }

  function render(data) {
    if (!data || typeof data !== "object" || !data.brief || !data.radar || !data.wsj || !data.s2) {
      showFailure("演示包格式不完整，已停止展示，避免用空表冒充本期内容。");
      return;
    }

    var zone = text(data.asOfZone);
    var zoneSuffix = zone ? " " + zone : "";
    dateline.textContent = "来源：" + (text(data.source) || "未标注")
      + " · 数据日期：" + (text(data.asOf) || "未标注") + zoneSuffix
      + " · 更新时间：" + (text(data.updatedAt) || "未标注") + zoneSuffix + "（未提供钟点）"
      + " · 频率：" + (FREQUENCY[data.frequency] || text(data.frequency) || "未标注")
      + " · 状态：" + (STATUS[text(data.status)] || text(data.status) || "未标注")
      + " · 演示数据";

    clear(edition);
    var synced = briefRadarSynced(data);
    addChip("编号", "投研汇总");
    addChip(synced ? "同步" : "演示", synced ? "Brief/雷达已同步" : "是");
    var token = briefToken(data.brief && data.brief.header);
    if (token) addChip("Brief", token);
    var selected = data.radar && data.radar.selected;
    var radarCount = typeof selected === "number"
      ? selected
      : (Array.isArray(data.radar.items) ? data.radar.items.length : "—");
    addChip("雷达 N", String(radarCount));

    clear(board);
    board.appendChild(renderBrief(data));
    board.appendChild(renderRadar(data));
    board.appendChild(renderWsj(data));
    board.appendChild(renderS2(data));

    if (text(data.note)) board.appendChild(el("p", "note pack-note", text(data.note)));

    var messages = [];
    if (data.demo !== true) messages.push("数据文件未标记为演示数据。");
    if (text(data.status) === "error") messages.push("来源状态为失败。");
    else if (text(data.status) === "stale") messages.push("这份演示包已过期。");
    else if (text(data.status) === "partial") messages.push("数据状态为部分缺失。");
    if (messages.length) {
      var warn = el("p", "banner partial", messages.join(" "));
      board.insertBefore(warn, board.firstChild);
    }

    banner.textContent = synced
      ? "投研汇总 · Brief/雷达已同步当日 · WSJ/S2 仍为演示 · 非正式产品"
      : "临时演示 · 非正式产品";

    clear(foot);
    var lines = Array.isArray(data.footer) && data.footer.length
      ? data.footer
      : ["研究用／非投资建议"];
    lines.forEach(function (line) {
      if (text(line)) foot.appendChild(el("p", "", text(line)));
    });
  }

  fetch("data.json", { cache: "no-store" })
    .then(function (response) {
      if (!response.ok) throw new Error("status " + response.status);
      return response.json();
    })
    .then(render)
    .catch(function () {
      showFailure("投研日看板暂时无法加载。请稍后重试。简报与雷达仍可从下方公开对照打开。");
    });
})();

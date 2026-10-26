/* 全球投资情报雷达专区：只渲染同目录 data.json。外部文字一律 textContent。
   硬规则：archive ≠ 正式入选。
   正式入选条数只数 items 里的非二级条目。
   archive、funnel.tier2、scanOverview 不得并入 items，也不得加进「正式入选」数字。 */
(function () {
  "use strict";

  var dateline = document.getElementById("dateline");
  var edition = document.getElementById("edition");
  var lead = document.getElementById("lead");
  var note = document.getElementById("note");
  var banner = document.getElementById("banner");
  var countNum = document.getElementById("count-num");
  var countCaption = document.getElementById("count-caption");
  var emptyPanel = document.getElementById("empty-panel");
  var itemsRoot = document.getElementById("items");
  var scanSection = document.getElementById("scan");
  var scanTitle = document.getElementById("scan-title");
  var scanWindow = document.getElementById("scan-window");
  var scanKind = document.getElementById("scan-kind");
  var funnelList = document.getElementById("funnel");
  var scanAside = document.getElementById("scan-aside");
  var coverageWrap = document.getElementById("coverage");
  var coverageTitle = document.getElementById("coverage-title");
  var coverageList = document.getElementById("coverage-list");
  var coverageNote = document.getElementById("coverage-note");
  var scanPaths = document.getElementById("scan-paths");
  var archiveSection = document.getElementById("archive");
  var archiveHeading = document.getElementById("archive-heading");
  var archiveNote = document.getElementById("archive-note");
  var archiveList = document.getElementById("archive-list");
  var footMeta = document.getElementById("foot-meta");

  var NOT_COUNTED = "非正式入选 · 不计入正式入选 · 不计入终极结果";
  var FUNNEL_FIELDS = [
    { key: "scans", label: "L0 扫描触及", approx: true },
    { key: "independent", label: "L1 去重后候选" },
    { key: "tier1", label: "一级（例行／无增量）" },
    { key: "tier2", label: "二级存档（不计入正式入选）" },
    { key: "tier3", label: "三级研究" },
    { key: "tier4", label: "四级正式入选（不含二级存档）", formal: true }
  ];

  var STATUS = {
    ok: "正常",
    partial: "部分缺失",
    stale: "已过期",
    error: "失败"
  };
  var FREQUENCY = {
    realtime: "实时",
    delayed: "延迟",
    daily: "日频",
    weekly: "周频",
    monthly: "月频",
    quarterly: "季频",
    annual: "年频"
  };

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function clear(node) {
    while (node && node.firstChild) node.removeChild(node.firstChild);
  }

  function setBanner(kind, text) {
    banner.className = "banner" + (kind ? " " + kind : "");
    banner.textContent = text || "";
    banner.hidden = !text;
  }

  function safeHttps(url) {
    if (typeof url !== "string") return "";
    var value = url.trim();
    if (!/^https:\/\/[^\s<>"']+$/i.test(value)) return "";
    return value;
  }

  function textOrMissing(value) {
    if (typeof value === "string" && value.trim()) return value.trim();
    return "";
  }

  function formatStamp(value, zoneLabel) {
    if (typeof value !== "string" || !value.trim()) return "—";
    var raw = value.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
      var zone = textOrMissing(zoneLabel);
      return raw + (zone ? "（" + zone + "，未提供钟点）" : "（未提供钟点）");
    }
    var date = new Date(raw);
    if (isNaN(date.getTime())) return raw;
    var pad = function (n) { return (n < 10 ? "0" : "") + n; };
    if (raw.indexOf("+08:00") !== -1 || raw.indexOf("+0800") !== -1) {
      var match = raw.match(/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/);
      if (match) return match[1] + " " + match[2] + "（UTC+8）";
    }
    if (/Z$/i.test(raw)) {
      return date.getUTCFullYear() + "-" + pad(date.getUTCMonth() + 1) + "-" + pad(date.getUTCDate())
        + " " + pad(date.getUTCHours()) + ":" + pad(date.getUTCMinutes()) + " UTC";
    }
    return raw;
  }

  function addChip(label, value) {
    var chip = el("span", "chip");
    chip.appendChild(el("strong", "", label));
    chip.appendChild(document.createTextNode(" " + value));
    edition.appendChild(chip);
  }

  function countText(value) {
    if (typeof value === "number" && isFinite(value)) return String(value);
    var text = textOrMissing(value);
    return text || "未标注";
  }

  function isSecondaryTier(item) {
    var tier = textOrMissing(item && item.tier);
    return tier.indexOf("二级") !== -1 || (item && item.formal === false);
  }

  function showFailure(message) {
    lead.textContent = "本轮雷达没有载入。";
    note.textContent = "";
    countNum.textContent = "—";
    countCaption.textContent = "正式入选条数未知";
    emptyPanel.hidden = true;
    clear(emptyPanel);
    clear(edition);
    clear(itemsRoot);
    clear(funnelList);
    clear(coverageList);
    clear(archiveList);
    scanSection.hidden = true;
    archiveSection.hidden = true;
    dateline.textContent = "来源与更新时间暂时不可用";
    setBanner("error", message);
    footMeta.textContent = "";
  }

  function renderSources(sources) {
    var section = el("div", "sources");
    if (!Array.isArray(sources) || !sources.length) return section;
    var heading = el("p", "source-label", "可核查来源");
    section.appendChild(heading);
    var list = document.createElement("ul");
    sources.forEach(function (source) {
      var item = document.createElement("li");
      var label = source && textOrMissing(source.label);
      var href = safeHttps(source && source.url);
      if (href) {
        var link = document.createElement("a");
        link.href = href;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.textContent = label || href;
        item.appendChild(link);
      } else {
        item.textContent = label || "（来源未提供可打开链接）";
      }
      list.appendChild(item);
    });
    section.appendChild(list);
    return section;
  }

  function renderFormalItem(item, index) {
    var article = el("article", "item");
    article.id = "item-" + (textOrMissing(item.id) || String(index + 1));
    var kicker = el("p", "item-kicker");
    kicker.appendChild(el("span", "", textOrMissing(item.id) || String(index + 1)));
    var tier = textOrMissing(item.tier);
    if (tier) {
      kicker.appendChild(el("span", "", " · "));
      kicker.appendChild(el("span", "badge formal", tier));
    }
    article.appendChild(kicker);
    article.appendChild(el("h2", "item-title", textOrMissing(item.title) || "（无标题）"));
    var summary = textOrMissing(item.summary);
    if (summary) article.appendChild(el("p", "item-summary", summary));
    if (item.sources) article.appendChild(renderSources(item.sources));
    return article;
  }

  function coverageName(entry) {
    if (typeof entry === "string") return textOrMissing(entry);
    if (entry && typeof entry === "object") return textOrMissing(entry.name) || textOrMissing(entry.label);
    return "";
  }

  function setOptionalText(node, value) {
    var text = textOrMissing(value);
    node.textContent = text;
    node.hidden = !text;
    return text;
  }

  function renderFunnel(funnel, approxScans) {
    clear(funnelList);
    if (!funnel || typeof funnel !== "object") {
      funnelList.hidden = true;
      return 0;
    }
    var shown = 0;
    FUNNEL_FIELDS.forEach(function (field) {
      if (!Object.prototype.hasOwnProperty.call(funnel, field.key)) return;
      var value = funnel[field.key];
      var numText = "";
      if (typeof value === "number" && isFinite(value)) {
        numText = (field.approx && approxScans) ? ("约 " + value) : String(value);
      } else {
        numText = textOrMissing(value);
      }
      if (!numText) return;
      var li = document.createElement("li");
      if (field.formal) li.className = "is-formal";
      li.appendChild(el("span", "funnel-num", numText));
      li.appendChild(el("span", "funnel-label", field.label));
      funnelList.appendChild(li);
      shown += 1;
    });
    funnelList.hidden = shown === 0;
    return shown;
  }

  function renderScan(data) {
    var overview = data.scanOverview && typeof data.scanOverview === "object" ? data.scanOverview : {};
    var funnelCount = renderFunnel(data.funnel, overview.scansApprox === true);
    scanTitle.textContent = textOrMissing(overview.title) || "本轮扫描／漏斗概览";
    var windowText = setOptionalText(scanWindow, overview.window);
    var kindText = setOptionalText(scanKind, overview.kind);
    var pathsText = setOptionalText(scanPaths, overview.pathsNote);

    var asideBits = [];
    var funnel = data.funnel && typeof data.funnel === "object" ? data.funnel : null;
    if (funnel && typeof funnel.duplicates === "number" && isFinite(funnel.duplicates)) {
      asideBits.push("去重 " + funnel.duplicates);
    }
    if (funnel && typeof funnel.notPublished === "number" && isFinite(funnel.notPublished)) {
      asideBits.push("未发布 " + funnel.notPublished);
    }
    scanAside.textContent = asideBits.length
      ? ("记录中的剔除：" + asideBits.join("，") + "。这两项不是入选，也不计入正式入选。")
      : "";
    scanAside.hidden = !asideBits.length;

    clear(coverageList);
    var names = [];
    var coverage = Array.isArray(overview.coverage) ? overview.coverage : [];
    coverage.forEach(function (entry) {
      var name = coverageName(entry);
      if (name) names.push(name);
    });
    names.forEach(function (name) {
      coverageList.appendChild(el("li", "", name));
    });
    coverageTitle.textContent = textOrMissing(overview.coverageHeading) || "本轮已扫描领域";
    var coverageNoteText = textOrMissing(overview.coverageNote);
    coverageNote.textContent = coverageNoteText;
    coverageNote.hidden = !coverageNoteText;
    coverageWrap.hidden = names.length === 0;

    var visible = funnelCount > 0 || !!windowText || !!kindText || !!pathsText || names.length > 0;
    scanSection.hidden = !visible;
  }

  function renderArchiveItem(item, index) {
    var li = document.createElement("li");
    var id = textOrMissing(item && item.id);
    li.id = "archive-" + (id || String(index + 1));
    var kickerBits = [];
    if (id) kickerBits.push(id);
    kickerBits.push(textOrMissing(item && item.tier) || "二级");
    kickerBits.push("非正式入选");
    li.appendChild(el("p", "archive-kicker", kickerBits.join(" · ")));
    li.appendChild(el("p", "archive-title", textOrMissing(item && item.title) || "（无标题）"));
    li.appendChild(el("p", "archive-flag", NOT_COUNTED));
    var why = textOrMissing(item && item.whyNot) || textOrMissing(item && item.reason);
    if (why) {
      var whyNode = el("p", "archive-why");
      whyNode.appendChild(el("span", "archive-why-label", "未升级原因："));
      whyNode.appendChild(document.createTextNode(why));
      li.appendChild(whyNode);
    }
    return li;
  }

  function render(data) {
    if (!data || typeof data !== "object" || !Array.isArray(data.items)) {
      showFailure("雷达数据格式不完整，已停止展示，避免把缺字段当成空名单或有条目。");
      return;
    }

    var rawItems = data.items;
    var formal = [];
    var misplaced = 0;
    rawItems.forEach(function (item) {
      if (!item || typeof item !== "object") {
        misplaced += 1;
        return;
      }
      if (isSecondaryTier(item)) misplaced += 1;
      else formal.push(item);
    });

    var archive = Array.isArray(data.archive) ? data.archive : [];
    var listed = formal.length;
    var declared = data.counts && typeof data.counts.selected === "number" ? data.counts.selected : null;
    var status = textOrMissing(data.status) || "未标注";
    var zone = textOrMissing(data.asOfZone);
    dateline.textContent = "来源：" + (textOrMissing(data.source) || "未标注")
      + " · 数据时点：" + formatStamp(data.asOf, zone)
      + " · 更新时间：" + formatStamp(data.updatedAt, zone)
      + " · 频率：" + (FREQUENCY[data.frequency] || data.frequency || "未标注") + " · 人工编辑（非实时）"
      + " · 状态：" + (STATUS[status] || status);

    clear(edition);
    if (data.edition) addChip("期次", data.edition);
    if (data.version) addChip("版本", data.version);
    if (data.runKind) addChip("轮次", data.runKind);
    addChip("正式入选", listed + " 条");
    if (archive.length) addChip("二级存档", archive.length + " 条（不计入）");
    if (data.counts && typeof data.counts === "object") {
      if ("s1" in data.counts) addChip("S1", countText(data.counts.s1));
      if ("s2" in data.counts) addChip("S2", countText(data.counts.s2));
      if ("hardFlags" in data.counts) addChip("硬伤", countText(data.counts.hardFlags));
    }

    lead.textContent = textOrMissing(data.lead) || (listed
      ? "本轮正式入选见下方列表。"
      : "本轮正式入选为 0 条。");
    note.textContent = textOrMissing(data.note);

    /* 正式入选只等于 listed。archive.length 与 funnel 各级不得加进来。 */
    countNum.textContent = String(listed);
    countCaption.textContent = listed === 0
      ? "正式入选 0 条"
      : "正式入选 " + listed + " 条";

    clear(itemsRoot);
    clear(emptyPanel);
    if (!listed) {
      emptyPanel.hidden = false;
      itemsRoot.hidden = true;
      emptyPanel.appendChild(el("p", "empty-title", "正式入选 0 条"));
      emptyPanel.appendChild(el("p", "empty-reason", textOrMissing(data.emptyReason) || "本轮没有可列入正式雷达的条目。"));
    } else {
      emptyPanel.hidden = true;
      itemsRoot.hidden = false;
      formal.forEach(function (item, index) {
        itemsRoot.appendChild(renderFormalItem(item, index));
      });
    }

    renderScan(data);
    clear(archiveList);
    if (!archive.length) {
      archiveSection.hidden = true;
    } else {
      archiveSection.hidden = false;
      archiveHeading.textContent = "二级存档 · " + archive.length + " 条";
      archiveNote.textContent = "以下为本轮筛到、但未达正式入选的二级存档。非正式入选，不计入正式入选，也不计入终极结果。不得并入上方正式名单。未升级原因只说明筛选结论，不是行情判断。";
      archive.forEach(function (item, index) {
        archiveList.appendChild(renderArchiveItem(item, index));
      });
    }

    var messages = [];
    if (data.demo === true) messages.push("模拟数据。此页不是当前真实筛选结果。");
    if (declared !== null && declared !== listed) {
      messages.push("文件标注的正式入选数（" + declared + "）与实际列出的正式条目（" + listed + "）不一致。页面以列出的条目为准。");
    }
    if (misplaced) {
      messages.push("有 " + misplaced + " 条放在正式列表里，但属于二级或未完成条目，已从正式入选中剔除。");
    }
    if (status === "error") messages.push("来源状态为失败。下面仍保留文件中的上一份内容，请勿当作最新成功更新。");
    else if (status === "stale") messages.push("这份雷达已过期。下面仍展示文件中的有效内容，并标明原数据时点。");
    else if (status === "partial") messages.push("数据状态为部分缺失。");

    if (data.demo === true) setBanner("demo", messages.join(" "));
    else if (messages.length) setBanner(declared !== null && declared !== listed ? "partial" : (status === "error" ? "error" : status === "stale" ? "stale" : "partial"), messages.join(" "));
    else if (!listed) setBanner("empty", "正式入选 0 条。" + (textOrMissing(data.emptyReason) || ""));
    else setBanner("", "");

    footMeta.textContent = (data.edition || "雷达")
      + (data.version ? " · " + data.version : "")
      + " · 正式入选 " + listed + " 条"
      + (archive.length ? " · 二级存档 " + archive.length + " 条（不计入正式入选）" : "")
      + " · 来源 " + (textOrMissing(data.source) || "环球新闻情报中心／全球投资情报雷达")
      + " · 更新 " + formatStamp(data.updatedAt, textOrMissing(data.asOfZone));
  }

  fetch("data.json", { cache: "no-store" })
    .then(function (response) {
      if (!response.ok) throw new Error("status " + response.status);
      return response.json();
    })
    .then(render)
    .catch(function () {
      showFailure("雷达专区暂时无法加载。请稍后重试。自动抓取要闻仍可从「最新消息」查看。");
    });
})();

/* 全球投资情报雷达专区：只渲染同目录 data.json。外部文字一律 textContent。
   items 才是正式入选。archive 只是二级存档索引，不得并入正式列表。 */
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
  var archiveDetails = document.getElementById("archive");
  var archiveSummary = document.getElementById("archive-summary");
  var archiveNote = document.getElementById("archive-note");
  var archiveList = document.getElementById("archive-list");
  var footMeta = document.getElementById("foot-meta");

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
    clear(archiveList);
    archiveDetails.hidden = true;
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

  function renderArchiveItem(item, index) {
    var li = document.createElement("li");
    var title = el("span", "archive-title", textOrMissing(item && item.title) || "（无标题）");
    var meta = el("span", "archive-meta", (textOrMissing(item && item.tier) || "二级")
      + " · " + (textOrMissing(item && item.role) || "存档索引／非正式入选"));
    li.appendChild(title);
    li.appendChild(meta);
    if (item && item.id) li.id = "archive-" + String(item.id);
    else li.id = "archive-" + String(index + 1);
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
    if (data.counts && typeof data.counts === "object") {
      if ("s1" in data.counts) addChip("S1", countText(data.counts.s1));
      if ("s2" in data.counts) addChip("S2", countText(data.counts.s2));
      if ("hardFlags" in data.counts) addChip("硬伤", countText(data.counts.hardFlags));
    }

    lead.textContent = textOrMissing(data.lead) || (listed
      ? "本轮正式入选见下方列表。"
      : "本轮正式入选为 0 条。");
    note.textContent = textOrMissing(data.note);

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

    var archive = Array.isArray(data.archive) ? data.archive : [];
    clear(archiveList);
    if (!archive.length) {
      archiveDetails.hidden = true;
    } else {
      archiveDetails.hidden = false;
      archiveSummary.textContent = "二级存档索引 · " + archive.length + " 条（非正式入选，不计入正式入选）";
      archiveNote.textContent = "以下只是存档索引，不是正式雷达条，不计入正式入选条数。本页不展开这些条目的事实、数字或市场影响。";
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

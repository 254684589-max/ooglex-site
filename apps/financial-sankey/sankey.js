/* Pure layout plus a DOM renderer for the statement Sankey. No third-party chart library. */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.OoglexSankey = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  function layoutSankey(statement, width) {
    var nodes = statement.nodes.map(function (node) {
      return {
        id: node.id,
        label: node.label,
        en: node.en || "",
        column: node.column,
        order: node.order || 0,
        value: node.value,
        tone: node.tone || "total",
        concept: node.concept || "",
        formula: node.formula || "",
        signed: node.signed,
        plug: !!node.plug
      };
    });
    var links = statement.links.map(function (link) {
      return { source: link.source, target: link.target, value: link.value };
    });
    var byId = {};
    nodes.forEach(function (node) { byId[node.id] = node; });
    var columns = [];
    nodes.forEach(function (node) {
      if (!columns[node.column]) columns[node.column] = [];
      columns[node.column].push(node);
    });
    var colIndex = [];
    columns.forEach(function (col, index) { if (col) colIndex.push(index); });
    var busiest = 1;
    var fattest = 0;
    colIndex.forEach(function (index) {
      var col = columns[index];
      busiest = Math.max(busiest, col.length);
      var total = col.reduce(function (sum, node) { return sum + node.value; }, 0);
      fattest = Math.max(fattest, total);
    });
    var nodeW = 12;
    var gapY = 16;
    var padT = 18;
    var padB = 12;
    var height = Math.max(520, busiest * 52 + padT + padB + 36);
    var innerH = height - padT - padB;
    var gutter = Math.max(132, Math.min(176, width * 0.17));
    var innerW = Math.max(40, width - gutter * 2 - nodeW);
    var step = colIndex.length <= 1 ? 0 : innerW / (colIndex.length - 1);
    var scale = 0;
    if (fattest > 0) {
      var gapLimit = gapY * Math.max(0, busiest - 1);
      scale = (innerH - gapLimit) / fattest;
      if (scale < 0) scale = innerH / fattest;
    }

    colIndex.forEach(function (index, position) {
      var col = columns[index];
      col.sort(function (a, b) { return a.order - b.order || b.value - a.value; });
      var y = padT;
      var x = gutter + position * step;
      col.forEach(function (node) {
        node.x = x;
        node.y = y;
        node.h = Math.max(node.value * scale, 2);
        node.w = nodeW;
        node.scale = scale;
        y += node.h + gapY;
      });
    });

    var outgoing = {};
    var incoming = {};
    links.forEach(function (link) {
      (outgoing[link.source] || (outgoing[link.source] = [])).push(link);
      (incoming[link.target] || (incoming[link.target] = [])).push(link);
    });
    nodes.forEach(function (node) {
      var outs = outgoing[node.id] || [];
      outs.sort(function (a, b) { return byId[a.target].y - byId[b.target].y; });
      var y = node.y;
      outs.forEach(function (link) {
        link.sy = y;
        link.sh = link.value * node.scale;
        link.x0 = node.x + node.w;
        y += link.sh;
      });
      var ins = incoming[node.id] || [];
      ins.sort(function (a, b) { return byId[a.source].y - byId[b.source].y; });
      y = node.y;
      ins.forEach(function (link) {
        link.ty = y;
        link.th = link.value * node.scale;
        link.x1 = node.x;
        y += link.th;
      });
    });
    links.forEach(function (link) {
      var x0 = link.x0;
      var x1 = link.x1;
      var c = Math.max(24, (x1 - x0) / 2);
      link.path = [
        "M", x0, link.sy,
        "C", x0 + c, link.sy, x1 - c, link.ty, x1, link.ty,
        "L", x1, link.ty + link.th,
        "C", x1 - c, link.ty + link.th, x0 + c, link.sy + link.sh, x0, link.sy + link.sh,
        "Z"
      ].join(" ");
    });

    nodes.forEach(function (node) {
      var last = positionOf(colIndex, node.column) === colIndex.length - 1;
      node.labelAnchor = last ? "end" : "start";
      node.labelX = last ? node.x - 8 : node.x + node.w + 8;
      node.labelY = node.y + Math.max(12, Math.min(node.h / 2, 18));
      node.showLabel = true;
    });
    colIndex.forEach(function (index) {
      var lastY = -999;
      columns[index].forEach(function (node) {
        if (node.labelY < lastY + 30) node.showLabel = false;
        else lastY = node.labelY;
      });
    });

    return { width: width, height: height, nodes: nodes, links: links };
  }

  function positionOf(list, value) {
    return list.indexOf(value);
  }

  function drawSankey(svg, layout, handlers) {
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    svg.setAttribute("viewBox", "0 0 " + layout.width + " " + layout.height);
    svg.setAttribute("width", String(layout.width));
    svg.setAttribute("height", String(layout.height));
    var ns = "http://www.w3.org/2000/svg";

    layout.links.forEach(function (link) {
      var path = document.createElementNS(ns, "path");
      path.setAttribute("d", link.path);
      path.setAttribute("class", "ribbon");
      path.dataset.source = link.source;
      path.dataset.target = link.target;
      svg.appendChild(path);
    });

    layout.nodes.forEach(function (node) {
      var group = document.createElementNS(ns, "g");
      group.setAttribute("class", "node tone-" + node.tone);
      group.setAttribute("tabindex", "0");
      group.setAttribute("role", "button");
      group.setAttribute("aria-label", node.label);
      group.dataset.id = node.id;
      var rect = document.createElementNS(ns, "rect");
      rect.setAttribute("x", node.x);
      rect.setAttribute("y", node.y);
      rect.setAttribute("width", node.w);
      rect.setAttribute("height", node.h);
      rect.setAttribute("rx", "2");
      group.appendChild(rect);
      if (node.showLabel) {
        var text = document.createElementNS(ns, "text");
        text.setAttribute("class", "node-label");
        text.setAttribute("x", node.labelX);
        text.setAttribute("y", node.labelY);
        text.setAttribute("text-anchor", node.labelAnchor);
        text.textContent = node.label;
        group.appendChild(text);
      }
      group.addEventListener("focus", function () { if (handlers && handlers.onSelect) handlers.onSelect(node.id); });
      group.addEventListener("click", function () { if (handlers && handlers.onSelect) handlers.onSelect(node.id); });
      group.addEventListener("pointerenter", function (event) {
        if (event.pointerType === "mouse" && handlers && handlers.onSelect) handlers.onSelect(node.id);
      });
      svg.appendChild(group);
    });
  }

  function highlight(svg, nodeId) {
    svg.classList.add("is-hot");
    svg.querySelectorAll(".ribbon, .node").forEach(function (el) {
      var on = el.dataset.id === nodeId || el.dataset.source === nodeId || el.dataset.target === nodeId;
      el.classList.toggle("is-on", on);
    });
  }

  function clearHighlight(svg) {
    svg.classList.remove("is-hot");
    svg.querySelectorAll(".is-on").forEach(function (el) { el.classList.remove("is-on"); });
  }

  return {
    layoutSankey: layoutSankey,
    drawSankey: drawSankey,
    highlight: highlight,
    clearHighlight: clearHighlight
  };
});

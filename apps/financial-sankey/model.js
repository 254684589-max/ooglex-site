/* US-GAAP companyfacts → three statement Sankey models.
   Same builder for a live SEC payload and for the committed snapshots. */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.OoglexSankeyModel = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var ABSORB = 10000;
  var ANNUAL_FORMS = ["10-K", "10-K/A", "20-F", "20-F/A"];
  var QUARTER_FORMS = ["10-Q", "10-Q/A"];
  var REVENUE_CONCEPTS = [
    "Revenues",
    "RevenueFromContractWithCustomerExcludingAssessedTax",
    "SalesRevenueNet",
    "RevenueFromContractWithCustomerIncludingAssessedTax"
  ];

  function daysBetween(start, end) {
    var a = Date.parse(start + "T00:00:00Z");
    var b = Date.parse(end + "T00:00:00Z");
    if (!isFinite(a) || !isFinite(b)) return NaN;
    return Math.round((b - a) / 86400000);
  }

  function gaap(facts) {
    return (facts && facts.facts && facts.facts["us-gaap"]) || {};
  }

  function usdRows(facts, concept) {
    var node = gaap(facts)[concept];
    if (!node || !node.units || !node.units.USD) return [];
    return node.units.USD;
  }

  function secLabel(facts, concept) {
    var node = gaap(facts)[concept];
    return (node && node.label) || concept;
  }

  function unique(rows, field) {
    var seen = {};
    var out = [];
    rows.forEach(function (row) {
      var key = String(row[field]);
      if (!seen[key]) {
        seen[key] = true;
        out.push(row[field]);
      }
    });
    return out;
  }

  function choose(rows) {
    if (!rows.length) return null;
    var values = unique(rows, "val");
    var row = rows[rows.length - 1];
    if (values.length === 1) {
      return { value: values[0], conflict: false, row: row };
    }
    var framed = rows.filter(function (item) { return item.frame; });
    var framedValues = unique(framed, "val");
    if (framedValues.length === 1) {
      return { value: framedValues[0], conflict: true, row: framed[framed.length - 1] };
    }
    return { value: row.val, conflict: true, row: row };
  }

  function findAnchor(facts, forms, minDays, maxDays) {
    var best = null;
    REVENUE_CONCEPTS.forEach(function (concept) {
      usdRows(facts, concept).forEach(function (row) {
        if (forms.indexOf(row.form) < 0 || !row.start || !row.end) return;
        var span = daysBetween(row.start, row.end);
        if (span < minDays || span > maxDays) return;
        var key = row.end + "|" + (row.filed || "");
        if (!best || key > best.key) best = { key: key, row: row, concept: concept };
      });
    });
    if (!best) return null;
    return {
      forms: forms,
      start: best.row.start,
      end: best.row.end,
      filed: best.row.filed || "",
      fp: best.row.fp || "",
      fy: best.row.fy,
      form: best.row.form,
      concept: best.concept,
      span: daysBetween(best.row.start, best.row.end)
    };
  }

  function lookup(facts, concept, period, instant) {
    var matched = usdRows(facts, concept).filter(function (row) {
      if (period.forms.indexOf(row.form) < 0 || row.end !== period.end) return false;
      if (instant) return !row.start;
      return row.start === period.start;
    });
    if (!matched.length) return null;
    var pool = matched.filter(function (row) { return row.filed === period.filed; });
    if (!pool.length) {
      var latest = matched.map(function (row) { return row.filed || ""; }).sort().pop();
      pool = matched.filter(function (row) { return (row.filed || "") === latest; });
    }
    if (period.fp) {
      var byFp = pool.filter(function (row) { return row.fp === period.fp; });
      if (byFp.length) pool = byFp;
    }
    var chosen = choose(pool);
    if (!chosen || chosen.value == null || !isFinite(chosen.value)) return null;
    return {
      concept: concept,
      en: secLabel(facts, concept),
      value: chosen.value,
      conflict: chosen.conflict,
      filed: chosen.row.filed || period.filed,
      form: chosen.row.form,
      fp: chosen.row.fp || period.fp,
      fy: chosen.row.fy,
      start: chosen.row.start || null,
      end: chosen.row.end
    };
  }

  function makePicker(facts, period) {
    return {
      dur: function (concepts) {
        for (var i = 0; i < concepts.length; i += 1) {
          var hit = lookup(facts, concepts[i], period, false);
          if (hit && hit.value !== 0) return hit;
        }
        return null;
      },
      durKeepZero: function (concepts) {
        for (var i = 0; i < concepts.length; i += 1) {
          var hit = lookup(facts, concepts[i], period, false);
          if (hit) return hit;
        }
        return null;
      },
      instant: function (concepts) {
        for (var i = 0; i < concepts.length; i += 1) {
          var hit = lookup(facts, concepts[i], period, true);
          if (hit && hit.value !== 0) return hit;
        }
        return null;
      },
      instantAny: function (concepts) {
        for (var i = 0; i < concepts.length; i += 1) {
          var hit = lookup(facts, concepts[i], period, true);
          if (hit) return hit;
        }
        return null;
      }
    };
  }

  function emptyStatement(id, title, status, note) {
    return {
      id: id,
      title: title,
      status: status,
      notes: note ? [note] : [],
      nodes: [],
      links: [],
      rows: [],
      period: null
    };
  }

  function row(label, en, concept, value, role, formula) {
    return {
      label: label,
      en: en || "",
      concept: concept || "",
      value: value,
      role: role || "sec",
      formula: formula || ""
    };
  }

  function addLink(links, source, target, value) {
    if (value > ABSORB) links.push({ source: source, target: target, value: value });
  }

  function finalize(nodes, links) {
    var incoming = {};
    var outgoing = {};
    nodes.forEach(function (node) {
      incoming[node.id] = 0;
      outgoing[node.id] = 0;
    });
    links.forEach(function (link) {
      outgoing[link.source] = (outgoing[link.source] || 0) + link.value;
      incoming[link.target] = (incoming[link.target] || 0) + link.value;
    });
    nodes.forEach(function (node) {
      var inn = incoming[node.id] || 0;
      var out = outgoing[node.id] || 0;
      node.value = Math.max(inn, out);
    });
  }

  function absorb(parts, parent) {
    var kept = parts.filter(function (part) { return part.value > ABSORB; });
    var sum = kept.reduce(function (total, part) { return total + part.value; }, 0);
    var plug = parent - sum;
    if (Math.abs(plug) <= ABSORB) {
      if (kept.length) {
        var host = kept.slice().sort(function (a, b) { return b.value - a.value; })[0];
        host.value += plug;
      }
      plug = 0;
    }
    return { parts: kept, plug: plug };
  }

  function buildIncome(facts, period) {
    var pick = makePicker(facts, period);
    var notes = [];
    var rows = [];
    var rev = pick.dur(REVENUE_CONCEPTS);
    if (!rev) {
      return emptyStatement("income", "利润表", "error", "没有找到营业收入科目（Revenues 等），无法绘制利润表。");
    }
    var cogs = pick.dur(["CostOfRevenue", "CostOfGoodsAndServicesSold", "CostOfGoodsSold", "CostOfServices"]);
    var gp = pick.dur(["GrossProfit"]);
    if (!gp && cogs) {
      gp = {
        concept: "",
        en: "Gross profit",
        value: rev.value - cogs.value,
        computed: true
      };
      notes.push("毛利由营业收入减营业成本计算。");
    }
    if (!cogs || !gp || rev.value <= 0 || cogs.value <= 0 || gp.value <= 0) {
      var missing = emptyStatement("income", "利润表", "error", "营业成本或毛利缺失，或毛利不为正。当前版本只绘制常见盈利结构。");
      missing.rows = [row("营业收入", rev.en, rev.concept, rev.value, "sec")];
      if (cogs) missing.rows.push(row("营业成本", cogs.en, cogs.concept, cogs.value, "sec"));
      if (gp) missing.rows.push(row("毛利", gp.en, gp.concept, gp.value, gp.computed ? "plug" : "sec"));
      return missing;
    }

    var rd = pick.dur(["ResearchAndDevelopmentExpense"]);
    var sga = pick.dur(["SellingGeneralAndAdministrativeExpense"]);
    var sm = pick.dur(["SellingAndMarketingExpense"]);
    var ga = pick.dur(["GeneralAndAdministrativeExpense"]);
    var opex = pick.dur(["OperatingExpenses"]);
    var oi = pick.durKeepZero(["OperatingIncomeLoss"]);
    var pretax = pick.durKeepZero([
      "IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest"
    ]);
    var nonop = pick.dur(["NonoperatingIncomeExpense"]);
    var tax = pick.durKeepZero(["IncomeTaxExpenseBenefit"]);
    var ni = pick.durKeepZero(["NetIncomeLoss"]);

    rows.push(row("营业收入", rev.en, rev.concept, rev.value, "sec"));
    rows.push(row("营业成本", cogs.en, cogs.concept, cogs.value, "sec"));
    rows.push(row("毛利", gp.en, gp.concept, gp.value, gp.computed ? "plug" : "subtotal", gp.computed ? "营业收入 − 营业成本" : ""));

    var expenseParts = [];
    if (rd) expenseParts.push({ id: "in_rd", label: "研发费用", en: rd.en, concept: rd.concept, value: rd.value, order: 30 });
    if (sga) {
      expenseParts.push({ id: "in_sga", label: "销售及管理费用", en: sga.en, concept: sga.concept, value: sga.value, order: 40 });
    } else {
      if (sm) expenseParts.push({ id: "in_sm", label: "销售费用", en: sm.en, concept: sm.concept, value: sm.value, order: 40 });
      if (ga) expenseParts.push({ id: "in_ga", label: "管理费用", en: ga.en, concept: ga.concept, value: ga.value, order: 50 });
    }
    if (opex) {
      var named = expenseParts.reduce(function (sum, part) { return sum + part.value; }, 0);
      var otherOpex = opex.value - named;
      if (otherOpex < -ABSORB) {
        notes.push("费用明细与营业费用合计重叠，桑基图改为只画营业费用合计。");
        expenseParts = [{ id: "in_opex", label: "营业费用", en: opex.en, concept: opex.concept, value: opex.value, order: 30 }];
      } else if (otherOpex > ABSORB) {
        expenseParts.push({
          id: "in_opex_plug",
          label: "其他营业费用（轧差）",
          en: "Other operating expenses",
          concept: "",
          value: otherOpex,
          order: 60,
          plug: true,
          formula: "营业费用 − 已列示费用"
        });
      }
      rows.push(row("营业费用", opex.en, opex.concept, opex.value, "subtotal"));
    }
    expenseParts.forEach(function (part) {
      rows.push(row(part.label, part.en, part.concept, part.value, part.plug ? "plug" : "sec", part.formula || ""));
    });

    if (!oi || oi.value <= 0) {
      var loss = emptyStatement("income", "利润表", "error", "没有正的营业利润，当前版本画不出这条利润表桑基图。");
      loss.rows = rows;
      return loss;
    }
    rows.push(row("营业利润", oi.en, oi.concept, oi.value, "subtotal"));

    var splitGp = absorb(expenseParts, gp.value - oi.value);
    if (splitGp.plug < -ABSORB) {
      var broken = emptyStatement("income", "利润表", "error", "毛利盖不住已列示的费用和营业利润，未绘制以免条带宽与金额不符。");
      broken.rows = rows;
      return broken;
    }
    if (splitGp.plug > ABSORB) {
      splitGp.parts.push({
        id: "in_gp_plug",
        label: "其他毛利运用（轧差）",
        en: "Unlisted use of gross profit",
        concept: "",
        value: splitGp.plug,
        order: 70,
        plug: true,
        formula: "毛利 − 营业利润 − 已列示费用"
      });
      notes.push("毛利与费用、营业利润之间有轧差，已单独标出。");
      rows.push(row("其他毛利运用（轧差）", "Unlisted use of gross profit", "", splitGp.plug, "plug", "毛利 − 营业利润 − 已列示费用"));
    }
    expenseParts = splitGp.parts;

    var nonopValue = nonop ? nonop.value : (pretax ? pretax.value - oi.value : 0);
    var nonopComputed = !nonop && pretax;
    if (nonopComputed) notes.push("营业外损益由税前利润减营业利润计算。");
    if (!pretax || pretax.value <= 0 || !tax || !ni) {
      var incomplete = emptyStatement("income", "利润表", "partial", "税前利润、所得税或净利润缺失，只画出了毛利到营业利润这一段。");
      incomplete.rows = rows;
      incomplete.notes = notes.concat(incomplete.notes);
      return incomplete;
    }
    rows.push(row(
      nonopValue >= 0 ? "营业外收益（净额）" : "营业外支出（净额）",
      nonop ? nonop.en : "Nonoperating income (expense)",
      nonop ? nonop.concept : "",
      nonopValue,
      nonopComputed ? "plug" : "sec",
      nonopComputed ? "税前利润 − 营业利润" : ""
    ));
    rows.push(row("税前利润", pretax.en, pretax.concept, pretax.value, "subtotal"));
    rows.push(row("所得税费用", tax.en, tax.concept, tax.value, "sec"));
    rows.push(row("净利润", ni.en, ni.concept, ni.value, "subtotal"));

    if (Math.abs((oi.value + nonopValue) - pretax.value) > Math.max(ABSORB, Math.abs(pretax.value) * 0.01)) {
      notes.push("营业利润与营业外损益之和，和税前利润不完全相等。");
    }
    if (ni.value <= 0 || tax.value < 0) {
      var signed = emptyStatement("income", "利润表", "error", "净利润不为正，或所得税为收益。当前版本只绘制费用与盈利同向的利润表。");
      signed.rows = rows;
      signed.notes = notes.concat(signed.notes);
      return signed;
    }
    if (Math.abs(pretax.value - tax.value - ni.value) > Math.max(ABSORB, pretax.value * 0.01)) {
      notes.push("税前利润减所得税与净利润有差异，已放入轧差。");
    }

    var nodes = [];
    var links = [];
    function node(spec) { nodes.push(spec); }

    node({ id: "in_rev", label: "营业收入", en: rev.en, column: 0, order: 10, tone: "in", concept: rev.concept, signed: rev.value });
    node({ id: "in_gp", label: "毛利", en: gp.en || "Gross profit", column: 1, order: 10, tone: "total", concept: gp.concept || "", signed: gp.value, formula: gp.computed ? "营业收入 − 营业成本" : "" });
    node({ id: "in_cogs", label: "营业成本", en: cogs.en, column: 1, order: 20, tone: "out", concept: cogs.concept, signed: cogs.value });
    addLink(links, "in_rev", "in_gp", gp.value);
    addLink(links, "in_rev", "in_cogs", cogs.value);
    var revGap = rev.value - gp.value - cogs.value;
    if (revGap > ABSORB) {
      node({ id: "in_rev_plug", label: "营业收入轧差", en: "Revenue reconciliation", column: 1, order: 30, tone: "plug", concept: "", signed: revGap, plug: true, formula: "营业收入 − 营业成本 − 毛利" });
      addLink(links, "in_rev", "in_rev_plug", revGap);
      notes.push("营业收入与营业成本、毛利不完全相加，差额已标为轧差。");
    }

    node({ id: "in_oi", label: "营业利润", en: oi.en, column: 2, order: 10, tone: "total", concept: oi.concept, signed: oi.value });
    addLink(links, "in_gp", "in_oi", oi.value);
    expenseParts.forEach(function (part) {
      node({
        id: part.id,
        label: part.label,
        en: part.en,
        column: 2,
        order: part.order,
        tone: part.plug ? "plug" : "out",
        concept: part.concept,
        signed: part.value,
        plug: !!part.plug,
        formula: part.formula || ""
      });
      addLink(links, "in_gp", part.id, part.value);
    });

    node({ id: "in_pretax", label: "税前利润", en: pretax.en, column: 3, order: 10, tone: "total", concept: pretax.concept, signed: pretax.value });
    if (nonopValue >= 0) {
      addLink(links, "in_oi", "in_pretax", oi.value);
      if (nonopValue > ABSORB) {
        node({
          id: "in_nonop",
          label: "营业外收益",
          en: nonop ? nonop.en : "Nonoperating income",
          column: 2,
          order: 80,
          tone: nonopComputed ? "plug" : "in",
          concept: nonop ? nonop.concept : "",
          signed: nonopValue,
          plug: nonopComputed,
          formula: nonopComputed ? "税前利润 − 营业利润" : ""
        });
        addLink(links, "in_nonop", "in_pretax", nonopValue);
      }
    } else {
      addLink(links, "in_oi", "in_pretax", pretax.value);
      node({
        id: "in_nonop",
        label: "营业外支出",
        en: nonop ? nonop.en : "Nonoperating expense",
        column: 3,
        order: 40,
        tone: "out",
        concept: nonop ? nonop.concept : "",
        signed: nonopValue,
        formula: nonopComputed ? "税前利润 − 营业利润" : ""
      });
      addLink(links, "in_oi", "in_nonop", Math.abs(nonopValue));
    }

    var bottom = absorb(
      [
        { id: "in_tax", label: "所得税", en: tax.en, concept: tax.concept, value: tax.value, order: 20 },
        { id: "in_ni", label: "净利润", en: ni.en, concept: ni.concept, value: ni.value, order: 10 }
      ],
      pretax.value
    );
    if (bottom.plug < -ABSORB) {
      var taxGap = emptyStatement("income", "利润表", "error", "所得税与净利润之和大于税前利润，未绘制最后一段。");
      taxGap.rows = rows;
      taxGap.notes = notes.concat(taxGap.notes);
      return taxGap;
    }
    node({ id: "in_ni", label: "净利润", en: ni.en, column: 4, order: 10, tone: "in", concept: ni.concept, signed: ni.value });
    node({ id: "in_tax", label: "所得税", en: tax.en, column: 4, order: 20, tone: "out", concept: tax.concept, signed: tax.value });
    addLink(links, "in_pretax", "in_ni", ni.value);
    addLink(links, "in_pretax", "in_tax", tax.value);
    if (bottom.plug > ABSORB) {
      node({
        id: "in_bottom_plug",
        label: "税后轧差",
        en: "Pretax reconciliation",
        column: 4,
        order: 30,
        tone: "plug",
        concept: "",
        signed: bottom.plug,
        plug: true,
        formula: "税前利润 − 所得税 − 净利润"
      });
      addLink(links, "in_pretax", "in_bottom_plug", bottom.plug);
      rows.push(row("税后轧差", "Pretax reconciliation", "", bottom.plug, "plug", "税前利润 − 所得税 − 净利润"));
    }

    finalize(nodes, links);
    var status = notes.some(function (note) { return note.indexOf("轧差") >= 0 || note.indexOf("差异") >= 0 || note.indexOf("重叠") >= 0; })
      ? "partial"
      : "ok";
    return {
      id: "income",
      title: "利润表",
      status: status,
      notes: notes,
      nodes: nodes,
      links: links,
      rows: rows,
      period: period
    };
  }

  var MIN_SHARE = 0.008;

  function fitGroup(total, candidates) {
    var picked = [];
    var skipped = [];
    var used = 0;
    candidates.forEach(function (candidate) {
      if (!candidate || candidate.value == null || candidate.value <= ABSORB) return;
      if (candidate.value < total * MIN_SHARE) {
        skipped.push(candidate.label + "（金额相对小计过小，并入轧差）");
        return;
      }
      if (used + candidate.value <= total + ABSORB) {
        picked.push(candidate);
        used += candidate.value;
      } else {
        skipped.push(candidate.label + "（与已列示项目相加会超过小计，未再画入，避免重复）");
      }
    });
    var residual = total - used;
    if (residual > ABSORB) {
      picked.push({
        id: candidates.residualId,
        label: candidates.residualLabel,
        en: "Reconciliation residual",
        concept: "",
        value: residual,
        plug: true,
        formula: candidates.residualFormula,
        order: 900
      });
    }
    return { picked: picked, skipped: skipped, residual: residual };
  }

  function buildBalance(facts, period) {
    var pick = makePicker(facts, period);
    var notes = [];
    var rows = [];
    var assets = pick.instantAny(["Assets"]);
    var equity = pick.instantAny(["StockholdersEquity", "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest"]);
    var liabilities = pick.instantAny(["Liabilities"]);
    if (!assets || assets.value <= 0) {
      return emptyStatement("balance", "资产负债表", "error", "没有找到资产总计，无法绘制资产负债表。");
    }
    if (!equity || !liabilities) {
      var missing = emptyStatement("balance", "资产负债表", "error", "负债或股东权益合计缺失，无法让左右两边平衡。");
      missing.rows = [row("资产总计", assets.en, assets.concept, assets.value, "subtotal")];
      return missing;
    }
    var currentAssets = pick.instantAny(["AssetsCurrent"]);
    var currentLiab = pick.instantAny(["LiabilitiesCurrent"]);
    var noncurrentAssets = currentAssets ? assets.value - currentAssets.value : null;
    var noncurrentLiab = currentLiab ? liabilities.value - currentLiab.value : null;

    function take(concepts) {
      return pick.instant(concepts);
    }

    var assetLeaves = [];
    var liabilityLeaves = [];
    var equityLeaves = [];

    function pushLeaf(bucket, hit, id, label, order) {
      if (!hit) return;
      bucket.push({
        id: id,
        label: label,
        en: hit.en,
        concept: hit.concept,
        value: hit.value,
        order: order,
        signed: hit.value
      });
      rows.push(row(label, hit.en, hit.concept, hit.value, "sec"));
    }

    if (currentAssets && currentAssets.value > 0) {
      var currentCandidates = [];
      pushLeaf(currentCandidates, take(["CashAndCashEquivalentsAtCarryingValue", "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents"]), "bs_cash", "现金及现金等价物", 10);
      pushLeaf(currentCandidates, take(["MarketableSecuritiesCurrent", "ShortTermInvestments", "AvailableForSaleSecuritiesDebtMaturitiesWithinOneYearFairValue"]), "bs_stinv", "短期投资 / 一年内证券", 20);
      pushLeaf(currentCandidates, take(["AccountsReceivableNetCurrent"]), "bs_ar", "应收账款", 30);
      pushLeaf(currentCandidates, take(["InventoryNet"]), "bs_inv", "存货", 40);
      pushLeaf(currentCandidates, take(["OtherAssetsCurrent"]), "bs_oca", "其他流动资产", 50);
      pushLeaf(currentCandidates, take(["PrepaidExpenseAndOtherAssetsCurrent"]), "bs_prepay", "预付款及其他", 55);
      currentCandidates.residualId = "bs_ca_plug";
      currentCandidates.residualLabel = "未映射流动资产";
      currentCandidates.residualFormula = "流动资产 − 已列示流动项目";
      var fittedCurrent = fitGroup(currentAssets.value, currentCandidates);
      fittedCurrent.picked.forEach(function (item) { item.group = "ca"; });
      assetLeaves = assetLeaves.concat(fittedCurrent.picked);
      fittedCurrent.skipped.forEach(function (text) { notes.push(text); });
      if (fittedCurrent.residual > assets.value * 0.08) {
        notes.push("未映射流动资产金额较大，说明还有没画成单独色带的流动项目。明细表保留了已识别科目。");
      }
      rows.push(row("流动资产", currentAssets.en, currentAssets.concept, currentAssets.value, "subtotal"));
    }

    if (noncurrentAssets > ABSORB) {
      var noncurrentCandidates = [];
      pushLeaf(noncurrentCandidates, take(["PropertyPlantAndEquipmentNet"]), "bs_ppe", "不动产、厂房及设备", 110);
      pushLeaf(noncurrentCandidates, take(["Goodwill"]), "bs_gw", "商誉", 120);
      pushLeaf(noncurrentCandidates, take(["IntangibleAssetsNetExcludingGoodwill", "FiniteLivedIntangibleAssetsNet"]), "bs_intang", "无形资产（不含商誉）", 130);
      pushLeaf(noncurrentCandidates, take(["LongTermInvestments", "MarketableSecuritiesNoncurrent", "EquitySecuritiesFVNINoncurrent", "EquitySecuritiesWithoutReadilyDeterminableFairValueAmount"]), "bs_ltinv", "长期投资", 140);
      pushLeaf(noncurrentCandidates, take(["AvailableForSaleSecuritiesDebtMaturitiesAfterOneThroughFiveYearsFairValue"]), "bs_afs", "一年后到期可供出售证券", 150);
      pushLeaf(noncurrentCandidates, take(["OperatingLeaseRightOfUseAsset"]), "bs_rou", "经营租赁使用权资产", 160);
      pushLeaf(noncurrentCandidates, take(["OtherAssetsNoncurrent"]), "bs_onca", "其他非流动资产", 170);
      noncurrentCandidates.residualId = "bs_nca_plug";
      noncurrentCandidates.residualLabel = "未映射非流动资产";
      noncurrentCandidates.residualFormula = "资产总计 − 流动资产 − 已列示非流动项目";
      var fittedNoncurrent = fitGroup(noncurrentAssets, noncurrentCandidates);
      fittedNoncurrent.picked.forEach(function (item) { item.group = "nca"; });
      assetLeaves = assetLeaves.concat(fittedNoncurrent.picked);
      fittedNoncurrent.skipped.forEach(function (text) { notes.push(text); });
      rows.push(row("非流动资产", "Noncurrent assets", "", noncurrentAssets, "subtotal", "资产总计 − 流动资产"));
    }
    rows.push(row("资产总计", assets.en, assets.concept, assets.value, "subtotal"));

    if (currentLiab && currentLiab.value > 0) {
      var clCandidates = [];
      pushLeaf(clCandidates, take(["AccountsPayableCurrent"]), "bs_ap", "应付账款", 10);
      pushLeaf(clCandidates, take(["ContractWithCustomerLiabilityCurrent"]), "bs_contract", "合同负债", 20);
      pushLeaf(clCandidates, take(["LongTermDebtCurrent", "DebtCurrent"]), "bs_std", "一年内到期债务", 30);
      pushLeaf(clCandidates, take(["ShortTermBorrowings", "CommercialPaper"]), "bs_cp", "短期借款", 40);
      pushLeaf(clCandidates, take(["AccruedLiabilitiesCurrent"]), "bs_accrued", "应计负债", 50);
      clCandidates.residualId = "bs_cl_plug";
      clCandidates.residualLabel = "其他流动负债（轧差）";
      clCandidates.residualFormula = "流动负债 − 已列示流动负债";
      var fittedCl = fitGroup(currentLiab.value, clCandidates);
      fittedCl.picked.forEach(function (item) { item.group = "cl"; });
      liabilityLeaves = liabilityLeaves.concat(fittedCl.picked);
      fittedCl.skipped.forEach(function (text) { notes.push(text); });
      rows.push(row("流动负债", currentLiab.en, currentLiab.concept, currentLiab.value, "subtotal"));
    }
    if (noncurrentLiab > ABSORB) {
      var nclCandidates = [];
      pushLeaf(nclCandidates, take(["LongTermDebtNoncurrent"]), "bs_ltd", "长期债务", 110);
      pushLeaf(nclCandidates, take(["OtherLiabilitiesNoncurrent"]), "bs_oncl", "其他非流动负债（已单列）", 120);
      nclCandidates.residualId = "bs_ncl_plug";
      nclCandidates.residualLabel = "其他非流动负债（轧差）";
      nclCandidates.residualFormula = "负债合计 − 流动负债 − 已列示非流动负债";
      var fittedNcl = fitGroup(noncurrentLiab, nclCandidates);
      fittedNcl.picked.forEach(function (item) { item.group = "ncl"; });
      liabilityLeaves = liabilityLeaves.concat(fittedNcl.picked);
      fittedNcl.skipped.forEach(function (text) { notes.push(text); });
      rows.push(row("非流动负债", "Noncurrent liabilities", "", noncurrentLiab, "subtotal", "负债合计 − 流动负债"));
    }
    rows.push(row("负债合计", liabilities.en, liabilities.concept, liabilities.value, "subtotal"));

    var re = pick.instantAny(["RetainedEarningsAccumulatedDeficit"]);
    var cap = pick.instant(["CommonStocksIncludingAdditionalPaidInCapital"]);
    var apic = pick.instant(["AdditionalPaidInCapital"]);
    var common = pick.instant(["CommonStockValue"]);
    var aoci = pick.instantAny(["AccumulatedOtherComprehensiveIncomeLossNetOfTax"]);
    var treasury = pick.instantAny(["TreasuryStockValue"]);
    var equityParts = [];
    if (re && re.value > ABSORB) {
      equityParts.push({ id: "bs_re", label: "留存收益", en: re.en, concept: re.concept, value: re.value, order: 10 });
      rows.push(row("留存收益", re.en, re.concept, re.value, "sec"));
    } else if (re && re.value < -ABSORB) {
      notes.push("留存收益为累计亏损，已放在明细表，不单独画成正向条带。");
      rows.push(row("累计亏损", re.en, re.concept, re.value, "sec"));
    }
    if (cap) {
      equityParts.push({ id: "bs_cap", label: "股本及资本公积", en: cap.en, concept: cap.concept, value: cap.value, order: 20 });
      rows.push(row("股本及资本公积", cap.en, cap.concept, cap.value, "sec"));
    } else {
      if (apic) {
        equityParts.push({ id: "bs_apic", label: "资本公积", en: apic.en, concept: apic.concept, value: apic.value, order: 20 });
        rows.push(row("资本公积", apic.en, apic.concept, apic.value, "sec"));
      }
      if (common) {
        equityParts.push({ id: "bs_common", label: "普通股", en: common.en, concept: common.concept, value: common.value, order: 30 });
        rows.push(row("普通股", common.en, common.concept, common.value, "sec"));
      }
    }
    var contra = 0;
    var contraBits = [];
    if (aoci && aoci.value < -ABSORB) {
      contra += -aoci.value;
      contraBits.push("累计其他综合亏损 " + aoci.value);
      rows.push(row("累计其他综合收益（亏损）", aoci.en, aoci.concept, aoci.value, "sec"));
    } else if (aoci && aoci.value > ABSORB) {
      equityParts.push({ id: "bs_aoci", label: "累计其他综合收益", en: aoci.en, concept: aoci.concept, value: aoci.value, order: 40 });
      rows.push(row("累计其他综合收益", aoci.en, aoci.concept, aoci.value, "sec"));
    }
    if (treasury && treasury.value < -ABSORB) {
      contra += -treasury.value;
      contraBits.push("库存股 " + treasury.value);
      rows.push(row("库存股", treasury.en, treasury.concept, treasury.value, "sec"));
    } else if (treasury && treasury.value > ABSORB) {
      contra += treasury.value;
      contraBits.push("库存股 " + treasury.value);
      rows.push(row("库存股", treasury.en, treasury.concept, treasury.value, "sec"));
    }
    var equityBudget = equity.value;
    var equityUsed = 0;
    equityParts.forEach(function (part) {
      if (part.value < equity.value * MIN_SHARE) return;
      var room = equityBudget - equityUsed;
      var draw = Math.min(part.value, room);
      if (draw <= ABSORB) return;
      var leaf = {
        id: part.id,
        label: part.label,
        en: part.en,
        concept: part.concept,
        value: draw,
        order: part.order,
        group: "eq"
      };
      if (draw + ABSORB < part.value) {
        leaf.label = part.label + "（净额）";
        leaf.plug = true;
        leaf.formula = "已扣减抵销项：" + contraBits.join("；");
        leaf.tone = "plug";
        notes.push(part.label + "在图上按净额绘制，抵销项见明细表。");
      }
      equityLeaves.push(leaf);
      equityUsed += draw;
    });
    if (equity.value - equityUsed > ABSORB) {
      equityLeaves.push({
        id: "bs_eq_plug",
        label: "其他股东权益（轧差）",
        en: "Other equity",
        concept: "",
        value: equity.value - equityUsed,
        order: 900,
        plug: true,
        formula: "股东权益 − 已列示权益项目（抵销项已从条带扣减）",
        group: "eq"
      });
      rows.push(row("其他股东权益（轧差）", "Other equity", "", equity.value - equityUsed, "plug", "股东权益 − 已画入的权益项目"));
    }
    rows.push(row("股东权益", equity.en, equity.concept, equity.value, "subtotal"));
    if (contraBits.length) notes.push("抵销项不单独占一条正向流入：" + contraBits.join("；") + "。");

    var identityGap = assets.value - liabilities.value - equity.value;
    if (Math.abs(identityGap) > Math.max(ABSORB, assets.value * 0.002)) {
      notes.push("资产总计与负债加股东权益相差 " + identityGap + " 美元，已单独标出。");
    }

    var nodes = [];
    var links = [];
    function add(spec) { nodes.push(spec); }

    assetLeaves.forEach(function (leaf) {
      add({
        id: leaf.id,
        label: leaf.label,
        en: leaf.en,
        column: 0,
        order: leaf.order,
        tone: leaf.plug ? "plug" : "in",
        concept: leaf.concept,
        signed: leaf.value,
        plug: !!leaf.plug,
        formula: leaf.formula || ""
      });
    });
    if (currentAssets && currentAssets.value > 0) {
      add({ id: "bs_ca", label: "流动资产", en: currentAssets.en, column: 1, order: 10, tone: "total", concept: currentAssets.concept, signed: currentAssets.value });
      assetLeaves.filter(function (leaf) { return leaf.group === "ca"; }).forEach(function (leaf) {
        addLink(links, leaf.id, "bs_ca", leaf.value);
      });
    }
    if (noncurrentAssets > ABSORB) {
      add({ id: "bs_nca", label: "非流动资产", en: "Noncurrent assets", column: 1, order: 20, tone: "total", concept: "", signed: noncurrentAssets, formula: "资产总计 − 流动资产" });
      assetLeaves.filter(function (leaf) { return leaf.group === "nca"; }).forEach(function (leaf) {
        addLink(links, leaf.id, "bs_nca", leaf.value);
      });
    }
    add({ id: "bs_assets", label: "资产总计", en: assets.en, column: 2, order: 10, tone: "total", concept: assets.concept, signed: assets.value });
    if (currentAssets && currentAssets.value > 0) addLink(links, "bs_ca", "bs_assets", currentAssets.value);
    if (noncurrentAssets > ABSORB) addLink(links, "bs_nca", "bs_assets", noncurrentAssets);
    if (!currentAssets) {
      assetLeaves.forEach(function (leaf) { addLink(links, leaf.id, "bs_assets", leaf.value); });
    }

    if (currentLiab && currentLiab.value > 0) {
      add({ id: "bs_cl", label: "流动负债", en: currentLiab.en, column: 3, order: 10, tone: "out", concept: currentLiab.concept, signed: currentLiab.value });
      addLink(links, "bs_assets", "bs_cl", currentLiab.value);
      liabilityLeaves.filter(function (leaf) { return leaf.group === "cl"; }).forEach(function (leaf) {
        add({
          id: leaf.id, label: leaf.label, en: leaf.en, column: 4, order: leaf.order,
          tone: leaf.plug ? "plug" : "out", concept: leaf.concept, signed: leaf.value, plug: !!leaf.plug, formula: leaf.formula || ""
        });
        addLink(links, "bs_cl", leaf.id, leaf.value);
      });
    }
    if (noncurrentLiab > ABSORB) {
      add({ id: "bs_ncl", label: "非流动负债", en: "Noncurrent liabilities", column: 3, order: 20, tone: "out", concept: "", signed: noncurrentLiab, formula: "负债合计 − 流动负债" });
      addLink(links, "bs_assets", "bs_ncl", noncurrentLiab);
      liabilityLeaves.filter(function (leaf) { return leaf.group === "ncl"; }).forEach(function (leaf) {
        add({
          id: leaf.id, label: leaf.label, en: leaf.en, column: 4, order: leaf.order + 100,
          tone: leaf.plug ? "plug" : "out", concept: leaf.concept, signed: leaf.value, plug: !!leaf.plug, formula: leaf.formula || ""
        });
        addLink(links, "bs_ncl", leaf.id, leaf.value);
      });
    }
    add({ id: "bs_eq", label: "股东权益", en: equity.en, column: 3, order: 30, tone: "equity", concept: equity.concept, signed: equity.value });
    addLink(links, "bs_assets", "bs_eq", equity.value);
    equityLeaves.forEach(function (leaf) {
      add({
        id: leaf.id, label: leaf.label, en: leaf.en, column: 4, order: 200 + leaf.order,
        tone: leaf.plug ? "plug" : "equity", concept: leaf.concept, signed: leaf.value, plug: !!leaf.plug, formula: leaf.formula || ""
      });
      addLink(links, "bs_eq", leaf.id, leaf.value);
    });
    if (identityGap > ABSORB) {
      add({ id: "bs_gap", label: "平衡轧差", en: "Balance sheet gap", column: 3, order: 90, tone: "plug", concept: "", signed: identityGap, plug: true, formula: "资产 − 负债 − 股东权益" });
      addLink(links, "bs_assets", "bs_gap", identityGap);
    } else if (identityGap < -ABSORB) {
      notes.push("负债加权益大于资产，图上仍按所披露的资产总计分摊，差额见明细。");
    }

    finalize(nodes, links);
    var status = notes.length ? "partial" : "ok";
    return {
      id: "balance",
      title: "资产负债表",
      status: status,
      notes: notes,
      nodes: nodes,
      links: links,
      rows: rows,
      period: period
    };
  }

  function findCashPeriod(facts, incomePeriod) {
    var rows = usdRows(facts, "NetCashProvidedByUsedInOperatingActivities").filter(function (row) {
      return incomePeriod.forms.indexOf(row.form) >= 0 && row.end === incomePeriod.end && row.start;
    });
    if (!rows.length) return null;
    var target = incomePeriod.span;
    rows.sort(function (a, b) {
      var da = Math.abs(daysBetween(a.start, a.end) - target);
      var db = Math.abs(daysBetween(b.start, b.end) - target);
      if (da !== db) return da - db;
      return (b.filed || "").localeCompare(a.filed || "");
    });
    var best = rows[0];
    var span = daysBetween(best.start, best.end);
    return {
      forms: incomePeriod.forms,
      start: best.start,
      end: best.end,
      filed: best.filed || incomePeriod.filed,
      fp: best.fp || incomePeriod.fp,
      fy: best.fy || incomePeriod.fy,
      form: best.form,
      span: span,
      ytd: Math.abs(span - target) > 20
    };
  }

  function buildCash(facts, incomePeriod) {
    var cashPeriod = findCashPeriod(facts, incomePeriod) || incomePeriod;
    var pick = makePicker(facts, cashPeriod);
    var notes = [];
    var rows = [];
    if (cashPeriod.ytd) {
      notes.push("这份季报的现金流量是年初至本季末，不是单季。不要把它和单季利润表直接相加。");
    }
    var cfoHit = pick.durKeepZero(["NetCashProvidedByUsedInOperatingActivities"]);
    var cfiHit = pick.durKeepZero(["NetCashProvidedByUsedInInvestingActivities"]);
    var cffHit = pick.durKeepZero(["NetCashProvidedByUsedInFinancingActivities"]);
    if (!cfoHit || !cfiHit || !cffHit) {
      var missing = emptyStatement("cashflow", "现金流量表", "error", "经营、投资或筹资活动现金净额缺失，无法绘制现金流量表。");
      missing.period = cashPeriod;
      return missing;
    }
    var deltaHit = pick.durKeepZero([
      "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalentsPeriodIncreaseDecreaseIncludingExchangeRateEffect"
    ]);
    var fxHit = pick.dur([
      "EffectOfExchangeRateOnCashCashEquivalentsRestrictedCashAndRestrictedCashEquivalentsIncludingRestrictedCash",
      "EffectOfExchangeRateOnCashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents",
      "EffectOfExchangeRateOnCashAndCashEquivalents"
    ]);
    var ni = pick.durKeepZero(["NetIncomeLoss"]);
    var daCombined = pick.dur([
      "DepreciationDepletionAndAmortization",
      "DepreciationAndAmortization",
      "DepreciationAmortizationAndAccretionNet"
    ]);
    var depreciation = daCombined ? null : pick.dur(["Depreciation"]);
    var amortization = daCombined ? null : pick.dur(["AmortizationOfIntangibleAssets"]);
    var sbc = pick.dur(["ShareBasedCompensation"]);
    var capex = pick.dur(["PaymentsToAcquirePropertyPlantAndEquipment", "PaymentsToAcquireProductiveAssets"]);
    var dividends = pick.dur(["PaymentsOfDividends", "PaymentsOfDividendsCommonStock"]);
    var buybacks = pick.dur(["PaymentsForRepurchaseOfCommonStock"]);

    function pushSec(label, hit, role) {
      if (!hit) return;
      rows.push(row(label, hit.en, hit.concept, hit.value, role || "sec"));
    }
    pushSec("净利润", ni, "sec");
    pushSec("折旧与摊销", daCombined, "sec");
    pushSec("折旧", depreciation, "sec");
    pushSec("无形资产摊销", amortization, "sec");
    pushSec("股份支付", sbc, "sec");
    pushSec("经营活动现金净额", cfoHit, "subtotal");
    pushSec("购建长期资产", capex, "sec");
    pushSec("投资活动现金净额", cfiHit, "subtotal");
    pushSec("分红", dividends, "sec");
    pushSec("回购普通股", buybacks, "sec");
    pushSec("筹资活动现金净额", cffHit, "subtotal");
    pushSec("汇率影响", fxHit, "sec");
    if (deltaHit) pushSec("现金及受限现金净增加", deltaHit, "subtotal");

    var nodes = [];
    var links = [];
    function add(spec) { nodes.push(spec); }

    var bridgeSources = [];
    var bridgeUses = [];

    if (cfoHit.value > 0 && ni) {
      var pieces = [];
      if (ni.value > ABSORB) pieces.push({ id: "cf_ni", label: "净利润", en: ni.en, concept: ni.concept, value: ni.value, order: 10 });
      if (daCombined && daCombined.value > ABSORB) pieces.push({ id: "cf_da", label: "折旧与摊销", en: daCombined.en, concept: daCombined.concept, value: daCombined.value, order: 20 });
      if (depreciation && depreciation.value > ABSORB) pieces.push({ id: "cf_dep", label: "折旧", en: depreciation.en, concept: depreciation.concept, value: depreciation.value, order: 20 });
      if (amortization && amortization.value > ABSORB) pieces.push({ id: "cf_amort", label: "无形资产摊销", en: amortization.en, concept: amortization.concept, value: amortization.value, order: 30 });
      if (sbc && sbc.value > ABSORB) pieces.push({ id: "cf_sbc", label: "股份支付", en: sbc.en, concept: sbc.concept, value: sbc.value, order: 40 });
      var addSum = pieces.reduce(function (sum, piece) { return sum + piece.value; }, 0);
      var opPlug = cfoHit.value - addSum;
      if (opPlug > ABSORB) {
        pieces.push({ id: "cf_op_plug_in", label: "其他经营调节", en: "Other operating items", concept: "", value: opPlug, order: 50, plug: true, formula: "经营活动现金净额 − 已列示调节项" });
      }
      pieces.forEach(function (piece) {
        add({
          id: piece.id, label: piece.label, en: piece.en, column: 0, order: piece.order,
          tone: piece.plug ? "plug" : "in", concept: piece.concept, signed: piece.value, plug: !!piece.plug, formula: piece.formula || ""
        });
      });
      add({ id: "cf_op", label: "经营调节合计", en: "Operating reconciliation", column: 1, order: 10, tone: "total", concept: "", signed: addSum + Math.max(opPlug, 0) });
      pieces.forEach(function (piece) { addLink(links, piece.id, "cf_op", piece.value); });
      add({ id: "cf_cfo", label: "经营活动现金净额", en: cfoHit.en, column: 2, order: 10, tone: "in", concept: cfoHit.concept, signed: cfoHit.value });
      addLink(links, "cf_op", "cf_cfo", cfoHit.value);
      if (opPlug < -ABSORB) {
        add({
          id: "cf_op_plug_out",
          label: "其他经营调节（占用）",
          en: "Other operating uses",
          column: 2,
          order: 20,
          tone: "plug",
          concept: "",
          signed: opPlug,
          plug: true,
          formula: "已列示调节项 − 经营活动现金净额"
        });
        addLink(links, "cf_op", "cf_op_plug_out", -opPlug);
        rows.push(row("其他经营调节（占用）", "Other operating uses", "", opPlug, "plug", "经营活动现金净额 − 净利润 − 折旧摊销 − 股份支付"));
        notes.push("净利润到经营现金的差额含营运资本等未逐项展开的项目，图上标为其他经营调节。");
      } else if (opPlug > ABSORB) {
        rows.push(row("其他经营调节", "Other operating items", "", opPlug, "plug", "经营活动现金净额 − 已列示调节项"));
      }
      bridgeSources.push({ id: "cf_cfo", value: cfoHit.value });
    } else if (cfoHit.value > 0) {
      add({ id: "cf_cfo", label: "经营活动现金净额", en: cfoHit.en, column: 2, order: 10, tone: "in", concept: cfoHit.concept, signed: cfoHit.value });
      bridgeSources.push({ id: "cf_cfo", value: cfoHit.value });
      notes.push("缺少净利润，经营现金未再向左拆开。");
    } else {
      add({ id: "cf_cfo_use", label: "经营活动净流出", en: cfoHit.en, column: 4, order: 10, tone: "out", concept: cfoHit.concept, signed: cfoHit.value });
      bridgeUses.push({ id: "cf_cfo_use", value: -cfoHit.value });
      notes.push("经营活动为净流出，未再展开净利润调节。");
    }

    function pushUse(id, label, en, concept, value, order, plug, formula) {
      if (value <= ABSORB) return;
      add({
        id: id, label: label, en: en, column: 4, order: order, tone: plug ? "plug" : "out",
        concept: concept || "", signed: -value, plug: !!plug, formula: formula || ""
      });
      bridgeUses.push({ id: id, value: value });
    }
    function pushSource(id, label, en, concept, value, order) {
      if (value <= ABSORB) return;
      add({ id: id, label: label, en: en, column: 2, order: order, tone: "in", concept: concept || "", signed: value });
      bridgeSources.push({ id: id, value: value });
    }

    if (cfiHit.value < 0) {
      var cfiLeft = -cfiHit.value;
      if (capex && capex.value > 0) {
        var capexDraw = Math.min(capex.value, cfiLeft);
        pushUse("cf_capex", "购建长期资产", capex.en, capex.concept, capexDraw, 20, false, "");
        cfiLeft -= capexDraw;
      }
      if (cfiLeft > ABSORB) {
        pushUse("cf_cfi_plug", "其他投资活动（轧差）", "Other investing", "", cfiLeft, 30, true, "投资净流出 − 已列示购建");
        rows.push(row("其他投资活动（轧差）", "Other investing", "", -cfiLeft, "plug", "投资活动现金净额 + 已列示购建"));
      }
    } else if (cfiHit.value > ABSORB) {
      pushSource("cf_cfi_in", "投资活动净流入", cfiHit.en, cfiHit.concept, cfiHit.value, 40);
    }

    if (cffHit.value < 0) {
      var cffLeft = -cffHit.value;
      if (buybacks && buybacks.value > 0) {
        var buyDraw = Math.min(buybacks.value, cffLeft);
        pushUse("cf_buy", "回购普通股", buybacks.en, buybacks.concept, buyDraw, 40, false, "");
        cffLeft -= buyDraw;
      }
      if (dividends && dividends.value > 0) {
        var divDraw = Math.min(dividends.value, cffLeft);
        pushUse("cf_div", "分红", dividends.en, dividends.concept, divDraw, 50, false, "");
        cffLeft -= divDraw;
      }
      if (cffLeft > ABSORB) {
        pushUse("cf_cff_plug", "其他筹资活动（轧差）", "Other financing", "", cffLeft, 60, true, "筹资净流出 − 回购 − 分红");
        rows.push(row("其他筹资活动（轧差）", "Other financing", "", -cffLeft, "plug", "筹资活动现金净额 + 回购 + 分红"));
      }
    } else if (cffHit.value > ABSORB) {
      pushSource("cf_cff_in", "筹资活动净流入", cffHit.en, cffHit.concept, cffHit.value, 50);
    }

    var sectionSum = cfoHit.value + cfiHit.value + cffHit.value + (fxHit ? fxHit.value : 0);
    var deltaValue = deltaHit ? deltaHit.value : sectionSum;
    if (!deltaHit) notes.push("现金净增加额由三项活动（及汇率，若有）相加得出。");
    var fxPlug = deltaValue - sectionSum;
    if (Math.abs(fxPlug) > ABSORB) {
      if (fxPlug > 0) pushSource("cf_fx_plug", "汇率及其他调节", "FX and other", "", fxPlug, 70);
      else pushUse("cf_fx_plug", "汇率及其他调节", "FX and other", "", -fxPlug, 70, true, "现金净增加 − 三项活动 − 已列汇率");
      rows.push(row("汇率及其他调节（轧差）", "FX and other", "", fxPlug, "plug", "现金净增加 − 经营 − 投资 − 筹资 − 已列汇率"));
      notes.push("现金净增加与经营活动、投资、筹资及已列汇率之和有差额。");
    } else if (fxHit && fxHit.value > ABSORB) {
      pushSource("cf_fx", "汇率影响", fxHit.en, fxHit.concept, fxHit.value, 70);
    } else if (fxHit && fxHit.value < -ABSORB) {
      pushUse("cf_fx", "汇率影响", fxHit.en, fxHit.concept, -fxHit.value, 80, false, "");
    }

    if (deltaValue > ABSORB) {
      pushUse("cf_delta", "现金净增加", deltaHit ? deltaHit.en : "Increase in cash", deltaHit ? deltaHit.concept : "", deltaValue, 90, !deltaHit, deltaHit ? "" : "经营 + 投资 + 筹资");
    } else if (deltaValue < -ABSORB) {
      pushSource("cf_delta", "现金净减少", deltaHit ? deltaHit.en : "Decrease in cash", deltaHit ? deltaHit.concept : "", -deltaValue, 80);
    }

    var sourceSum = bridgeSources.reduce(function (sum, item) { return sum + item.value; }, 0);
    var useSum = bridgeUses.reduce(function (sum, item) { return sum + item.value; }, 0);
    if (Math.abs(sourceSum - useSum) > ABSORB) {
      notes.push("现金来源与运用相差 " + Math.round(sourceSum - useSum) + " 美元，未强行配平。");
    }
    if (bridgeSources.length && bridgeUses.length) {
      var direct = bridgeSources.length === 1;
      if (direct) {
        bridgeUses.forEach(function (use) { addLink(links, bridgeSources[0].id, use.id, use.value); });
      } else {
        add({ id: "cf_bridge", label: "现金来源与运用", en: "Cash bridge", column: 3, order: 10, tone: "total", concept: "", signed: sourceSum });
        bridgeSources.forEach(function (source) { addLink(links, source.id, "cf_bridge", source.value); });
        bridgeUses.forEach(function (use) { addLink(links, "cf_bridge", use.id, use.value); });
      }
    }

    finalize(nodes, links);
    var status = notes.length ? "partial" : "ok";
    return {
      id: "cashflow",
      title: "现金流量表",
      status: status,
      notes: notes,
      nodes: nodes,
      links: links,
      rows: rows,
      period: cashPeriod
    };
  }

  function packageReport(facts, frequency, anchor) {
    if (!anchor) return null;
    var income = buildIncome(facts, anchor);
    var balance = buildBalance(facts, anchor);
    var cashflow = buildCash(facts, anchor);
    var statuses = [income.status, balance.status, cashflow.status];
    var status = statuses.indexOf("error") >= 0 && statuses.indexOf("ok") < 0 && statuses.indexOf("partial") < 0
      ? "error"
      : (statuses.indexOf("partial") >= 0 || statuses.indexOf("error") >= 0 ? "partial" : "ok");
    return {
      frequency: frequency,
      form: anchor.form,
      fp: anchor.fp,
      fy: anchor.fy,
      start: anchor.start,
      end: anchor.end,
      filed: anchor.filed,
      status: status,
      statements: { income: income, balance: balance, cashflow: cashflow }
    };
  }

  function buildReports(companyfacts) {
    var annualAnchor = findAnchor(companyfacts, ANNUAL_FORMS, 300, 400);
    var quarterAnchor = findAnchor(companyfacts, QUARTER_FORMS, 70, 120);
    return {
      annual: packageReport(companyfacts, "annual", annualAnchor),
      quarterly: packageReport(companyfacts, "quarterly", quarterAnchor)
    };
  }

  function auditStatement(statement) {
    var problems = [];
    if (!statement || statement.status === "error") return problems;
    var nodes = {};
    statement.nodes.forEach(function (node) { nodes[node.id] = node; });
    var incoming = {};
    var outgoing = {};
    statement.nodes.forEach(function (node) {
      incoming[node.id] = 0;
      outgoing[node.id] = 0;
      if (!(node.value > 0)) problems.push(node.id + " value");
    });
    statement.links.forEach(function (link) {
      if (!(link.value > 0)) problems.push("link " + link.source);
      if (!nodes[link.source] || !nodes[link.target]) problems.push("dangling " + link.source);
      else if (nodes[link.source].column >= nodes[link.target].column) problems.push("column " + link.source);
      outgoing[link.source] += link.value;
      incoming[link.target] += link.value;
    });
    statement.nodes.forEach(function (node) {
      var inn = incoming[node.id];
      var out = outgoing[node.id];
      if (inn === 0 && out === 0) problems.push("isolated " + node.id);
      if (inn > 0 && out > 0 && Math.abs(inn - out) > 2) problems.push("through " + node.id);
      if (out > 0 && inn === 0 && Math.abs(out - node.value) > 2) problems.push("source " + node.id);
      if (inn > 0 && out === 0 && Math.abs(inn - node.value) > 2) problems.push("sink " + node.id);
      if (inn > 0 && out > 0 && Math.abs(node.value - inn) > 2) problems.push("size " + node.id);
    });
    return problems;
  }

  return {
    buildReports: buildReports,
    auditStatement: auditStatement,
    ABSORB: ABSORB
  };
});

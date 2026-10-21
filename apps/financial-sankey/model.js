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
  var COGS_CONCEPTS = ["CostOfRevenue", "CostOfGoodsAndServicesSold", "CostOfGoodsSold", "CostOfServices"];
  var PRETAX_CONCEPTS = [
    "IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest"
  ];
  var TAX_CONCEPTS = ["IncomeTaxExpenseBenefit"];
  var NET_INCOME_CONCEPTS = ["NetIncomeLoss"];
  var INTEREST_INCOME_CONCEPTS = ["InterestAndDividendIncomeOperating", "InterestIncomeOperating"];
  var INTEREST_EXPENSE_CONCEPTS = ["InterestExpenseOperating", "InterestExpense"];
  var NET_INTEREST_CONCEPTS = ["InterestIncomeExpenseNet"];
  var NONINTEREST_INCOME_CONCEPTS = ["NoninterestIncome"];
  var NONINTEREST_EXPENSE_CONCEPTS = ["NoninterestExpense"];
  /* Totals already include loan and off-balance-sheet credit losses when a bank files them. */
  var PROVISION_TOTAL_CONCEPTS = ["ProvisionForCreditLosses", "ProvisionForLoanLeaseAndOtherLosses"];
  var PROVISION_LOAN_CONCEPTS = [
    "ProvisionForLoanLossesExpensed",
    "FinancingReceivableExcludingAccruedInterestCreditLossExpenseReversal",
    "ProvisionForLoanLosses",
    "ProvisionForLoanAndLeaseLosses"
  ];
  var PROVISION_OFF_CONCEPTS = [
    "OffBalanceSheetCreditLossLiabilityCreditLossExpenseReversal",
    "ProvisionForOtherCreditLosses"
  ];
  var PREMIUM_CONCEPTS = ["PremiumsEarnedNet", "PremiumsEarnedGross"];
  var INVESTMENT_INCOME_CONCEPTS = ["NetInvestmentIncome"];
  var OTHER_INCOME_CONCEPTS = ["OtherIncome"];
  var BENEFIT_CONCEPTS = ["PolicyholderBenefitsAndClaimsIncurredNet", "LossesAndLossAdjustmentExpenses"];
  var BENEFIT_TOTAL_CONCEPTS = ["BenefitsLossesAndExpenses"];
  var UNDERWRITING_CONCEPTS = ["OtherUnderwritingExpense", "PolicyAcquisitionCostsAndOtherUnderwritingExpenses"];
  var DAC_CONCEPTS = [
    "DeferredPolicyAcquisitionCostAmortizationExpense",
    "AmortizationOfDeferredPolicyAcquisitionCosts"
  ];
  var UNSUPPORTED_INCOME = "已取到这一报告期的利润表数据，但当前还画不成桑基图：没有可用的毛利结构，也没有银行净利息或保险保费这条链路。下表是已经识别的科目，并不是没取到数据。";

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

  function buildIndustrialIncome(facts, period) {
    var pick = makePicker(facts, period);
    var notes = [];
    var rows = [];
    var rev = pick.dur(REVENUE_CONCEPTS);
    if (!rev) {
      return emptyStatement("income", "利润表", "error", "这一报告期没有找到营业收入等科目，画不出利润表。");
    }
    var cogs = pick.dur(COGS_CONCEPTS);
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
      var missing = emptyStatement("income", "利润表", "partial", "已取到这一报告期的利润表数据，但营业成本或毛利不完整，当前还画不成常见的毛利结构。下表是已经识别的科目，并不是没取到数据。");
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
    var pretax = pick.durKeepZero(PRETAX_CONCEPTS);
    var nonop = pick.dur(["NonoperatingIncomeExpense"]);
    var tax = pick.durKeepZero(TAX_CONCEPTS);
    var ni = pick.durKeepZero(NET_INCOME_CONCEPTS);

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
      var loss = emptyStatement("income", "利润表", "partial", "已取到这一报告期的利润表数据，但营业利润不为正，当前版本画不出这条桑基图。下表是已经识别的科目，并不是没取到数据。");
      loss.rows = rows;
      return loss;
    }
    rows.push(row("营业利润", oi.en, oi.concept, oi.value, "subtotal"));

    var splitGp = absorb(expenseParts, gp.value - oi.value);
    if (splitGp.plug < -ABSORB) {
      var broken = emptyStatement("income", "利润表", "partial", "已取到这一报告期的利润表数据，但毛利盖不住已列示的费用和营业利润，没有绘制，以免色带宽和金额对不上。下表是已经识别的科目，并不是没取到数据。");
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
      var incomplete = emptyStatement("income", "利润表", "partial", "已取到这一报告期的利润表数据，但税前利润、所得税或净利润缺失，没有画成桑基图。下表是已经识别的科目，并不是没取到数据。");
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
      var signed = emptyStatement("income", "利润表", "partial", "已取到这一报告期的利润表数据，但净利润不为正，或所得税为收益。当前版本只画费用和盈利同向的利润表。下表是已经识别的科目，并不是没取到数据。");
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
      var taxGap = emptyStatement("income", "利润表", "partial", "已取到这一报告期的利润表数据，但所得税与净利润之和大于税前利润，没有绘制，以免色带宽和金额对不上。下表是已经识别的科目，并不是没取到数据。");
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

  function english(hit, fallback) {
    if (!hit) return fallback || "";
    if (hit.en && hit.en !== hit.concept) return hit.en;
    return fallback || hit.en || "";
  }

  function mergeRows(primary, extra) {
    var seen = {};
    var out = (primary || []).slice();
    out.forEach(function (item) { seen[item.label] = true; });
    (extra || []).forEach(function (item) {
      if (!seen[item.label]) {
        out.push(item);
        seen[item.label] = true;
      }
    });
    return out;
  }

  function pushRecognized(rows, pick, label, concepts, keepZero) {
    var hit = keepZero ? pick.durKeepZero(concepts) : pick.dur(concepts);
    if (!hit) return;
    rows.push(row(label, hit.en, hit.concept, hit.value, "sec"));
  }

  function recognizedIncomeRows(pick) {
    var rows = [];
    pushRecognized(rows, pick, "营业收入", REVENUE_CONCEPTS, false);
    pushRecognized(rows, pick, "营业成本", COGS_CONCEPTS, false);
    pushRecognized(rows, pick, "毛利", ["GrossProfit"], false);
    pushRecognized(rows, pick, "研发费用", ["ResearchAndDevelopmentExpense"], false);
    pushRecognized(rows, pick, "销售及管理费用", ["SellingGeneralAndAdministrativeExpense"], false);
    pushRecognized(rows, pick, "销售费用", ["SellingAndMarketingExpense"], false);
    pushRecognized(rows, pick, "管理费用", ["GeneralAndAdministrativeExpense"], false);
    pushRecognized(rows, pick, "营业费用", ["OperatingExpenses"], false);
    pushRecognized(rows, pick, "营业利润", ["OperatingIncomeLoss"], true);
    pushRecognized(rows, pick, "利息收入", INTEREST_INCOME_CONCEPTS, false);
    pushRecognized(rows, pick, "利息支出", INTEREST_EXPENSE_CONCEPTS, false);
    pushRecognized(rows, pick, "净利息收入", NET_INTEREST_CONCEPTS, false);
    pushRecognized(rows, pick, "非利息收入", NONINTEREST_INCOME_CONCEPTS, false);
    pushRecognized(rows, pick, "非利息费用", NONINTEREST_EXPENSE_CONCEPTS, false);
    var provisionTotal = pick.dur(PROVISION_TOTAL_CONCEPTS);
    var provisionLoan = pick.dur(PROVISION_LOAN_CONCEPTS);
    var provisionOff = pick.dur(PROVISION_OFF_CONCEPTS);
    if (provisionTotal) rows.push(row("信贷拨备", provisionTotal.en, provisionTotal.concept, provisionTotal.value, "sec"));
    if (provisionLoan && (!provisionTotal || provisionLoan.concept !== provisionTotal.concept)) {
      rows.push(row(provisionTotal ? "贷款信贷损失" : "信贷拨备", provisionLoan.en, provisionLoan.concept, provisionLoan.value, "sec"));
    }
    if (provisionOff) rows.push(row("表外信用损失", provisionOff.en, provisionOff.concept, provisionOff.value, "sec"));
    pushRecognized(rows, pick, "已赚保费", PREMIUM_CONCEPTS, false);
    pushRecognized(rows, pick, "净投资收益", INVESTMENT_INCOME_CONCEPTS, false);
    pushRecognized(rows, pick, "其他收入", OTHER_INCOME_CONCEPTS, false);
    pushRecognized(rows, pick, "保单给付与赔款", BENEFIT_CONCEPTS, false);
    pushRecognized(rows, pick, "给付、损失与费用", BENEFIT_TOTAL_CONCEPTS, false);
    pushRecognized(rows, pick, "承保费用", UNDERWRITING_CONCEPTS, false);
    pushRecognized(rows, pick, "递延保单获取成本摊销", DAC_CONCEPTS, false);
    pushRecognized(rows, pick, "税前利润", PRETAX_CONCEPTS, true);
    pushRecognized(rows, pick, "所得税费用", TAX_CONCEPTS, true);
    pushRecognized(rows, pick, "净利润", NET_INCOME_CONCEPTS, true);
    return rows;
  }

  function mappingStatus(notes) {
    var partial = notes.some(function (note) {
      return note.indexOf("轧差") >= 0 || note.indexOf("差异") >= 0 || note.indexOf("重叠") >= 0;
    });
    return partial ? "partial" : "ok";
  }

  function industrialReady(pick, rev) {
    if (!rev || rev.value <= 0) return false;
    var cogs = pick.dur(COGS_CONCEPTS);
    var gp = pick.dur(["GrossProfit"]);
    if (!gp && cogs && rev.value - cogs.value > 0) gp = { value: rev.value - cogs.value };
    return !!(cogs && gp && cogs.value > 0 && gp.value > 0);
  }

  function bankReady(pick) {
    var net = pick.dur(NET_INTEREST_CONCEPTS);
    var income = pick.dur(INTEREST_INCOME_CONCEPTS);
    var expense = pick.dur(INTEREST_EXPENSE_CONCEPTS);
    var nonIncome = pick.dur(NONINTEREST_INCOME_CONCEPTS);
    var nonExpense = pick.dur(NONINTEREST_EXPENSE_CONCEPTS);
    var hasInterest = (net && net.value > 0) || (income && expense && income.value > 0 && expense.value > 0);
    var hasNoninterest = (nonIncome && nonIncome.value > 0) || (nonExpense && nonExpense.value > 0);
    return !!(hasInterest && hasNoninterest);
  }

  function insuranceReady(pick) {
    var premiums = pick.dur(PREMIUM_CONCEPTS);
    var benefits = pick.dur(BENEFIT_CONCEPTS) || pick.dur(BENEFIT_TOTAL_CONCEPTS);
    return !!(premiums && premiums.value > 0 && benefits && benefits.value > 0);
  }

  function provisionChoice(pick, rev, nonExpense, pretax) {
    var total = pick.dur(PROVISION_TOTAL_CONCEPTS);
    var loan = pick.dur(PROVISION_LOAN_CONCEPTS);
    var off = pick.dur(PROVISION_OFF_CONCEPTS);
    var options = [];
    function pushOption(kind, parts) {
      var kept = [];
      var value = 0;
      parts.forEach(function (part) {
        if (part && part.value > ABSORB) {
          kept.push(part);
          value += part.value;
        }
      });
      if (kept.length) options.push({ kind: kind, parts: kept, value: value });
    }
    if (total) pushOption("total", [total]);
    if (loan || (off && off.value > ABSORB)) pushOption("parts", [loan, off]);
    if (loan) pushOption("loan", [loan]);
    if (!options.length) return { kind: "none", parts: [], value: 0, total: total, loan: loan, off: off };
    if (rev && nonExpense && pretax) {
      var implied = rev.value - nonExpense.value - pretax.value;
      options.sort(function (a, b) {
        return Math.abs(a.value - implied) - Math.abs(b.value - implied);
      });
    }
    options[0].total = total;
    options[0].loan = loan;
    options[0].off = off;
    return options[0];
  }

  function unfinishedIncome(message, notes, rows, period) {
    return {
      id: "income",
      title: "利润表",
      status: "partial",
      notes: [message].concat(notes || []),
      nodes: [],
      links: [],
      rows: rows || [],
      period: period
    };
  }

  function incomeResult(notes, nodes, links, rows, period) {
    finalize(nodes, links);
    return {
      id: "income",
      title: "利润表",
      status: mappingStatus(notes),
      notes: notes,
      nodes: nodes,
      links: links,
      rows: rows,
      period: period
    };
  }

  function linkBottom(prefix, column, pretaxId, pretax, tax, ni, nodes, links, rows, notes) {
    var niPart = { value: ni.value };
    var taxPart = tax.value > ABSORB ? { value: tax.value } : null;
    var parts = [niPart];
    if (taxPart) parts.push(taxPart);
    var bottom = absorb(parts, pretax.value);
    if (bottom.plug < -ABSORB) return false;
    nodes.push({
      id: prefix + "ni",
      label: "净利润",
      en: english(ni, "Net income"),
      column: column,
      order: 10,
      tone: "in",
      concept: ni.concept,
      signed: ni.value
    });
    addLink(links, pretaxId, prefix + "ni", niPart.value);
    if (taxPart && taxPart.value > ABSORB) {
      nodes.push({
        id: prefix + "tax",
        label: "所得税",
        en: english(tax, "Income tax expense"),
        column: column,
        order: 20,
        tone: "out",
        concept: tax.concept,
        signed: tax.value
      });
      addLink(links, pretaxId, prefix + "tax", taxPart.value);
    }
    if (bottom.plug > ABSORB) {
      nodes.push({
        id: prefix + "bottom_plug",
        label: "税后轧差",
        en: "Pretax reconciliation",
        column: column,
        order: 30,
        tone: "plug",
        concept: "",
        signed: bottom.plug,
        plug: true,
        formula: "税前利润 − 所得税 − 净利润"
      });
      addLink(links, pretaxId, prefix + "bottom_plug", bottom.plug);
      rows.push(row("税后轧差", "Pretax reconciliation", "", bottom.plug, "plug", "税前利润 − 所得税 − 净利润"));
      notes.push("税前利润减所得税与净利润还有差额，已标成轧差。净利润取归属母公司的金额，差额里常有少数股东损益。");
    }
    return true;
  }

  function buildBankIncome(facts, period) {
    var pick = makePicker(facts, period);
    var notes = [];
    var rows = [];
    var rev = pick.dur(REVENUE_CONCEPTS);
    var interestIncome = pick.dur(INTEREST_INCOME_CONCEPTS);
    var interestExpense = pick.dur(INTEREST_EXPENSE_CONCEPTS);
    var netInterest = pick.dur(NET_INTEREST_CONCEPTS);
    var noninterestIncome = pick.dur(NONINTEREST_INCOME_CONCEPTS);
    var noninterestExpense = pick.dur(NONINTEREST_EXPENSE_CONCEPTS);
    var pretax = pick.durKeepZero(PRETAX_CONCEPTS);
    var tax = pick.durKeepZero(TAX_CONCEPTS);
    var ni = pick.durKeepZero(NET_INCOME_CONCEPTS);
    var grossInterest = !!(interestIncome && interestExpense && interestIncome.value > 0 && interestExpense.value > 0);

    if (!netInterest && grossInterest && interestIncome.value - interestExpense.value > 0) {
      netInterest = {
        concept: "",
        en: "Net interest income",
        value: interestIncome.value - interestExpense.value,
        computed: true
      };
    }
    if (!noninterestIncome && rev && netInterest && rev.value - netInterest.value > ABSORB) {
      noninterestIncome = {
        concept: "",
        en: "Noninterest income",
        value: rev.value - netInterest.value,
        computed: true
      };
    }
    if (!rev && netInterest && noninterestIncome) {
      rev = {
        concept: "",
        en: "Revenues",
        value: netInterest.value + noninterestIncome.value,
        computed: true
      };
    }

    function fail(message) {
      return unfinishedIncome(message, notes, mergeRows(rows, recognizedIncomeRows(pick)), period);
    }

    if (grossInterest) {
      rows.push(row("利息收入", english(interestIncome, "Interest income, operating"), interestIncome.concept, interestIncome.value, "sec"));
      rows.push(row("利息支出", english(interestExpense, "Interest expense, operating"), interestExpense.concept, interestExpense.value, "sec"));
    }
    if (netInterest) {
      rows.push(row(
        "净利息收入",
        english(netInterest, "Net interest income"),
        netInterest.concept,
        netInterest.value,
        netInterest.computed ? "plug" : "subtotal",
        netInterest.computed ? "利息收入 − 利息支出" : ""
      ));
    }
    if (noninterestIncome) {
      rows.push(row(
        "非利息收入",
        english(noninterestIncome, "Noninterest income"),
        noninterestIncome.concept,
        noninterestIncome.value,
        noninterestIncome.computed ? "plug" : "sec",
        noninterestIncome.computed ? "营业收入 − 净利息收入" : ""
      ));
    }
    if (rev) {
      rows.push(row("营业收入", english(rev, "Revenues"), rev.concept, rev.value, rev.computed ? "plug" : "subtotal", "净利息收入 + 非利息收入"));
    }

    var choice = provisionChoice(pick, rev, noninterestExpense, pretax);
    if (choice.kind === "total" && choice.total) {
      rows.push(row("信贷拨备", english(choice.total, "Provision for credit losses"), choice.total.concept, choice.total.value, "sec"));
      if (choice.loan && choice.loan.concept !== choice.total.concept) {
        rows.push(row("贷款信贷损失", english(choice.loan, "Loan credit loss expense"), choice.loan.concept, choice.loan.value, "sec", "分项，色带按信贷拨备合计绘制"));
      }
      if (choice.off && choice.off.value !== 0) {
        rows.push(row("表外信用损失", english(choice.off, "Off-balance-sheet credit loss"), choice.off.concept, choice.off.value, "sec", "分项，色带按信贷拨备合计绘制"));
      }
    } else if (choice.value > ABSORB) {
      if (choice.parts.length === 1) {
        var only = choice.parts[0];
        rows.push(row("信贷拨备", english(only, "Provision for credit losses"), only.concept, only.value, "sec"));
      } else {
        choice.parts.forEach(function (part) {
          var offConcept = choice.off && choice.off.concept;
          var label = part.concept === offConcept ? "表外信用损失" : "贷款信贷损失";
          var fallback = label === "表外信用损失" ? "Off-balance-sheet credit loss" : "Loan credit loss expense";
          rows.push(row(label, english(part, fallback), part.concept, part.value, "sec"));
        });
        rows.push(row("信贷拨备", "Provision for credit losses", "", choice.value, "subtotal", "贷款信贷损失 + 表外信用损失"));
      }
    } else {
      if (choice.loan && choice.loan.value !== 0) {
        rows.push(row("信贷拨备", english(choice.loan, "Provision for credit losses"), choice.loan.concept, choice.loan.value, "sec"));
      }
      if (choice.off && choice.off.value !== 0) {
        rows.push(row("表外信用损失", english(choice.off, "Off-balance-sheet credit loss"), choice.off.concept, choice.off.value, "sec"));
      }
    }
    if (choice.off && choice.off.value < -ABSORB) {
      notes.push("表外信用损失为负，表示转回，没有画成流出。");
    }
    if (noninterestExpense) rows.push(row("非利息费用", english(noninterestExpense, "Noninterest expense"), noninterestExpense.concept, noninterestExpense.value, "sec"));
    if (pretax) rows.push(row("税前利润", english(pretax, "Income before tax"), pretax.concept, pretax.value, "subtotal"));
    if (tax) rows.push(row("所得税费用", english(tax, "Income tax expense"), tax.concept, tax.value, "sec"));
    if (ni) rows.push(row("净利润", english(ni, "Net income"), ni.concept, ni.value, "subtotal"));

    if (!netInterest || netInterest.value <= 0 || !noninterestIncome || noninterestIncome.value <= 0 || !rev || rev.value <= 0) {
      return fail("已取到银行类利润表数据，但净利息收入、非利息收入或营业收入不完整，没有画成桑基图。下表是已经识别的科目，并不是没取到数据。");
    }
    if (!noninterestExpense || noninterestExpense.value <= 0) {
      return fail("已取到银行类利润表数据，但没有正的非利息费用，没有画成桑基图。下表是已经识别的科目，并不是没取到数据。");
    }
    if (!pretax || pretax.value <= 0 || !tax || tax.value < 0 || !ni || ni.value <= 0) {
      return fail("已取到银行类利润表数据，但税前利润、所得税或净利润不完整，或盈亏方向和当前图不一致，没有画成桑基图。下表是已经识别的科目，并不是没取到数据。");
    }

    var interestGap = 0;
    if (grossInterest) {
      interestGap = interestIncome.value - netInterest.value - interestExpense.value;
      if (interestGap < -ABSORB) {
        return fail("已取到银行类利润表数据，但利息收入盖不住净利息收入和利息支出，没有绘制，以免色带宽和金额对不上。下表是已经识别的科目，并不是没取到数据。");
      }
    }
    var revenueGap = rev.value - netInterest.value - noninterestIncome.value;
    if (revenueGap < -ABSORB) {
      return fail("已取到银行类利润表数据，但净利息收入与非利息收入之和超过营业收入，没有绘制，以免重复加总。下表是已经识别的科目，并不是没取到数据。");
    }
    var provisionValue = choice.value > ABSORB ? choice.value : 0;
    if (provisionValue > rev.value) {
      return fail("已取到银行类利润表数据，但信贷拨备大于营业收入，没有绘制。下表是已经识别的科目，并不是没取到数据。");
    }
    var bridgeGap = rev.value - provisionValue - noninterestExpense.value - pretax.value;
    if (bridgeGap < -ABSORB && rev.value - provisionValue - noninterestExpense.value <= ABSORB) {
      return fail("已取到银行类利润表数据，但信贷拨备和非利息费用已经盖过营业收入，没有绘制。下表是已经识别的科目，并不是没取到数据。");
    }

    notes.push("按银行口径绘制：利息收入减去利息支出得到净利息收入，再加上非利息收入。这里的营业收入已经扣过利息支出，还没有扣信贷拨备和非利息费用。");
    var nodes = [];
    var links = [];
    var revenueColumn = grossInterest ? 2 : 1;

    if (grossInterest) {
      var expenseLink = interestExpense.value;
      if (interestGap > 2 && interestGap <= ABSORB) expenseLink += interestGap;
      nodes.push({ id: "bk_iint", label: "利息收入", en: english(interestIncome, "Interest income, operating"), column: 0, order: 10, tone: "in", concept: interestIncome.concept, signed: interestIncome.value });
      nodes.push({ id: "bk_nii", label: "净利息收入", en: english(netInterest, "Net interest income"), column: 1, order: 10, tone: "total", concept: netInterest.concept || "", signed: netInterest.value, formula: netInterest.computed ? "利息收入 − 利息支出" : "" });
      nodes.push({ id: "bk_iexp", label: "利息支出", en: english(interestExpense, "Interest expense, operating"), column: 1, order: 20, tone: "out", concept: interestExpense.concept, signed: interestExpense.value });
      addLink(links, "bk_iint", "bk_nii", netInterest.value);
      addLink(links, "bk_iint", "bk_iexp", expenseLink);
      if (interestGap > ABSORB) {
        nodes.push({ id: "bk_int_plug", label: "利息收入轧差", en: "Interest income reconciliation", column: 1, order: 30, tone: "plug", concept: "", signed: interestGap, plug: true, formula: "利息收入 − 净利息收入 − 利息支出" });
        addLink(links, "bk_iint", "bk_int_plug", interestGap);
        rows.push(row("利息收入轧差", "Interest income reconciliation", "", interestGap, "plug", "利息收入 − 净利息收入 − 利息支出"));
        notes.push("利息收入与净利息收入、利息支出不完全相加，差额已标成轧差。");
      }
    } else {
      nodes.push({ id: "bk_nii", label: "净利息收入", en: english(netInterest, "Net interest income"), column: 0, order: 10, tone: "in", concept: netInterest.concept || "", signed: netInterest.value });
    }

    var nonintLink = noninterestIncome.value;
    if (revenueGap > 2 && revenueGap <= ABSORB) nonintLink += revenueGap;
    nodes.push({
      id: "bk_nonint",
      label: "非利息收入",
      en: english(noninterestIncome, "Noninterest income"),
      column: grossInterest ? 1 : 0,
      order: grossInterest ? 40 : 20,
      tone: noninterestIncome.computed ? "plug" : "in",
      concept: noninterestIncome.concept || "",
      signed: noninterestIncome.value,
      plug: !!noninterestIncome.computed,
      formula: noninterestIncome.computed ? "营业收入 − 净利息收入" : ""
    });
    nodes.push({
      id: "bk_rev",
      label: "营业收入",
      en: english(rev, "Revenues"),
      column: revenueColumn,
      order: 10,
      tone: "total",
      concept: rev.concept || "",
      signed: rev.value,
      formula: "净利息收入 + 非利息收入"
    });
    addLink(links, "bk_nii", "bk_rev", netInterest.value);
    addLink(links, "bk_nonint", "bk_rev", nonintLink);
    if (revenueGap > ABSORB) {
      nodes.push({ id: "bk_rev_plug", label: "其他收入（轧差）", en: "Other revenue", column: grossInterest ? 1 : 0, order: 50, tone: "plug", concept: "", signed: revenueGap, plug: true, formula: "营业收入 − 净利息收入 − 非利息收入" });
      addLink(links, "bk_rev_plug", "bk_rev", revenueGap);
      rows.push(row("其他收入（轧差）", "Other revenue", "", revenueGap, "plug", "营业收入 − 净利息收入 − 非利息收入"));
      notes.push("营业收入与净利息收入、非利息收入不完全相加，差额已标成轧差。");
    }

    var useColumn = revenueColumn + 1;
    var expenseDraw = noninterestExpense.value;
    if (bridgeGap > 2 && bridgeGap <= ABSORB) expenseDraw += bridgeGap;
    if (bridgeGap < -2 && bridgeGap >= -ABSORB && expenseDraw + bridgeGap > ABSORB) expenseDraw += bridgeGap;
    nodes.push({ id: "bk_pretax", label: "税前利润", en: english(pretax, "Income before tax"), column: useColumn, order: 10, tone: "total", concept: pretax.concept, signed: pretax.value });
    if (provisionValue > ABSORB) {
      nodes.push({
        id: "bk_prov",
        label: "信贷拨备",
        en: "Provision for credit losses",
        column: useColumn,
        order: 20,
        tone: "out",
        concept: choice.kind === "total" && choice.total ? choice.total.concept : "",
        signed: provisionValue,
        formula: choice.parts.length > 1 ? "贷款信贷损失 + 表外信用损失" : ""
      });
      addLink(links, "bk_rev", "bk_prov", provisionValue);
    } else {
      notes.push("没有读到可绘制的信贷拨备，图上没有单列这一条。");
    }
    nodes.push({ id: "bk_niexp", label: "非利息费用", en: english(noninterestExpense, "Noninterest expense"), column: useColumn, order: 30, tone: "out", concept: noninterestExpense.concept, signed: noninterestExpense.value });
    addLink(links, "bk_rev", "bk_niexp", expenseDraw);

    if (bridgeGap > ABSORB) {
      nodes.push({ id: "bk_bridge_plug", label: "其他项目（轧差）", en: "Other income statement items", column: useColumn, order: 40, tone: "plug", concept: "", signed: bridgeGap, plug: true, formula: "营业收入 − 信贷拨备 − 非利息费用 − 税前利润" });
      addLink(links, "bk_rev", "bk_bridge_plug", bridgeGap);
      rows.push(row("其他项目（轧差）", "Other income statement items", "", bridgeGap, "plug", "营业收入 − 信贷拨备 − 非利息费用 − 税前利润"));
      notes.push("营业收入减去信贷拨备和非利息费用之后，与税前利润还有差额，已标成轧差。这里可能包含减值或其他没有逐项展开的损益。");
      addLink(links, "bk_rev", "bk_pretax", pretax.value);
    } else if (bridgeGap >= -ABSORB) {
      addLink(links, "bk_rev", "bk_pretax", pretax.value);
    } else {
      var direct = rev.value - provisionValue - noninterestExpense.value;
      addLink(links, "bk_rev", "bk_pretax", direct);
      var extra = -bridgeGap;
      nodes.push({ id: "bk_bridge_in", label: "其他收益（轧差）", en: "Other income", column: revenueColumn, order: 40, tone: "plug", concept: "", signed: extra, plug: true, formula: "税前利润 −（营业收入 − 信贷拨备 − 非利息费用）" });
      addLink(links, "bk_bridge_in", "bk_pretax", extra);
      rows.push(row("其他收益（轧差）", "Other income", "", extra, "plug", "税前利润 −（营业收入 − 信贷拨备 − 非利息费用）"));
      notes.push("税前利润高于营业收入减去信贷拨备和非利息费用后的结果，多出的部分已标成轧差。");
    }

    if (!linkBottom("bk_", useColumn + 1, "bk_pretax", pretax, tax, ni, nodes, links, rows, notes)) {
      return fail("已取到银行类利润表数据，但所得税与净利润之和大于税前利润，没有绘制，以免色带宽和金额对不上。下表是已经识别的科目，并不是没取到数据。");
    }
    return incomeResult(notes, nodes, links, rows, period);
  }

  function buildInsuranceIncome(facts, period) {
    var pick = makePicker(facts, period);
    var notes = [];
    var rows = [];
    var rev = pick.dur(REVENUE_CONCEPTS);
    var premiums = pick.dur(PREMIUM_CONCEPTS);
    var investment = pick.dur(INVESTMENT_INCOME_CONCEPTS);
    var otherIncome = pick.dur(OTHER_INCOME_CONCEPTS);
    var benefits = pick.dur(BENEFIT_CONCEPTS);
    var benefitTotal = pick.dur(BENEFIT_TOTAL_CONCEPTS);
    var underwriting = pick.dur(UNDERWRITING_CONCEPTS);
    var opex = pick.dur(["OperatingExpenses"]);
    var dac = pick.dur(DAC_CONCEPTS);
    var pretax = pick.durKeepZero(PRETAX_CONCEPTS);
    var tax = pick.durKeepZero(TAX_CONCEPTS);
    var ni = pick.durKeepZero(NET_INCOME_CONCEPTS);

    function addLine(label, hit) {
      if (!hit) return;
      rows.push(row(label, english(hit, label), hit.concept, hit.value, "sec"));
    }
    addLine("已赚保费", premiums);
    addLine("净投资收益", investment);
    addLine("其他收入", otherIncome);
    if (rev) rows.push(row("营业收入", english(rev, "Revenues"), rev.concept, rev.value, "subtotal"));
    addLine("保单给付与赔款", benefits);
    addLine("给付、损失与费用", benefitTotal);
    addLine("承保费用", underwriting);
    addLine("营业费用", opex);
    addLine("递延保单获取成本摊销", dac);
    if (pretax) rows.push(row("税前利润", english(pretax, "Income before tax"), pretax.concept, pretax.value, "subtotal"));
    if (tax) rows.push(row("所得税费用", english(tax, "Income tax expense"), tax.concept, tax.value, "sec"));
    if (ni) rows.push(row("净利润", english(ni, "Net income"), ni.concept, ni.value, "subtotal"));

    function fail(message) {
      return unfinishedIncome(message, notes, mergeRows(rows, recognizedIncomeRows(pick)), period);
    }
    if (!rev || rev.value <= 0 || !premiums || premiums.value <= 0) {
      return fail("已取到保险类利润表数据，但已赚保费或营业收入不完整，没有画成桑基图。下表是已经识别的科目，并不是没取到数据。");
    }
    if (!pretax || pretax.value <= 0 || rev.value - pretax.value <= ABSORB) {
      return fail("已取到保险类利润表数据，但税前利润不完整，没有画成桑基图。下表是已经识别的科目，并不是没取到数据。");
    }
    if (!tax || tax.value < 0 || !ni || ni.value <= 0) {
      return fail("已取到保险类利润表数据，但所得税或净利润不完整，或盈亏方向和当前图不一致，没有画成桑基图。下表是已经识别的科目，并不是没取到数据。");
    }

    var revenueParts = [];
    function pushPart(list, id, label, hit, order) {
      if (!hit || hit.value <= ABSORB) return;
      list.push({ id: id, label: label, en: english(hit, label), concept: hit.concept, value: hit.value, order: order });
    }
    pushPart(revenueParts, "ins_prem", "已赚保费", premiums, 10);
    pushPart(revenueParts, "ins_invest", "净投资收益", investment, 20);
    pushPart(revenueParts, "ins_other", "其他收入", otherIncome, 30);
    var revenueSplit = absorb(revenueParts, rev.value);
    if (revenueSplit.plug < -ABSORB) {
      return fail("已取到保险类利润表数据，但已赚保费和投资收益等加总超过营业收入，没有绘制，以免重复加总。下表是已经识别的科目，并不是没取到数据。");
    }
    if (revenueSplit.plug > ABSORB) {
      revenueSplit.parts.push({ id: "ins_rev_plug", label: "其他收入（轧差）", en: "Other revenue", concept: "", value: revenueSplit.plug, order: 40, plug: true, formula: "营业收入 − 已列示收入" });
      rows.push(row("其他收入（轧差）", "Other revenue", "", revenueSplit.plug, "plug", "营业收入 − 已列示收入"));
      notes.push("营业收入与已列示的保费和投资收益不完全相加，差额已标成轧差。");
    }

    var budget = rev.value - pretax.value;
    var expenseParts = [];
    pushPart(expenseParts, "ins_ben", "保单给付与赔款", benefits, 20);
    pushPart(expenseParts, "ins_uw", "承保费用", underwriting, 30);
    pushPart(expenseParts, "ins_opex", "营业费用", opex, 40);
    pushPart(expenseParts, "ins_dac", "递延保单获取成本摊销", dac, 50);
    if (!expenseParts.length && benefitTotal && benefitTotal.value > ABSORB) {
      expenseParts.push({
        id: "ins_ble",
        label: "给付、损失与费用",
        en: english(benefitTotal, "Benefits, losses and expenses"),
        concept: benefitTotal.concept,
        value: benefitTotal.value,
        order: 20
      });
    }
    expenseParts.residualId = "ins_exp_plug";
    expenseParts.residualLabel = "其他给付与费用（轧差）";
    expenseParts.residualFormula = "营业收入 − 税前利润 − 已列示给付与费用";
    var fitted = fitGroup(budget, expenseParts);
    fitted.skipped.forEach(function (text) { notes.push(text); });
    var expenseSplit = absorb(fitted.picked, budget);
    if (expenseSplit.plug < -ABSORB) {
      return fail("已取到保险类利润表数据，但给付和费用加总超过营业收入减税前利润，没有绘制，以免重复加总。下表是已经识别的科目，并不是没取到数据。");
    }
    if (expenseSplit.plug > ABSORB) {
      expenseSplit.parts.push({ id: "ins_exp_plug", label: "其他给付与费用（轧差）", en: "Other benefits and expenses", concept: "", value: expenseSplit.plug, order: 90, plug: true, formula: "营业收入 − 税前利润 − 已列示给付与费用" });
      rows.push(row("其他给付与费用（轧差）", "Other benefits and expenses", "", expenseSplit.plug, "plug", "营业收入 − 税前利润 − 已列示给付与费用"));
      notes.push("给付与费用的已列示项目和税前利润相加后，与营业收入还有差额，已标成轧差。");
    } else if (fitted.picked.some(function (part) { return part.plug; })) {
      var residual = fitted.picked.filter(function (part) { return part.plug; })[0];
      rows.push(row(residual.label, residual.en, "", residual.value, "plug", residual.formula || ""));
      notes.push("给付与费用的已列示项目和税前利润相加后，与营业收入还有差额，已标成轧差。");
    }

    notes.unshift("按保险口径绘制：已赚保费、净投资收益等先汇总成营业收入，再减给付与费用得到税前利润。");
    var nodes = [];
    var links = [];
    revenueSplit.parts.forEach(function (part) {
      nodes.push({ id: part.id, label: part.label, en: part.en, column: 0, order: part.order, tone: part.plug ? "plug" : "in", concept: part.concept || "", signed: part.value, plug: !!part.plug, formula: part.formula || "" });
    });
    nodes.push({ id: "ins_rev", label: "营业收入", en: english(rev, "Revenues"), column: 1, order: 10, tone: "total", concept: rev.concept, signed: rev.value });
    revenueSplit.parts.forEach(function (part) { addLink(links, part.id, "ins_rev", part.value); });
    nodes.push({ id: "ins_pretax", label: "税前利润", en: english(pretax, "Income before tax"), column: 2, order: 10, tone: "total", concept: pretax.concept, signed: pretax.value });
    addLink(links, "ins_rev", "ins_pretax", pretax.value);
    expenseSplit.parts.forEach(function (part) {
      nodes.push({ id: part.id, label: part.label, en: part.en || "Reconciliation residual", column: 2, order: part.order || 90, tone: part.plug ? "plug" : "out", concept: part.concept || "", signed: part.value, plug: !!part.plug, formula: part.formula || "" });
      addLink(links, "ins_rev", part.id, part.value);
    });
    if (!linkBottom("ins_", 3, "ins_pretax", pretax, tax, ni, nodes, links, rows, notes)) {
      return fail("已取到保险类利润表数据，但所得税与净利润之和大于税前利润，没有绘制，以免色带宽和金额对不上。下表是已经识别的科目，并不是没取到数据。");
    }
    return incomeResult(notes, nodes, links, rows, period);
  }

  function buildIncome(facts, period) {
    var pick = makePicker(facts, period);
    var rev = pick.dur(REVENUE_CONCEPTS);
    var statement;
    if (!rev) {
      statement = emptyStatement("income", "利润表", "error", "这一报告期没有找到营业收入等科目，画不出利润表。");
    } else if (industrialReady(pick, rev)) {
      statement = buildIndustrialIncome(facts, period);
    } else if (bankReady(pick)) {
      statement = buildBankIncome(facts, period);
    } else if (insuranceReady(pick)) {
      statement = buildInsuranceIncome(facts, period);
    } else {
      statement = emptyStatement("income", "利润表", "partial", UNSUPPORTED_INCOME);
    }
    if (!statement.nodes || !statement.nodes.length) {
      statement.rows = mergeRows(statement.rows, recognizedIncomeRows(pick));
      if (statement.rows.length) statement.status = "partial";
    }
    return statement;
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

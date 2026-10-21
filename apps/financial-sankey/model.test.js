/* node apps/financial-sankey/model.test.js */
"use strict";

var fs = require("fs");
var path = require("path");
var model = require("./model.js");
var sankey = require("./sankey.js");

var root = __dirname;
var failed = 0;

function assert(cond, message) {
  if (!cond) {
    failed += 1;
    console.error("FAIL", message);
  }
}

function load(name) {
  return JSON.parse(fs.readFileSync(path.join(root, name), "utf8"));
}

function valueOf(statement, label) {
  var hit = statement.rows.filter(function (row) { return row.label === label; })[0];
  return hit ? hit.value : null;
}

function checkCompany(ticker, file) {
  var doc = load(file);
  assert(doc.extract && doc.extract.demo === false, ticker + " extract is real");
  assert(doc.facts && doc.facts["us-gaap"], ticker + " has us-gaap");
  var reports = model.buildReports(doc);
  assert(reports.annual, ticker + " annual");
  assert(reports.quarterly, ticker + " quarterly");
  ["annual", "quarterly"].forEach(function (key) {
    var report = reports[key];
    ["income", "balance", "cashflow"].forEach(function (id) {
      var statement = report.statements[id];
      assert(statement.status !== "error", ticker + " " + key + " " + id + " " + (statement.notes || []).join(" | "));
      var problems = model.auditStatement(statement);
      assert(problems.length === 0, ticker + " " + key + " " + id + " audit " + problems.join(", "));
      var layout = sankey.layoutSankey(statement, 1100);
      assert(layout.nodes.length === statement.nodes.length, ticker + " layout nodes");
      layout.links.forEach(function (link) {
        assert(link.path && link.path.indexOf("NaN") < 0, ticker + " path");
        assert(link.sh > 0 && link.th > 0, ticker + " thickness");
      });
      layout.nodes.forEach(function (node) {
        assert(isFinite(node.x) && isFinite(node.y) && node.h > 0, ticker + " node box " + node.id);
      });
    });
  });
  return reports;
}

var tickers = load("tickers.json");
assert(tickers.NVDA[0] === 1045810, "NVDA cik");
assert(tickers.MSFT[0] === 789019, "MSFT cik");
assert(tickers.NVDA[1] === "NVIDIA CORP", "NVDA name");

var nvda = checkCompany("NVDA", "snapshots/nvda.json");
var msft = checkCompany("MSFT", "snapshots/msft.json");

assert(valueOf(nvda.annual.statements.income, "营业收入") === 215938000000, "NVDA revenue");
assert(valueOf(nvda.annual.statements.income, "净利润") === 120067000000, "NVDA net income");
assert(valueOf(nvda.annual.statements.balance, "资产总计") === 206803000000, "NVDA assets");
assert(valueOf(nvda.annual.statements.cashflow, "经营活动现金净额") === 102718000000, "NVDA cfo");
assert(valueOf(nvda.quarterly.statements.income, "营业收入") === 96221000000, "NVDA quarter revenue");
assert(nvda.quarterly.statements.cashflow.notes.some(function (note) { return note.indexOf("年初至") >= 0; }), "NVDA quarter cash is YTD");

assert(valueOf(msft.annual.statements.income, "营业收入") === 331839000000, "MSFT revenue");
assert(valueOf(msft.annual.statements.income, "净利润") === 133749000000, "MSFT net income");
assert(valueOf(msft.annual.statements.balance, "资产总计") === 758376000000, "MSFT assets");
assert(valueOf(msft.annual.statements.cashflow, "经营活动现金净额") === 182935000000, "MSFT cfo");

var empty = model.buildReports({ facts: { "us-gaap": {} } });
assert(!empty.annual && !empty.quarterly, "empty facts have no period");

function labelsOf(statement) {
  return statement.nodes.map(function (node) { return node.label; });
}

function checkDrawnIncome(ticker, file, frequency) {
  var doc = load(file);
  assert(doc.extract && doc.extract.demo === false, ticker + " fixture is real SEC extract");
  var reports = model.buildReports(doc);
  var report = reports[frequency || "annual"];
  assert(report, ticker + " " + (frequency || "annual"));
  var statement = report.statements.income;
  assert(statement.nodes.length > 0, ticker + " income nodes");
  assert(statement.links.length > 0, ticker + " income links");
  var problems = model.auditStatement(statement);
  assert(!problems.length, ticker + " income audit " + problems.join(", "));
  var layout = sankey.layoutSankey(statement, 360);
  layout.links.forEach(function (link) {
    assert(link.path && link.path.indexOf("NaN") < 0, ticker + " narrow path");
    assert(link.sh > 0 && link.th > 0, ticker + " narrow thickness");
  });
  var wide = sankey.layoutSankey(statement, 1280);
  assert(wide.nodes.length === statement.nodes.length, ticker + " wide nodes");
  return statement;
}

assert(labelsOf(nvda.annual.statements.income).indexOf("毛利") >= 0, "NVDA keeps gross profit");
assert((nvda.annual.statements.income.notes || []).join(" ").indexOf("银行口径") < 0, "NVDA is not a bank diagram");
assert(labelsOf(msft.annual.statements.income).indexOf("毛利") >= 0, "MSFT keeps gross profit");

var citi = checkDrawnIncome("C", "fixtures/c.json", "annual");
assert(citi.status === "partial", "C annual is partial because of the pretax plug");
assert(valueOf(citi, "利息收入") === 142864000000, "C interest income");
assert(valueOf(citi, "净利息收入") === 59792000000, "C net interest income");
assert(valueOf(citi, "非利息收入") === 25433000000, "C noninterest income");
assert(valueOf(citi, "营业收入") === 85225000000, "C revenue");
assert(valueOf(citi, "信贷拨备") === 9699000000, "C provision sums loan and off-balance sheet");
assert(valueOf(citi, "非利息费用") === 55132000000, "C noninterest expense");
assert(valueOf(citi, "净利润") === 14306000000, "C net income");
assert(citi.notes[0].indexOf("银行口径") >= 0, "C explains the bank shape");
assert(labelsOf(citi).indexOf("毛利") < 0, "C does not use gross profit");

var citiQuarter = checkDrawnIncome("C", "fixtures/c.json", "quarterly");
assert(valueOf(citiQuarter, "营业收入") === 22090000000, "C quarter revenue");
assert(valueOf(citiQuarter, "信贷拨备") === 2359000000, "C quarter provision");

var bac = checkDrawnIncome("BAC", "fixtures/bac.json", "annual");
assert(bac.status === "ok", "BAC annual ties out");
assert(valueOf(bac, "营业收入") === 113097000000, "BAC revenue");
assert(valueOf(bac, "信贷拨备") === 5675000000, "BAC provision");
assert(valueOf(bac, "净利润") === 30509000000, "BAC net income");
assert(labelsOf(bac).indexOf("利息收入") >= 0 && labelsOf(bac).indexOf("净利息收入") >= 0, "BAC sankey labels");

var jpm = checkDrawnIncome("JPM", "fixtures/jpm.json", "annual");
assert(jpm.status === "ok", "JPM annual ties out");
assert(valueOf(jpm, "信贷拨备") === 14212000000, "JPM uses the total provision");
assert(valueOf(jpm, "贷款信贷损失") === 11264000000, "JPM still lists the loan component");
assert(valueOf(jpm, "表外信用损失") === 2969000000, "JPM still lists off-balance-sheet credit loss");
assert(valueOf(jpm, "净利润") === 57048000000, "JPM net income");

var aapl = checkDrawnIncome("AAPL", "fixtures/aapl.json", "annual");
assert(aapl.status === "ok", "AAPL income still ok");
assert(valueOf(aapl, "营业收入") === 416161000000, "AAPL revenue");
assert(valueOf(aapl, "毛利") === 195201000000, "AAPL gross profit");
assert(valueOf(aapl, "净利润") === 112010000000, "AAPL net income");
assert(labelsOf(aapl).indexOf("毛利") >= 0, "AAPL sankey uses gross profit");
assert(labelsOf(aapl).indexOf("净利息收入") < 0, "AAPL does not take the bank path");

var pgr = checkDrawnIncome("PGR", "fixtures/pgr.json", "annual");
assert(valueOf(pgr, "已赚保费") === 81661000000, "PGR premiums");
assert(valueOf(pgr, "营业收入") === 87671000000, "PGR revenue");
assert(valueOf(pgr, "净利润") === 11308000000, "PGR net income");
assert(labelsOf(pgr).indexOf("已赚保费") >= 0, "PGR sankey shows premiums");
assert(pgr.notes[0].indexOf("保险口径") >= 0, "PGR explains the insurance shape");

var met = checkDrawnIncome("MET", "fixtures/met.json", "annual");
assert(valueOf(met, "已赚保费") === 49779000000, "MET premiums");
assert(valueOf(met, "净投资收益") === 22559000000, "MET investment income");
assert(valueOf(met, "净利润") === 3379000000, "MET net income");
assert(labelsOf(met).indexOf("保单给付与赔款") >= 0, "MET sankey shows policyholder benefits");

function usdFact(value) {
  return {
    label: "Amount",
    units: {
      USD: [{
        start: "2024-01-01",
        end: "2024-12-31",
        val: value,
        form: "10-K",
        filed: "2025-02-01",
        fy: 2024,
        fp: "FY"
      }]
    }
  };
}

var unmapped = model.buildReports({
  facts: {
    "us-gaap": {
      Revenues: usdFact(5000000000),
      ResearchAndDevelopmentExpense: usdFact(800000000),
      IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest: usdFact(1200000000),
      IncomeTaxExpenseBenefit: usdFact(200000000),
      NetIncomeLoss: usdFact(1000000000)
    }
  }
}).annual.statements.income;
assert(!unmapped.nodes.length, "unmapped income draws no sankey");
assert(unmapped.status === "partial", "unmapped income is partial, not an empty fetch");
assert(unmapped.rows.length >= 4, "unmapped income keeps recognized rows");
assert(valueOf(unmapped, "营业收入") === 5000000000, "unmapped revenue row");
assert(valueOf(unmapped, "研发费用") === 800000000, "unmapped R&D row");
assert(valueOf(unmapped, "税前利润") === 1200000000, "unmapped pretax row");
assert(valueOf(unmapped, "所得税费用") === 200000000, "unmapped tax row");
assert(valueOf(unmapped, "净利润") === 1000000000, "unmapped net income row");
assert(unmapped.notes[0].indexOf("已取到") >= 0, "unmapped copy says the data arrived");
assert(unmapped.notes[0].indexOf("并不是没取到数据") >= 0, "unmapped copy is not a missing-data error");
assert(unmapped.notes.join(" ").indexOf("营业成本或毛利缺失") < 0, "old gross-profit failure copy is gone");

var revenueOnly = model.buildReports({
  facts: { "us-gaap": { Revenues: usdFact(1000000000) } }
}).annual.statements.income;
assert(!revenueOnly.nodes.length, "revenue-only company has no sankey");
assert(revenueOnly.rows.length >= 1, "revenue-only company still lists revenue");
assert(valueOf(revenueOnly, "营业收入") === 1000000000, "revenue-only amount");
assert(revenueOnly.notes[0].indexOf("并不是没取到数据") >= 0, "revenue-only copy");

var brokenBank = load("fixtures/c.json");
delete brokenBank.facts["us-gaap"].IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest;
delete brokenBank.facts["us-gaap"].IncomeTaxExpenseBenefit;
delete brokenBank.facts["us-gaap"].NetIncomeLoss;
var brokenIncome = model.buildReports(brokenBank).annual.statements.income;
assert(!brokenIncome.nodes.length, "bank missing the bottom line does not draw");
assert(brokenIncome.status === "partial", "incomplete bank map stays partial");
assert(valueOf(brokenIncome, "利息收入") === 142864000000, "incomplete bank still lists interest income");
assert(valueOf(brokenIncome, "非利息收入") === 25433000000, "incomplete bank still lists noninterest income");
assert(valueOf(brokenIncome, "非利息费用") === 55132000000, "incomplete bank still lists noninterest expense");
assert(valueOf(brokenIncome, "信贷拨备") === 9699000000, "incomplete bank still lists provision");
assert(brokenIncome.notes[0].indexOf("已取到") >= 0, "incomplete bank says data arrived");
assert(brokenIncome.notes[0].indexOf("并不是没取到数据") >= 0, "incomplete bank is not a fetch failure");

if (failed) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("ok", Object.keys(tickers).length, "tickers");
console.log("NVDA annual", nvda.annual.start, nvda.annual.end, nvda.annual.statements.income.status, nvda.annual.statements.balance.status, nvda.annual.statements.cashflow.status);
console.log("MSFT annual", msft.annual.start, msft.annual.end, msft.annual.statements.income.status, msft.annual.statements.balance.status, msft.annual.statements.cashflow.status);

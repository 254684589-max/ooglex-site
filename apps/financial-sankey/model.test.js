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

if (failed) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("ok", Object.keys(tickers).length, "tickers");
console.log("NVDA annual", nvda.annual.start, nvda.annual.end, nvda.annual.statements.income.status, nvda.annual.statements.balance.status, nvda.annual.statements.cashflow.status);
console.log("MSFT annual", msft.annual.start, msft.annual.end, msft.annual.statements.income.status, msft.annual.statements.balance.status, msft.annual.statements.cashflow.status);

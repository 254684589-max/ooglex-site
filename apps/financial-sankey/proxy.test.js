/* node apps/financial-sankey/proxy.test.js */
"use strict";

var fs = require("fs");
var path = require("path");

var root = __dirname;
var failed = 0;

function assert(cond, message) {
  if (!cond) {
    failed += 1;
    console.error("FAIL", message);
  }
}

var proxy = JSON.parse(fs.readFileSync(path.join(root, "proxy.json"), "utf8"));
var app = fs.readFileSync(path.join(root, "app.js"), "utf8");
var html = fs.readFileSync(path.join(root, "index.html"), "utf8");
var content = fs.readFileSync(path.join(root, "CONTENT.md"), "utf8");

assert(proxy.companyfacts === "https://sec-facts.ooglex.com/companyfacts/", "proxy.json edge URL");
assert(app.indexOf("companyfacts/") !== -1, "same-origin prefix");
assert(app.indexOf("https://sec-facts.ooglex.com/companyfacts/") !== -1, "edge fallback in app.js");
assert(app.indexOf("https://data.sec.gov/api/xbrl/companyfacts/") !== -1, "direct SEC still present");
assert(app.indexOf("snapshots/nvda.json") !== -1 && app.indexOf("snapshots/msft.json") !== -1, "snapshot fallback");
assert(app.indexOf('getElementById("facts-file")') !== -1, "local JSON picker is wired");
assert(html.indexOf('id="facts-file"') !== -1, "local JSON picker");
assert(html.indexOf("app.js?v=20261021sec") !== -1, "cache buster");
assert(html.indexOf("/apps/financial-sankey/companyfacts/CIK##########.json") !== -1, "footer documents same-origin path");
assert(content.indexOf("sec-facts.ooglex.com/companyfacts/CIK##########.json") !== -1, "CONTENT documents edge path");
assert(content.indexOf("User-Agent") !== -1, "CONTENT documents user agent");
assert(content.indexOf("6 小时") !== -1, "CONTENT documents cache");
assert(content.indexOf("whats-latest") === -1 && content.indexOf("最新消息") !== -1, "still keeps the news-nav boundary, without naming the pipeline");

if (failed) {
  console.error(failed + " failed");
  process.exit(1);
}
console.log("proxy contract ok");

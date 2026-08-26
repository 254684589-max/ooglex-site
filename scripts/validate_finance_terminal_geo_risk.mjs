#!/usr/bin/env node
/** 地缘风险定价的离线契约：四条轴的取数、映射、缺轴与过期传导。
    这里只用站内已发布的数据文件与手工构造的边界样本，不联网。 */

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  buildGeoRisk,
  clampScore,
  GEO_AXES,
  GEO_LEVELS,
  levelOf,
  linearScore,
  percentileScore
} from "../apps/finance-terminal/finance-terminal-geo-risk.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function readJson(relative) {
  return JSON.parse(await readFile(path.join(ROOT, relative), "utf8"));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

async function loadGroup() {
  return {
    assetTracker: { data: await readJson("apps/asset-tracker/data.json"), error: null },
    macro: { data: await readJson("apps/macro-radar/data.json"), error: null },
    ofr: { data: await readJson("apps/ofr-monitor/data.json"), error: null }
  };
}

function validateMappings() {
  assert.equal(linearScore(0, -15, 15), 50, "区间中点必须落在50分");
  assert.equal(linearScore(15, -15, 15), 100);
  assert.equal(linearScore(-15, -15, 15), 0);
  assert.equal(linearScore(60, -15, 15), 100, "超出上界必须取端点，不得给出100以上的分数");
  assert.equal(linearScore(-60, -15, 15), 0, "超出下界必须取端点");
  assert.equal(linearScore(null, -15, 15), null, "缺值不得被当作0");
  assert.equal(linearScore(Number.NaN, -15, 15), null);
  assert.equal(clampScore(101), 100);
  assert.equal(clampScore(-1), 0);

  const series = Array.from({ length: 20 }, (unused, index) => index + 1);
  assert.equal(percentileScore(series, 20), 100, "最大值应处于第100百分位");
  assert.equal(percentileScore(series, 1), 5);
  assert.equal(percentileScore(series, 10), 50);
  assert.equal(percentileScore(series.slice(0, 8), 5), null, "观测窗口过短时不得给出百分位");
  assert.equal(percentileScore(series, null), null);

  assert.equal(levelOf(0).key, "low");
  assert.equal(levelOf(19).key, "low");
  assert.equal(levelOf(20).key, "mild");
  assert.equal(levelOf(40).key, "mid");
  assert.equal(levelOf(60).key, "high");
  assert.equal(levelOf(80).key, "severe");
  assert.equal(levelOf(100).key, "severe");
  assert.equal(GEO_LEVELS.length, 5, "等级梯必须恰好五档");
  assert.equal(GEO_AXES.reduce((sum, axis) => sum + axis.weight, 0), 100, "四条轴权重之和必须为100");
}

function validateLiveModel(model) {
  assert.equal(model.available, true, "当前站内数据应当足以给出四条轴");
  assert.equal(model.axes.length, 4);
  assert.deepEqual(model.axes.map((axis) => axis.key), ["energy", "haven", "volatility", "stress"]);
  model.axes.forEach((axis) => {
    assert.ok(axis.score >= 0 && axis.score <= 100, `${axis.label}分数越界`);
    assert.ok(axis.rawText && axis.method, `${axis.label}必须给出原值与映射口径`);
    assert.ok(axis.sourceName, `${axis.label}必须写明来源`);
    assert.match(axis.asOf, /^\d{4}-\d{2}-\d{2}$/, `${axis.label}必须给出数据日`);
    assert.match(axis.updatedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/, `${axis.label}必须给出上游更新时间`);
  });
  const expected = Math.round(model.axes.reduce((sum, axis) => sum + axis.score * axis.weight, 0) / 100);
  assert.equal(model.score, expected, "总分必须是四条轴的等权平均，不得另行加权");
  assert.equal(model.level.key, levelOf(model.score).key);
  const dates = model.axes.map((axis) => axis.asOf).sort();
  assert.equal(model.asOf, dates[0], "整体数据日取四条轴里最旧的一条，不得用最新的一条代表全部");
}

function validateMissingAxes(group) {
  const noTracker = buildGeoRisk({ macro: group.macro, ofr: group.ofr });
  assert.equal(noTracker.available, false, "缺跨资产管道时不得给出等级");
  assert.equal(noTracker.score, null);
  assert.equal(noTracker.missing.length, 2, "能源溢价与避险需求都应被点名");
  assert.ok(noTracker.missing.every((text) => text.includes("：")));

  const brokenMacro = clone(group.macro.data);
  brokenMacro.signals = brokenMacro.signals.filter((signal) => signal.key !== "volatility");
  const noVolatility = buildGeoRisk({
    assetTracker: group.assetTracker,
    macro: { data: brokenMacro, error: null },
    ofr: group.ofr
  });
  assert.equal(noVolatility.available, false, "少一条轴也不得用其余三条的平均顶替");
  assert.ok(noVolatility.missing.join("").includes("波动率制度"));

  const shortOfr = clone(group.ofr.data);
  shortOfr.fsi.spark = shortOfr.fsi.spark.slice(0, 6);
  const thinWindow = buildGeoRisk({
    assetTracker: group.assetTracker,
    macro: group.macro,
    ofr: { data: shortOfr, error: null }
  });
  assert.equal(thinWindow.available, false, "观测窗口不足以定位百分位时必须如实说不可用");

  const failed = buildGeoRisk({
    assetTracker: { data: null, error: new Error("HTTP 500") },
    macro: group.macro,
    ofr: group.ofr
  });
  assert.equal(failed.available, false, "上游读取失败必须传导为不可用，不得回退到旧值");
}

function validateStaleAndSpread(group) {
  const stale = clone(group.assetTracker.data);
  stale.assets.filter((asset) => asset.symbol === "GC=F").forEach((asset) => { asset.stale = true; });
  const model = buildGeoRisk({
    assetTracker: { data: stale, error: null },
    macro: group.macro,
    ofr: group.ofr
  });
  assert.equal(model.available, true);
  assert.equal(model.stale, true, "任一轴的上游过期都必须在整体上标注出来");
  assert.equal(model.axes.filter((axis) => axis.key === "haven")[0].stale, true);

  const shifted = clone(group.assetTracker.data);
  shifted.assets.forEach((asset) => {
    if (asset.symbol === "GC=F") asset.returns.m1 = 20;
    if (asset.symbol === "^GSPC") asset.returns.m1 = -10;
    if (asset.symbol === "BZ=F") asset.returns.m1 = 30;
  });
  const stressed = buildGeoRisk({
    assetTracker: { data: shifted, error: null },
    macro: group.macro,
    ofr: group.ofr
  });
  const haven = stressed.axes.filter((axis) => axis.key === "haven")[0];
  const energy = stressed.axes.filter((axis) => axis.key === "energy")[0];
  assert.equal(haven.score, 100, "黄金大幅跑赢股票时避险需求必须到顶");
  assert.equal(energy.score, 100, "油价大涨时能源溢价必须到顶");
  assert.ok(haven.rawText.includes("+30.00个百分点"), "原值必须写明实际价差，而不是只给映射后的分数");
}

async function main() {
  const group = await loadGroup();
  const model = buildGeoRisk(group);
  validateMappings();
  validateLiveModel(model);
  validateMissingAxes(group);
  validateStaleAndSpread(group);
  console.log("Finance Terminal geopolitical risk pricing contract: PASS");
  console.log(`- four in-repo axes / equal weights / current level: ${model.score}/100 ${model.level.label}`);
  console.log("- explicit linear mappings / self-window percentile / clamped ends: PASS");
  console.log("- missing axis / thin window / upstream failure never yields a level: PASS");
  console.log("- stale propagation / raw value alongside every mapped score: PASS");
}

main().catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exitCode = 1;
});

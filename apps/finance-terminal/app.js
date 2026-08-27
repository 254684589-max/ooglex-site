(function (root) {
  "use strict";

  var DGS10_MAX_BUSINESS_DAYS = 3;
  /* DTWEXBGS 的观测是日度的，但美联储 H.10 按周成批发布：每周一次性补齐上一周的
     日度值。实测滞后天数每周在 1 到 5 个工作日之间循环（2026-08-16 与 08-22 两个
     周末均恰好滞后 5 个工作日，中间一次性从 08-07 跳到 08-14）。原阈值 3 是按日频
     假设定的，会让它从每周三四起一直误报到周日——每周约一半时间。
     改为 8：正常周期内不再误报，而一旦某周的批次真的没发布，两三天内仍会触发。 */
  var DTWEXBGS_MAX_BUSINESS_DAYS = 8;
  var RWTC_MAX_BUSINESS_DAYS = 4;
  var MACRO_REGIME_MAX_BUSINESS_DAYS = 2;
  var FEAR_GREED_MAX_BUSINESS_DAYS = 2;
  var OFR_FSI_MAX_BUSINESS_DAYS = 5;
  var ASSET_TRACKER_MAX_AGE_HOURS = 72;
  var ASSET_RANKING_MAX_AGE_HOURS = 72;
  var BITCOIN_MAX_AGE_HOURS = 36;
  var COMPANIES_MAX_AGE_HOURS = 72;
  var SOURCE_HEALTH_MAX_AGE_HOURS = {
    "macro-radar": 72,
    "asset-tracker": ASSET_TRACKER_MAX_AGE_HOURS,
    "asset-ranking": ASSET_RANKING_MAX_AGE_HOURS,
    companies: COMPANIES_MAX_AGE_HOURS
  };
  var PROVIDER_WIDGET_TAG = "tv-mini-chart";
  var PROVIDER_WIDGET_REGRESSION_TIMEOUT_MS = 150;
  var DATA_MODES = ["market", "fallback", "estimate", "unknown", "unavailable"];
  var DATA_STATUSES = ["ok", "partial", "stale", "error"];
  var DATA_FREQUENCIES = ["realtime", "delayed", "daily", "weekly", "monthly", "quarterly", "annual", "irregular"];
  var PIPELINE_HEALTH_STATUSES = ["healthy", "degraded", "failed"];
  var PIPELINE_HISTORY_STATUSES = ["tracked", "migrated"];
  var MACRO_HEALTH_MODES = ["market", "fallback", "unavailable", "unknown"];
  var MACRO_HEALTH_SOURCE_STATUSES = ["healthy", "degraded", "failed", "unknown"];
  var RWTC_ACCESS_METHODS = ["EIA API v2", "EIA public history page"];
  var OFFICIAL_SOURCE_HEALTH_SPECS = {
    DGS10: {
      provider: "FRED / Federal Reserve H.15", maxBusinessDays: 3, changeUnit: "bp"
    },
    DTWEXBGS: {
      provider: "FRED / Federal Reserve H.10", maxBusinessDays: 3, changeUnit: "percent"
    },
    RWTC: {
      provider: "U.S. EIA / Cushing WTI Spot", maxBusinessDays: 4, changeUnit: "percent"
    }
  };

  var SVG_NS = "http://www.w3.org/2000/svg";

  function isNumber(value) {
    return typeof value === "number" && Number.isFinite(value);
  }

  function parseIsoDate(value) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
    var date = new Date(value + "T00:00:00Z");
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function dateKey(value) {
    return value.toISOString().slice(0, 10);
  }

  function observedFixedHoliday(year, month, day) {
    var holiday = new Date(Date.UTC(year, month, day));
    if (holiday.getUTCDay() === 6) holiday.setUTCDate(holiday.getUTCDate() - 1);
    if (holiday.getUTCDay() === 0) holiday.setUTCDate(holiday.getUTCDate() + 1);
    return dateKey(holiday);
  }

  function nthWeekday(year, month, weekday, nth) {
    var date = new Date(Date.UTC(year, month, 1));
    var offset = (weekday - date.getUTCDay() + 7) % 7;
    date.setUTCDate(1 + offset + (nth - 1) * 7);
    return dateKey(date);
  }

  function lastWeekday(year, month, weekday) {
    var date = new Date(Date.UTC(year, month + 1, 0));
    var offset = (date.getUTCDay() - weekday + 7) % 7;
    date.setUTCDate(date.getUTCDate() - offset);
    return dateKey(date);
  }

  function usFederalHolidays(year) {
    return [
      observedFixedHoliday(year, 0, 1),
      nthWeekday(year, 0, 1, 3),
      nthWeekday(year, 1, 1, 3),
      lastWeekday(year, 4, 1),
      observedFixedHoliday(year, 5, 19),
      observedFixedHoliday(year, 6, 4),
      nthWeekday(year, 8, 1, 1),
      nthWeekday(year, 9, 1, 2),
      observedFixedHoliday(year, 10, 11),
      nthWeekday(year, 10, 4, 4),
      observedFixedHoliday(year, 11, 25)
    ];
  }

  function isUsBusinessDay(value) {
    var weekday = value.getUTCDay();
    if (weekday === 0 || weekday === 6) return false;
    var key = dateKey(value);
    var year = value.getUTCFullYear();
    var holidays = usFederalHolidays(year - 1).concat(usFederalHolidays(year), usFederalHolidays(year + 1));
    return holidays.indexOf(key) === -1;
  }

  function businessDaysSince(value, now) {
    var observed = parseIsoDate(value);
    var current = now instanceof Date ? new Date(now.getTime()) : new Date();
    if (!observed || Number.isNaN(current.getTime())) return null;
    current.setUTCHours(0, 0, 0, 0);
    if (observed > current) return null;

    var count = 0;
    var cursor = new Date(observed.getTime());
    while (cursor < current) {
      cursor.setUTCDate(cursor.getUTCDate() + 1);
      if (isUsBusinessDay(cursor)) count += 1;
    }
    return count;
  }

  function hoursSince(value, now) {
    var observed = new Date(value);
    var current = now instanceof Date ? new Date(now.getTime()) : new Date();
    if (Number.isNaN(observed.getTime()) || Number.isNaN(current.getTime()) || observed > current) return null;
    return (current.getTime() - observed.getTime()) / 3600000;
  }

  function parseUnitValue(value, unit) {
    if (typeof value !== "string") return null;
    var escapedUnit = unit.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    var match = value.trim().match(new RegExp("^([+-]?\\d+(?:\\.\\d+)?)\\s*" + escapedUnit + "$", "i"));
    if (!match) return null;
    var number = Number(match[1]);
    return Number.isFinite(number) ? number : null;
  }

  function validDataMeta(meta) {
    if (!meta || typeof meta !== "object"
      || DATA_MODES.indexOf(meta.mode) === -1
      || DATA_STATUSES.indexOf(meta.status) === -1
      || typeof meta.source !== "string" || !meta.source.trim()
      || DATA_FREQUENCIES.indexOf(meta.frequency) === -1) return false;
    if (meta.mode === "fallback" && ["stale", "partial"].indexOf(meta.status) === -1) return false;
    if (meta.mode === "unknown" && meta.status !== "partial") return false;
    if (meta.mode === "unavailable" && meta.status !== "error") return false;
    if (meta.asOf !== null && meta.asOf !== undefined && Number.isNaN(new Date(meta.asOf).getTime())) return false;
    if (meta.updatedAt !== null && meta.updatedAt !== undefined && Number.isNaN(new Date(meta.updatedAt).getTime())) return false;
    if (meta.mode === "market" && (!meta.asOf || !meta.updatedAt)) return false;
    return true;
  }

  function normalizeDataMeta(meta, legacy) {
    var source = validDataMeta(meta) ? meta : legacy;
    if (!validDataMeta(source)) {
      return {
        mode: "unknown", status: "partial", source: "逐条来源待确认",
        asOf: null, updatedAt: null, frequency: "irregular", contractKnown: false
      };
    }
    return {
      mode: source.mode,
      status: source.status,
      source: source.source.trim(),
      asOf: source.asOf || null,
      updatedAt: source.updatedAt || null,
      frequency: source.frequency,
      note: typeof source.note === "string" ? source.note.trim() : "",
      contractKnown: validDataMeta(meta)
    };
  }

  function summarizeRowQuality(metas, declared) {
    var counts = { market: 0, fallback: 0, estimate: 0, unknown: 0, unavailable: 0 };
    var sources = {};
    metas.forEach(function (meta) {
      var mode = DATA_MODES.indexOf(meta.mode) === -1 ? "unknown" : meta.mode;
      counts[mode] += 1;
      if (typeof meta.source === "string" && meta.source.trim()) {
        sources[meta.source] = (sources[meta.source] || 0) + 1;
      }
    });
    var sourceRows = Object.keys(sources).sort(function (a, b) {
      if (sources[b] !== sources[a]) return sources[b] - sources[a];
      return a < b ? -1 : a > b ? 1 : 0;
    }).map(function (name) { return { name: name, count: sources[name] }; });
    var degraded = metas.some(function (meta) {
      return meta.mode === "fallback" || meta.mode === "unknown" || meta.mode === "unavailable"
        || meta.status === "partial" || meta.status === "stale" || meta.status === "error";
    });
    var expectedStatus = metas.length && counts.unavailable !== metas.length ? (degraded ? "partial" : "ok") : "error";
    var declaredValid = !!declared && declared.contractVersion === 1 && declared.total === metas.length
      && declared.status === expectedStatus
      && declared.counts && DATA_MODES.every(function (mode) { return declared.counts[mode] === counts[mode]; })
      && Array.isArray(declared.sources) && declared.sources.length === sourceRows.length
      && declared.sources.every(function (source, index) {
        return source && source.name === sourceRows[index].name && source.count === sourceRows[index].count;
      });
    return {
      counts: counts,
      sources: sourceRows,
      total: metas.length,
      contractKnown: metas.every(function (meta) { return meta.contractKnown; }),
      declaredValid: declaredValid,
      degraded: degraded
    };
  }

  function dataModeLabel(meta) {
    if (!meta) return "来源待确认";
    if (meta.mode === "market") return "行情 · " + meta.source;
    if (meta.mode === "fallback") return "历史回退 · " + meta.source;
    if (meta.mode === "estimate") return "静态估算 · " + meta.source;
    if (meta.mode === "unavailable") return "不可用 · " + meta.source;
    return "来源待确认";
  }

  function unavailableSourceHealth(dataset, error) {
    return {
      dataset: dataset,
      status: "unknown",
      pipelineStatus: "unknown",
      label: "UNKNOWN",
      contractKnown: false,
      historyKnown: false,
      reportStale: true,
      reportAgeHours: null,
      freshCoveragePct: null,
      verifiedCoveragePct: null,
      availableCoveragePct: null,
      dynamicIssueRecords: null,
      dynamicProxyRecords: null,
      slowRecords: null,
      slowEstimateRecords: null,
      consecutiveFailures: null,
      lastAttemptAt: null,
      lastSuccessfulAt: null,
      snapshotPreserved: false,
      failureReason: null,
      note: "来源健康状态不可用。" + (error && error.message ? " " + error.message : "")
    };
  }

  function sourceHealthRows(dataset, data) {
    if (dataset === "asset-tracker") return Array.isArray(data && data.assets) ? data.assets : [];
    if (dataset === "companies") return Array.isArray(data && data.companies) ? data.companies : [];
    if (dataset === "asset-ranking") return Array.isArray(data && data.assets) ? data.assets : [];
    return [];
  }

  function sourceHealthDynamicCount(dataset, rows) {
    if (dataset === "asset-tracker") return rows.length;
    if (dataset === "companies") return rows.filter(function (row) { return row && row.private !== true; }).length;
    if (dataset === "asset-ranking") return rows.filter(function (row) {
      return row && row.static !== true && row.private !== true;
    }).length;
    return 0;
  }

  function sourceHealthPercent(numerator, denominator) {
    return denominator > 0 ? Math.round(numerator / denominator * 10000) / 100 : 0;
  }

  function sourceHealthClassification(dataset, rows, health) {
    var slowFrequencies = ["weekly", "monthly", "quarterly", "annual", "irregular"];
    var dynamicRecords = 0;
    var dynamicMarketRecords = 0;
    var dynamicProxyRecords = 0;
    var slowRecords = 0;
    var slowEstimateRecords = 0;
    rows.forEach(function (row) {
      var current = row && typeof row === "object" ? row : {};
      var meta = current.dataMeta && typeof current.dataMeta === "object" ? current.dataMeta : {};
      var dynamic = dataset === "asset-tracker"
        || (dataset === "companies" && current.private !== true)
        || (dataset === "asset-ranking" && current.static !== true && current.private !== true);
      if (dynamic) {
        dynamicRecords += 1;
        var registeredProxy = dataset === "asset-ranking" && meta.mode === "market" && meta.status === "partial"
          && (/公开存量基准/.test(meta.source || "") || /世界黄金协会/.test(meta.source || ""));
        if (meta.mode === "market" && (meta.status === "ok" || registeredProxy)) {
          dynamicMarketRecords += 1;
          if (registeredProxy) dynamicProxyRecords += 1;
        }
      } else {
        slowRecords += 1;
        if (meta.mode === "estimate" && ["ok", "partial"].indexOf(meta.status) !== -1
          && slowFrequencies.indexOf(meta.frequency) !== -1) slowEstimateRecords += 1;
      }
    });
    var sourceFailures = (health.sources || []).filter(function (source) {
      return source && (source.status === "failed" || source.status === "unknown");
    }).map(function (source) { return source.id; });
    return {
      dynamicRecords: dynamicRecords,
      dynamicMarketRecords: dynamicMarketRecords,
      dynamicIssueRecords: dynamicRecords - dynamicMarketRecords,
      dynamicProxyRecords: dynamicProxyRecords,
      slowRecords: slowRecords,
      slowEstimateRecords: slowEstimateRecords,
      slowIssueRecords: slowRecords - slowEstimateRecords,
      sourceFailures: sourceFailures
    };
  }

  function adaptSourceHealth(health, dataset, data, now) {
    /* 跨资产标的清单会随取数脚本扩容，健康文件与 data.json 由同一次任务一起产出。
       这里接受该数据集已登记的任一期望条数，覆盖率仍必须按健康文件自己声明的
       期望值逐项复算；扩容后的第一份健康文件发布后即可收回成单值。 */
    var expectedRecordOptions = {
      "asset-tracker": [55, 56], companies: [500], "asset-ranking": [250]
    }[dataset];
    if (!expectedRecordOptions || !health || typeof health !== "object") throw new Error("健康文件缺失");
    if (health.contractVersion !== 1 || health.dataset !== dataset
      || PIPELINE_HEALTH_STATUSES.indexOf(health.status) === -1
      || PIPELINE_HISTORY_STATUSES.indexOf(health.historyStatus) === -1) {
      throw new Error("健康文件契约或数据集标识无效");
    }
    var attemptAgeHours = hoursSince(health.lastAttemptAt, now);
    if (hoursSince(health.generatedAt, now) === null || attemptAgeHours === null
      || health.generatedAt !== health.lastAttemptAt) throw new Error("健康文件尝试时间无效");
    if (health.lastSuccessfulAt !== null && hoursSince(health.lastSuccessfulAt, now) === null) {
      throw new Error("健康文件最后成功时间无效");
    }
    if (health.publishedSnapshotAt !== data.updatedAt) throw new Error("健康文件与行情快照时间不一致");
    if (health.snapshotPreserved !== (health.status === "failed")) throw new Error("快照保留状态无效");
    if (health.status === "failed" && (typeof health.failureReason !== "string" || !health.failureReason.trim())) {
      throw new Error("失败健康状态缺少原因");
    }
    if (health.status !== "failed" && health.failureReason !== null) throw new Error("非失败状态包含失败原因");
    if (health.historyStatus === "migrated" && health.consecutiveFailures !== null) {
      throw new Error("迁移历史不得猜测连续失败次数");
    }
    if (health.historyStatus === "tracked"
      && (!Number.isInteger(health.consecutiveFailures) || health.consecutiveFailures < 0)) {
      throw new Error("连续失败次数无效");
    }
    if (health.status === "failed" && health.consecutiveFailures < 1) throw new Error("失败次数与状态不一致");

    var rows = sourceHealthRows(dataset, data);
    var dynamicRecords = sourceHealthDynamicCount(dataset, rows);
    var coverage = health.coverage;
    var counts = coverage && coverage.counts;
    var expectedRecords = coverage && coverage.expectedRecords;
    if (!coverage || expectedRecordOptions.indexOf(expectedRecords) === -1
      || coverage.publishedRecords !== rows.length
      || coverage.dynamicRecords !== dynamicRecords || !counts
      || !DATA_MODES.every(function (mode) { return Number.isInteger(counts[mode]) && counts[mode] >= 0; })
      || DATA_MODES.reduce(function (sum, mode) { return sum + counts[mode]; }, 0) !== rows.length) {
      throw new Error("健康覆盖数量无效");
    }
    var declaredCounts = data.dataQuality && data.dataQuality.counts;
    if (!declaredCounts || DATA_MODES.some(function (mode) { return declaredCounts[mode] !== counts[mode]; })) {
      throw new Error("健康覆盖与逐条数据状态不一致");
    }
    var expectedPercentages = {
      publishedCoveragePct: sourceHealthPercent(rows.length, expectedRecords),
      freshCoveragePct: sourceHealthPercent(counts.market, dynamicRecords),
      verifiedCoveragePct: sourceHealthPercent(counts.market + counts.fallback + counts.estimate, expectedRecords),
      availableCoveragePct: sourceHealthPercent(rows.length - counts.unavailable, expectedRecords)
    };
    Object.keys(expectedPercentages).forEach(function (key) {
      if (!isNumber(coverage[key]) || Math.abs(coverage[key] - expectedPercentages[key]) > 0.001) {
        throw new Error("健康覆盖率不可复算：" + key);
      }
    });
    if (!health.attempt || ["success", "failed", "unknown"].indexOf(health.attempt.status) === -1
      || typeof health.attempt.published !== "boolean" || !Number.isInteger(health.attempt.producedRecords)
      || !health.attempt.counts || !Array.isArray(health.sources)
      || !health.recovery || health.recovery.preservesLastValidSnapshot !== true
      || !Array.isArray(health.recovery.steps) || !health.recovery.steps.length) {
      throw new Error("健康尝试、来源或恢复链无效");
    }
    var attemptTotal = DATA_MODES.reduce(function (sum, mode) {
      var value = health.attempt.counts[mode];
      if (!Number.isInteger(value) || value < 0) throw new Error("健康尝试计数无效");
      return sum + value;
    }, 0);
    if (attemptTotal !== health.attempt.producedRecords
      || health.attempt.published !== (health.status !== "failed")) throw new Error("健康尝试汇总不一致");

    var classification = sourceHealthClassification(dataset, rows, health);
    var countsHaveNoFailures = counts.fallback === 0 && counts.unknown === 0 && counts.unavailable === 0;
    var expectedSlowOnly = classification.dynamicIssueRecords === 0
      && classification.slowIssueRecords === 0 && classification.sourceFailures.length === 0
      && countsHaveNoFailures;
    var normalizedPipelineStatus = health.status === "degraded" && expectedSlowOnly
      && health.historyStatus === "tracked" && health.attempt.status === "success"
      && health.consecutiveFailures === 0 ? "healthy" : health.status;
    var reportStale = attemptAgeHours > SOURCE_HEALTH_MAX_AGE_HOURS[dataset];
    var displayStatus = reportStale && normalizedPipelineStatus !== "failed" ? "stale" : normalizedPipelineStatus;
    var note = normalizedPipelineStatus === "failed"
      ? "本轮取数失败，页面继续使用最后有效快照。"
      : health.historyStatus === "migrated"
        ? "健康历史从当前快照开始建立；此前连续失败次数未知。"
        : expectedSlowOnly && classification.slowRecords
          ? "动态行情（含" + classification.dynamicProxyRecords + "项已披露市值代理）与"
            + classification.slowEstimateRecords + "项慢频估值分层通过；慢变量不冒充每日行情。"
          : "来源健康、覆盖率与恢复状态已跟踪。";
    if (reportStale) {
      note = health.status === "failed"
        ? "健康报告已超过" + SOURCE_HEALTH_MAX_AGE_HOURS[dataset] + "小时；上次记录为取数失败，页面继续使用最后有效快照。"
        : "健康报告已超过" + SOURCE_HEALTH_MAX_AGE_HOURS[dataset] + "小时；本轮行情覆盖仅代表上次任务，不代表当前行情新鲜度。";
    }
    return {
      dataset: dataset,
      status: displayStatus,
      pipelineStatus: normalizedPipelineStatus,
      reportedPipelineStatus: health.status,
      label: displayStatus.toUpperCase(),
      expectedRecords: expectedRecords,
      contractKnown: true,
      historyKnown: health.historyStatus === "tracked",
      reportStale: reportStale,
      reportAgeHours: attemptAgeHours,
      freshCoveragePct: coverage.freshCoveragePct,
      verifiedCoveragePct: coverage.verifiedCoveragePct,
      availableCoveragePct: coverage.availableCoveragePct,
      dynamicIssueRecords: classification.dynamicIssueRecords,
      dynamicProxyRecords: classification.dynamicProxyRecords,
      slowRecords: classification.slowRecords,
      slowEstimateRecords: classification.slowEstimateRecords,
      consecutiveFailures: health.consecutiveFailures,
      lastAttemptAt: health.lastAttemptAt,
      lastSuccessfulAt: health.lastSuccessfulAt,
      snapshotPreserved: health.snapshotPreserved,
      failureReason: health.failureReason,
      note: note
    };
  }

  function safeSourceHealth(health, dataset, data, now, error) {
    if (error) return unavailableSourceHealth(dataset, error);
    try {
      return adaptSourceHealth(health, dataset, data, now);
    } catch (healthError) {
      return unavailableSourceHealth(dataset, healthError);
    }
  }

  function sameStringArray(left, right) {
    return Array.isArray(left) && Array.isArray(right) && left.length === right.length
      && left.every(function (value, index) { return value === right[index]; });
  }

  function unavailableSupportingHealth(dataset, error) {
    return {
      dataset: dataset,
      status: "unknown",
      pipelineStatus: "unknown",
      terminalStatus: "unknown",
      label: "UNKNOWN",
      historyKnown: false,
      publishedCoveragePct: null,
      freshCoveragePct: null,
      consecutiveFailures: null,
      lastAttemptAt: null,
      lastSuccessfulAt: null,
      snapshotPreserved: null,
      note: "更新链健康不可用。" + (error && error.message ? " " + error.message : "")
    };
  }

  var radarTrigger = null;
  /* 雷达构成抽屉按需加载：只有真的去点「六轴如何算出」才下载这段代码。
     入口在首屏就绑好，不等风险区渲染完——窄屏下风险区可能一直没加载，
     若把绑定挂在渲染回调里，按钮在那些尺寸下会变成点了没反应的死键。
     数据尚未到达时抽屉照常打开，并如实说明输入不可用。 */
  function bindRadarDetail(cards) {
    var trigger = radarTrigger || document.getElementById("risk-radar-detail");
    if (!trigger) return;
    if (cards) trigger.radarCards = cards;
    if (radarTrigger) return;
    radarTrigger = trigger;
    trigger.addEventListener("click", function () {
      import("./finance-terminal-radar-view.mjs").then(function (mod) {
        mod.openRadar(document, trigger.radarCards || []);
      }).catch(function () {});
    });
  }

  var supportingHealthAdapter = null;
  var SUPPORTING_HEALTH_SECTIONS = { risk: true, information: true };

  /* 由分区加载或离线测试显式安装，安装前 attachSupportingHealth 明确报未就绪，不臆造健康状态。 */
  function installSupportingHealthAdapter(implementation) {
    supportingHealthAdapter = implementation || null;
    return supportingHealthAdapter;
  }

  /* 共享辅助留在 app.js（首屏其他路径也用），仅把辅助来源健康逻辑按需注入。 */
  function supportingHealthHelpers() {
    return {
      isNumber: isNumber,
      hoursSince: hoursSince,
      sameStringArray: sameStringArray,
      sourceHealthPercent: sourceHealthPercent,
      PIPELINE_HISTORY_STATUSES: PIPELINE_HISTORY_STATUSES
    };
  }

  function attachSupportingHealth(card, dataset, dataSource, healthSource, now) {
    var state;
    if (!dataSource || dataSource.error || !healthSource || healthSource.error) {
      state = unavailableSupportingHealth(dataset, (dataSource && dataSource.error) || (healthSource && healthSource.error));
    } else if (!supportingHealthAdapter) {
      state = unavailableSupportingHealth(dataset, new Error("辅助来源健康适配层尚未加载"));
    } else {
      try {
        state = supportingHealthAdapter.adaptSupportingSourceHealth(
          healthSource.data, dataset, dataSource.data, now);
      } catch (error) {
        state = unavailableSupportingHealth(dataset, error);
      }
    }
    card.sourceHealth = state;
    if (card.status === "ok") {
      if (state.status === "failed" || state.status === "stale" || state.terminalStatus === "failed") {
        card.status = "stale";
      } else if (state.terminalStatus === "degraded") {
        card.status = "partial";
      }
    }
    return card;
  }

  function macroPublishedRecords(data) {
    var dgsMatch = findDgs10Row(data);
    var dollar = findDtwexbgsReference(data);
    var oil = findRwtcReference(data);
    var dgs = dgsMatch && dgsMatch.row;
    return {
      DGS10: dgs ? {
        published: dgs.status !== "error",
        asOf: dgs.status === "error" ? null : dgs.asOf,
        updatedAt: dgs.status === "error" ? null : (dgs.updatedAt || data.updatedAt),
        status: dgs.status || "ok"
      } : null,
      DTWEXBGS: dollar ? {
        published: dollar.status !== "error",
        asOf: dollar.status === "error" ? null : dollar.asOf,
        updatedAt: dollar.status === "error" ? null : dollar.updatedAt,
        status: dollar.status
      } : null,
      RWTC: oil ? {
        published: oil.status !== "error",
        asOf: oil.status === "error" ? null : oil.asOf,
        updatedAt: oil.status === "error" ? null : oil.updatedAt,
        status: oil.status,
        accessMethod: oil.source && oil.source.accessMethod || null
      } : null
    };
  }

  function unavailableOfficialSourceHealth(seriesId, error) {
    return {
      seriesId: seriesId,
      status: "unknown",
      pipelineStatus: "unknown",
      label: "UNKNOWN",
      mode: "unknown",
      refreshLabel: "不可验证",
      historyKnown: false,
      reportStale: false,
      consecutiveFailures: null,
      lastAttemptAt: null,
      lastSuccessfulAt: null,
      snapshotPreserved: null,
      failureReason: null,
      note: "逐源更新链健康不可用。" + (error && error.message ? " " + error.message : "")
    };
  }

  function adaptOfficialSourceHealth(health, macroData, asset, seriesId, now) {
    var spec = OFFICIAL_SOURCE_HEALTH_SPECS[seriesId];
    if (!spec || !health || typeof health !== "object" || !macroData || typeof macroData !== "object"
      || !asset || typeof asset !== "object") {
      throw new Error("官方逐源健康输入缺失");
    }
    if (health.contractVersion !== 1 || health.dataset !== "macro-radar"
      || PIPELINE_HEALTH_STATUSES.indexOf(health.status) === -1
      || PIPELINE_HISTORY_STATUSES.indexOf(health.historyStatus) === -1) {
      throw new Error("官方逐源健康顶层契约无效");
    }
    var reportAgeHours = hoursSince(health.generatedAt, now);
    var attemptAgeHours = hoursSince(health.lastAttemptAt, now);
    if (reportAgeHours === null || attemptAgeHours === null || health.generatedAt !== health.lastAttemptAt
      || health.publishedSnapshotAt !== macroData.updatedAt) {
      throw new Error("官方逐源健康快照或尝试时间无效");
    }
    var expectedIds = ["DGS10", "DTWEXBGS", "RWTC"];
    if (!Array.isArray(health.sources) || !sameStringArray(health.sources.map(function (source) {
      return source && source.id;
    }), expectedIds)) throw new Error("官方逐源健康来源集合无效");

    var source = health.sources.filter(function (item) { return item && item.id === seriesId; })[0];
    var published = macroPublishedRecords(macroData)[seriesId];
    if (!source || !published || !asset.source || asset.source.seriesId !== seriesId || asset.demo !== false) {
      throw new Error(seriesId + "逐源健康与行情卡片无法对应");
    }
    if (source.provider !== spec.provider || source.role !== "primary" || source.frequency !== "daily"
      || source.maxBusinessDays !== spec.maxBusinessDays || source.changeUnit !== spec.changeUnit
      || source.historyStatus !== health.historyStatus
      || MACRO_HEALTH_SOURCE_STATUSES.indexOf(source.status) === -1
      || MACRO_HEALTH_MODES.indexOf(source.mode) === -1) {
      throw new Error(seriesId + "逐源健康口径无效");
    }
    if (!source.source || source.source.seriesId !== seriesId || source.source.name !== spec.provider
      || typeof source.source.url !== "string" || source.source.url.indexOf("https://") !== 0
      || asset.source.name !== spec.provider) {
      throw new Error(seriesId + "逐源健康来源登记无效");
    }
    if (source.published !== published.published || source.asOf !== published.asOf
      || source.publishedUpdatedAt !== published.updatedAt || asset.asOf !== published.asOf
      || asset.updatedAt !== published.updatedAt) {
      throw new Error(seriesId + "逐源健康与发布快照不一致");
    }
    if (seriesId === "RWTC") {
      var accessMethod = source.source.accessMethod || null;
      if (accessMethod !== published.accessMethod || accessMethod !== (asset.source.accessMethod || null)
        || (accessMethod !== null && RWTC_ACCESS_METHODS.indexOf(accessMethod) === -1)) {
        throw new Error("RWTC实际访问路径与健康证据不一致");
      }
    }
    var sourceAttemptAgeHours = hoursSince(source.lastAttemptAt, now);
    if (sourceAttemptAgeHours === null
      || (source.lastSuccessfulAt !== null && hoursSince(source.lastSuccessfulAt, now) === null)) {
      throw new Error(seriesId + "逐源健康运行时间无效");
    }

    var expectedStatus = {
      market: "healthy", fallback: "degraded", unavailable: "failed", unknown: "unknown"
    }[source.mode];
    if (source.status !== expectedStatus) throw new Error(seriesId + "逐源模式与状态不一致");
    if (health.historyStatus === "migrated") {
      if (source.mode !== "unknown" || source.consecutiveFailures !== null
        || source.snapshotPreserved !== null || source.failureReason !== null) {
        throw new Error(seriesId + "迁移历史被错误推断");
      }
    } else {
      if (source.lastAttemptAt !== health.lastAttemptAt
        || !Number.isInteger(source.consecutiveFailures) || source.consecutiveFailures < 0) {
        throw new Error(seriesId + "跟踪历史无效");
      }
      if (source.mode === "market" && (source.consecutiveFailures !== 0
        || source.snapshotPreserved !== false || source.failureReason !== null || published.status !== "ok")) {
        throw new Error(seriesId + "成功更新语义不一致");
      }
      if (source.mode === "fallback" && (source.consecutiveFailures < 1
        || source.snapshotPreserved !== true || typeof source.failureReason !== "string"
        || !source.failureReason.trim() || published.status !== "stale")) {
        throw new Error(seriesId + "失败回退语义不一致");
      }
      if (source.mode === "unavailable" && (source.consecutiveFailures < 1
        || source.snapshotPreserved !== false || typeof source.failureReason !== "string"
        || !source.failureReason.trim() || published.status !== "error")) {
        throw new Error(seriesId + "不可用语义不一致");
      }
      if (source.mode === "unknown") throw new Error(seriesId + "跟踪状态不得使用unknown");
    }

    var reportStale = reportAgeHours > SOURCE_HEALTH_MAX_AGE_HOURS["macro-radar"]
      || sourceAttemptAgeHours > SOURCE_HEALTH_MAX_AGE_HOURS["macro-radar"];
    var displayStatus = reportStale && source.status !== "failed" ? "stale" : source.status;
    var refreshLabel = {
      market: "已刷新", fallback: "保留旧值", unavailable: "不可用", unknown: "历史待建立"
    }[source.mode];
    var note = health.historyStatus === "migrated"
      ? "首次迁移无法追溯旧任务结果，等待一次真实自动运行建立历史。"
      : source.mode === "market"
        ? "最近任务已取得并发布同一官方序列的新观测。"
        : source.mode === "fallback"
          ? "最近任务未取得新观测，继续保留同一序列的最后有效值。"
          : "最近任务未取得可发布观测，页面不使用默认值或错误标的替代。";
    if (reportStale) {
      note = health.historyStatus === "migrated"
        ? "健康证据已超过72小时，且迁移历史仍待首次真实自动运行建立。"
        : "健康证据已超过72小时，不能证明该序列的更新链仍在正常运行。";
    }
    return {
      seriesId: seriesId,
      status: displayStatus,
      pipelineStatus: source.status,
      label: displayStatus.toUpperCase(),
      mode: source.mode,
      refreshLabel: refreshLabel,
      historyKnown: health.historyStatus === "tracked",
      reportStale: reportStale,
      consecutiveFailures: source.consecutiveFailures,
      lastAttemptAt: source.lastAttemptAt,
      lastSuccessfulAt: source.lastSuccessfulAt,
      snapshotPreserved: source.snapshotPreserved,
      failureReason: source.failureReason,
      accessMethod: seriesId === "RWTC" ? source.source.accessMethod || null : null,
      accessMethodLabel: seriesId === "RWTC"
        ? source.source.accessMethod === "EIA API v2" ? "API v2"
          : source.source.accessMethod === "EIA public history page" ? "官方历史页" : "待记录"
        : null,
      note: note
    };
  }

  function attachOfficialSourceHealth(asset, seriesId, macroData, healthSource, now) {
    var state;
    if (!macroData || !healthSource || healthSource.error || !healthSource.data) {
      state = unavailableOfficialSourceHealth(seriesId, healthSource && healthSource.error);
    } else {
      try {
        state = adaptOfficialSourceHealth(healthSource.data, macroData, asset, seriesId, now);
      } catch (error) {
        state = unavailableOfficialSourceHealth(seriesId, error);
      }
    }
    asset.updateHealth = state;
    return asset;
  }

  function findDgs10Row(macroData) {
    if (!macroData || !Array.isArray(macroData.macro)) return null;
    for (var i = 0; i < macroData.macro.length; i += 1) {
      var category = macroData.macro[i];
      if (!category || !Array.isArray(category.rows)) continue;
      for (var j = 0; j < category.rows.length; j += 1) {
        if (category.rows[j] && category.rows[j].id === "DGS10") {
          return { category: category, row: category.rows[j] };
        }
      }
    }
    return null;
  }

  function normalizeOfficialObservations(record) {
    var source = record && Array.isArray(record.observations) ? record.observations : null;
    var candidates = source ? source.slice() : [];
    if (!source && record) {
      if (record.previousAsOf && isNumber(record.previousPrice)) {
        candidates.push({ asOf: record.previousAsOf, value: record.previousPrice });
      }
      if (record.asOf && isNumber(record.price)) {
        candidates.push({ asOf: record.asOf, value: record.price });
      }
    }
    if (candidates.length > 8) throw new Error("官方观测窗口超过8项");
    var previousDate = null;
    var observations = candidates.map(function (item) {
      var observed = parseIsoDate(item && item.asOf);
      if (!observed || !isNumber(item && item.value) || item.value <= 0
          || (previousDate && observed <= previousDate)) {
        throw new Error("官方观测窗口包含无效或非递增记录");
      }
      previousDate = observed;
      return { asOf: item.asOf, value: item.value };
    });
    if (observations.length && record) {
      var last = observations[observations.length - 1];
      if (last.asOf !== record.asOf || !isNumber(record.price)
          || Math.abs(last.value - record.price) > 1e-9) {
        throw new Error("官方观测窗口末值与当前记录不一致");
      }
    }
    return observations;
  }

  function buildOfficialObservationTrend(record, changeUnit) {
    var observations = normalizeOfficialObservations(record);
    var first = observations[0] || null;
    var last = observations[observations.length - 1] || null;
    var change = null;
    if (first && last && observations.length >= 2) {
      change = changeUnit === "bp"
        ? Math.round((last.value - first.value) * 10000) / 100
        : (last.value / first.value - 1) * 100;
    }
    return {
      count: observations.length,
      targetCount: 8,
      startAsOf: first && first.asOf,
      endAsOf: last && last.asOf,
      values: observations.map(function (item) { return item.value; }),
      change: change,
      changeUnit: changeUnit
    };
  }

  function adaptDgs10(template, macroData, now) {
    var match = findDgs10Row(macroData);
    if (!match) throw new Error("宏观雷达未提供DGS10记录");
    if (String(match.category.src || "").toUpperCase() !== "FRED") {
      throw new Error("DGS10来源不是FRED");
    }

    var source = match.row.source;
    var recordStatus = match.row.status || "ok";
    if (recordStatus !== "ok" && recordStatus !== "stale") {
      throw new Error("DGS10自动更新记录不可用");
    }
    if (source && (source.seriesId !== "DGS10" || !/^FRED\b/.test(source.name || ""))) {
      throw new Error("DGS10逐条来源不是FRED");
    }
    var parsedPrice = parseUnitValue(match.row.val, "%");
    var parsedChange = parseUnitValue(match.row.chg, "bp");
    var price = isNumber(match.row.price) ? match.row.price : parsedPrice;
    var change = isNumber(match.row.changeBps) ? match.row.changeBps : parsedChange;
    var age = businessDaysSince(match.row.asOf, now);
    var sourceUpdatedAt = match.row.updatedAt || macroData.updatedAt;
    var updatedAt = new Date(sourceUpdatedAt);
    if (!isNumber(price) || !isNumber(change)) throw new Error("DGS10数值或bp变化无效");
    if (isNumber(match.row.price) && isNumber(parsedPrice) && Math.abs(match.row.price - parsedPrice) > 1e-9) {
      throw new Error("DGS10数值字段不一致");
    }
    if (isNumber(match.row.changeBps) && isNumber(parsedChange) && Math.abs(match.row.changeBps - parsedChange) > 1e-9) {
      throw new Error("DGS10变化字段不一致");
    }
    if (isNumber(match.row.previousPrice)
        && Math.abs(Math.round((price - match.row.previousPrice) * 100) - change) > 1e-9) {
      throw new Error("DGS10基点变化无法由当前值和前值复算");
    }
    if (age === null) throw new Error("DGS10数据日期无效");
    if (Number.isNaN(updatedAt.getTime())) throw new Error("DGS10更新时间无效");

    var refreshFailed = recordStatus === "stale";
    var stale = refreshFailed || age > DGS10_MAX_BUSINESS_DAYS;
    var observationTrend = buildOfficialObservationTrend(match.row, "bp");
    var note = "日频官方数据；变化为相对上一观测值的基点数。";
    if (refreshFailed) {
      note = "本轮FRED自动更新失败，保留上次有效DGS10观测值并标记为过期。";
    } else if (age > DGS10_MAX_BUSINESS_DAYS) {
      note = "已超过3个工作日未更新，保留最后一项官方观测值。";
    }

    return Object.assign({}, template, {
      symbol: "DGS10",
      price: price,
      change: change,
      changeUnit: "bp",
      asOf: match.row.asOf,
      updatedAt: sourceUpdatedAt,
      demo: false,
      status: stale ? "stale" : "ok",
      source: {
        name: "FRED / Federal Reserve H.15",
        url: "https://fred.stlouisfed.org/series/DGS10",
        seriesId: "DGS10"
      },
      note: note,
      spark: observationTrend.values,
      observationTrend: observationTrend
    });
  }

  function unavailableDgs10(template, error) {
    return Object.assign({}, template, {
      symbol: "DGS10",
      price: null,
      change: null,
      asOf: null,
      updatedAt: null,
      demo: false,
      status: "error",
      note: "无法读取宏观雷达中的DGS10数据。" + (error && error.message ? " " + error.message : ""),
      spark: []
    });
  }

  function findDtwexbgsReference(macroData) {
    var references = macroData && macroData.referenceSeries;
    if (!references || typeof references !== "object") return null;
    return references.DTWEXBGS || null;
  }

  function adaptDtwexbgs(template, macroData, now) {
    var record = findDtwexbgsReference(macroData);
    var source = record && record.source;
    var observed = parseIsoDate(record && record.asOf);
    var previousObserved = parseIsoDate(record && record.previousAsOf);
    var updatedAt = new Date(record && record.updatedAt);
    var age = businessDaysSince(record && record.asOf, now);

    if (!template || template.symbol !== "DTWEXBGS") {
      throw new Error("美元卡片代码不是DTWEXBGS");
    }
    if (!record || record.id !== "DTWEXBGS") {
      throw new Error("宏观雷达未提供DTWEXBGS自动更新记录");
    }
    if (record.status !== "ok" && record.status !== "stale") {
      throw new Error("DTWEXBGS自动更新记录不可用");
    }
    if (!source || source.seriesId !== "DTWEXBGS" || !/^FRED\b/.test(source.name || "")) {
      throw new Error("DTWEXBGS来源不是FRED");
    }
    if (!isNumber(record.price) || record.price <= 0 || !isNumber(record.previousPrice) || record.previousPrice <= 0) {
      throw new Error("DTWEXBGS当前值或前值无效");
    }
    if (!observed || !previousObserved || previousObserved >= observed || age === null) {
      throw new Error("DTWEXBGS观测日期无效");
    }
    if (Number.isNaN(updatedAt.getTime())) {
      throw new Error("DTWEXBGS更新时间无效");
    }

    var changePct = (record.price / record.previousPrice - 1) * 100;
    if (isNumber(record.changePct) && Math.abs(record.changePct - changePct) > 1e-9) {
      throw new Error("DTWEXBGS涨跌幅与观测值不一致");
    }
    var refreshFailed = record.status === "stale";
    var stale = refreshFailed || age > DTWEXBGS_MAX_BUSINESS_DAYS;
    var observationTrend = buildOfficialObservationTrend(record, "percent");
    var note = "观测为日度，但美联储H.10按周成批发布，通常每周一次性补齐上一周；"
      + "变化为相对上一观测值的百分比。";
    if (refreshFailed) {
      note = "本轮FRED自动更新失败，保留上次有效观测值并标记为过期。";
    } else if (age > DTWEXBGS_MAX_BUSINESS_DAYS) {
      note = "已超过8个美国工作日未发布新观测值——按H.10每周成批发布的节奏，"
        + "这意味着至少一次周批次缺失，保留最后有效数据。";
    }
    return Object.assign({}, template, record, {
      id: template.id,
      changePct: changePct,
      demo: false,
      status: stale ? "stale" : "ok",
      delayLabel: "日度观测 · 每周成批发布",
      source: {
        name: "FRED / Federal Reserve H.10",
        url: "https://fred.stlouisfed.org/series/DTWEXBGS",
        seriesId: "DTWEXBGS"
      },
      note: note,
      spark: observationTrend.values,
      observationTrend: observationTrend
    });
  }

  function unavailableDtwexbgs(template, error) {
    return Object.assign({}, template, {
      symbol: "DTWEXBGS",
      price: null,
      previousPrice: null,
      changePct: null,
      asOf: null,
      updatedAt: null,
      demo: false,
      status: "error",
      note: "无法读取宏观雷达中的DTWEXBGS自动更新数据。" + (error && error.message ? " " + error.message : ""),
      spark: []
    });
  }

  function findRwtcReference(macroData) {
    var references = macroData && macroData.referenceSeries;
    if (!references || typeof references !== "object") return null;
    return references.RWTC || null;
  }

  function adaptRwtc(template, macroData, now) {
    var record = findRwtcReference(macroData);
    var source = record && record.source;
    var observed = parseIsoDate(record && record.asOf);
    var previousObserved = parseIsoDate(record && record.previousAsOf);
    var updatedAt = new Date(record && record.updatedAt);
    var age = businessDaysSince(record && record.asOf, now);

    if (!template || template.symbol !== "WTI") {
      throw new Error("原油卡片代码不是WTI");
    }
    if (!record || record.id !== "RWTC") {
      throw new Error("宏观雷达未提供EIA RWTC自动更新记录");
    }
    if (record.status !== "ok" && record.status !== "stale") {
      throw new Error("RWTC自动更新记录不可用");
    }
    if (!source || source.seriesId !== "RWTC" || !/EIA/.test(source.name || "")) {
      throw new Error("RWTC来源不是EIA");
    }
    if (source.accessMethod !== undefined && RWTC_ACCESS_METHODS.indexOf(source.accessMethod) === -1) {
      throw new Error("RWTC实际访问路径无效");
    }
    if (!isNumber(record.price) || record.price <= 0 || !isNumber(record.previousPrice) || record.previousPrice <= 0) {
      throw new Error("RWTC当前值或前值无效");
    }
    if (!observed || !previousObserved || previousObserved >= observed || age === null) {
      throw new Error("RWTC观测日期无效");
    }
    if (Number.isNaN(updatedAt.getTime())) {
      throw new Error("RWTC更新时间无效");
    }

    var changePct = (record.price / record.previousPrice - 1) * 100;
    if (isNumber(record.changePct) && Math.abs(record.changePct - changePct) > 1e-9) {
      throw new Error("RWTC涨跌幅与观测值不一致");
    }
    var refreshFailed = record.status === "stale";
    var stale = refreshFailed || age > RWTC_MAX_BUSINESS_DAYS;
    var observationTrend = buildOfficialObservationTrend(record, "percent");
    var note = "EIA官方日频WTI现货数据；变化为相对上一发布观测值的百分比。";
    if (refreshFailed) {
      note = "本轮EIA自动更新未成功，保留上次有效现货观测值并标记为过期。";
    } else if (age > RWTC_MAX_BUSINESS_DAYS) {
      note = "已超过4个美国工作日未发布新观测值，保留最后有效现货数据。";
    }
    return Object.assign({}, template, record, {
      id: template.id,
      symbol: "WTI",
      changePct: changePct,
      demo: false,
      status: stale ? "stale" : "ok",
      delayLabel: "日频现货 · 自动更新",
      source: {
        name: "U.S. EIA / Cushing WTI Spot",
        url: "https://www.eia.gov/dnav/pet/hist/rwtcd.htm",
        seriesId: "RWTC",
        accessMethod: source.accessMethod || null
      },
      note: note,
      spark: observationTrend.values,
      observationTrend: observationTrend
    });
  }

  function unavailableRwtc(template, error) {
    return Object.assign({}, template, {
      symbol: "WTI",
      price: null,
      previousPrice: null,
      changePct: null,
      asOf: null,
      updatedAt: null,
      demo: false,
      status: "error",
      note: "无法读取宏观雷达中的EIA RWTC自动更新数据。" + (error && error.message ? " " + error.message : ""),
      spark: []
    });
  }

  function adaptMacroRegime(macroData, now) {
    var regime = macroData && macroData.regime;
    var observed = parseIsoDate(macroData && macroData.asOf);
    var updatedAt = new Date(macroData && macroData.updatedAt);
    var age = businessDaysSince(macroData && macroData.asOf, now);
    if (!regime || !isNumber(regime.score) || regime.score < 0 || regime.score > 100) {
      throw new Error("宏观状态分数无效");
    }
    if (!observed || age === null || Number.isNaN(updatedAt.getTime())) {
      throw new Error("宏观状态时间字段无效");
    }
    if (typeof regime.labelZh !== "string" || !regime.labelZh.trim()
        || typeof regime.labelEn !== "string" || !regime.labelEn.trim()
        || typeof regime.desc !== "string" || !regime.desc.trim()) {
      throw new Error("宏观状态说明不完整");
    }
    if (typeof macroData.source !== "string" || !macroData.source.trim()) {
      throw new Error("宏观状态来源缺失");
    }

    var stale = macroData.live !== true || age > MACRO_REGIME_MAX_BUSINESS_DAYS;
    var note = regime.desc;
    if (macroData.live !== true) {
      note = "本轮底层行情命中不足，保留宏观雷达最后有效制度信号。";
    } else if (age > MACRO_REGIME_MAX_BUSINESS_DAYS) {
      note = "宏观状态已超过2个美国工作日未更新，当前保留最后有效读数。";
    }
    return {
      id: "macro-regime",
      name: "宏观状态",
      nameEn: "MACRO REGIME",
      symbol: "REGIME",
      value: regime.score,
      decimals: 0,
      suffix: " / 100",
      assessment: regime.labelZh + " · " + regime.labelEn,
      changeText: "制度信号分位 · 越高越偏宽松与支持",
      note: note,
      meterPercent: regime.score,
      meterLabels: ["承压", "中性", "支持"],
      asOf: macroData.asOf,
      updatedAt: macroData.updatedAt,
      frequency: "日频",
      status: stale ? "stale" : "ok",
      source: { name: macroData.source, url: "../macro-radar/" },
      detailUrl: "../macro-radar/",
      regimeSignals: extractRegimeSignals(macroData)
    };
  }

  /* 宏观管线本就算出 8 个制度信号（波动率来自 VIX、信用来自高收益债 OAS、
     流动性来自净流动性与 SOFR−IORB 等），此前终端只读了聚合后的一个分数，
     把分项全丢了——雷达才不得不用那一个数字重组出六个轴。这里把它们取出来，
     只保留分数确为 0–100 有限值的条目，缺项由雷达按不可用处理，不做填补。 */
  function extractRegimeSignals(macroData) {
    var raw = macroData && Array.isArray(macroData.signals) ? macroData.signals : [];
    var out = [];
    raw.forEach(function (signal) {
      if (!signal || typeof signal.key !== "string") return;
      if (!isNumber(signal.score) || signal.score < 0 || signal.score > 100) return;
      out.push({
        key: signal.key,
        label: typeof signal.zh === "string" ? signal.zh : signal.key,
        score: signal.score,
        statusLabel: typeof signal.statusZh === "string" ? signal.statusZh : "",
        detail: typeof signal.desc === "string" ? signal.desc : ""
      });
    });
    return out;
  }

  function unavailableMacroRegime(error) {
    return {
      id: "macro-regime",
      name: "宏观状态",
      nameEn: "MACRO REGIME",
      symbol: "REGIME",
      value: null,
      decimals: 0,
      suffix: " / 100",
      assessment: "数据不可用",
      changeText: "未显示无效或缺失的制度信号",
      note: "无法读取宏观雷达状态。" + (error && error.message ? " " + error.message : ""),
      meterPercent: null,
      meterLabels: ["承压", "中性", "支持"],
      asOf: null,
      updatedAt: null,
      frequency: "日频",
      status: "error",
      source: { name: "Ooglex宏观雷达", url: "../macro-radar/" },
      detailUrl: "../macro-radar/"
    };
  }

  function adaptFearGreed(data, now) {
    var observed = parseIsoDate(data && data.asOf);
    var updatedAt = new Date(data && data.updatedAt);
    var age = businessDaysSince(data && data.asOf, now);
    var nowRef = data && data.refs && data.refs.now;
    var closeRef = data && data.refs && data.refs.close;
    if (!isNumber(data && data.score) || data.score < 0 || data.score > 100) {
      throw new Error("恐慌与贪婪读数无效");
    }
    if (!nowRef || nowRef.score !== data.score) {
      throw new Error("恐慌与贪婪当前参考值不一致");
    }
    if (typeof data.rating !== "string" || !data.rating.trim()
        || typeof data.ratingZh !== "string" || !data.ratingZh.trim()) {
      throw new Error("恐慌与贪婪评级缺失");
    }
    if (data.source !== "CNN Business Fear & Greed Index") {
      throw new Error("恐慌与贪婪来源不准确");
    }
    if (!observed || age === null || Number.isNaN(updatedAt.getTime())) {
      throw new Error("恐慌与贪婪时间字段无效");
    }

    var stale = age > FEAR_GREED_MAX_BUSINESS_DAYS;
    var changeText = "上一收盘参考不可用 · 0=极度恐惧 / 100=极度贪婪";
    if (closeRef && isNumber(closeRef.score) && closeRef.score >= 0 && closeRef.score <= 100) {
      var delta = data.score - closeRef.score;
      var sign = delta > 0 ? "+" : delta < 0 ? "−" : "";
      changeText = "较上一收盘 " + sign + Math.abs(delta) + " 点 · 0=极度恐惧 / 100=极度贪婪";
    }
    return {
      id: "fear-greed",
      name: "恐慌与贪婪",
      nameEn: "FEAR & GREED",
      symbol: "CNN F&G",
      value: data.score,
      decimals: 0,
      suffix: " / 100",
      assessment: data.ratingZh,
      changeText: changeText,
      note: stale
        ? "该情绪指标已超过2个美国工作日未更新，当前保留最后有效读数。"
        : "CNN综合7项市场情绪指标；分数方向代表恐惧到贪婪，不等同于买卖信号。",
      meterPercent: data.score,
      meterLabels: ["极度恐惧", "中性", "极度贪婪"],
      asOf: data.asOf,
      updatedAt: data.updatedAt,
      frequency: "日频",
      status: stale ? "stale" : "ok",
      source: { name: data.source, url: "../fear-greed/" },
      detailUrl: "../fear-greed/"
    };
  }

  function unavailableFearGreed(error) {
    return {
      id: "fear-greed",
      name: "恐慌与贪婪",
      nameEn: "FEAR & GREED",
      symbol: "CNN F&G",
      value: null,
      decimals: 0,
      suffix: " / 100",
      assessment: "数据不可用",
      changeText: "未显示无效或缺失的情绪读数",
      note: "无法读取CNN恐慌与贪婪数据。" + (error && error.message ? " " + error.message : ""),
      meterPercent: null,
      meterLabels: ["极度恐惧", "中性", "极度贪婪"],
      asOf: null,
      updatedAt: null,
      frequency: "日频",
      status: "error",
      source: { name: "CNN Business Fear & Greed Index", url: "../fear-greed/" },
      detailUrl: "../fear-greed/"
    };
  }

  function adaptOfrFsi(data, now) {
    var fsi = data && data.fsi;
    var observed = parseIsoDate(fsi && fsi.asOf);
    var updatedAt = new Date(data && data.updatedAt);
    var age = businessDaysSince(fsi && fsi.asOf, now);
    if (!fsi || !isNumber(fsi.value)) {
      throw new Error("OFR金融压力读数无效");
    }
    if (data.source !== "U.S. Office of Financial Research (OFR)") {
      throw new Error("OFR金融压力来源不准确");
    }
    if (!isSafeOfrUrl(fsi.url)) {
      throw new Error("OFR金融压力来源链接无效");
    }
    if (!observed || age === null || Number.isNaN(updatedAt.getTime())) {
      throw new Error("OFR金融压力时间字段无效");
    }

    var stale = age > OFR_FSI_MAX_BUSINESS_DAYS;
    var partial = !isNumber(fsi.change);
    var assessment = fsi.value > 0 ? "高于历史平均压力" : fsi.value < 0 ? "低于历史平均压力" : "处于历史平均压力";
    var changeText = "日变化暂不可用";
    if (!partial) {
      var sign = fsi.change > 0 ? "+" : fsi.change < 0 ? "−" : "";
      var direction = fsi.change > 0 ? "压力上升" : fsi.change < 0 ? "压力下降" : "压力持平";
      changeText = "较前日 " + sign + Math.abs(fsi.change).toFixed(2) + " · " + direction;
    }
    var note = "OFR FSI以0为历史平均压力；正值高于平均，负值低于平均。";
    if (stale) {
      note = "OFR FSI已超过5个美国工作日未发布新值，当前保留最后有效读数。";
    } else if (partial) {
      note = "OFR FSI当前值可用，但日变化字段缺失，卡片标记为部分数据。";
    }
    return {
      id: "ofr-fsi",
      name: "OFR金融压力",
      nameEn: "FINANCIAL STRESS INDEX",
      symbol: "OFR FSI",
      value: fsi.value,
      decimals: 2,
      suffix: "",
      assessment: assessment,
      changeText: changeText,
      note: note,
      meterPercent: null,
      meterLabels: null,
      asOf: fsi.asOf,
      updatedAt: data.updatedAt,
      frequency: "日频",
      status: stale ? "stale" : partial ? "partial" : "ok",
      source: { name: data.source, url: "../ofr-monitor/" },
      detailUrl: "../ofr-monitor/"
    };
  }

  function isSafeOfrUrl(value) {
    return typeof value === "string" && /^https:\/\/www\.financialresearch\.gov\/financial-stress-index\/?$/.test(value);
  }

  function unavailableOfrFsi(error) {
    return {
      id: "ofr-fsi",
      name: "OFR金融压力",
      nameEn: "FINANCIAL STRESS INDEX",
      symbol: "OFR FSI",
      value: null,
      decimals: 2,
      suffix: "",
      assessment: "数据不可用",
      changeText: "未显示无效或缺失的金融压力读数",
      note: "无法读取OFR金融压力指数。" + (error && error.message ? " " + error.message : ""),
      meterPercent: null,
      meterLabels: null,
      asOf: null,
      updatedAt: null,
      frequency: "日频",
      status: "error",
      source: { name: "U.S. Office of Financial Research (OFR)", url: "../ofr-monitor/" },
      detailUrl: "../ofr-monitor/"
    };
  }

  function buildRiskCards(sources, now) {
    var macroSource = sources && sources.macro ? sources.macro : {};
    var fearGreedSource = sources && sources.fearGreed ? sources.fearGreed : {};
    var fearGreedHealthSource = sources && sources.fearGreedHealth ? sources.fearGreedHealth : {};
    var ofrSource = sources && sources.ofr ? sources.ofr : {};
    var ofrHealthSource = sources && sources.ofrHealth ? sources.ofrHealth : {};
    var cards = [];
    if (macroSource.error) {
      cards.push(unavailableMacroRegime(macroSource.error));
    } else {
      try {
        cards.push(adaptMacroRegime(macroSource.data, now));
      } catch (error) {
        cards.push(unavailableMacroRegime(error));
      }
    }
    if (fearGreedSource.error) {
      cards.push(attachSupportingHealth(
        unavailableFearGreed(fearGreedSource.error), "fear-greed", fearGreedSource, fearGreedHealthSource, now
      ));
    } else {
      try {
        cards.push(attachSupportingHealth(
          adaptFearGreed(fearGreedSource.data, now), "fear-greed", fearGreedSource, fearGreedHealthSource, now
        ));
      } catch (error) {
        cards.push(attachSupportingHealth(
          unavailableFearGreed(error), "fear-greed", fearGreedSource, fearGreedHealthSource, now
        ));
      }
    }
    if (ofrSource.error) {
      cards.push(attachSupportingHealth(
        unavailableOfrFsi(ofrSource.error), "ofr-monitor", ofrSource, ofrHealthSource, now
      ));
    } else {
      try {
        cards.push(attachSupportingHealth(
          adaptOfrFsi(ofrSource.data, now), "ofr-monitor", ofrSource, ofrHealthSource, now
        ));
      } catch (error) {
        cards.push(attachSupportingHealth(
          unavailableOfrFsi(error), "ofr-monitor", ofrSource, ofrHealthSource, now
        ));
      }
    }
    return cards;
  }

  function normalizeAssetProxy(asset) {
    var proxy = asset && asset.proxy;
    if (proxy === undefined || proxy === null) return null;
    var expectedKeys = [
      "currency", "instrumentName", "instrumentSymbol", "note",
      "returnBasis", "targetSymbol", "type"
    ];
    var actualKeys = proxy && typeof proxy === "object" && !Array.isArray(proxy)
      ? Object.keys(proxy).sort() : [];
    var validText = function (value) { return typeof value === "string" && value.trim(); };
    if (!proxy || typeof proxy !== "object" || Array.isArray(proxy)
      || actualKeys.length !== expectedKeys.length
      || expectedKeys.some(function (key, index) { return actualKeys[index] !== key; })
      || ["etf", "futures", "index"].indexOf(proxy.type) === -1
      || ["price", "total-return"].indexOf(proxy.returnBasis) === -1
      || !validText(proxy.targetSymbol) || !validText(proxy.instrumentName)
      || !validText(proxy.instrumentSymbol) || !validText(proxy.note)
      || !/^[A-Z]{3}$/.test(proxy.currency)
      || !asset || !validText(asset.symbol)
      || proxy.instrumentSymbol.trim() !== asset.symbol.trim()
      || proxy.targetSymbol.trim() === proxy.instrumentSymbol.trim()) {
      throw new Error("跨资产代理标的契约无效");
    }
    return {
      type: proxy.type,
      targetSymbol: proxy.targetSymbol.trim(),
      instrumentName: proxy.instrumentName.trim(),
      instrumentSymbol: proxy.instrumentSymbol.trim(),
      currency: proxy.currency,
      returnBasis: proxy.returnBasis,
      note: proxy.note.trim()
    };
  }

  function adaptCrossAsset(data, now, health, healthError) {
    if (!data || data.source !== "Yahoo Finance") throw new Error("跨资产数据来源不是Yahoo Finance");
    var age = hoursSince(data.updatedAt, now);
    var observed = parseIsoDate(data.asOf);
    var current = now instanceof Date ? new Date(now.getTime()) : new Date();
    if (age === null) throw new Error("跨资产更新时间无效或晚于当前时间");
    if (!observed || Number.isNaN(current.getTime())) throw new Error("跨资产数据日期无效");
    current.setUTCHours(0, 0, 0, 0);
    if (observed > current) throw new Error("跨资产数据日期晚于当前时间");

    var expectedPeriods = ["d1", "w1", "m1", "ytd", "y1"];
    if (!Array.isArray(data.periods)) throw new Error("跨资产周期配置缺失");
    var periods = data.periods.filter(function (period) {
      return period && expectedPeriods.indexOf(period.key) !== -1 && typeof period.label === "string" && period.label.trim();
    }).map(function (period) { return { key: period.key, label: period.label.trim() }; });
    if (periods.length !== expectedPeriods.length || expectedPeriods.some(function (key) {
      return !periods.some(function (period) { return period.key === key; });
    })) throw new Error("跨资产周期配置不完整");
    if (expectedPeriods.indexOf(data.defaultPeriod) === -1) throw new Error("跨资产默认周期无效");
    if (!Array.isArray(data.assets) || data.assets.length < 8) throw new Error("跨资产样本数量不足");

    var rowMetas = data.assets.map(function (asset) {
      var legacy = asset && asset.stale === true
        ? { mode: "fallback", status: "stale", source: "Yahoo Finance", asOf: null,
          updatedAt: data.updatedAt, frequency: "daily" }
        : asset && asset.suspect === true
          ? { mode: "market", status: "partial", source: "Yahoo Finance", asOf: data.asOf,
            updatedAt: data.updatedAt, frequency: "daily" }
          : { mode: "market", status: "ok", source: "Yahoo Finance", asOf: data.asOf,
            updatedAt: data.updatedAt, frequency: "daily" };
      return normalizeDataMeta(asset && asset.dataMeta, legacy);
    });
    var quality = summarizeRowQuality(rowMetas, data.dataQuality);
    var assets = data.assets.map(function (asset, index) {
      if (!asset || typeof asset.name !== "string" || !asset.name.trim()
        || typeof asset.symbol !== "string" || !asset.symbol.trim()
        || typeof asset.category !== "string" || !asset.category.trim()
        || !asset.returns || typeof asset.returns !== "object") return null;
      var returns = {};
      expectedPeriods.forEach(function (key) {
        var value = asset.returns[key];
        returns[key] = isNumber(value) && value >= -100 && value <= 10000 ? value : null;
      });
      if (!expectedPeriods.some(function (key) { return isNumber(returns[key]); })) return null;
      var proxy = normalizeAssetProxy(asset);
      return {
        name: asset.name.trim(),
        symbol: asset.symbol.trim(),
        category: asset.category.trim(),
        returns: returns,
        stale: rowMetas[index].mode === "fallback" || asset.stale === true,
        suspect: asset.suspect === true || rowMetas[index].status === "partial" && rowMetas[index].mode === "market",
        proxy: proxy,
        note: typeof asset.note === "string" && asset.note.trim() ? asset.note.trim() : null,
        dataMeta: rowMetas[index],
        dataLabel: (proxy ? "PROXY · " : "") + dataModeLabel(rowMetas[index])
      };
    }).filter(Boolean);
    if (assets.length < 8) throw new Error("跨资产有效样本数量不足");

    var usableDefault = assets.filter(function (asset) {
      return !asset.stale && !asset.suspect && isNumber(asset.returns[data.defaultPeriod]);
    }).length;
    if (usableDefault < 6) throw new Error("跨资产默认周期可比样本不足");
    var hasPartialRows = assets.length !== data.assets.length || quality.degraded
      || !quality.contractKnown || !quality.declaredValid || assets.some(function (asset) {
      return asset.stale || asset.suspect || !isNumber(asset.returns[data.defaultPeriod]);
    });
    var status = age > ASSET_TRACKER_MAX_AGE_HOURS ? "stale" : hasPartialRows ? "partial" : "ok";

    return {
      id: "cross-asset",
      name: "跨资产强弱",
      nameEn: "Cross-Asset Performance",
      symbol: data.assets.length + " ASSETS",
      status: status,
      periods: periods,
      defaultPeriod: data.defaultPeriod,
      assets: assets,
      quality: quality,
      sourceHealth: safeSourceHealth(health, "asset-tracker", data, now, healthError),
      sourceCount: data.assets.length,
      asOf: data.asOf,
      updatedAt: data.updatedAt,
      frequency: "日频快照",
      source: { name: "Yahoo Finance", url: "../asset-tracker/" },
      detailUrl: "../asset-tracker/",
      note: status === "stale"
        ? "数据文件已超过72小时未更新；保留历史周期供参考，暂停生成“今日”强弱排行。"
        : hasPartialRows
          ? "逐条状态会排除历史回退、异常或缺值；旧快照无法反推精确数据日时保持PARTIAL。债券与部分金属含ETF或期货代理。"
          : "逐条来源与数据日已校验；比较各标的自身价格回报。债券与部分金属含ETF或期货代理。"
    };
  }

  function unavailableCrossAsset(error) {
    return {
      id: "cross-asset",
      name: "跨资产强弱",
      nameEn: "Cross-Asset Performance",
      symbol: "— ASSETS",
      status: "error",
      periods: [
        { key: "d1", label: "今日" }, { key: "w1", label: "近一周" },
        { key: "m1", label: "近一月" }, { key: "ytd", label: "年初至今" },
        { key: "y1", label: "近一年" }
      ],
      defaultPeriod: "ytd",
      assets: [],
      quality: summarizeRowQuality([], null),
      sourceHealth: unavailableSourceHealth("asset-tracker", error),
      sourceCount: 0,
      asOf: null,
      updatedAt: null,
      frequency: "日频快照",
      source: { name: "Yahoo Finance", url: "../asset-tracker/" },
      detailUrl: "../asset-tracker/",
      note: "无法读取跨资产表现数据。" + (error && error.message ? " " + error.message : "")
    };
  }

  function rankCrossAssetPeriod(card, periodKey) {
    var periods = card && Array.isArray(card.periods) ? card.periods : [];
    var period = periods.filter(function (item) { return item.key === periodKey; })[0]
      || periods.filter(function (item) { return item.key === card.defaultPeriod; })[0]
      || periods[0] || null;
    if (!period || !Array.isArray(card.assets)) {
      return { period: period, leaders: [], laggards: [], coverage: 0, total: 0, paused: false };
    }
    var usable = card.assets.filter(function (asset) {
      return !asset.stale && !asset.suspect && isNumber(asset.returns && asset.returns[period.key]);
    });
    var paused = card.status === "stale" && period.key === "d1";
    if (paused) return { period: period, leaders: [], laggards: [], coverage: usable.length, total: card.sourceCount, paused: true };
    var sorted = usable.slice().sort(function (a, b) { return a.returns[period.key] - b.returns[period.key]; });
    return {
      period: period,
      leaders: sorted.slice(-3).reverse(),
      laggards: sorted.slice(0, 3),
      coverage: usable.length,
      total: card.sourceCount,
      paused: false
    };
  }

  function periodTabTargetIndex(currentIndex, key, total) {
    if (!Number.isInteger(currentIndex) || !Number.isInteger(total) || total < 1) return currentIndex;
    if (key === "ArrowRight" || key === "ArrowDown") return (currentIndex + 1) % total;
    if (key === "ArrowLeft" || key === "ArrowUp") return (currentIndex - 1 + total) % total;
    if (key === "Home") return 0;
    if (key === "End") return total - 1;
    return currentIndex;
  }

  function adaptAssetRanking(data, now, health, healthError) {
    var source = data && data.source;
    if (typeof source !== "string" || !/Yahoo Finance/.test(source) || !/CoinGecko/.test(source) || !/公开估算/.test(source)) {
      throw new Error("全球资产市值来源不完整");
    }
    var age = hoursSince(data.updatedAt, now);
    var observed = parseIsoDate(data.asOf);
    var current = now instanceof Date ? new Date(now.getTime()) : new Date();
    if (age === null) throw new Error("全球资产市值更新时间无效或晚于当前时间");
    if (!observed || Number.isNaN(current.getTime())) throw new Error("全球资产市值数据日期无效");
    current.setUTCHours(0, 0, 0, 0);
    if (observed > current) throw new Error("全球资产市值数据日期晚于当前时间");
    if (!Array.isArray(data.assets) || data.assets.length < 100) throw new Error("全球资产市值样本数量不足");
    if (!isNumber(data.totalMarketCap) || data.totalMarketCap <= 0) throw new Error("全球资产总市值无效");

    var categoryLabels = {};
    if (Array.isArray(data.categories)) data.categories.forEach(function (category) {
      if (category && typeof category.key === "string" && typeof category.label === "string") {
        categoryLabels[category.key] = category.label;
      }
    });
    var rowMetas = data.assets.map(function (asset) {
      var legacy = asset && asset.static === true
        ? { mode: "estimate", status: "partial", source: "公开慢变量估值（旧快照）", asOf: null,
          updatedAt: data.updatedAt, frequency: "irregular" }
        : asset && asset.stale === true
          ? { mode: "fallback", status: "stale", source: source, asOf: null,
            updatedAt: data.updatedAt, frequency: "daily" }
          : { mode: "unknown", status: "partial", source: source, asOf: null,
            updatedAt: data.updatedAt, frequency: "daily" };
      return normalizeDataMeta(asset && asset.dataMeta, legacy);
    });
    var quality = summarizeRowQuality(rowMetas, data.dataQuality);
    var assets = data.assets.map(function (asset, index) {
      if (!asset || typeof asset.name !== "string" || !asset.name.trim()
        || typeof asset.category !== "string" || !asset.category.trim()
        || !isNumber(asset.marketCap) || asset.marketCap <= 0
        || !Number.isInteger(asset.rank) || asset.rank < 1) return null;
      return {
        name: asset.name.trim(),
        nameEn: typeof asset.nameEn === "string" ? asset.nameEn.trim() : "",
        category: asset.category,
        categoryLabel: categoryLabels[asset.category] || asset.category,
        marketCap: asset.marketCap,
        rank: asset.rank,
        static: rowMetas[index].mode === "estimate" || asset.static === true,
        stale: rowMetas[index].mode === "fallback" || asset.stale === true,
        dataMeta: rowMetas[index],
        dataLabel: dataModeLabel(rowMetas[index])
      };
    }).filter(Boolean);
    if (assets.length < 100) throw new Error("全球资产市值有效样本数量不足");
    var sorted = assets.slice().sort(function (a, b) { return b.marketCap - a.marketCap; });
    var topAssets = sorted.slice(0, 5);
    if (topAssets.length !== 5 || topAssets.some(function (asset, index) {
      var sourceAsset = data.assets[index];
      return !sourceAsset || sourceAsset.name !== asset.name || sourceAsset.rank !== index + 1;
    })) throw new Error("全球资产市值榜首顺序或排名无效");

    var inputComplete = assets.length === data.assets.length && data.count === data.assets.length;
    if (inputComplete) {
      var calculatedTotal = assets.reduce(function (sum, asset) { return sum + asset.marketCap; }, 0);
      if (Math.abs(calculatedTotal - data.totalMarketCap) > 1) throw new Error("全球资产总市值不可由分项复现");
    }
    var hasFallback = assets.some(function (asset) { return asset.stale; });
    var status = age > ASSET_RANKING_MAX_AGE_HOURS ? "stale"
      : (!inputComplete || !quality.contractKnown || !quality.declaredValid || quality.degraded || hasFallback)
        ? "partial" : "ok";
    var pendingCount = quality.counts.unknown + quality.counts.unavailable;

    return {
      id: "asset-ranking",
      name: "全球资产市值",
      nameEn: "Global Asset Ranking",
      symbol: "TOP 250",
      status: status,
      assets: topAssets,
      quality: quality,
      sourceHealth: safeSourceHealth(health, "asset-ranking", data, now, healthError),
      count: data.count,
      totalMarketCap: data.totalMarketCap,
      asOf: data.asOf,
      updatedAt: data.updatedAt,
      frequency: "每日更新 · 混合频率",
      source: { name: source, url: "../asset-ranking/" },
      detailUrl: "../asset-ranking/",
      note: status === "stale"
        ? "榜单文件已超过72小时未更新；保留最后有效市值与明确的数据日期。"
        : pendingCount
          ? pendingCount + "项旧快照的逐条取值路径待确认；" + quality.counts.estimate
            + "项明确为静态估值。市值单位为十亿美元。"
          : "逐条来源与数据日已校验；静态估值、历史回退和行情快照分别标明，市值单位为十亿美元。"
    };
  }

  function unavailableAssetRanking(error) {
    return {
      id: "asset-ranking",
      name: "全球资产市值",
      nameEn: "Global Asset Ranking",
      symbol: "TOP 250",
      status: "error",
      assets: [],
      quality: summarizeRowQuality([], null),
      sourceHealth: unavailableSourceHealth("asset-ranking", error),
      count: 0,
      totalMarketCap: null,
      asOf: null,
      updatedAt: null,
      frequency: "每日更新 · 混合频率",
      source: { name: "Yahoo Finance · CoinGecko · 公开估算", url: "../asset-ranking/" },
      detailUrl: "../asset-ranking/",
      note: "无法读取全球资产市值榜。" + (error && error.message ? " " + error.message : "")
    };
  }

  function findBitcoinAsset(data) {
    var matches = Array.isArray(data && data.assets) ? data.assets.filter(function (asset) {
      return asset && asset.category === "crypto" && asset.symbol === "BTC"
        && (asset.nameEn === "Bitcoin" || asset.name === "比特币");
    }) : [];
    if (matches.length !== 1) throw new Error("资产榜必须且只能包含一条比特币记录");
    return matches[0];
  }

  function adaptBitcoin(config, data, now) {
    if (!config || config.id !== "bitcoin" || config.demo !== false || config.symbol !== "BTC/USD") {
      throw new Error("比特币卡片配置无效");
    }
    if (!data || typeof data.source !== "string" || !/CoinGecko/.test(data.source)
      || !/Yahoo Finance/.test(data.source)) throw new Error("比特币上游来源声明不完整");
    var row = findBitcoinAsset(data);
    if (!isNumber(row.price) || row.price <= 0) throw new Error("比特币价格无效");
    if (!isNumber(row.changePct) || row.changePct < -100 || row.changePct > 10000) {
      throw new Error("比特币涨跌幅无效");
    }
    var meta = normalizeDataMeta(row.dataMeta, null);
    if (!meta.contractKnown || meta.frequency !== "daily" || !meta.asOf || !meta.updatedAt) {
      throw new Error("比特币逐条来源或时间契约无效");
    }
    var isCoinGecko = meta.mode === "market" && meta.status === "ok" && meta.source === "CoinGecko";
    var isYahoo = meta.mode === "market" && meta.status === "partial"
      && /^Yahoo Finance · 静态流通量基准$/.test(meta.source);
    var isRetained = meta.mode === "fallback" && ["stale", "partial"].indexOf(meta.status) !== -1
      && /CoinGecko|Yahoo Finance/.test(meta.source);
    if (!isCoinGecko && !isYahoo && !isRetained) {
      throw new Error("比特币不得使用估值、未知或不可用记录冒充行情");
    }
    var age = hoursSince(meta.asOf, now);
    var updateAge = hoursSince(meta.updatedAt, now);
    if (age === null || updateAge === null) throw new Error("比特币行情时间无效或晚于当前时间");
    if (meta.mode === "market" && meta.updatedAt !== data.updatedAt) {
      throw new Error("比特币逐条更新时间与资产榜快照不一致");
    }
    var stale = age > BITCOIN_MAX_AGE_HOURS || isRetained || row.stale === true;
    var status = stale ? "stale" : isYahoo ? "partial" : "ok";
    var source = isCoinGecko
      ? { name: "Powered by CoinGecko", url: "https://www.coingecko.com/" }
      : { name: meta.source, url: "https://finance.yahoo.com/quote/BTC-USD/" };
    return Object.assign({}, config, {
      demo: false,
      status: status,
      price: row.price,
      changePct: row.changePct,
      asOf: meta.asOf,
      updatedAt: meta.updatedAt,
      delayLabel: isCoinGecko ? "日度快照 · 24小时涨跌"
        : isYahoo ? "日频报价 · 较前收盘" : "日频快照 · 历史回退",
      changePeriod: isCoinGecko ? "24_hours" : isYahoo ? "previous_close" : "retained_snapshot",
      source: source,
      note: stale
        ? "CoinGecko与Yahoo本轮均未形成可发布新值，保留资产榜上一份同标的行情并标记过期。"
        : isYahoo
          ? "CoinGecko本轮不可用；使用Yahoo BTC-USD报价作为明确降级，涨跌为较前收盘。"
          : "复用资产榜CoinGecko日度快照；涨跌为上游返回的过去24小时变化，不宣称实时。"
    });
  }

  function unavailableBitcoin(config, error) {
    return Object.assign({}, config, {
      demo: false,
      status: "error",
      price: null,
      changePct: null,
      asOf: null,
      updatedAt: null,
      delayLabel: "日度行情不可用",
      source: { name: "CoinGecko · Yahoo Finance", url: "../asset-ranking/" },
      note: "无法从资产榜读取可验证的BTC/USD行情。" + (error && error.message ? " " + error.message : "")
    });
  }

  function unavailableBitcoinSourceHealth(error) {
    return {
      seriesId: "BTC/USD",
      status: "unknown",
      pipelineStatus: "unknown",
      label: "UNKNOWN",
      mode: "unknown",
      refreshLabel: "不可验证",
      accessMethodLabel: "不可验证",
      historyKnown: false,
      reportStale: false,
      consecutiveFailures: null,
      lastAttemptAt: null,
      lastSuccessfulAt: null,
      snapshotPreserved: null,
      failureReason: null,
      note: "BTC/USD逐源更新链健康不可用。" + (error && error.message ? " " + error.message : "")
    };
  }

  function validateBitcoinHealthSource(source, expectedMode) {
    if (!source || ["healthy", "degraded", "failed", "unknown"].indexOf(source.status) === -1
      || !Number.isInteger(source.records) || source.records < 0 || !source.counts
      || !DATA_MODES.every(function (mode) {
        return Number.isInteger(source.counts[mode]) && source.counts[mode] >= 0;
      }) || DATA_MODES.reduce(function (sum, mode) {
        return sum + source.counts[mode];
      }, 0) !== source.records || source.counts[expectedMode] < 1) {
      throw new Error("BTC/USD逐源健康计数无效");
    }
    return source;
  }

  function adaptBitcoinSourceHealth(health, data, asset, now) {
    var pipeline = adaptSourceHealth(health, "asset-ranking", data, now);
    var row = findBitcoinAsset(data);
    var meta = normalizeDataMeta(row.dataMeta, null);
    if (!asset || asset.id !== "bitcoin" || asset.asOf !== meta.asOf || asset.updatedAt !== meta.updatedAt) {
      throw new Error("BTC/USD行情与资产榜健康输入不一致");
    }
    var source;
    var refreshLabel;
    var accessMethodLabel;
    if (meta.mode === "market" && meta.source === "CoinGecko") {
      source = validateBitcoinHealthSource(health.sources.filter(function (item) {
        return item && item.id === "coingecko";
      })[0], "market");
      if (source.status !== "healthy" || source.lastSuccessAt !== meta.updatedAt) {
        throw new Error("CoinGecko BTC/USD缺少同批成功证据");
      }
      refreshLabel = "已刷新";
      accessMethodLabel = "CoinGecko";
    } else if (meta.mode === "market" && /^Yahoo Finance · 静态流通量基准$/.test(meta.source)) {
      source = validateBitcoinHealthSource(health.sources.filter(function (item) {
        return item && item.id === "yahoo-finance";
      })[0], "market");
      if (["healthy", "degraded"].indexOf(source.status) === -1 || source.lastSuccessAt !== meta.updatedAt) {
        throw new Error("Yahoo BTC-USD缺少同批降级证据");
      }
      refreshLabel = "明确降级";
      accessMethodLabel = "Yahoo BTC-USD";
    } else if (meta.mode === "fallback") {
      source = health.sources.filter(function (item) {
        return item && (item.id === "coingecko" || item.id === "yahoo-finance")
          && item.counts && item.counts.fallback > 0;
      })[0];
      validateBitcoinHealthSource(source, "fallback");
      refreshLabel = "保留旧值";
      accessMethodLabel = "历史快照";
    } else {
      throw new Error("BTC/USD健康证据不支持当前逐条模式");
    }

    var status = pipeline.reportStale ? "stale"
      : health.status === "failed" ? "failed"
        : meta.mode === "market" && meta.source === "CoinGecko" ? "healthy" : "degraded";
    return {
      seriesId: "BTC/USD",
      status: status,
      pipelineStatus: health.status,
      label: status.toUpperCase(),
      mode: meta.mode,
      refreshLabel: refreshLabel,
      accessMethodLabel: accessMethodLabel,
      historyKnown: health.historyStatus === "tracked",
      reportStale: pipeline.reportStale,
      consecutiveFailures: health.consecutiveFailures,
      lastAttemptAt: health.lastAttemptAt,
      lastSuccessfulAt: source.lastSuccessAt || health.lastSuccessfulAt,
      snapshotPreserved: health.snapshotPreserved,
      failureReason: health.failureReason,
      note: status === "healthy"
        ? "BTC/USD逐条行情与资产榜同批来源健康证据一致。"
        : status === "degraded"
          ? "BTC/USD当前使用已披露降级或历史回退路径，未冒充CoinGecko新鲜行情。"
          : status === "stale"
            ? "资产榜健康证据已超过72小时，价格快照与更新链状态分开显示。"
            : "资产榜最近一次整批任务失败，页面仅保留可验证旧快照。"
    };
  }

  function attachBitcoinSourceHealth(asset, dataSource, healthSource, now) {
    var state;
    if (!dataSource || dataSource.error || !dataSource.data || !healthSource
      || healthSource.error || !healthSource.data || asset.status === "error") {
      state = unavailableBitcoinSourceHealth(
        (dataSource && dataSource.error) || (healthSource && healthSource.error) || new Error("BTC/USD健康输入缺失")
      );
    } else {
      try {
        state = adaptBitcoinSourceHealth(healthSource.data, dataSource.data, asset, now);
      } catch (error) {
        state = unavailableBitcoinSourceHealth(error);
      }
    }
    asset.updateHealth = state;
    if (asset.status === "ok" && (state.status === "failed" || state.status === "stale")) {
      asset.status = "stale";
    }
    return asset;
  }

  function adaptCompanies(data, now, health, healthError) {
    if (!data || data.source !== "Yahoo Finance") throw new Error("公司榜数据来源不是Yahoo Finance");
    var age = hoursSince(data.updatedAt, now);
    var observed = parseIsoDate(data.asOf);
    var current = now instanceof Date ? new Date(now.getTime()) : new Date();
    if (age === null) throw new Error("公司榜更新时间无效或晚于当前时间");
    if (!observed || Number.isNaN(current.getTime())) throw new Error("公司榜数据日期无效");
    current.setUTCHours(0, 0, 0, 0);
    if (observed > current) throw new Error("公司榜数据日期晚于当前时间");
    if (!Array.isArray(data.companies) || data.companies.length < 100) throw new Error("公司榜样本数量不足");
    if (!Number.isInteger(data.listedCount) || !Number.isInteger(data.privateCount)
      || !Number.isInteger(data.count) || data.listedCount < 1 || data.privateCount < 0) {
      throw new Error("公司榜数量元数据无效");
    }
    if (!isNumber(data.totalMarketCap) || data.totalMarketCap <= 0) throw new Error("公司榜总市值无效");

    var rowMetas = data.companies.map(function (company) {
      var isPrivate = company && company.private === true;
      var legacy = isPrivate
        ? { mode: "estimate", status: "partial", source: "公开融资估值（旧快照）", asOf: null,
          updatedAt: data.updatedAt, frequency: "irregular" }
        : company && company.stale === true
          ? { mode: "fallback", status: "stale", source: "Yahoo Finance", asOf: null,
            updatedAt: data.updatedAt, frequency: "daily" }
          : { mode: "unknown", status: "partial", source: "Yahoo Finance", asOf: null,
            updatedAt: data.updatedAt, frequency: "daily" };
      return normalizeDataMeta(company && company.dataMeta, legacy);
    });
    var quality = summarizeRowQuality(rowMetas, data.dataQuality);
    var companies = data.companies.map(function (company, index) {
      if (!company || typeof company.name !== "string" || !company.name.trim()
        || !isNumber(company.marketCap) || company.marketCap <= 0
        || !Number.isInteger(company.rank) || company.rank < 1) return null;
      var isPrivate = company.private === true;
      if (!isPrivate && (typeof company.symbol !== "string" || !company.symbol.trim() || company.symbol === "—")) return null;
      var change = company.changePct;
      return {
        name: company.name.trim(),
        nameEn: typeof company.nameEn === "string" ? company.nameEn.trim() : "",
        symbol: isPrivate ? "—" : company.symbol.trim(),
        marketCap: company.marketCap,
        changePct: isNumber(change) && change >= -100 && change <= 1000 ? change : null,
        rank: company.rank,
        private: isPrivate,
        stale: rowMetas[index].mode === "fallback" || company.stale === true,
        freshnessKnown: rowMetas[index].contractKnown
          && ["market", "fallback", "estimate"].indexOf(rowMetas[index].mode) !== -1,
        dataMeta: rowMetas[index],
        dataLabel: dataModeLabel(rowMetas[index])
      };
    }).filter(Boolean);
    if (companies.length < 100) throw new Error("公司榜有效样本数量不足");

    var listed = companies.filter(function (company) { return !company.private; });
    var privateCompanies = companies.filter(function (company) { return company.private; });
    if (listed.length < 50) throw new Error("上市公司有效样本数量不足");
    var topCompanies = listed.slice().sort(function (a, b) { return b.marketCap - a.marketCap; }).slice(0, 3);
    if (topCompanies.length !== 3 || topCompanies.some(function (company, index) {
      var sourceCompany = data.companies[index];
      return !sourceCompany || sourceCompany.name !== company.name || sourceCompany.rank !== index + 1;
    })) throw new Error("上市公司市值榜首顺序或排名无效");

    var movers = listed.filter(function (company) {
      return !company.stale && company.dataMeta.mode === "market" && company.dataMeta.status === "ok"
        && isNumber(company.changePct);
    }).sort(function (a, b) { return a.changePct - b.changePct; });
    var inputComplete = companies.length === data.companies.length
      && data.count === data.companies.length
      && data.listedCount === listed.length
      && data.privateCount === privateCompanies.length;
    if (inputComplete) {
      var calculatedTotal = companies.reduce(function (sum, company) { return sum + company.marketCap; }, 0);
      if (Math.abs(calculatedTotal - data.totalMarketCap) > 1) throw new Error("公司榜总市值不可由分项复现");
    }
    var freshnessKnown = listed.every(function (company) {
      return company.freshnessKnown && ["market", "fallback"].indexOf(company.dataMeta.mode) !== -1;
    });
    var hasFallback = listed.some(function (company) { return company.stale; });
    var hasUnknown = listed.some(function (company) {
      return company.dataMeta.mode === "unknown" || company.dataMeta.mode === "unavailable";
    });
    var missingChanges = listed.some(function (company) {
      return company.dataMeta.mode === "market" && !isNumber(company.changePct);
    });
    var status = age > COMPANIES_MAX_AGE_HOURS ? "stale"
      : (!inputComplete || !quality.contractKnown || !quality.declaredValid || !freshnessKnown
        || hasFallback || hasUnknown || missingChanges || movers.length < 20) ? "partial" : "ok";
    var pendingCount = quality.counts.unknown + quality.counts.unavailable;

    return {
      id: "company-leaders",
      name: "全球公司领袖",
      nameEn: "Global Company Leaders",
      symbol: "TOP 500",
      status: status,
      topCompanies: topCompanies,
      gainer: movers.length >= 20 ? movers[movers.length - 1] : null,
      laggard: movers.length >= 20 ? movers[0] : null,
      moverCoverage: movers.length,
      listedCount: listed.length,
      privateCount: privateCompanies.length,
      listedMarketCap: listed.reduce(function (sum, company) { return sum + company.marketCap; }, 0),
      quality: quality,
      sourceHealth: safeSourceHealth(health, "companies", data, now, healthError),
      asOf: data.asOf,
      updatedAt: data.updatedAt,
      frequency: "日频快照",
      source: { name: "Yahoo Finance · multiples.vc公开估值", url: "../companies/" },
      detailUrl: "../companies/",
      note: status === "stale"
        ? "公司榜文件已超过72小时未更新；保留最后快照并停止把它描述为今日行情。"
        : pendingCount
          ? pendingCount + "条旧快照无法确认本轮行情或历史回退，暂停当日领涨与领跌；未上市估值不参与。"
          : hasFallback
            ? "已排除" + quality.counts.fallback + "条历史回退，仅用本轮有效行情计算领涨与领跌；未上市估值不参与。"
            : "逐公司来源与数据日已校验；仅用本轮有效行情计算领涨与领跌，未上市估值不参与。"
    };
  }

  function unavailableCompanies(error) {
    return {
      id: "company-leaders",
      name: "全球公司领袖",
      nameEn: "Global Company Leaders",
      symbol: "TOP 500",
      status: "error",
      topCompanies: [],
      gainer: null,
      laggard: null,
      moverCoverage: 0,
      listedCount: 0,
      privateCount: 0,
      listedMarketCap: null,
      quality: summarizeRowQuality([], null),
      sourceHealth: unavailableSourceHealth("companies", error),
      asOf: null,
      updatedAt: null,
      frequency: "日频快照",
      source: { name: "Yahoo Finance · multiples.vc公开估值", url: "../companies/" },
      detailUrl: "../companies/",
      note: "无法读取全球公司市值榜。" + (error && error.message ? " " + error.message : "")
    };
  }

  function buildResearchCards(sources, now) {
    var trackerSource = sources && sources.assetTracker ? sources.assetTracker : {};
    var trackerHealthSource = sources && sources.assetTrackerHealth ? sources.assetTrackerHealth : {};
    var rankingSource = sources && sources.assetRanking ? sources.assetRanking : {};
    var rankingHealthSource = sources && sources.assetRankingHealth ? sources.assetRankingHealth : {};
    var companiesSource = sources && sources.companies ? sources.companies : {};
    var companiesHealthSource = sources && sources.companiesHealth ? sources.companiesHealth : {};
    var cards = [];
    if (trackerSource.error) cards.push(unavailableCrossAsset(trackerSource.error));
    else {
      try { cards.push(adaptCrossAsset(trackerSource.data, now, trackerHealthSource.data, trackerHealthSource.error)); }
      catch (error) { cards.push(unavailableCrossAsset(error)); }
    }
    if (rankingSource.error) cards.push(unavailableAssetRanking(rankingSource.error));
    else {
      try { cards.push(adaptAssetRanking(rankingSource.data, now, rankingHealthSource.data, rankingHealthSource.error)); }
      catch (error) { cards.push(unavailableAssetRanking(error)); }
    }
    if (companiesSource.error) cards.push(unavailableCompanies(companiesSource.error));
    else {
      try { cards.push(adaptCompanies(companiesSource.data, now, companiesHealthSource.data, companiesHealthSource.error)); }
      catch (error) { cards.push(unavailableCompanies(error)); }
    }
    return cards;
  }

  function latestOfficialUpdate(assets) {
    var latest = null;
    assets.forEach(function (asset) {
      if (asset.demo || !asset.updatedAt) return;
      var parsed = new Date(asset.updatedAt);
      if (Number.isNaN(parsed.getTime())) return;
      if (!latest || parsed > latest.date) latest = { date: parsed, value: asset.updatedAt };
    });
    return latest ? latest.value : null;
  }

  function sourceSummary(assets) {
    var dgs10 = assets.filter(function (asset) { return asset.id === "us10y"; })[0];
    var dollar = assets.filter(function (asset) { return asset.id === "dxy"; })[0];
    var wti = assets.filter(function (asset) { return asset.id === "wti"; })[0];
    var bitcoin = assets.filter(function (asset) { return asset.id === "bitcoin"; })[0];
    var parts = [];
    parts.push(dgs10 && dgs10.status !== "error" ? "FRED H.15（DGS10）" : "DGS10暂不可用");
    parts.push(dollar && dollar.status !== "error" ? "FRED H.10（DTWEXBGS自动更新）" : "DTWEXBGS暂不可用");
    parts.push(wti && wti.status !== "error" ? "U.S. EIA（RWTC现货）" : "RWTC暂不可用");
    parts.push(bitcoin && bitcoin.status !== "error" ? bitcoin.source.name + "（BTC/USD）" : "BTC/USD暂不可用");
    parts.push("TradingView免费组件（DIA / GLD代理）");
    return parts.join(" · ");
  }

  function validateConfig(config) {
    if (!config || config.schemaVersion !== 3 || config.demo !== false) {
      throw new Error("页面数据配置无效或免费代理标记缺失");
    }
    if (!Array.isArray(config.assets) || config.assets.length !== 6) {
      throw new Error("核心资产配置不完整");
    }
    var officialIds = config.assets.filter(function (asset) {
      return asset.demo === false && !asset.externalDisplay;
    }).map(function (asset) { return asset.id; });
    var proxyAssets = config.assets.filter(function (asset) { return Boolean(asset.externalDisplay); });
    var demoCount = config.assets.filter(function (asset) { return asset.demo === true; }).length;
    if (officialIds.length !== 4 || officialIds.indexOf("us10y") === -1 || officialIds.indexOf("dxy") === -1
      || officialIds.indexOf("wti") === -1 || officialIds.indexOf("bitcoin") === -1
      || proxyAssets.length !== 2 || demoCount !== 0) {
      throw new Error("4项站内行情与2项免费嵌入代理的配置不一致");
    }
    var expectedProxies = {
      sp500: ["SPY", "AMEX:SPY", "SPX"],
      nasdaq100: ["QQQ", "NASDAQ:QQQ", "NDX"],
      dow: ["DIA", "AMEX:DIA", "DJIA"],
      gold: ["GLD", "AMEX:GLD", "LBMA-GOLD-PM-USD"]
    };
    proxyAssets.forEach(function (asset) {
      var expected = expectedProxies[asset.id];
      if (!expected || asset.demo !== false || asset.status !== "provider"
        || asset.instrument !== "etf-proxy" || asset.frequency !== "provider-managed"
        || asset.symbol !== expected[0]
        || asset.externalDisplay.provider !== "TradingView"
        || asset.externalDisplay.widget !== "tv-mini-chart"
        || asset.externalDisplay.widgetSymbol !== expected[1]
        || asset.externalDisplay.rawDataStored !== false
        || !asset.proxyFor || asset.proxyFor.symbol !== expected[2]
        || asset.proxyFor.isSameInstrument !== false
        || !asset.source || asset.source.name !== "TradingView免费组件"
        || typeof asset.source.url !== "string"
        || asset.source.url.indexOf("https://www.tradingview.com/symbols/") !== 0
        || asset.price !== null || asset.changePct !== null
        || asset.asOf !== null || asset.updatedAt !== null) {
        throw new Error("免费代理配置不得冒充原标的、保存原始行情或内置数值");
      }
    });
  }

  function buildPageData(
    config, macroData, now, macroError, macroHealthSource, assetRankingSource, assetRankingHealthSource
  ) {
    validateConfig(config);
    var assets = config.assets.map(function (asset) {
      if (asset.id === "us10y") {
        if (macroError) return attachOfficialSourceHealth(
          unavailableDgs10(asset, macroError), "DGS10", macroData, macroHealthSource, now
        );
        try {
          return attachOfficialSourceHealth(
            adaptDgs10(asset, macroData, now), "DGS10", macroData, macroHealthSource, now
          );
        } catch (error) {
          return attachOfficialSourceHealth(
            unavailableDgs10(asset, error), "DGS10", macroData, macroHealthSource, now
          );
        }
      }
      if (asset.id === "dxy") {
        if (macroError) return attachOfficialSourceHealth(
          unavailableDtwexbgs(asset, macroError), "DTWEXBGS", macroData, macroHealthSource, now
        );
        try {
          return attachOfficialSourceHealth(
            adaptDtwexbgs(asset, macroData, now), "DTWEXBGS", macroData, macroHealthSource, now
          );
        } catch (error) {
          return attachOfficialSourceHealth(
            unavailableDtwexbgs(asset, error), "DTWEXBGS", macroData, macroHealthSource, now
          );
        }
      }
      if (asset.id === "wti") {
        if (macroError) return attachOfficialSourceHealth(
          unavailableRwtc(asset, macroError), "RWTC", macroData, macroHealthSource, now
        );
        try {
          return attachOfficialSourceHealth(
            adaptRwtc(asset, macroData, now), "RWTC", macroData, macroHealthSource, now
          );
        } catch (error) {
          return attachOfficialSourceHealth(
            unavailableRwtc(asset, error), "RWTC", macroData, macroHealthSource, now
          );
        }
      }
      if (asset.id === "bitcoin") {
        var ranking = assetRankingSource || {};
        var rankingHealth = assetRankingHealthSource || {};
        if (ranking.error || !ranking.data) return attachBitcoinSourceHealth(
          unavailableBitcoin(asset, ranking.error || new Error("资产榜数据缺失")), ranking, rankingHealth, now
        );
        try { return attachBitcoinSourceHealth(adaptBitcoin(asset, ranking.data, now), ranking, rankingHealth, now); }
        catch (error) { return attachBitcoinSourceHealth(unavailableBitcoin(asset, error), ranking, rankingHealth, now); }
      }
      return Object.assign({}, asset);
    });
    var hasStale = assets.some(function (asset) {
      return !asset.externalDisplay && !asset.demo && asset.status === "stale";
    });
    return Object.assign({}, config, {
      assets: assets,
      status: hasStale ? "stale" : "ok",
      updatedAt: latestOfficialUpdate(assets),
      source: sourceSummary(assets)
    });
  }

  function buildPageDataWithMacroError(
    config, error, now, macroHealthSource, assetRankingSource, assetRankingHealthSource
  ) {
    return buildPageData(
      config, null, now, error, macroHealthSource, assetRankingSource, assetRankingHealthSource
    );
  }

  function adaptMarketLicenseReadiness(data) {
    /* 2026-08-25 所有者决定撤下标普500与纳斯达克100两张代理卡；这里与契约文件、
       许可门禁保持同一份名单，任一处多出或少一项都会被判为计数不可复算。 */
    var expected = {
      dow: ["DJIA", "DIA", "AMEX:DIA"],
      gold: ["LBMA-GOLD-PM-USD", "GLD", "AMEX:GLD"]
    };
    var expectedCount = Object.keys(expected).length;
    if (!data || data.schemaVersion !== 3 || data.displayScope !== "public-web"
      || !data.selection || data.selection.strategy !== "free-embedded-proxy"
      || data.selection.proxySubstitutionAllowed !== true
      || data.selection.exactBenchmarkProcurementPaused !== true) {
      throw new Error("免费嵌入代理决策无效");
    }
    var useCase = data.useCase;
    if (!useCase || useCase.operatorType !== "individual-hobbyist"
      || useCase.domain !== "ooglex.com" || useCase.commercial !== false
      || useCase.advertising !== false || useCase.subscriptions !== false
      || useCase.otherRevenue !== false || useCase.publicApiRedistribution !== false
      || useCase.rawMarketDataStored !== false || useCase.tradingExecution !== false
      || useCase.investmentProduct !== false || useCase.costPolicy !== "free-only") {
      throw new Error("免费非商业使用范围无效");
    }
    var provider = data.provider;
    if (!provider || provider.name !== "TradingView"
      || provider.delivery !== "official-free-web-component"
      || provider.widget !== "tv-mini-chart"
      || provider.scriptUrl !== "https://widgets.tradingview-widget.com/w/en/tv-mini-chart.js"
      || provider.cost !== "free" || provider.credentialsRequired !== false
      || provider.attributionRequired !== true || provider.exportAllowed !== false
      || provider.providerControlsDelay !== true) {
      throw new Error("TradingView免费嵌入配置无效");
    }
    var runtimeVerification = provider.runtimeVerification;
    if (!runtimeVerification
      || runtimeVerification.registrationTag !== PROVIDER_WIDGET_TAG
      || runtimeVerification.registrationTimeoutMs !== 8000
      || runtimeVerification.registrationEvidence !== "custom-element-registered"
      || runtimeVerification.hostCheckDelayMs !== 100
      || runtimeVerification.successEvidence !== "connected-defined-element-with-layout"
      || JSON.stringify(runtimeVerification.successDoesNotAssert)
        !== JSON.stringify(["quote-rendered", "quote-freshness", "market-open"])
      || runtimeVerification.failureFallback !== "official-symbol-link"
      || runtimeVerification.lateRegistrationRecovery !== true) {
      throw new Error("TradingView组件运行时验证边界无效");
    }
    if (!Array.isArray(data.assets) || data.assets.length !== expectedCount) {
      throw new Error("免费代理标的数量无效");
    }
    var seen = {};
    var proxies = [];
    data.assets.forEach(function (asset) {
      var spec = asset && expected[asset.id];
      var proxy = asset && asset.proxy;
      if (!spec || seen[asset.id] || !asset.original || asset.original.symbol !== spec[0]
        || !proxy || proxy.symbol !== spec[1] || proxy.widgetSymbol !== spec[2]
        || proxy.instrumentType !== "etf-proxy" || proxy.isSameInstrument !== false
        || proxy.selected !== true || asset.productionAction !== "embed-provider-widget") {
        throw new Error("免费ETF代理配置无效或冒充原标的");
      }
      seen[asset.id] = true;
      proxies.push(proxy.symbol);
    });
    if (Object.keys(expected).some(function (id) { return !seen[id]; })
      || data.proxyAssetCount !== expectedCount || data.freeDisplayAssetCount !== expectedCount) {
      throw new Error("免费代理计数不可复算");
    }
    return {
      status: "free",
      strategy: data.selection.strategy,
      targets: proxies,
      proxyAssets: expectedCount,
      provider: provider.name,
      cost: provider.cost,
      rawMarketDataStored: useCase.rawMarketDataStored,
      runtimeVerification: runtimeVerification
    };
  }

  function unavailableMarketLicenseReadiness(error) {
    return {
      status: "unknown",
      strategy: "unknown",
      targets: [],
      proxyAssets: 0,
      provider: "unknown",
      cost: "unknown",
      rawMarketDataStored: null,
      error: error && error.message ? error.message : "免费代理状态不可用"
    };
  }

  var testApi = {
    sectionDataHelpers: sectionDataHelpers,
    adaptDgs10: adaptDgs10,
    adaptDtwexbgs: adaptDtwexbgs,
    adaptOfficialSourceHealth: adaptOfficialSourceHealth,
    adaptMarketLicenseReadiness: adaptMarketLicenseReadiness,
    adaptCrossAsset: adaptCrossAsset,
    adaptAssetRanking: adaptAssetRanking,
    adaptCompanies: adaptCompanies,
    adaptFearGreed: adaptFearGreed,
    adaptMacroRegime: adaptMacroRegime,
    adaptOfrFsi: adaptOfrFsi,
    adaptRwtc: adaptRwtc,
    adaptBitcoin: adaptBitcoin,
    adaptBitcoinSourceHealth: adaptBitcoinSourceHealth,
    findBitcoinAsset: findBitcoinAsset,
    buildOfficialObservationTrend: buildOfficialObservationTrend,
    adaptSourceHealth: adaptSourceHealth,
    supportingHealthHelpers: supportingHealthHelpers,
    installSupportingHealthAdapter: installSupportingHealthAdapter,
    buildPageData: buildPageData,
    buildPageDataWithMacroError: buildPageDataWithMacroError,
    buildResearchCards: buildResearchCards,
    buildRiskCards: buildRiskCards,
    businessDaysSince: businessDaysSince,
    DTWEXBGS_MAX_BUSINESS_DAYS: DTWEXBGS_MAX_BUSINESS_DAYS,
    findDgs10Row: findDgs10Row,
    findDtwexbgsReference: findDtwexbgsReference,
    findRwtcReference: findRwtcReference,
    normalizeOfficialObservations: normalizeOfficialObservations,
    isUsBusinessDay: isUsBusinessDay,
    isSafeOfrUrl: isSafeOfrUrl,
    hoursSince: hoursSince,
    parseUnitValue: parseUnitValue,
    rankCrossAssetPeriod: rankCrossAssetPeriod,
    normalizeDataMeta: normalizeDataMeta,
    normalizeAssetProxy: normalizeAssetProxy,
    summarizeRowQuality: summarizeRowQuality,
    dataModeLabel: dataModeLabel,
    periodTabTargetIndex: periodTabTargetIndex,
    inspectProviderWidgetHost: inspectProviderWidgetHost,
    waitForProviderWidgetRegistration: waitForProviderWidgetRegistration,
    unavailableCrossAsset: unavailableCrossAsset,
    unavailableAssetRanking: unavailableAssetRanking,
    unavailableCompanies: unavailableCompanies,
    unavailableFearGreed: unavailableFearGreed,
    unavailableMacroRegime: unavailableMacroRegime,
    unavailableOfrFsi: unavailableOfrFsi,
    unavailableOfficialSourceHealth: unavailableOfficialSourceHealth,
    unavailableBitcoinSourceHealth: unavailableBitcoinSourceHealth,
    unavailableSourceHealth: unavailableSourceHealth,
    unavailableSupportingHealth: unavailableSupportingHealth
  };
  if (typeof module === "object" && module.exports) module.exports = testApi;
  if (typeof document === "undefined") return;

  var grid = document.getElementById("market-grid");
  var watch = null;
  var lastRendered = null;
  bindRadarDetail(null);
  /* 收益率曲线抽屉按需加载；入口在首屏即绑定，不依赖任何延迟分区。 */
  /* 相关性矩阵按需加载：只有真的去点才下载这段代码与那份滚动历史。
     入口在首屏就绑好，不等研究区渲染完——窄屏下研究区可能一直没加载。 */
  (function bindCorrelation() {
    var trigger = document.getElementById("correlation-entry");
    if (!trigger) return;
    trigger.addEventListener("click", function () {
      import("./finance-terminal-correlation-view.mjs").then(function (mod) {
        mod.openCorrelation(document);
      }).catch(function () {});
    });
  }());

  (function bindYieldCurve() {
    /* 两个入口：总览的遥测卡与「市场状态」页标题栏。后者才是访客找它的地方——
       曲线属于市场状态，不属于首页概览。 */
    ["yield-curve-entry", "yield-curve-entry-risk"].forEach(function (id) {
      var trigger = document.getElementById(id);
      if (!trigger) return;
      trigger.addEventListener("click", function () {
        import("./finance-terminal-curve-view.mjs").then(function (mod) {
          mod.openCurve(document);
        }).catch(function () {});
      });
    });
  }());
  import("./finance-terminal-watchlist.mjs").then(function (mod) {
    watch = mod.mountWatchlist(document, window, function () {
      if (lastRendered) render(lastRendered);
    });
    if (lastRendered) render(lastRendered);
  }).catch(function () {});
  var pageUpdated = document.getElementById("page-updated");
  var pageSource = document.getElementById("page-source");
  var assetCount = document.getElementById("asset-count");
  var dataStatus = document.getElementById("data-status");
  var marketState = document.getElementById("market-state");
  var banner = document.getElementById("data-banner");
  var bannerLabel = document.getElementById("banner-label");
  var bannerTitle = document.getElementById("banner-title");
  var bannerCopy = document.getElementById("banner-copy");
  var bannerNote = document.getElementById("banner-note");
  var licenseNotice = document.getElementById("license-notice");
  var licenseLabel = document.getElementById("license-label");
  var licenseTitle = document.getElementById("license-title");
  var licenseCopy = document.getElementById("license-copy");
  var riskGrid = document.getElementById("risk-grid");
  var riskSummary = document.getElementById("risk-summary");
  var researchGrid = document.getElementById("research-grid");
  var researchSummary = document.getElementById("research-summary");
  var informationGrid = document.getElementById("information-grid");
  var informationSummary = document.getElementById("information-summary");
  var operationsGrid = document.getElementById("operations-grid");
  var operationsSummary = document.getElementById("operations-summary");
  var boardPanel = document.getElementById("board-panel");
  var boardSummary = document.getElementById("board-summary");
  var pageAnnouncer = document.getElementById("page-announcer");
  var sectionViewImports = {};
  var sectionViewModules = {};
  var sectionViewEvidence = {
    requested: [],
    states: { board: "idle", risk: "idle", research: "idle", information: "idle", operations: "idle" }
  };
  root.__financeTerminalSectionModules = sectionViewEvidence;
  var terminalVisualsPromise = import("./finance-terminal-visuals.mjs").then(function (visualModule) {
    if (!visualModule || typeof visualModule.createTerminalVisuals !== "function") {
      throw new Error("终端视觉层缺少工厂函数");
    }
    return visualModule.createTerminalVisuals({ document: document, window: window });
  }).catch(function () {
    return null;
  });

  /* 分区数据层与视图一样按需加载：只有事件资讯分区用得上的适配代码，不该让每个
     访客在首屏就下载。助手仍留在 app.js（首屏自己也要用），这里注入过去。 */
  var sectionDataImports = {};
  function sectionDataHelpers() {
    return {
      adaptSourceHealth: adaptSourceHealth,
      attachSupportingHealth: attachSupportingHealth,
      hoursSince: hoursSince,
      isNumber: isNumber,
      macroPublishedRecords: macroPublishedRecords,
      parseIsoDate: parseIsoDate,
      sameStringArray: sameStringArray,
      sourceHealthPercent: sourceHealthPercent,
      sourceHealthRows: sourceHealthRows,
      unavailableSourceHealth: unavailableSourceHealth,
      MACRO_HEALTH_MODES: MACRO_HEALTH_MODES,
      MACRO_HEALTH_SOURCE_STATUSES: MACRO_HEALTH_SOURCE_STATUSES,
      PIPELINE_HEALTH_STATUSES: PIPELINE_HEALTH_STATUSES,
      PIPELINE_HISTORY_STATUSES: PIPELINE_HISTORY_STATUSES,
      SOURCE_HEALTH_MAX_AGE_HOURS: SOURCE_HEALTH_MAX_AGE_HOURS
    };
  }

  function importSectionData(name) {
    /* 品类行情板的数据层是纯函数模块，没有需要注入的首屏助手，直接返回模块本身。 */
    if (name === "board") return import("./finance-terminal-board-data.mjs");
    if (name === "information") {
      return import("./finance-terminal-information-data.mjs")
        .then(function (mod) { return mod.createInformationData(sectionDataHelpers()); });
    }
    if (name === "operations") {
      return import("./finance-terminal-operations-data.mjs")
        .then(function (mod) { return mod.createOperationsData(sectionDataHelpers()); });
    }
    return Promise.resolve(null);
  }

  function loadSectionData(name) {
    if (!sectionDataImports[name]) {
      sectionDataImports[name] = importSectionData(name).then(function (data) {
        if (!data) throw new Error("延迟区块数据模块缺少工厂函数：" + name);
        return data;
      });
    }
    return sectionDataImports[name];
  }

  function importSectionView(name) {
    if (name === "board") return import("./finance-terminal-board-view.mjs");
    if (name === "risk") return import("./finance-terminal-risk-view.mjs");
    if (name === "research") return import("./finance-terminal-research-view.mjs");
    if (name === "information") return import("./finance-terminal-information-view.mjs");
    if (name === "operations") return import("./finance-terminal-operations-view.mjs");
    return Promise.resolve(null);
  }

  function loadSectionView(name) {
    var factoryNames = {
      board: "createBoardView",
      risk: "createRiskView",
      research: "createResearchView",
      information: "createInformationView",
      operations: "createOperationsView"
    };
    if (!factoryNames[name]) return Promise.resolve(null);
    if (!sectionViewImports[name]) {
      sectionViewEvidence.requested.push(name);
      sectionViewEvidence.states[name] = "loading";
      sectionViewImports[name] = importSectionView(name).then(function (viewModule) {
        if (!viewModule || typeof viewModule[factoryNames[name]] !== "function") {
          throw new Error("延迟区块视图模块缺少工厂函数：" + name);
        }
        sectionViewModules[name] = viewModule;
        sectionViewEvidence.states[name] = "ready";
        /* 市场状态与事件资讯两个分区都要渲染辅助来源健康面板，两者都必须等适配层装好
           再解析，否则先加载的那个分区会渲染出「尚未加载」的 UNKNOWN 面板。 */
        if (!SUPPORTING_HEALTH_SECTIONS[name] || supportingHealthAdapter) return viewModule;
        return import("./finance-terminal-health-adapters.mjs").then(function (mod) {
          installSupportingHealthAdapter(mod.createSupportingHealthAdapter(supportingHealthHelpers()));
          return viewModule;
        });
      }).catch(function (error) {
        sectionViewEvidence.states[name] = "error";
        throw error;
      });
    }
    return sectionViewImports[name];
  }

  function formatTimestamp(value, demo) {
    if (!value) return demo ? "演示时间未提供" : "更新时间不可用";
    var time = new Date(value);
    if (Number.isNaN(time.getTime())) return demo ? "演示时间未提供" : "更新时间不可用";
    var formatted = new Intl.DateTimeFormat("zh-CN", {
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
      timeZone: "Asia/Shanghai"
    }).format(time);
    return formatted + " UTC+8" + (demo ? " · 演示" : "");
  }

  function formatDate(value, demo) {
    if (demo) return "演示日期";
    return parseIsoDate(value) ? value : "数据日期不可用";
  }

  function formatPrice(asset) {
    if (!isNumber(asset.price)) return "—";
    var decimals = Number.isInteger(asset.decimals) ? asset.decimals : 2;
    var number = asset.price.toLocaleString("en-US", {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals
    });
    return (asset.prefix || "") + number + (asset.suffix || "");
  }

  function changeValue(asset) {
    return asset.changeUnit === "bp" ? asset.change : asset.changePct;
  }

  function formatChange(asset) {
    var value = changeValue(asset);
    if (!isNumber(value)) return "—";
    var sign = value > 0 ? "+" : value < 0 ? "−" : "";
    var decimals = asset.changeUnit === "bp" && Number.isInteger(value) ? 0 : 2;
    return sign + Math.abs(value).toFixed(decimals) + (asset.changeUnit === "bp" ? " bp" : "%");
  }

  function directionOf(asset) {
    var value = changeValue(asset);
    if (!isNumber(value) || value === 0) return "neutral";
    return value > 0 ? "positive" : "negative";
  }

  function appendText(parent, tag, className, value) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    node.textContent = value;
    parent.appendChild(node);
    return node;
  }

  function makeSparkline(values, direction) {
    var ariaLabel = arguments.length > 2 ? arguments[2] : null;
    var svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "sparkline");
    svg.setAttribute("viewBox", "0 0 240 42");
    svg.setAttribute("preserveAspectRatio", "none");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", ariaLabel || (direction === "positive" ? "演示走势向上" : "演示走势向下"));

    var base = document.createElementNS(SVG_NS, "line");
    base.setAttribute("class", "base");
    base.setAttribute("x1", "0");
    base.setAttribute("x2", "240");
    base.setAttribute("y1", "34");
    base.setAttribute("y2", "34");
    svg.appendChild(base);

    if (!Array.isArray(values) || values.length < 2) return svg;
    var min = Math.min.apply(Math, values);
    var max = Math.max.apply(Math, values);
    var span = max - min || 1;
    var points = values.map(function (value, index) {
      var x = index * 240 / (values.length - 1);
      var y = 35 - ((value - min) / span) * 28;
      return x.toFixed(1) + "," + y.toFixed(1);
    }).join(" ");

    /* 面积用同一组观测点闭合到基线，只是同一条折线的填充，不新增任何推断数据点。 */
    var area = document.createElementNS(SVG_NS, "polygon");
    area.setAttribute("class", "area");
    area.setAttribute("points", "0,42 " + points + " 240,42");
    svg.appendChild(area);

    var line = document.createElementNS(SVG_NS, "polyline");
    line.setAttribute("class", "line");
    line.setAttribute("points", points);
    svg.appendChild(line);
    return svg;
  }

  function formatTrendChange(trend) {
    if (!trend || !isNumber(trend.change)) return "区间变化待补足";
    var sign = trend.change > 0 ? "+" : trend.change < 0 ? "−" : "";
    var decimals = trend.changeUnit === "bp" && Number.isInteger(trend.change) ? 0 : 2;
    return "区间 " + sign + Math.abs(trend.change).toFixed(decimals)
      + (trend.changeUnit === "bp" ? " bp" : "%");
  }

  function makeOfficialTrend(trend) {
    var direction = !trend || !isNumber(trend.change) || trend.change === 0
      ? "neutral" : trend.change > 0 ? "positive" : "negative";
    var box = document.createElement("div");
    box.className = "official-trend trend-" + direction;
    box.setAttribute("aria-label", "最近官方观测趋势");
    var head = document.createElement("div");
    head.className = "official-trend-head";
    appendText(head, "span", "official-trend-label", "RECENT OBSERVATIONS");
    appendText(head, "span", "official-trend-count", (trend ? trend.count : 0) + " / 8");
    box.appendChild(head);
    if (!trend || trend.count < 2) {
      appendText(box, "p", "official-trend-empty", trend && trend.count === 1
        ? "当前仅1个可追溯观测点，等待下次官方刷新补足。"
        : "暂无可追溯观测窗口，等待官方刷新。"
      );
      return box;
    }
    var aria = "最近" + trend.count + "个官方观测点，" + trend.startAsOf + "至" + trend.endAsOf
      + "，" + formatTrendChange(trend);
    box.appendChild(makeSparkline(trend.values, direction, aria));
    var meta = document.createElement("div");
    meta.className = "official-trend-meta";
    appendText(meta, "span", "", trend.startAsOf + " → " + trend.endAsOf);
    appendText(meta, "span", "", formatTrendChange(trend));
    box.appendChild(meta);
    return box;
  }

  function statusLabel(asset) {
    if (asset.demo) return { className: "demo-chip", text: "DEMO" };
    if (asset.status === "provider") return { className: "proxy-chip", text: "FREE · PROXY" };
    if (asset.status === "stale") return { className: "stale-chip", text: "STALE" };
    if (asset.status === "error") return { className: "error-chip", text: "ERROR" };
    if (asset.status === "partial") return { className: "partial-chip", text: "PARTIAL" };
    if (asset.source && asset.source.seriesId === "RWTC") {
      return { className: "official-chip", text: "EIA · DAILY" };
    }
    if (asset.id === "bitcoin") return { className: "official-chip", text: "BTC · DAILY" };
    return { className: "official-chip", text: "FRED · DAILY" };
  }

  function isSafeHref(value) {
    return typeof value === "string" && (/^https:\/\//.test(value) || /^\.\.\/[a-z0-9/_-]*$/i.test(value));
  }

  function appendSource(parent, asset) {
    var source = asset.source || {};
    if (isSafeHref(source.url)) {
      var link = appendText(parent, "a", "source-link", source.name || "查看来源");
      link.href = source.url;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.setAttribute("aria-label", (source.name || "查看来源") + "（在新窗口打开）");
      if (source.name === "Powered by CoinGecko") link.classList.add("coingecko-attribution");
      return;
    }
    appendText(parent, "span", "source-name", source.name || "来源未提供");
  }

  var riskView = null;

  /* 品类行情板：视图实例只建一次，切换品类和展开折叠都在实例内部完成。 */
  var boardViewInstance = null;
  function renderBoardCategories(board, viewModule) {
    if (!viewModule || !boardPanel) return;
    if (!boardViewInstance) boardViewInstance = viewModule.createBoardView(document, window);
    boardViewInstance.render(board);
  }

  /* 地缘风险定价要读的是原始的分区资源（跨资产、宏观雷达、OFR），
     不是适配后的卡片；这里只留住本轮 risk 分区拿到的那一份，不另发请求。 */
  var riskSources = null;

  function renderRiskCards(cards, viewModule) {
    if (!viewModule || typeof viewModule.createRiskView !== "function") {
      throw new Error("市场状态视图模块契约无效");
    }
    if (!riskView) {
      riskView = viewModule.createRiskView({
        document: document,
        grid: riskGrid,
        summary: riskSummary,
        isNumber: isNumber,
        appendText: appendText,
        appendSupportingHealth: appendSupportingHealth,
        formatDate: formatDate,
        appendSource: appendSource,
        formatTimestamp: formatTimestamp,
        isSafeHref: isSafeHref
      });
    }
    riskView.render(cards);
    if (typeof riskView.renderGeo === "function") riskView.renderGeo(riskSources);
    bindRadarDetail(cards);
    return terminalVisualsPromise.then(function (visuals) {
      if (visuals) visuals.renderRiskRadar(cards);
    });
  }

  function formatSignedPercent(value) {
    if (!isNumber(value)) return "—";
    var sign = value > 0 ? "+" : value < 0 ? "−" : "";
    return sign + Math.abs(value).toFixed(2) + "%";
  }

  function researchStatusLabel(card) {
    if (card.status === "stale") return { className: "stale-chip", text: "STALE" };
    if (card.status === "error") return { className: "error-chip", text: "ERROR" };
    if (card.status === "partial") return { className: "partial-chip", text: "PARTIAL" };
    return { className: "official-chip", text: "ACTIVE" };
  }

  function appendResearchFooter(card, parent) {
    var meta = document.createElement("div");
    meta.className = "research-meta";
    appendText(meta, "span", "", "数据日 · " + formatDate(card.asOf, false));
    appendText(meta, "span", "", card.frequency || "频率未提供");
    parent.appendChild(meta);

    var footer = document.createElement("div");
    footer.className = "research-footer";
    var sourceBox = document.createElement("div");
    sourceBox.className = "research-source";
    appendSource(sourceBox, card);
    footer.appendChild(sourceBox);
    var time = appendText(footer, "time", "", "更新 · " + formatTimestamp(card.updatedAt, false));
    if (card.updatedAt) time.dateTime = card.updatedAt;
    var chip = researchStatusLabel(card);
    appendText(footer, "span", "status-chip " + chip.className, chip.text);
    if (isSafeHref(card.detailUrl)) {
      var detail = appendText(footer, "a", "detail-link", "查看完整页面 →");
      detail.href = card.detailUrl;
    }
    parent.appendChild(footer);
  }

  function appendQualitySummary(parent, quality) {
    if (!quality || !quality.counts) return;
    var strip = document.createElement("div");
    strip.className = "quality-strip";
    strip.setAttribute("aria-label", "逐条数据状态覆盖");
    [
      ["行情", quality.counts.market],
      ["回退", quality.counts.fallback],
      ["估算", quality.counts.estimate],
      ["待确认", quality.counts.unknown + quality.counts.unavailable]
    ].forEach(function (item) {
      var cell = document.createElement("span");
      cell.className = "quality-item";
      appendText(cell, "strong", "quality-value", item[1]);
      appendText(cell, "span", "quality-label", item[0]);
      strip.appendChild(cell);
    });
    parent.appendChild(strip);
  }

  function formatHealthCoverage(value) {
    if (!isNumber(value)) return "—";
    return value.toFixed(value % 1 === 0 ? 0 : 2) + "%";
  }

  function appendSourceHealth(parent, health) {
    var state = health || unavailableSourceHealth("unknown");
    var panel = document.createElement("div");
    panel.className = "pipeline-health pipeline-health-" + state.status;
    panel.setAttribute("aria-label", "数据管道健康状态");

    var header = document.createElement("div");
    header.className = "pipeline-health-head";
    appendText(header, "span", "pipeline-health-label", "SOURCE HEALTH");
    appendText(header, "strong", "pipeline-health-state", state.label || "UNKNOWN");
    panel.appendChild(header);

    var metrics = document.createElement("div");
    metrics.className = "pipeline-health-metrics";
    appendText(metrics, "span", "", "本轮行情 " + formatHealthCoverage(state.freshCoveragePct));
    appendText(metrics, "span", "", "连续失败 " + (state.historyKnown ? state.consecutiveFailures + "次" : "历史待建立"));
    appendText(metrics, "span", "", "最近尝试 " + formatTimestamp(state.lastAttemptAt, false));
    appendText(metrics, "span", "", "最后成功 " + formatTimestamp(state.lastSuccessfulAt, false));
    panel.appendChild(metrics);
    appendText(panel, "p", "pipeline-health-note", state.note || "来源健康说明不可用。");
    parent.appendChild(panel);
  }

  function appendSupportingHealth(parent, health) {
    var state = health || unavailableSupportingHealth("unknown");
    var panel = document.createElement("div");
    panel.className = "pipeline-health pipeline-health-" + state.status;
    panel.setAttribute("aria-label", "辅助来源更新链健康状态");

    var header = document.createElement("div");
    header.className = "pipeline-health-head";
    appendText(header, "span", "pipeline-health-label", "UPDATE HEALTH");
    appendText(header, "strong", "pipeline-health-state", state.label || "UNKNOWN");
    panel.appendChild(header);

    var metrics = document.createElement("div");
    metrics.className = "pipeline-health-metrics";
    appendText(metrics, "span", "", "本轮刷新 " + formatHealthCoverage(state.freshCoveragePct));
    appendText(metrics, "span", "", "可展示 " + formatHealthCoverage(state.publishedCoveragePct));
    appendText(metrics, "span", "", "连续失败 " + (state.historyKnown ? state.consecutiveFailures + "次" : "历史待建立"));
    appendText(metrics, "span", "", "最近尝试 " + formatTimestamp(state.lastAttemptAt, false));
    panel.appendChild(metrics);
    appendText(panel, "p", "pipeline-health-note", state.note || "更新链说明不可用。");
    parent.appendChild(panel);
  }

  function appendOfficialUpdateHealth(parent, health) {
    var state = health || unavailableOfficialSourceHealth("unknown");
    var panel = document.createElement("div");
    panel.className = "pipeline-health official-update-health pipeline-health-" + state.status;
    panel.setAttribute("aria-label", (state.seriesId || "官方序列") + "逐源更新链健康状态");

    var header = document.createElement("div");
    header.className = "pipeline-health-head";
    appendText(header, "span", "pipeline-health-label", "UPDATE HEALTH");
    appendText(header, "strong", "pipeline-health-state", state.label || "UNKNOWN");
    panel.appendChild(header);

    var metrics = document.createElement("div");
    metrics.className = "pipeline-health-metrics";
    appendText(metrics, "span", "", "本轮更新 " + (state.refreshLabel || "不可验证"));
    if (state.accessMethodLabel) {
      appendText(metrics, "span", "", "访问路径 " + state.accessMethodLabel);
    }
    appendText(metrics, "span", "", "连续失败 " + (state.historyKnown ? state.consecutiveFailures + "次" : "历史待建立"));
    appendText(metrics, "span", "", "最近尝试 " + formatTimestamp(state.lastAttemptAt, false));
    appendText(metrics, "span", "", "最后成功 " + formatTimestamp(state.lastSuccessfulAt, false));
    panel.appendChild(metrics);
    appendText(panel, "p", "pipeline-health-note", state.note || "逐源更新链说明不可用。");
    parent.appendChild(panel);
  }

  var researchView = null;

  function renderResearchCards(cards, viewModule) {
    if (!viewModule || typeof viewModule.createResearchView !== "function") {
      throw new Error("市场研究视图模块契约无效");
    }
    if (!researchView) {
      researchView = viewModule.createResearchView({
        document: document,
        grid: researchGrid,
        summary: researchSummary,
        isNumber: isNumber,
        appendText: appendText,
        formatSignedPercent: formatSignedPercent,
        appendQualitySummary: appendQualitySummary,
        appendSourceHealth: appendSourceHealth,
        rankCrossAssetPeriod: rankCrossAssetPeriod,
        periodTabTargetIndex: periodTabTargetIndex,
        appendResearchFooter: appendResearchFooter
      });
    }
    researchView.render(cards);
    return terminalVisualsPromise.then(function (visuals) {
      if (visuals) visuals.renderGlobalRiskHeatmap(cards);
    });
  }

  var informationView = null;

  function renderInformationCards(cards, viewModule) {
    if (!viewModule || typeof viewModule.createInformationView !== "function") {
      throw new Error("事件资讯视图模块契约无效");
    }
    if (!informationView) {
      informationView = viewModule.createInformationView({
        document: document,
        grid: informationGrid,
        summary: informationSummary,
        appendText: appendText,
        formatDate: formatDate,
        appendSource: appendSource,
        formatTimestamp: formatTimestamp,
        isSafeHref: isSafeHref,
        appendSupportingHealth: appendSupportingHealth
      });
    }
    informationView.render(cards);
  }

  var operationsView = null;

  function renderOperationsCards(cards, viewModule) {
    if (!viewModule || typeof viewModule.createOperationsView !== "function") {
      throw new Error("稳定V1运行证据视图模块契约无效");
    }
    if (!operationsView) {
      operationsView = viewModule.createOperationsView({
        document: document,
        grid: operationsGrid,
        summary: operationsSummary,
        appendText: appendText,
        formatHealthCoverage: formatHealthCoverage,
        formatTimestamp: formatTimestamp,
        isSafeHref: isSafeHref
      });
    }
    operationsView.render(cards);
    return terminalVisualsPromise.then(function (visuals) {
      if (visuals) visuals.renderPipelineOverview(cards);
    });
  }

  function renderMarketLicenseNotice(state) {
    if (!licenseNotice || !licenseLabel || !licenseTitle || !licenseCopy) return;
    licenseNotice.className = "license-notice status-" + state.status;
    if (state.status === "free") {
      licenseLabel.textContent = "FREE DATA";
      licenseTitle.textContent = "两项免费ETF代理已启用";
      licenseCopy.textContent = "DIA与GLD由TradingView官方免费组件直接展示；均明确标为代理，不保存、导出或再分发原始行情，也不需要API密钥。";
    } else {
      licenseLabel.textContent = "SOURCE UNKNOWN";
      licenseTitle.textContent = "免费代理状态暂不可核验";
      licenseCopy.textContent = "无法读取或验证免费嵌入契约；页面不会用来源不明的数值替代SPY、QQQ、DIA或GLD组件。";
    }
  }

  function makeProviderWidget(asset) {
    var shell = document.createElement("div");
    shell.className = "provider-widget-shell";
    shell.setAttribute("data-provider-state", "loading");
    shell.setAttribute("data-provider-symbol", asset.symbol);
    var widget = document.createElement("tv-mini-chart");
    widget.setAttribute("symbol", asset.externalDisplay.widgetSymbol);
    widget.setAttribute("theme", "dark");
    widget.setAttribute("transparent", "");
    widget.setAttribute("aria-label", asset.symbol + "免费代理行情，由TradingView提供");
    shell.appendChild(widget);
    var fallback = document.createElement("p");
    fallback.className = "provider-widget-fallback";
    appendText(fallback, "span", "provider-widget-fallback-copy", "免费行情组件加载中；若持续不可用，");
    var link = appendText(fallback, "a", "source-link", "前往TradingView查看 " + asset.symbol);
    link.href = asset.source.url;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    shell.appendChild(fallback);
    return shell;
  }


  function makeCard(asset) {
    var direction = directionOf(asset);
    var card = document.createElement("article");
    card.className = "asset-card " + direction + " status-" + asset.status;
    card.setAttribute("role", "listitem");

    var top = document.createElement("div");
    top.className = "card-top";
    var titleBox = document.createElement("div");
    appendText(titleBox, "h3", "asset-name", asset.name);
    appendText(titleBox, "span", "asset-en", asset.nameEn + " · " + asset.category);
    top.appendChild(titleBox);
    appendText(top, "span", "asset-symbol", asset.symbol);
    if (watch) top.appendChild(watch.button(asset.symbol));
    var detail = appendText(top, "button", "detail-open", "详情");
    detail.type = "button";
    detail.setAttribute("aria-label", "查看 " + asset.symbol + " 数据详情");
    detail.addEventListener("click", function () {
      import("./finance-terminal-detail-view.mjs").then(function (mod) {
        mod.openAsset(document, window, asset);
      }).catch(function () {});
    });
    card.appendChild(top);

    if (asset.externalDisplay) {
      card.classList.add("provider-widget-card");
      card.appendChild(makeProviderWidget(asset));
      var proxyNote = appendText(card, "p", "official-note", asset.note);
      proxyNote.title = asset.note;
      var proxyDetails = document.createElement("div");
      proxyDetails.className = "asset-details";
      appendText(proxyDetails, "span", "", "代理原标的 · " + asset.proxyFor.symbol);
      appendText(proxyDetails, "span", "", asset.delayLabel);
      card.appendChild(proxyDetails);
      var proxyFooter = document.createElement("div");
      proxyFooter.className = "asset-footer";
      var proxySource = document.createElement("div");
      proxySource.className = "asset-source";
      appendSource(proxySource, asset);
      proxyFooter.appendChild(proxySource);
      appendText(proxyFooter, "span", "provider-time provider-runtime-status", "组件加载中 · 行情时效见组件");
      var proxyChip = statusLabel(asset);
      appendText(proxyFooter, "span", "status-chip " + proxyChip.className, proxyChip.text);
      card.appendChild(proxyFooter);
      return card;
    }

    appendText(card, "div", "asset-price", formatPrice(asset));
    var changeRow = document.createElement("div");
    changeRow.className = "change-row";
    appendText(changeRow, "span", "asset-change", formatChange(asset));
    var arrow = direction === "positive" ? "▲" : direction === "negative" ? "▼" : "●";
    var changeText = asset.demo ? "演示涨跌" : asset.status === "error" ? "数据不可用" : "较前值";
    appendText(changeRow, "span", "change-word", arrow + " " + changeText);
    card.appendChild(changeRow);

    if (asset.demo) {
      card.appendChild(makeSparkline(asset.spark, direction));
    } else {
      if (asset.observationTrend) card.appendChild(makeOfficialTrend(asset.observationTrend));
      var officialNote = appendText(card, "p", "official-note", asset.note || "日频官方数据");
      officialNote.title = asset.note || "";
      if (asset.updateHealth) appendOfficialUpdateHealth(card, asset.updateHealth);
    }

    var details = document.createElement("div");
    details.className = "asset-details";
    appendText(details, "span", "", "数据日 · " + formatDate(asset.asOf, asset.demo));
    appendText(details, "span", "", asset.delayLabel || "频率未提供");
    card.appendChild(details);

    var footer = document.createElement("div");
    footer.className = "asset-footer";
    var sourceBox = document.createElement("div");
    sourceBox.className = "asset-source";
    appendSource(sourceBox, asset);
    footer.appendChild(sourceBox);
    var time = appendText(footer, "time", "", "更新 · " + formatTimestamp(asset.updatedAt, asset.demo));
    if (asset.updatedAt) time.dateTime = asset.updatedAt;
    var chip = statusLabel(asset);
    appendText(footer, "span", "status-chip " + chip.className, chip.text);
    card.appendChild(footer);
    return card;
  }

  function updateSummary(data) {
    var proxies = data.assets.filter(function (asset) { return Boolean(asset.externalDisplay); });
    var official = data.assets.filter(function (asset) {
      return asset.demo === false && !asset.externalDisplay;
    });
    var demos = data.assets.filter(function (asset) { return asset.demo === true; });
    var ok = official.filter(function (asset) { return asset.status === "ok"; });
    var partial = official.filter(function (asset) { return asset.status === "partial"; });
    var stale = official.filter(function (asset) { return asset.status === "stale"; });
    var errors = official.filter(function (asset) { return asset.status === "error"; });
    var breakdown = ok.length + "项站内真实正常 · " + proxies.length + "项免费嵌入代理 · "
      + partial.length + "项降级 · " + stale.length + "项过期 · " + errors.length + "项不可用";
    var compactStatus = [ok.length + "正常"];
    if (partial.length > 0) compactStatus.push(partial.length + "降级");
    if (stale.length > 0) compactStatus.push(stale.length + "过期");
    if (errors.length > 0) compactStatus.push(errors.length + "不可用");
    compactStatus.push(proxies.length + "提供方代理");
    marketState.textContent = compactStatus.join("／");
    marketState.setAttribute("aria-label", "核心资产状态：" + compactStatus.join("，"));

    if (errors.length > 0) {
      banner.className = "data-banner status-error";
      bannerLabel.textContent = "PARTIAL";
      bannerTitle.textContent = "部分真实数据暂不可用";
      bannerCopy.textContent = errors.map(function (asset) { return asset.symbol; }).join("、") + "已隐藏无效数值；其他卡片保留各自的来源和状态。";
      bannerNote.textContent = ok.length + " REAL · " + partial.length + " PARTIAL · " + stale.length
        + " STALE · " + errors.length + " ERROR · " + proxies.length + " FREE PROXY";
      dataStatus.textContent = breakdown;
    } else if (stale.length > 0) {
      banner.className = "data-banner status-stale";
      bannerLabel.textContent = "STALE";
      bannerTitle.textContent = stale.length === 1 ? stale[0].symbol + "数据已过期" : "部分真实数据已过期";
      bannerCopy.textContent = "页面保留同一标的最后有效值并醒目标记；没有使用演示值冒充真实行情。";
      bannerNote.textContent = ok.length + " REAL · " + partial.length + " PARTIAL · " + stale.length
        + " STALE · " + proxies.length + " FREE PROXY";
      dataStatus.textContent = breakdown;
    } else if (partial.length > 0) {
      banner.className = "data-banner status-stale";
      bannerLabel.textContent = "PARTIAL";
      bannerTitle.textContent = "部分真实数据使用明确降级来源";
      bannerCopy.textContent = partial.map(function (asset) { return asset.symbol; }).join("、")
        + "已在卡片内同步显示来源、时间与涨跌口径；没有静默切换。";
      bannerNote.textContent = ok.length + " REAL · " + partial.length + " PARTIAL · "
        + proxies.length + " FREE PROXY";
      dataStatus.textContent = breakdown;
    } else {
      banner.className = "data-banner";
      bannerLabel.textContent = "FREE";
      bannerTitle.textContent = "核心资产已取消演示数值";
      bannerCopy.textContent = "DGS10、DTWEXBGS、EIA RWTC与BTC/USD读取站内每日数据；DIA与GLD由TradingView免费组件直接展示，并明确标注ETF代理关系。";
      bannerNote.textContent = "4 REAL · 2 FREE PROXY · 0 DEMO";
      dataStatus.textContent = breakdown;
    }
  }

  function render(data) {
    var proxies = data.assets.filter(function (asset) { return Boolean(asset.externalDisplay); });
    var official = data.assets.filter(function (asset) {
      return asset.demo === false && !asset.externalDisplay;
    });
    var demos = data.assets.filter(function (asset) { return asset.demo === true; });
    var unavailable = official.filter(function (asset) { return asset.status === "error"; });
    lastRendered = data;
    /* 自选前置，只改呈现顺序，不改数值口径。 */
    var picked = watch ? watch.select(data.assets)
      : { ordered: data.assets, shown: data.assets };

    grid.textContent = "";
    picked.shown.forEach(function (asset) {
      grid.appendChild(makeCard(asset));
    });
    grid.setAttribute("aria-busy", "false");
    pageUpdated.textContent = data.updatedAt ? formatTimestamp(data.updatedAt, false) : "真实数据更新时间不可用";
    if (data.updatedAt) pageUpdated.dateTime = data.updatedAt;
    pageSource.textContent = data.source;
    assetCount.textContent = data.assets.length + "项资产 · " + (official.length - unavailable.length)
      + "项站内真实可用 / " + unavailable.length + "项不可用 / "
      + proxies.length + "项免费嵌入代理 / " + demos.length + "项演示";
    updateSummary(data);
    var overview = picked.ordered === data.assets ? data
      : Object.assign({}, data, { assets: picked.ordered });
    terminalVisualsPromise.then(function (visuals) {
      if (visuals) visuals.renderMarketOverview(overview);
    });
  }



  function renderError(error) {
    grid.textContent = "";
    var message = document.createElement("div");
    message.className = "load-error";
    message.textContent = "页面配置加载失败：" + error.message + " 请稍后刷新或返回首页。";
    grid.appendChild(message);
    grid.setAttribute("aria-busy", "false");
    dataStatus.textContent = "页面数据不可用";
    marketState.textContent = "DATA ERROR";
    banner.className = "data-banner status-error";
    bannerLabel.textContent = "ERROR";
    bannerTitle.textContent = "页面数据不可用";
    bannerCopy.textContent = "基础配置加载失败，页面已停止展示数值。";
    bannerNote.textContent = "NO DATA DISPLAYED";
    terminalVisualsPromise.then(function (visuals) {
      if (visuals) visuals.renderCriticalError(error && error.message);
    });
    riskGrid.textContent = "";
    var riskMessage = appendText(riskGrid, "div", "load-error", "市场状态暂不可用：基础配置加载失败。");
    riskMessage.setAttribute("role", "alert");
    riskGrid.setAttribute("aria-busy", "false");
    riskSummary.textContent = "SIGNALS UNAVAILABLE";
    researchGrid.textContent = "";
    var researchMessage = appendText(researchGrid, "div", "load-error", "市场研究暂不可用：基础配置加载失败。");
    researchMessage.setAttribute("role", "alert");
    researchGrid.setAttribute("aria-busy", "false");
    researchSummary.textContent = "RESEARCH UNAVAILABLE";
    informationGrid.textContent = "";
    var informationMessage = appendText(informationGrid, "div", "load-error", "事件资讯暂不可用：基础配置加载失败。");
    informationMessage.setAttribute("role", "alert");
    informationGrid.setAttribute("aria-busy", "false");
    informationSummary.textContent = "INFORMATION UNAVAILABLE";
    operationsGrid.textContent = "";
    var operationsMessage = appendText(operationsGrid, "div", "load-error", "数据运行状态暂不可用：基础配置加载失败。");
    operationsMessage.setAttribute("role", "alert");
    operationsGrid.setAttribute("aria-busy", "false");
    operationsSummary.textContent = "PIPELINES UNAVAILABLE";
    renderMarketLicenseNotice(unavailableMarketLicenseReadiness(error));
    if (pageAnnouncer) {
      pageAnnouncer.setAttribute("aria-live", "assertive");
      pageAnnouncer.textContent = "金融终端加载失败，页面未显示任何默认数值。";
    }
  }

  function countStatuses(cards) {
    return (cards || []).reduce(function (totals, card) {
      var key = card && typeof card.status === "string" ? card.status : "error";
      totals[key] = (totals[key] || 0) + 1;
      return totals;
    }, { ok: 0, partial: 0, stale: 0, error: 0 });
  }

  function announceExperience(experience) {
    if (!pageAnnouncer) return;
    var official = experience.market.assets.filter(function (asset) {
      return asset.demo === false && !asset.externalDisplay;
    });
    var proxies = experience.market.assets.filter(function (asset) { return Boolean(asset.externalDisplay); });
    var marketIssues = official.filter(function (asset) { return asset.status !== "ok"; }).length;
    var grouped = [experience.risks, experience.research, experience.information].reduce(function (total, cards) {
      var counts = countStatuses(cards);
      total.partial += counts.partial;
      total.stale += counts.stale;
      total.error += counts.error;
      return total;
    }, { partial: 0, stale: 0, error: 0 });
    var operationIssues = experience.operations.filter(function (card) { return card.status !== "healthy"; }).length;
    pageAnnouncer.setAttribute("aria-live", "polite");
    pageAnnouncer.textContent = "金融终端加载完成。6项核心资产，"
      + proxies.length + "项免费嵌入代理，" + marketIssues + "项站内行情需要注意；其他模块中"
      + grouped.partial + "项部分数据，" + grouped.stale + "项过期，"
      + grouped.error + "项不可用；四条数据管道中" + operationIssues + "条需要注意。";
  }

  function announceMarketReady(market) {
    if (!pageAnnouncer) return;
    var official = market.assets.filter(function (asset) {
      return asset.demo === false && !asset.externalDisplay;
    });
    var issues = official.filter(function (asset) { return asset.status !== "ok"; }).length;
    pageAnnouncer.setAttribute("aria-live", "polite");
    pageAnnouncer.textContent = "金融终端首屏加载完成。6项核心资产中"
      + issues + "项站内行情需要注意；首屏以下分区将在接近视口时继续加载。";
  }


  function waitForProviderWidgetRegistration(registry, tagName, timeoutMs) {
    if (!registry || typeof registry.get !== "function" || typeof registry.whenDefined !== "function") {
      return Promise.resolve({ status: "unavailable", reason: "custom-elements-unavailable" });
    }
    if (registry.get(tagName)) {
      return Promise.resolve({ status: "registered", reason: "custom-element-registered" });
    }
    return new Promise(function (resolve) {
      var settled = false;
      var timer = setTimeout(function () {
        if (settled) return;
        settled = true;
        resolve({ status: "unavailable", reason: "registration-timeout" });
      }, timeoutMs);
      registry.whenDefined(tagName).then(function () {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve({ status: "registered", reason: "custom-element-registered" });
      }).catch(function () {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve({ status: "unavailable", reason: "registration-failed" });
      });
    });
  }

  function inspectProviderWidgetHost(widget, tagName, successEvidence) {
    if (!widget) return { status: "unavailable", reason: "component-host-missing" };
    if (String(widget.localName || "").toLowerCase() !== tagName) {
      return { status: "unavailable", reason: "component-host-tag-mismatch" };
    }
    if (widget.isConnected !== true) {
      return { status: "unavailable", reason: "component-host-disconnected" };
    }
    if (typeof widget.matches !== "function" || !widget.matches(":defined")) {
      return { status: "unavailable", reason: "component-host-not-defined" };
    }
    if (typeof widget.getBoundingClientRect !== "function") {
      return { status: "unavailable", reason: "component-host-layout-unavailable" };
    }
    var rect = widget.getBoundingClientRect();
    if (!rect || !(rect.width > 0) || !(rect.height > 0)) {
      return { status: "unavailable", reason: "component-host-empty-layout" };
    }
    return { status: "mounted", reason: successEvidence };
  }

  function setProviderWidgetShellState(shell, state) {
    shell.setAttribute("data-provider-state", state.status);
    shell.setAttribute("data-provider-reason", state.reason);
    var unavailableCopy = providerWidgetUnavailableCopy(state.reason);
    var copy = shell.querySelector(".provider-widget-fallback-copy");
    if (copy) {
      copy.textContent = state.status === "mounted"
        ? "免费行情组件宿主已挂载；"
        : state.status === "registered"
          ? "组件代码已注册，正在验证挂载；"
          : unavailableCopy.fallback;
    }
    var card = shell.closest(".asset-card");
    var runtimeStatus = card && card.querySelector(".provider-runtime-status");
    if (runtimeStatus) {
      runtimeStatus.textContent = state.status === "mounted"
        ? "组件宿主已挂载 · 报价状态见组件"
        : state.status === "registered"
          ? "组件已注册 · 正在验证宿主"
          : unavailableCopy.status;
    }
  }

  function providerWidgetUnavailableCopy(reason) {
    if (reason === "registration-timeout") {
      return {
        fallback: "免费行情组件加载超时；",
        status: "组件加载超时 · 使用来源链接"
      };
    }
    if (reason === "registration-failed") {
      return {
        fallback: "免费行情组件注册失败；",
        status: "组件注册失败 · 使用来源链接"
      };
    }
    if (reason === "custom-elements-unavailable" || reason === "runtime-contract-unavailable") {
      return {
        fallback: "当前浏览器无法验证免费行情组件；",
        status: "组件验证不可用 · 使用来源链接"
      };
    }
    if ([
      "component-host-missing",
      "component-host-tag-mismatch",
      "component-host-disconnected",
      "component-host-not-defined",
      "component-host-layout-unavailable",
      "component-host-empty-layout"
    ].indexOf(reason) !== -1) {
      return {
        fallback: "免费行情组件宿主验证失败；",
        status: "组件挂载异常 · 使用来源链接"
      };
    }
    return {
      fallback: "免费行情组件暂不可用；",
      status: "组件未加载 · 使用来源链接"
    };
  }

  function applyProviderWidgetState(state) {
    Array.prototype.slice.call(document.querySelectorAll(".provider-widget-shell")).forEach(function (shell) {
      setProviderWidgetShellState(shell, state);
    });
  }

  function verifyProviderWidgetHosts(runtime) {
    return new Promise(function (resolve) {
      window.setTimeout(resolve, runtime.hostCheckDelayMs);
    }).then(function () {
      return Array.prototype.slice.call(document.querySelectorAll(".provider-widget-shell")).map(function (shell) {
        var state = inspectProviderWidgetHost(
          shell.querySelector(runtime.registrationTag),
          runtime.registrationTag,
          runtime.successEvidence
        );
        setProviderWidgetShellState(shell, state);
        return state;
      });
    });
  }

  function monitorProviderWidgets(marketLicenseState) {
    var runtime = marketLicenseState && marketLicenseState.runtimeVerification;
    if (!runtime || marketLicenseState.status !== "free") {
      var contractFailure = { status: "unavailable", reason: "runtime-contract-unavailable" };
      applyProviderWidgetState(contractFailure);
      return Promise.resolve(contractFailure);
    }
    var params = new URLSearchParams(window.location.search);
    var useProductionEvidenceWindow = params.get("runtimeEvidence") === "1";
    var timeoutMs = params.get("regression") === "1" && !useProductionEvidenceWindow
      ? PROVIDER_WIDGET_REGRESSION_TIMEOUT_MS
      : runtime.registrationTimeoutMs;
    return waitForProviderWidgetRegistration(window.customElements, runtime.registrationTag, timeoutMs)
      .then(function (state) {
        applyProviderWidgetState(state);
        if (state.status === "registered") {
          return verifyProviderWidgetHosts(runtime);
        }
        if (state.status === "unavailable" && runtime.lateRegistrationRecovery
          && window.customElements && typeof window.customElements.whenDefined === "function") {
          window.customElements.whenDefined(runtime.registrationTag).then(function () {
            applyProviderWidgetState({ status: "registered", reason: "late-custom-element-registration" });
            return verifyProviderWidgetHosts(runtime);
          }).catch(function () {
            // The official-link fallback remains available.
          });
        }
        return state;
      });
  }


  function renderDeferredSectionError(name, error) {
    var specs = {
      board: [boardPanel, boardSummary, "品类行情", "CATEGORIES UNAVAILABLE"],
      risk: [riskGrid, riskSummary, "市场状态", "SIGNALS UNAVAILABLE"],
      research: [researchGrid, researchSummary, "市场研究", "RESEARCH UNAVAILABLE"],
      information: [informationGrid, informationSummary, "事件资讯", "INFORMATION UNAVAILABLE"],
      operations: [operationsGrid, operationsSummary, "数据运行状态", "PIPELINES UNAVAILABLE"]
    };
    var spec = specs[name];
    if (!spec) return;
    spec[0].textContent = "";
    var message = appendText(spec[0], "div", "load-error", spec[2] + "暂不可用：" + error.message);
    message.setAttribute("role", "alert");
    spec[0].setAttribute("aria-busy", "false");
    spec[1].textContent = spec[3];
    if (name === "research" || name === "operations") {
      terminalVisualsPromise.then(function (visuals) {
        if (!visuals) return;
        if (name === "research") visuals.renderGlobalRiskHeatmap([]);
        if (name === "operations") visuals.renderPipelineOverview([]);
      });
    }
  }

  function startFinanceTerminal() {
    var root = document.documentElement;
    return import("./finance-terminal-loader.mjs").then(function (loaderModule) {
      return loaderModule.startFinanceTerminal({
        buildCritical: function (config, sources) {
          var marketLicenseState;
          try {
            if (sources.marketLicense.error) throw sources.marketLicense.error;
            marketLicenseState = adaptMarketLicenseReadiness(sources.marketLicense.data);
          } catch (marketLicenseError) {
            marketLicenseState = unavailableMarketLicenseReadiness(marketLicenseError);
          }
          var marketData = sources.macro.error
            ? buildPageDataWithMacroError(
              config, sources.macro.error, undefined, sources.macroHealth,
              sources.assetRanking, sources.assetRankingHealth
            )
            : buildPageData(
              config, sources.macro.data, undefined, null, sources.macroHealth,
              sources.assetRanking, sources.assetRankingHealth
            );
          return {
            market: marketData,
            marketLicense: marketLicenseState,
            board: null,
            risks: [],
            research: [],
            information: [],
            operations: []
          };
        },
        buildSection: function (name, group) {
          if (name === "board") {
            return loadSectionView(name).then(function () {
              return loadSectionData(name);
            }).then(function (data) {
              return data.buildBoard(group);
            });
          }
          if (name === "risk") {
            riskSources = group;
            return loadSectionView(name).then(function () {
              return buildRiskCards(group);
            });
          }
          if (name === "research") {
            return loadSectionView(name).then(function () {
              return buildResearchCards(group);
            });
          }
          if (name === "information") {
            return loadSectionView(name).then(function () {
              return loadSectionData(name);
            }).then(function (data) {
              return data.buildInformationCards(group);
            });
          }
          if (name === "operations") {
            return loadSectionView(name).then(function () {
              return loadSectionData(name);
            }).then(function (data) {
              return data.buildOperationsCards(group);
            });
          }
          throw new Error("未知金融终端分区：" + name);
        },
        renderCritical: function (experience) {
          render(experience.market);
          renderMarketLicenseNotice(experience.marketLicense);
        },
        renderSection: function (name, cards) {
          if (name === "board") return renderBoardCategories(cards, sectionViewModules.board);
          if (name === "risk") return renderRiskCards(cards, sectionViewModules.risk);
          if (name === "research") return renderResearchCards(cards, sectionViewModules.research);
          if (name === "information") return renderInformationCards(cards, sectionViewModules.information);
          if (name === "operations") return renderOperationsCards(cards, sectionViewModules.operations);
          return undefined;
        },
        renderSectionError: renderDeferredSectionError,
        announceCritical: function (experience) { announceMarketReady(experience.market); },
        announceComplete: announceExperience,
        monitorProvider: function (marketLicense) { return monitorProviderWidgets(marketLicense); },
        runRegression: function () {
          return terminalVisualsPromise.then(function () {
            return import("./finance-terminal-regression.mjs").then(function (regressionModule) {
              return regressionModule.runBrowserRegressionProbe({
                providerWidgetUnavailableCopy: providerWidgetUnavailableCopy
              });
            });
          });
        },
        experienceKeys: {
          board: "board",
          risk: "risks",
          research: "research",
          information: "information",
          operations: "operations"
        },
        sections: {
          board: document.getElementById("board-section"),
          /* 风险雷达画在首屏总览里，数据却属于 risk 分区。窄屏下 #risk-section
             在四千多像素之下，只观察它的话雷达会一直停在 LOADING，直到访客滚到
             那个不相干的分区为止；所以雷达面板本身也算 risk 的触发元素。 */
          risk: [document.getElementById("risk-section"),
                 document.querySelector(".risk-radar-panel")],
          research: document.getElementById("research-section"),
          information: document.getElementById("information-section"),
          operations: document.getElementById("operations-section")
        },
        navigationLinks: document.querySelectorAll(".section-nav a")
      });
    }).catch(function (error) {
      root.setAttribute("data-critical-data-state", "error");
      renderError(error);
      if (new URLSearchParams(window.location.search).get("regression") === "1") {
        var output = document.createElement("pre");
        output.id = "finance-terminal-regression-result";
        output.hidden = true;
        output.textContent = JSON.stringify({
          status: "fail",
          failures: ["bootFailure"],
          error: error && error.message ? error.message : "金融终端启动失败"
        });
        document.body.appendChild(output);
        root.setAttribute("data-regression-status", "fail");
      }
    });
  }

  startFinanceTerminal();
})(typeof globalThis !== "undefined" ? globalThis : this);

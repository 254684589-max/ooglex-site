(function (root) {
  "use strict";

  var MACRO_DATA_URL = "../macro-radar/data.json";
  var MACRO_HEALTH_URL = "../macro-radar/health.json";
  var FEAR_GREED_DATA_URL = "../fear-greed/data.json";
  var FEAR_GREED_HEALTH_URL = "../fear-greed/health.json";
  var OFR_DATA_URL = "../ofr-monitor/data.json";
  var OFR_HEALTH_URL = "../ofr-monitor/health.json";
  var ASSET_TRACKER_DATA_URL = "../asset-tracker/data.json";
  var ASSET_TRACKER_HEALTH_URL = "../asset-tracker/health.json";
  var ASSET_RANKING_DATA_URL = "../asset-ranking/data.json";
  var ASSET_RANKING_HEALTH_URL = "../asset-ranking/health.json";
  var COMPANIES_DATA_URL = "../companies/data.json";
  var COMPANIES_HEALTH_URL = "../companies/health.json";
  var ECON_CALENDAR_DATA_URL = "../econ-calendar/data.json";
  var ECON_CALENDAR_HEALTH_URL = "../econ-calendar/health.json";
  var FINANCE_NEWS_DATA_URL = "../whats-latest/data.json";
  var FINANCE_NEWS_HEALTH_URL = "../whats-latest/health.json";
  var READINESS_DATA_URL = "readiness.json";
  var DGS10_MAX_BUSINESS_DAYS = 3;
  var DTWEXBGS_MAX_BUSINESS_DAYS = 3;
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
  var ECON_CALENDAR_MAX_AGE_HOURS = 36;
  var FINANCE_NEWS_MAX_AGE_HOURS = 12;
  var FINANCE_NEWS_ITEM_MAX_AGE_HOURS = 36;
  var READINESS_MAX_AGE_HOURS = 72;
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
  var PIPELINE_OPERATION_SPECS = {
    "macro-radar": {
      name: "宏观官方序列", nameEn: "Macro Official Series", symbol: "3 SERIES",
      expectedRecords: 3, unit: "项官方序列", detailUrl: "../macro-radar/",
      workflow: "macro_radar.yml", readinessEnabled: true
    },
    "asset-tracker": {
      name: "跨资产强弱", nameEn: "Cross-Asset Strength", symbol: "28 ASSETS",
      expectedRecords: 28, unit: "项资产", detailUrl: "../asset-tracker/",
      workflow: "asset_tracker.yml", readinessEnabled: false
    },
    companies: {
      name: "全球公司榜", nameEn: "Global Companies", symbol: "500 COMPANIES",
      expectedRecords: 500, unit: "家公司", detailUrl: "../companies/",
      workflow: "companies.yml", readinessEnabled: false
    },
    "asset-ranking": {
      name: "全球资产榜", nameEn: "Global Asset Ranking", symbol: "250 ASSETS",
      expectedRecords: 250, unit: "项资产", detailUrl: "../asset-ranking/",
      workflow: "asset_ranking.yml", readinessEnabled: false
    }
  };
  var SUPPORTING_HEALTH_SPECS = {
    "fear-greed": {
      ids: ["cnn-index"], required: ["cnn-index"], maxAgeHours: 72
    },
    "ofr-monitor": {
      ids: ["fsi", "funding", "mmf", "hedge", "bank"], required: ["fsi"], maxAgeHours: 72
    },
    "econ-calendar": {
      ids: ["weekly-calendar"], required: ["weekly-calendar"], maxAgeHours: 36
    },
    "whats-latest": {
      ids: ["markets-news", "tech-news", "ent-news", "sports-news", "world-news", "market-quotes"],
      required: ["markets-news"], maxAgeHours: 12
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
    var expectedRecords = { "asset-tracker": 28, companies: 500, "asset-ranking": 250 }[dataset];
    if (!expectedRecords || !health || typeof health !== "object") throw new Error("健康文件缺失");
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
    if (!coverage || coverage.expectedRecords !== expectedRecords || coverage.publishedRecords !== rows.length
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

  function supportingComponentPresent(dataset, componentId, data) {
    if (!data || typeof data !== "object") return false;
    if (dataset === "fear-greed") {
      return componentId === "cnn-index" && isNumber(data.score) && data.refs && data.refs.now
        && data.refs.now.score === data.score;
    }
    if (dataset === "ofr-monitor") {
      var value = data[componentId];
      if (componentId === "fsi") return value && isNumber(value.value) && typeof value.asOf === "string";
      if (componentId === "funding") return value && (value.sofr || value.effr) && typeof value.asOf === "string";
      if (componentId === "mmf") return value && isNumber(value.total) && typeof value.asOf === "string";
      if (componentId === "hedge") return value && Boolean(value.gav || value.nav || value.url);
      if (componentId === "bank") return value && Array.isArray(value.gsibs) && value.gsibs.length > 0;
      return false;
    }
    if (dataset === "econ-calendar") {
      return componentId === "weekly-calendar" && Array.isArray(data.events) && data.events.length > 0
        && data.count === data.events.length;
    }
    if (dataset === "whats-latest") {
      if (componentId === "market-quotes") return Array.isArray(data["markets"]) && data["markets"].length > 0;
      var categoryKeys = {
        "markets-news": "markets", "tech-news": "tech", "ent-news": "ent",
        "sports-news": "sports", "world-news": "world"
      };
      var key = categoryKeys[componentId];
      var matches = Array.isArray(data.categories) ? data.categories.filter(function (category) {
        return category && category.key === key;
      }) : [];
      return matches.length === 1 && Array.isArray(matches[0].items) && matches[0].items.length > 0;
    }
    return false;
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

  function adaptSupportingSourceHealth(health, dataset, data, now) {
    var spec = SUPPORTING_HEALTH_SPECS[dataset];
    if (!spec || !health || typeof health !== "object" || !data || typeof data !== "object") {
      throw new Error("辅助来源健康输入缺失");
    }
    if (health.contractVersion !== 1 || health.dataset !== dataset
      || ["healthy", "degraded", "failed", "unknown"].indexOf(health.status) === -1
      || PIPELINE_HISTORY_STATUSES.indexOf(health.historyStatus) === -1) {
      throw new Error("辅助来源健康契约无效");
    }
    var reportAge = hoursSince(health.generatedAt, now);
    if (reportAge === null || health.publishedSnapshotAt !== data.updatedAt) {
      throw new Error("辅助来源健康时间或数据快照错配");
    }
    if (health.lastSuccessfulAt !== null && hoursSince(health.lastSuccessfulAt, now) === null) {
      throw new Error("辅助来源最后成功时间无效");
    }
    if (!Array.isArray(health.components) || !sameStringArray(health.components.map(function (component) {
      return component && component.id;
    }), spec.ids)) throw new Error("辅助来源组件集合无效");

    var modes = {};
    var published = [];
    health.components.forEach(function (component) {
      if (!component || ["fresh", "fallback", "unavailable", "unknown"].indexOf(component.mode) === -1
        || ["healthy", "degraded", "failed", "unknown"].indexOf(component.status) === -1
        || component.status !== {
          fresh: "healthy", fallback: "degraded", unavailable: "failed", unknown: "unknown"
        }[component.mode]
        || typeof component.published !== "boolean"
        || component.published !== supportingComponentPresent(dataset, component.id, data)
        || component.requiredForTerminal !== (spec.required.indexOf(component.id) !== -1)) {
        throw new Error("辅助来源逐组件健康无效");
      }
      if (component.lastAttemptAt !== null && hoursSince(component.lastAttemptAt, now) === null) {
        throw new Error("辅助来源组件尝试时间无效");
      }
      if (component.lastSuccessAt !== null && hoursSince(component.lastSuccessAt, now) === null) {
        throw new Error("辅助来源组件成功时间无效");
      }
      modes[component.id] = component.mode;
      if (component.published) published.push(component.id);
    });

    function idsFor(mode) {
      return spec.ids.filter(function (componentId) { return modes[componentId] === mode; });
    }
    var fresh = idsFor("fresh");
    var fallback = idsFor("fallback");
    var unavailable = idsFor("unavailable");
    var unknown = idsFor("unknown");
    var coverage = health.coverage;
    if (!coverage || coverage.expectedComponents !== spec.ids.length
      || coverage.publishedComponents !== published.length
      || coverage.refreshedComponents !== fresh.length
      || coverage.fallbackComponents !== fallback.length
      || coverage.unavailableComponents !== unavailable.length
      || coverage.unknownComponents !== unknown.length
      || coverage.publishedCoveragePct !== sourceHealthPercent(published.length, spec.ids.length)
      || coverage.freshCoveragePct !== sourceHealthPercent(fresh.length, spec.ids.length)) {
      throw new Error("辅助来源覆盖率不可复算");
    }
    var attempt = health.attempt;
    if (!attempt || ["success", "partial", "failed", "unknown"].indexOf(attempt.status) === -1
      || !sameStringArray(attempt.refreshedComponents, fresh)
      || !sameStringArray(attempt.fallbackComponents, fallback)
      || !sameStringArray(attempt.unavailableComponents, unavailable)
      || !sameStringArray(attempt.unknownComponents, unknown)) {
      throw new Error("辅助来源尝试汇总无效");
    }
    if (!health.policy || health.policy.maxReportAgeHours !== spec.maxAgeHours
      || !sameStringArray(health.policy.terminalRequiredComponents, spec.required)
      || !health.recovery || health.recovery.preservesLastValidSnapshot !== true
      || !Array.isArray(health.recovery.steps) || !health.recovery.steps.length) {
      throw new Error("辅助来源时效或恢复策略无效");
    }

    var migrated = health.historyStatus === "migrated";
    if (migrated) {
      if (health.status !== "unknown" || health.lastAttemptAt !== null
        || health.consecutiveFailures !== null || health.snapshotPreserved !== null
        || health.failureReason !== null || attempt.status !== "unknown" || attempt.published !== null
        || unknown.length !== spec.ids.length
        || health.components.some(function (component) { return component.lastAttemptAt !== null; })) {
        throw new Error("辅助来源迁移状态伪造运行历史");
      }
    } else {
      if (typeof attempt.published !== "boolean" || health.lastAttemptAt !== health.generatedAt
        || health.components.some(function (component) { return component.lastAttemptAt !== health.generatedAt; })
        || !Number.isInteger(health.consecutiveFailures) || health.consecutiveFailures < 0) {
        throw new Error("辅助来源真实尝试字段无效");
      }
      var expectedAttempt = attempt.published && fresh.length === spec.ids.length
        ? "success" : attempt.published ? "partial" : "failed";
      var expectedStatus = expectedAttempt === "success" ? "healthy" : attempt.published ? "degraded" : "failed";
      if (attempt.status !== expectedAttempt || health.status !== expectedStatus
        || (attempt.published && health.consecutiveFailures !== 0)
        || (!attempt.published && health.consecutiveFailures < 1)
        || health.snapshotPreserved !== Boolean(!attempt.published && published.length)
        || (attempt.published ? health.failureReason !== null
          : typeof health.failureReason !== "string" || !health.failureReason.trim())) {
        throw new Error("辅助来源顶层健康不可复算");
      }
    }

    var requiredModes = spec.required.map(function (componentId) { return modes[componentId]; });
    var terminalStatus = requiredModes.indexOf("unavailable") !== -1 ? "failed"
      : requiredModes.indexOf("fallback") !== -1 ? "degraded"
        : requiredModes.indexOf("unknown") !== -1 ? "unknown" : "healthy";
    var reportStale = !migrated && reportAge > spec.maxAgeHours;
    var displayStatus = reportStale && health.status !== "failed" ? "stale" : health.status;
    var label = {
      healthy: "HEALTHY", degraded: "DEGRADED", failed: "FAILED", unknown: "UNKNOWN", stale: "STALE"
    }[displayStatus];
    var note = migrated
      ? "首次迁移无法追溯旧任务结果，等待一次真实自动运行建立历史。"
      : health.status === "failed"
        ? "最近一次任务未发布新快照；旧内容仍可展示，但更新链失败。"
        : reportStale
          ? "健康报告已超过" + spec.maxAgeHours + "小时，不能证明更新链仍在运行。"
          : fallback.length || unavailable.length
            ? "本轮含" + fallback.length + "项回退、" + unavailable.length + "项不可用；未用空值覆盖旧内容。"
            : "本轮全部组件已刷新，数据快照与更新链证据一致。";
    return {
      dataset: dataset,
      status: displayStatus,
      pipelineStatus: health.status,
      terminalStatus: terminalStatus,
      label: label,
      historyKnown: !migrated,
      publishedCoveragePct: coverage.publishedCoveragePct,
      freshCoveragePct: coverage.freshCoveragePct,
      consecutiveFailures: health.consecutiveFailures,
      lastAttemptAt: health.lastAttemptAt,
      lastSuccessfulAt: health.lastSuccessfulAt,
      snapshotPreserved: health.snapshotPreserved,
      note: note
    };
  }

  function attachSupportingHealth(card, dataset, dataSource, healthSource, now) {
    var state;
    if (!dataSource || dataSource.error || !healthSource || healthSource.error) {
      state = unavailableSupportingHealth(dataset, (dataSource && dataSource.error) || (healthSource && healthSource.error));
    } else {
      try {
        state = adaptSupportingSourceHealth(healthSource.data, dataset, dataSource.data, now);
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

  function adaptMacroSourceHealth(health, data, now) {
    if (!health || typeof health !== "object" || !data || typeof data !== "object") {
      throw new Error("宏观健康或数据文件缺失");
    }
    if (health.contractVersion !== 1 || health.dataset !== "macro-radar"
      || PIPELINE_HEALTH_STATUSES.indexOf(health.status) === -1
      || PIPELINE_HISTORY_STATUSES.indexOf(health.historyStatus) === -1) {
      throw new Error("宏观健康契约或数据集标识无效");
    }
    var reportAgeHours = hoursSince(health.generatedAt, now);
    var attemptAgeHours = hoursSince(health.lastAttemptAt, now);
    if (reportAgeHours === null || attemptAgeHours === null || health.generatedAt !== health.lastAttemptAt) {
      throw new Error("宏观健康尝试时间无效");
    }
    if (health.lastSuccessfulAt !== null && hoursSince(health.lastSuccessfulAt, now) === null) {
      throw new Error("宏观健康最后成功时间无效");
    }
    if (health.publishedSnapshotAt !== data.updatedAt) throw new Error("宏观健康与数据快照时间不一致");

    var expectedIds = ["DGS10", "DTWEXBGS", "RWTC"];
    var sourceSpecs = {
      DGS10: { provider: "FRED / Federal Reserve H.15", maxBusinessDays: 3, changeUnit: "bp" },
      DTWEXBGS: { provider: "FRED / Federal Reserve H.10", maxBusinessDays: 3, changeUnit: "percent" },
      RWTC: { provider: "U.S. EIA / Cushing WTI Spot", maxBusinessDays: 4, changeUnit: "percent" }
    };
    if (!Array.isArray(health.sources) || !sameStringArray(health.sources.map(function (source) {
      return source && source.id;
    }), expectedIds)) throw new Error("宏观健康逐源顺序或ID无效");

    var published = macroPublishedRecords(data);
    var counts = { market: 0, fallback: 0, unavailable: 0, unknown: 0 };
    health.sources.forEach(function (source) {
      var spec = sourceSpecs[source.id];
      var record = published[source.id];
      if (!spec || !record || ["ok", "stale", "error"].indexOf(record.status) === -1) {
        throw new Error(source.id + "发布记录无效");
      }
      if (source.provider !== spec.provider || source.role !== "primary" || source.frequency !== "daily"
        || source.maxBusinessDays !== spec.maxBusinessDays || source.changeUnit !== spec.changeUnit
        || MACRO_HEALTH_SOURCE_STATUSES.indexOf(source.status) === -1
        || MACRO_HEALTH_MODES.indexOf(source.mode) === -1
        || PIPELINE_HISTORY_STATUSES.indexOf(source.historyStatus) === -1) {
        throw new Error(source.id + "健康来源口径无效");
      }
      if (!source.source || source.source.seriesId !== source.id || source.source.name !== spec.provider
        || typeof source.source.url !== "string" || source.source.url.indexOf("https://") !== 0) {
        throw new Error(source.id + "健康来源登记无效");
      }
      if (source.published !== record.published || source.asOf !== record.asOf
        || source.publishedUpdatedAt !== record.updatedAt) {
        throw new Error(source.id + "健康状态与发布快照不一致");
      }
      if (hoursSince(source.lastAttemptAt, now) === null
        || (source.lastSuccessfulAt !== null && hoursSince(source.lastSuccessfulAt, now) === null)) {
        throw new Error(source.id + "健康运行时间无效");
      }
      if (health.historyStatus === "migrated") {
        if (source.historyStatus !== "migrated" || source.mode !== "unknown" || source.status !== "unknown"
          || source.consecutiveFailures !== null || source.snapshotPreserved !== null
          || source.failureReason !== null) throw new Error(source.id + "迁移历史被错误推断");
      } else {
        if (source.historyStatus !== "tracked" || source.lastAttemptAt !== health.lastAttemptAt
          || !Number.isInteger(source.consecutiveFailures) || source.consecutiveFailures < 0) {
          throw new Error(source.id + "跟踪历史无效");
        }
        if (source.mode === "market" && (source.status !== "healthy" || source.consecutiveFailures !== 0
          || source.snapshotPreserved !== false || source.failureReason !== null || record.status !== "ok")) {
          throw new Error(source.id + "成功语义不一致");
        }
        if (source.mode === "fallback" && (source.status !== "degraded" || source.consecutiveFailures < 1
          || source.snapshotPreserved !== true || typeof source.failureReason !== "string"
          || !source.failureReason.trim() || record.published !== true)) {
          throw new Error(source.id + "回退语义不一致");
        }
        if (source.mode === "unavailable" && (source.status !== "failed" || source.consecutiveFailures < 1
          || source.snapshotPreserved !== false || typeof source.failureReason !== "string"
          || !source.failureReason.trim() || record.published !== false)) {
          throw new Error(source.id + "不可用语义不一致");
        }
        if (source.mode === "unknown") throw new Error(source.id + "跟踪状态不得使用unknown模式");
      }
      counts[source.mode] += 1;
    });

    var coverage = health.coverage;
    var publishedSeries = health.sources.filter(function (source) { return source.published; }).length;
    if (!coverage || coverage.expectedSeries !== expectedIds.length || coverage.publishedSeries !== publishedSeries
      || !coverage.counts || MACRO_HEALTH_MODES.some(function (mode) { return coverage.counts[mode] !== counts[mode]; })
      || !isNumber(coverage.freshCoveragePct) || !isNumber(coverage.availableCoveragePct)
      || Math.abs(coverage.freshCoveragePct - sourceHealthPercent(counts.market, expectedIds.length)) > 0.001
      || Math.abs(coverage.availableCoveragePct - sourceHealthPercent(publishedSeries, expectedIds.length)) > 0.001) {
      throw new Error("宏观健康覆盖率不可复算");
    }

    var refreshed = health.sources.filter(function (source) { return source.mode === "market"; })
      .map(function (source) { return source.id; });
    var failed = health.sources.filter(function (source) {
      return source.mode === "fallback" || source.mode === "unavailable";
    }).map(function (source) { return source.id; });
    var unknown = health.sources.filter(function (source) { return source.mode === "unknown"; })
      .map(function (source) { return source.id; });
    var attemptStatus = unknown.length ? "unknown" : refreshed.length === expectedIds.length
      ? "success" : refreshed.length ? "partial" : "failed";
    if (!health.attempt || health.attempt.status !== attemptStatus
      || !sameStringArray(health.attempt.refreshedSeries, refreshed)
      || !sameStringArray(health.attempt.failedSeries, failed)
      || !sameStringArray(health.attempt.unknownSeries, unknown)) {
      throw new Error("宏观健康任务汇总不可复算");
    }
    var expectedPipeline = unknown.length ? "degraded" : refreshed.length === expectedIds.length
      ? "healthy" : refreshed.length ? "degraded" : "failed";
    if (health.status !== expectedPipeline) throw new Error("宏观健康管道状态不可复算");
    if (health.historyStatus === "migrated") {
      if (health.consecutiveFailures !== null || health.snapshotPreserved !== null || health.failureReason !== null) {
        throw new Error("宏观迁移状态不得推断失败历史");
      }
    } else {
      if (!Number.isInteger(health.consecutiveFailures) || health.consecutiveFailures < 0) {
        throw new Error("宏观连续失败次数无效");
      }
      if (refreshed.length && (health.consecutiveFailures !== 0 || health.snapshotPreserved !== false)) {
        throw new Error("宏观部分成功时失败状态未归零");
      }
      if (!refreshed.length && (health.consecutiveFailures < 1
        || health.snapshotPreserved !== Boolean(publishedSeries)
        || typeof health.failureReason !== "string" || !health.failureReason.trim())) {
        throw new Error("宏观整批失败语义不一致");
      }
    }
    if (!health.recovery || health.recovery.preservesLastValidSnapshot !== true
      || !Array.isArray(health.recovery.steps) || !health.recovery.steps.length) {
      throw new Error("宏观健康恢复链无效");
    }

    var reportStale = attemptAgeHours > SOURCE_HEALTH_MAX_AGE_HOURS["macro-radar"];
    var displayStatus = reportStale && health.status !== "failed" ? "stale" : health.status;
    var note = health.status === "failed"
      ? "三项官方序列本轮均未刷新；可验证旧值按逐源规则保留。"
      : health.historyStatus === "migrated"
        ? "三项官方序列的健康历史从当前快照开始建立；此前连续失败次数未知。"
        : health.status === "degraded"
          ? "仅部分官方序列完成本轮刷新；其余来源保持独立回退或不可用状态。"
          : "三项官方序列均完成本轮刷新，逐源健康状态已跟踪。";
    if (reportStale) {
      note = "健康报告已超过72小时；可展示覆盖仅代表上次快照，不代表当前任务仍在正常运行。";
    }
    return {
      dataset: "macro-radar",
      status: displayStatus,
      pipelineStatus: health.status,
      label: displayStatus.toUpperCase(),
      contractKnown: true,
      historyKnown: health.historyStatus === "tracked",
      reportStale: reportStale,
      reportAgeHours: attemptAgeHours,
      freshCoveragePct: coverage.freshCoveragePct,
      verifiedCoveragePct: coverage.availableCoveragePct,
      availableCoveragePct: coverage.availableCoveragePct,
      consecutiveFailures: health.consecutiveFailures,
      lastAttemptAt: health.lastAttemptAt,
      lastSuccessfulAt: health.lastSuccessfulAt,
      snapshotPreserved: health.snapshotPreserved,
      failureReason: health.failureReason,
      note: note
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

  function pipelineOperationCard(dataset, state, data, health) {
    var spec = PIPELINE_OPERATION_SPECS[dataset];
    if (!spec) throw new Error("未知数据管道");
    var publishedRecords = dataset === "macro-radar"
      ? health.coverage.publishedSeries : sourceHealthRows(dataset, data).length;
    return Object.assign({}, state, {
      id: dataset,
      name: spec.name,
      nameEn: spec.nameEn,
      symbol: spec.symbol,
      expectedRecords: spec.expectedRecords,
      publishedRecords: publishedRecords,
      unit: spec.unit,
      detailUrl: spec.detailUrl
    });
  }

  function unavailablePipelineOperation(dataset, error) {
    var spec = PIPELINE_OPERATION_SPECS[dataset];
    var state = unavailableSourceHealth(dataset, error);
    return Object.assign({}, state, {
      id: dataset,
      name: spec.name,
      nameEn: spec.nameEn,
      symbol: spec.symbol,
      expectedRecords: spec.expectedRecords,
      publishedRecords: null,
      unit: spec.unit,
      detailUrl: spec.detailUrl
    });
  }

  function adaptPipelineOperation(dataset, data, health, now) {
    var state = dataset === "macro-radar"
      ? adaptMacroSourceHealth(health, data, now)
      : adaptSourceHealth(health, dataset, data, now);
    return pipelineOperationCard(dataset, state, data, health);
  }

  function unavailableReadinessEvidence(error) {
    return {
      status: "unknown",
      sourceStatus: "unknown",
      label: "UNKNOWN",
      consecutiveSuccessfulCycles: null,
      stableRequiredSuccessfulCycles: 7,
      remainingStableCycles: null,
      latestCreatedAt: null,
      latestCycleDate: null,
      latestRunUrl: null,
      reportStale: true,
      note: "稳定V1远端证据不可用。" + (error && error.message ? " " + error.message : "")
    };
  }

  function safeReadinessRunUrl(value) {
    return typeof value === "string"
      && /^https:\/\/github\.com\/[^/\s]+\/[^/\s]+\/actions\/runs\/\d+$/.test(value)
      ? value : null;
  }

  function adaptReadinessSnapshot(snapshot, now) {
    if (!snapshot || snapshot.schemaVersion !== 1) throw new Error("稳定V1证据版本无效");
    if (typeof snapshot.targetBranch !== "string"
      || !/^agent\/finance-terminal-[A-Za-z0-9._-]+$/.test(snapshot.targetBranch)) {
      throw new Error("稳定V1证据分支无效");
    }
    var targetStatuses = ["PASS", "WARN", "BLOCKED"];
    if (!snapshot.targets || targetStatuses.indexOf(snapshot.targets.beta) === -1
      || targetStatuses.indexOf(snapshot.targets.stableV1) === -1) {
      throw new Error("稳定V1目标结论无效");
    }
    if (snapshot.doesNotCallMarketApis !== true || snapshot.doesNotDeploy !== true) {
      throw new Error("稳定V1证据缺少只读安全声明");
    }
    if (snapshot.source !== "GitHub Actions workflow_dispatch / Finance Terminal release gate") {
      throw new Error("稳定V1证据来源无效");
    }
    var reportAgeHours = hoursSince(snapshot.generatedAt, now);
    if (reportAgeHours === null) throw new Error("稳定V1证据生成时间无效");
    var reportStale = reportAgeHours > READINESS_MAX_AGE_HOURS;
    var ids = Object.keys(PIPELINE_OPERATION_SPECS);
    if (!Array.isArray(snapshot.pipelines) || snapshot.pipelines.length !== ids.length) {
      throw new Error("稳定V1证据必须包含四条核心管道");
    }
    var allowedStatuses = ["progress", "qualified", "blocked"];
    var pipelines = {};
    snapshot.pipelines.forEach(function (item, index) {
      var id = ids[index];
      var spec = PIPELINE_OPERATION_SPECS[id];
      if (!item || item.id !== id || item.name !== spec.name || item.workflow !== spec.workflow) {
        throw new Error("稳定V1证据管道身份无效");
      }
      var cycles = item.consecutiveSuccessfulCycles;
      if (!Number.isInteger(cycles) || cycles < 0 || item.betaRequiredSuccessfulCycles !== 3
        || item.stableRequiredSuccessfulCycles !== 7
        || item.remainingStableCycles !== Math.max(0, 7 - cycles)
        || allowedStatuses.indexOf(item.status) === -1
        || targetStatuses.indexOf(item.checkStatus) === -1) {
        throw new Error(id + "稳定V1周期证据不可复算");
      }
      var expectedStatus = cycles >= 7 && item.checkStatus === "PASS" ? "qualified"
        : cycles > 0 && item.latestConclusion === "success" ? "progress" : "blocked";
      if (item.status !== expectedStatus) throw new Error(id + "稳定V1状态不可复算");
      if (!Array.isArray(item.cycleDates) || item.cycleDates.length > 7
        || item.cycleDates.some(function (date) { return !/^\d{4}-\d{2}-\d{2}$/.test(date); })
        || new Set(item.cycleDates).size !== item.cycleDates.length
        || item.cycleDates.join("|") !== item.cycleDates.slice().sort().reverse().join("|")) {
        throw new Error(id + "稳定V1周期日期无效");
      }
      if (item.latestCreatedAt !== null && item.latestCreatedAt !== undefined
        && Number.isNaN(new Date(item.latestCreatedAt).getTime())) {
        throw new Error(id + "最近远端运行时间无效");
      }
      var displayStatus = reportStale ? "stale" : item.status;
      pipelines[id] = {
        status: displayStatus,
        sourceStatus: item.status,
        label: displayStatus.toUpperCase(),
        consecutiveSuccessfulCycles: cycles,
        stableRequiredSuccessfulCycles: 7,
        remainingStableCycles: item.remainingStableCycles,
        latestCreatedAt: item.latestCreatedAt || null,
        latestCycleDate: item.cycleDates.length ? item.cycleDates[0] : null,
        latestRunUrl: safeReadinessRunUrl(item.latestRunUrl),
        reportStale: reportStale,
        note: reportStale ? "稳定V1证据快照已超过72小时，请以远端门禁为准。"
          : cycles + "/7个独立日更周期已验证；同周期重跑不会重复累计。"
      };
    });
    var minimum = Math.min.apply(null, ids.map(function (id) {
      return pipelines[id].consecutiveSuccessfulCycles;
    }));
    var qualified = ids.filter(function (id) { return pipelines[id].sourceStatus === "qualified"; }).length;
    var expectedSummary = snapshot.summary;
    if (!expectedSummary || expectedSummary.pipelineCount !== 4
      || expectedSummary.qualifiedPipelines !== qualified
      || expectedSummary.minimumConsecutiveSuccessfulCycles !== minimum
      || expectedSummary.stableRequiredSuccessfulCycles !== 7
      || expectedSummary.remainingStableCycles !== Math.max(0, 7 - minimum)) {
      throw new Error("稳定V1证据汇总不可复算");
    }
    return {
      generatedAt: snapshot.generatedAt,
      reportAgeHours: reportAgeHours,
      reportStale: reportStale,
      targets: snapshot.targets,
      pipelines: pipelines
    };
  }

  function buildOperationsCards(sources, now) {
    var readiness = null;
    var readinessError = sources && sources.readiness && sources.readiness.error;
    if (sources && sources.readiness && !readinessError) {
      try {
        readiness = adaptReadinessSnapshot(sources.readiness.data, now);
      } catch (error) {
        readinessError = error;
      }
    }
    var definitions = [
      ["macro-radar", sources && sources.macro, sources && sources.macroHealth],
      ["asset-tracker", sources && sources.assetTracker, sources && sources.assetTrackerHealth],
      ["companies", sources && sources.companies, sources && sources.companiesHealth],
      ["asset-ranking", sources && sources.assetRanking, sources && sources.assetRankingHealth]
    ];
    return definitions.map(function (definition) {
      var dataset = definition[0];
      var dataSource = definition[1] || {};
      var healthSource = definition[2] || {};
      var card;
      if (dataSource.error) card = unavailablePipelineOperation(dataset, dataSource.error);
      else if (healthSource.error) card = unavailablePipelineOperation(dataset, healthSource.error);
      try {
        if (!card) card = adaptPipelineOperation(dataset, dataSource.data, healthSource.data, now);
      } catch (error) {
        card = unavailablePipelineOperation(dataset, error);
      }
      if (PIPELINE_OPERATION_SPECS[dataset].readinessEnabled) {
        card.readiness = readiness
          ? readiness.pipelines[dataset] : unavailableReadinessEvidence(readinessError);
      }
      return card;
    });
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
    var note = "FRED官方日频数据；变化为相对上一观测值的百分比。";
    if (refreshFailed) {
      note = "本轮FRED自动更新失败，保留上次有效观测值并标记为过期。";
    } else if (age > DTWEXBGS_MAX_BUSINESS_DAYS) {
      note = "已超过3个美国工作日未发布新观测值，保留最后有效数据。";
    }
    return Object.assign({}, template, record, {
      id: template.id,
      changePct: changePct,
      demo: false,
      status: stale ? "stale" : "ok",
      delayLabel: "日频 · 自动更新",
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
      detailUrl: "../macro-radar/"
    };
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
      symbol: "28 ASSETS",
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
      symbol: "28 ASSETS",
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

  function parseWeekRange(value) {
    if (typeof value !== "string") return null;
    var match = value.match(/^(\d{4}-\d{2}-\d{2})\s*~\s*(\d{4}-\d{2}-\d{2})$/);
    if (!match) return null;
    var start = parseIsoDate(match[1]);
    var end = parseIsoDate(match[2]);
    if (!start || !end || start > end) return null;
    return { start: start, end: end, label: match[1] + " ~ " + match[2] };
  }

  function isCalendarValue(value) {
    return value === null || typeof value === "string";
  }

  function normalizeCalendarEvent(event) {
    if (!event || typeof event.ts !== "string") return null;
    var timestamp = new Date(event.ts);
    var allowedImpact = ["high", "medium", "low", "holiday"];
    if (Number.isNaN(timestamp.getTime()) || allowedImpact.indexOf(event.impact) === -1) return null;
    if (typeof event.title !== "string" || !event.title.trim()
      || typeof event.country !== "string" || !event.country.trim()
      || typeof event.ccy !== "string" || !event.ccy.trim()
      || !isCalendarValue(event.actual) || !isCalendarValue(event.forecast) || !isCalendarValue(event.previous)) {
      return null;
    }
    return {
      ts: event.ts,
      timestamp: timestamp.getTime(),
      ccy: event.ccy.trim(),
      country: event.country.trim(),
      flag: typeof event.flag === "string" ? event.flag : "🌐",
      title: event.title.trim(),
      titleEn: typeof event.titleEn === "string" ? event.titleEn.trim() : "",
      impact: event.impact,
      actual: event.actual,
      forecast: event.forecast,
      previous: event.previous
    };
  }

  function adaptEconomicCalendar(data, now) {
    if (!data || data.source !== "Forex Factory 经济日历") throw new Error("经济日历来源不是Forex Factory");
    var age = hoursSince(data.updatedAt, now);
    var observed = parseIsoDate(data.asOf);
    var week = parseWeekRange(data.weekOf);
    var current = now instanceof Date ? new Date(now.getTime()) : new Date();
    if (age === null) throw new Error("经济日历更新时间无效或晚于当前时间");
    if (!observed || !week || Number.isNaN(current.getTime())) throw new Error("经济日历日期或周范围无效");
    current.setUTCHours(0, 0, 0, 0);
    if (observed > current) throw new Error("经济日历数据日期晚于当前时间");
    if (!Array.isArray(data.events) || data.events.length < 1) throw new Error("经济日历没有事件");

    var events = data.events.map(normalizeCalendarEvent).filter(Boolean).sort(function (a, b) {
      return a.timestamp - b.timestamp;
    });
    if (!events.length) throw new Error("经济日历没有有效事件");
    var highCount = events.filter(function (event) { return event.impact === "high"; }).length;
    var rangeComplete = events.every(function (event) {
      var eventDate = new Date(event.timestamp);
      eventDate.setUTCHours(0, 0, 0, 0);
      return eventDate >= week.start && eventDate <= week.end;
    });
    var inputComplete = events.length === data.events.length
      && data.count === data.events.length
      && data.highCount === highCount
      && rangeComplete;
    var nowTime = (now instanceof Date ? now : new Date()).getTime();
    var important = events.filter(function (event) {
      return event.impact === "high" || event.impact === "medium";
    });
    var selected = important.filter(function (event) { return event.timestamp >= nowTime; }).slice(0, 4);
    var selectionLabel = "接下来重要事件";
    if (!selected.length) {
      selected = important.filter(function (event) { return event.timestamp < nowTime; }).slice(-4).reverse();
      selectionLabel = "最近重要事件";
    }
    if (!selected.length) {
      selected = events.filter(function (event) { return event.impact !== "holiday"; }).slice(0, 4);
      selectionLabel = "本周事件";
    }

    var outsideWeek = current < week.start || current > week.end;
    var status = age > ECON_CALENDAR_MAX_AGE_HOURS || outsideWeek
      ? "stale"
      : (!inputComplete || important.length === 0) ? "partial" : "ok";
    return {
      id: "economic-calendar",
      name: "重要经济事件",
      nameEn: "Economic Calendar",
      symbol: "CALENDAR",
      status: status,
      events: selected,
      selectionLabel: selectionLabel,
      count: events.length,
      highCount: highCount,
      weekOf: week.label,
      asOf: data.asOf,
      updatedAt: data.updatedAt,
      frequency: "每日更新 · 周历",
      source: { name: data.source, url: "../econ-calendar/" },
      detailUrl: "../econ-calendar/",
      note: status === "stale"
        ? "周历文件超过36小时未更新或已离开当前周范围；保留最后有效事件并明确标记过期。"
        : status === "partial"
          ? "部分事件或数量元数据不完整；仅展示通过校验的事件，不以空值补齐。"
          : "时间按你的设备时区显示；高、中影响级别来自上游日历，实际值公布后由既有任务回填。"
    };
  }

  function unavailableEconomicCalendar(error) {
    return {
      id: "economic-calendar",
      name: "重要经济事件",
      nameEn: "Economic Calendar",
      symbol: "CALENDAR",
      status: "error",
      events: [],
      selectionLabel: "事件不可用",
      count: 0,
      highCount: 0,
      weekOf: null,
      asOf: null,
      updatedAt: null,
      frequency: "每日更新 · 周历",
      source: { name: "Forex Factory 经济日历", url: "../econ-calendar/" },
      detailUrl: "../econ-calendar/",
      note: "无法读取经济日历。" + (error && error.message ? " " + error.message : "")
    };
  }

  function isSafeGoogleNewsUrl(value) {
    return typeof value === "string" && /^https:\/\/news\.google\.com\/rss\/articles\/[A-Za-z0-9_-]+(?:\?[^\s]*)?$/.test(value);
  }

  function normalizeFinanceNewsItem(item, nowTime) {
    if (!item || typeof item.title !== "string" || !item.title.trim()
      || typeof item.source !== "string" || !item.source.trim()
      || !isSafeGoogleNewsUrl(item.link)
      || !isNumber(item.published) || item.published <= 0) return null;
    var publishedAt = new Date(item.published * 1000);
    if (Number.isNaN(publishedAt.getTime()) || publishedAt.getTime() > nowTime + 15 * 60000) return null;
    return {
      title: item.title.trim(),
      sourceName: item.source.trim(),
      link: item.link,
      published: item.published,
      publishedAt: publishedAt.toISOString()
    };
  }

  function adaptFinanceNews(data, now) {
    if (!data || typeof data.source !== "string" || data.source.indexOf("Google News") === -1) {
      throw new Error("财经新闻来源不含Google News");
    }
    var age = hoursSince(data.updatedAt, now);
    var observed = parseIsoDate(data.asOf);
    var current = now instanceof Date ? new Date(now.getTime()) : new Date();
    if (age === null) throw new Error("财经新闻更新时间无效或晚于当前时间");
    if (!observed || Number.isNaN(current.getTime())) throw new Error("财经新闻数据日期无效");
    current.setUTCHours(0, 0, 0, 0);
    if (observed > current) throw new Error("财经新闻数据日期晚于当前时间");
    if (!Array.isArray(data.categories)) throw new Error("财经新闻缺少板块列表");
    var marketCategories = data.categories.filter(function (category) {
      return category && category.key === "markets";
    });
    if (marketCategories.length !== 1 || !Array.isArray(marketCategories[0].items) || !marketCategories[0].items.length) {
      throw new Error("财经新闻缺少唯一市场板块或新闻为空");
    }

    var rawItems = marketCategories[0].items;
    var currentTime = (now instanceof Date ? now : new Date()).getTime();
    var seenLinks = {};
    var articles = rawItems.map(function (item) { return normalizeFinanceNewsItem(item, currentTime); })
      .filter(function (item) {
        if (!item || seenLinks[item.link]) return false;
        seenLinks[item.link] = true;
        return true;
      })
      .sort(function (a, b) { return b.published - a.published; });
    if (!articles.length) throw new Error("财经新闻没有有效文章");
    var selected = articles.slice(0, 5);
    var newestAge = hoursSince(selected[0].publishedAt, now);
    if (newestAge === null) throw new Error("最新财经新闻发布时间无效");
    var inputComplete = articles.length === rawItems.length;
    var status = age > FINANCE_NEWS_MAX_AGE_HOURS || newestAge > FINANCE_NEWS_ITEM_MAX_AGE_HOURS
      ? "stale"
      : (!inputComplete || selected.length < 3) ? "partial" : "ok";
    return {
      id: "finance-news",
      name: "最新财经新闻",
      nameEn: "Latest Market News",
      symbol: "NEWS",
      status: status,
      articles: selected,
      count: articles.length,
      latestPublishedAt: selected[0].publishedAt,
      asOf: data.asOf,
      updatedAt: data.updatedAt,
      frequency: "每6小时聚合",
      source: { name: "Google News RSS · 原媒体", url: "../whats-latest/" },
      detailUrl: "../whats-latest/",
      note: status === "stale"
        ? "新闻文件超过12小时未更新或最新文章已超过36小时；保留最后有效标题并明确标记过期。"
        : status === "partial"
          ? "部分新闻字段或链接未通过校验；仅展示有效文章，不读取同文件的Yahoo行情快照。"
          : "只读取“市场”板块并按发布时间排序；标题来自Google News聚合，点击经Google News跳转原媒体。"
    };
  }

  function unavailableFinanceNews(error) {
    return {
      id: "finance-news",
      name: "最新财经新闻",
      nameEn: "Latest Market News",
      symbol: "NEWS",
      status: "error",
      articles: [],
      count: 0,
      latestPublishedAt: null,
      asOf: null,
      updatedAt: null,
      frequency: "每6小时聚合",
      source: { name: "Google News RSS · 原媒体", url: "../whats-latest/" },
      detailUrl: "../whats-latest/",
      note: "无法读取财经新闻。" + (error && error.message ? " " + error.message : "")
    };
  }

  function buildInformationCards(sources, now) {
    var cards = [];
    if (sources && Object.prototype.hasOwnProperty.call(sources, "calendar")) {
      var calendarSource = sources.calendar || {};
      var calendarHealthSource = sources.calendarHealth || {};
      if (calendarSource.error) cards.push(attachSupportingHealth(
        unavailableEconomicCalendar(calendarSource.error), "econ-calendar", calendarSource, calendarHealthSource, now
      ));
      else {
        try { cards.push(attachSupportingHealth(
          adaptEconomicCalendar(calendarSource.data, now), "econ-calendar", calendarSource, calendarHealthSource, now
        )); }
        catch (error) { cards.push(attachSupportingHealth(
          unavailableEconomicCalendar(error), "econ-calendar", calendarSource, calendarHealthSource, now
        )); }
      }
    }
    if (sources && Object.prototype.hasOwnProperty.call(sources, "news")) {
      var newsSource = sources.news || {};
      var newsHealthSource = sources.newsHealth || {};
      if (newsSource.error) cards.push(attachSupportingHealth(
        unavailableFinanceNews(newsSource.error), "whats-latest", newsSource, newsHealthSource, now
      ));
      else {
        try { cards.push(attachSupportingHealth(
          adaptFinanceNews(newsSource.data, now), "whats-latest", newsSource, newsHealthSource, now
        )); }
        catch (error) { cards.push(attachSupportingHealth(
          unavailableFinanceNews(error), "whats-latest", newsSource, newsHealthSource, now
        )); }
      }
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
    parts.push("Ooglex演示数据");
    return parts.join(" · ");
  }

  function validateConfig(config) {
    if (!config || config.schemaVersion !== 2 || config.demo !== true) {
      throw new Error("页面数据配置无效或演示标记缺失");
    }
    if (!Array.isArray(config.assets) || config.assets.length !== 8) {
      throw new Error("核心资产配置不完整");
    }
    var officialIds = config.assets.filter(function (asset) { return asset.demo === false; }).map(function (asset) { return asset.id; });
    var demoCount = config.assets.filter(function (asset) { return asset.demo === true; }).length;
    if (officialIds.length !== 4 || officialIds.indexOf("us10y") === -1 || officialIds.indexOf("dxy") === -1
      || officialIds.indexOf("wti") === -1 || officialIds.indexOf("bitcoin") === -1 || demoCount !== 4) {
      throw new Error("DGS10、DTWEXBGS、RWTC、BTC/USD真实卡片与4项演示卡片的配置不一致");
    }
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
    var hasStale = assets.some(function (asset) { return !asset.demo && asset.status === "stale"; });
    return Object.assign({}, config, {
      assets: assets,
      status: hasStale ? "stale" : "partial",
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

  var testApi = {
    adaptDgs10: adaptDgs10,
    adaptDtwexbgs: adaptDtwexbgs,
    adaptMacroSourceHealth: adaptMacroSourceHealth,
    adaptOfficialSourceHealth: adaptOfficialSourceHealth,
    adaptPipelineOperation: adaptPipelineOperation,
    adaptReadinessSnapshot: adaptReadinessSnapshot,
    adaptCrossAsset: adaptCrossAsset,
    adaptEconomicCalendar: adaptEconomicCalendar,
    adaptFinanceNews: adaptFinanceNews,
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
    adaptSupportingSourceHealth: adaptSupportingSourceHealth,
    buildPageData: buildPageData,
    buildPageDataWithMacroError: buildPageDataWithMacroError,
    buildInformationCards: buildInformationCards,
    buildOperationsCards: buildOperationsCards,
    buildResearchCards: buildResearchCards,
    buildRiskCards: buildRiskCards,
    businessDaysSince: businessDaysSince,
    findDgs10Row: findDgs10Row,
    findDtwexbgsReference: findDtwexbgsReference,
    findRwtcReference: findRwtcReference,
    normalizeOfficialObservations: normalizeOfficialObservations,
    isUsBusinessDay: isUsBusinessDay,
    isSafeOfrUrl: isSafeOfrUrl,
    isSafeGoogleNewsUrl: isSafeGoogleNewsUrl,
    hoursSince: hoursSince,
    parseUnitValue: parseUnitValue,
    rankCrossAssetPeriod: rankCrossAssetPeriod,
    normalizeDataMeta: normalizeDataMeta,
    normalizeAssetProxy: normalizeAssetProxy,
    summarizeRowQuality: summarizeRowQuality,
    dataModeLabel: dataModeLabel,
    periodTabTargetIndex: periodTabTargetIndex,
    unavailableCrossAsset: unavailableCrossAsset,
    unavailableAssetRanking: unavailableAssetRanking,
    unavailableCompanies: unavailableCompanies,
    unavailableEconomicCalendar: unavailableEconomicCalendar,
    unavailableFinanceNews: unavailableFinanceNews,
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
  var riskGrid = document.getElementById("risk-grid");
  var riskSummary = document.getElementById("risk-summary");
  var researchGrid = document.getElementById("research-grid");
  var researchSummary = document.getElementById("research-summary");
  var informationGrid = document.getElementById("information-grid");
  var informationSummary = document.getElementById("information-summary");
  var operationsGrid = document.getElementById("operations-grid");
  var operationsSummary = document.getElementById("operations-summary");
  var pageAnnouncer = document.getElementById("page-announcer");

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
      return;
    }
    appendText(parent, "span", "source-name", source.name || "来源未提供");
  }

  function formatRiskValue(card) {
    if (!isNumber(card.value)) return "—";
    var decimals = Number.isInteger(card.decimals) ? card.decimals : 2;
    return (card.prefix || "") + card.value.toLocaleString("en-US", {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals
    }) + (card.suffix || "");
  }

  function riskStatusLabel(card) {
    if (card.status === "stale") return { className: "stale-chip", text: "STALE" };
    if (card.status === "error") return { className: "error-chip", text: "ERROR" };
    if (card.status === "partial") return { className: "partial-chip", text: "PARTIAL" };
    return { className: "official-chip", text: "ACTIVE" };
  }

  function makeRiskCard(signal) {
    var card = document.createElement("article");
    card.className = "risk-card status-" + signal.status;
    card.setAttribute("role", "listitem");

    var head = document.createElement("div");
    head.className = "risk-card-head";
    var titleBox = document.createElement("div");
    appendText(titleBox, "h3", "risk-name", signal.name);
    appendText(titleBox, "span", "risk-en", signal.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "risk-symbol", signal.symbol);
    card.appendChild(head);

    var valueRow = document.createElement("div");
    valueRow.className = "risk-value-row";
    appendText(valueRow, "span", "risk-value", formatRiskValue(signal));
    appendText(valueRow, "span", "risk-assessment", signal.assessment);
    card.appendChild(valueRow);
    appendText(card, "div", "risk-change", signal.changeText || "暂无可比变化");

    if (isNumber(signal.meterPercent) && Array.isArray(signal.meterLabels) && signal.meterLabels.length === 3) {
      var meter = document.createElement("div");
      meter.className = "signal-meter";
      var track = document.createElement("div");
      track.className = "meter-track";
      track.setAttribute("role", "progressbar");
      track.setAttribute("aria-valuemin", "0");
      track.setAttribute("aria-valuemax", "100");
      track.setAttribute("aria-valuenow", String(signal.meterPercent));
      track.setAttribute("aria-label", signal.name + "分数");
      var fill = document.createElement("div");
      fill.className = "meter-fill";
      fill.style.width = Math.max(0, Math.min(100, signal.meterPercent)) + "%";
      track.appendChild(fill);
      meter.appendChild(track);
      var labels = document.createElement("div");
      labels.className = "meter-labels";
      signal.meterLabels.forEach(function (label) { appendText(labels, "span", "", label); });
      meter.appendChild(labels);
      card.appendChild(meter);
    }

    appendText(card, "p", "risk-note", signal.note);
    if (signal.sourceHealth) appendSupportingHealth(card, signal.sourceHealth);
    var meta = document.createElement("div");
    meta.className = "risk-meta";
    appendText(meta, "span", "", "数据日 · " + formatDate(signal.asOf, false));
    appendText(meta, "span", "", signal.frequency || "频率未提供");
    card.appendChild(meta);

    var footer = document.createElement("div");
    footer.className = "risk-footer";
    var sourceBox = document.createElement("div");
    sourceBox.className = "risk-source";
    appendSource(sourceBox, signal);
    footer.appendChild(sourceBox);
    var time = appendText(footer, "time", "", "更新 · " + formatTimestamp(signal.updatedAt, false));
    if (signal.updatedAt) time.dateTime = signal.updatedAt;
    var chip = riskStatusLabel(signal);
    appendText(footer, "span", "status-chip " + chip.className, chip.text);
    if (isSafeHref(signal.detailUrl)) {
      var detail = appendText(footer, "a", "detail-link", "查看完整页面 →");
      detail.href = signal.detailUrl;
    }
    card.appendChild(footer);
    return card;
  }

  function renderRiskCards(cards) {
    riskGrid.textContent = "";
    cards.forEach(function (card) { riskGrid.appendChild(makeRiskCard(card)); });
    riskGrid.setAttribute("aria-busy", "false");
    var ok = cards.filter(function (card) { return card.status === "ok"; }).length;
    var partial = cards.filter(function (card) { return card.status === "partial"; }).length;
    var stale = cards.filter(function (card) { return card.status === "stale"; }).length;
    var errors = cards.filter(function (card) { return card.status === "error"; }).length;
    riskSummary.textContent = ok + " ACTIVE · " + partial + " PARTIAL · " + stale + " STALE · " + errors + " ERROR";
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

  function appendRankColumn(parent, title, rows, periodKey, direction) {
    var column = document.createElement("div");
    column.className = "rank-column " + direction;
    appendText(column, "h4", "rank-title", title);
    var list = document.createElement("ol");
    list.className = "rank-list";
    rows.forEach(function (asset) {
      var item = document.createElement("li");
      item.className = "rank-row";
      var identity = document.createElement("span");
      identity.className = "rank-identity";
      appendText(identity, "span", "rank-name", asset.name);
      var provenance = document.createElement("span");
      provenance.className = "rank-provenance";
      if (asset.proxy) {
        var proxyBadge = appendText(provenance, "span", "proxy-badge", "PROXY");
        proxyBadge.title = asset.proxy.note;
      }
      appendText(provenance, "span", "rank-symbol", asset.symbol + " · " + asset.dataLabel.replace("PROXY · ", ""));
      identity.appendChild(provenance);
      item.appendChild(identity);
      appendText(item, "strong", "rank-value", formatSignedPercent(asset.returns[periodKey]));
      list.appendChild(item);
    });
    column.appendChild(list);
    parent.appendChild(column);
  }

  function makeCrossAssetCard(card) {
    var article = document.createElement("article");
    article.className = "research-card status-" + card.status;
    article.setAttribute("role", "listitem");

    var head = document.createElement("div");
    head.className = "research-card-head";
    var titleBox = document.createElement("div");
    appendText(titleBox, "h3", "research-name", card.name);
    appendText(titleBox, "span", "research-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "research-symbol", card.symbol);
    article.appendChild(head);
    appendQualitySummary(article, card.quality);
    appendSourceHealth(article, card.sourceHealth);

    var controls = document.createElement("div");
    controls.className = "period-tabs";
    controls.setAttribute("role", "tablist");
    controls.setAttribute("aria-label", "跨资产表现周期");
    controls.setAttribute("aria-orientation", "horizontal");
    var body = document.createElement("div");
    body.className = "research-body";
    body.id = card.id + "-period-panel";
    body.setAttribute("role", "tabpanel");
    body.tabIndex = 0;

    function draw(periodKey) {
      var ranking = rankCrossAssetPeriod(card, periodKey);
      controls.querySelectorAll("button").forEach(function (button) {
        var active = button.getAttribute("data-period") === ranking.period.key;
        button.classList.toggle("active", active);
        button.setAttribute("aria-selected", active ? "true" : "false");
        button.tabIndex = active ? 0 : -1;
        if (active) body.setAttribute("aria-labelledby", button.id);
      });
      body.textContent = "";
      if (card.status === "error") {
        appendText(body, "div", "research-empty", "数据不可用，未显示排行数值。");
        return;
      }
      if (ranking.paused) {
        appendText(body, "div", "research-empty", "数据已过期，“今日”排行暂停；可切换历史周期查看最后有效快照。");
        return;
      }
      var columns = document.createElement("div");
      columns.className = "leader-columns";
      appendRankColumn(columns, "领涨 TOP 3", ranking.leaders, ranking.period.key, "positive");
      appendRankColumn(columns, "领跌 BOTTOM 3", ranking.laggards, ranking.period.key, "negative");
      body.appendChild(columns);
      appendText(body, "p", "coverage-note", ranking.coverage + "/" + ranking.total + "项可比 · 已排除过期、可疑或缺失值");
    }

    card.periods.forEach(function (period) {
      var button = appendText(controls, "button", "period-tab", period.label);
      button.type = "button";
      button.id = card.id + "-period-" + period.key;
      button.setAttribute("role", "tab");
      button.setAttribute("data-period", period.key);
      button.setAttribute("aria-controls", body.id);
      button.setAttribute("aria-selected", "false");
      button.tabIndex = -1;
      button.addEventListener("click", function () { draw(period.key); });
    });
    controls.addEventListener("keydown", function (event) {
      var buttons = Array.prototype.slice.call(controls.querySelectorAll('[role="tab"]'));
      var currentIndex = buttons.indexOf(document.activeElement);
      if (currentIndex < 0) return;
      var nextIndex = periodTabTargetIndex(currentIndex, event.key, buttons.length);
      if (nextIndex === currentIndex && ["Home", "End"].indexOf(event.key) === -1) return;
      event.preventDefault();
      var nextButton = buttons[nextIndex];
      draw(nextButton.getAttribute("data-period"));
      nextButton.focus();
    });
    article.appendChild(controls);
    article.appendChild(body);
    appendText(article, "p", "research-note", card.note);
    appendResearchFooter(card, article);
    draw(card.defaultPeriod);
    return article;
  }

  function formatMarketCapBillions(value) {
    if (!isNumber(value)) return "—";
    if (value >= 1000) return "$" + (value / 1000).toFixed(value >= 100000 ? 1 : 2) + "T";
    return "$" + value.toFixed(1) + "B";
  }

  function makeAssetRankingCard(card) {
    var article = document.createElement("article");
    article.className = "research-card status-" + card.status;
    article.setAttribute("role", "listitem");

    var head = document.createElement("div");
    head.className = "research-card-head";
    var titleBox = document.createElement("div");
    appendText(titleBox, "h3", "research-name", card.name);
    appendText(titleBox, "span", "research-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "research-symbol", card.symbol);
    article.appendChild(head);
    appendQualitySummary(article, card.quality);
    appendSourceHealth(article, card.sourceHealth);

    var body = document.createElement("div");
    body.className = "research-body marketcap-body";
    if (card.status === "error") {
      appendText(body, "div", "research-empty", "数据不可用，未显示市值或排名。");
    } else {
      var total = document.createElement("div");
      total.className = "research-kpi";
      appendText(total, "strong", "research-kpi-value", formatMarketCapBillions(card.totalMarketCap));
      appendText(total, "span", "research-kpi-label", "榜单样本合计 · " + card.count + "项");
      body.appendChild(total);
      var list = document.createElement("ol");
      list.className = "marketcap-list";
      card.assets.forEach(function (asset) {
        var row = document.createElement("li");
        row.className = "marketcap-row" + (asset.stale ? " row-stale" : "");
        appendText(row, "span", "marketcap-rank", String(asset.rank).padStart(2, "0"));
        var identity = document.createElement("span");
        identity.className = "marketcap-identity";
        appendText(identity, "span", "marketcap-name", asset.name);
        appendText(identity, "span", "marketcap-category", asset.categoryLabel + " · " + asset.dataLabel);
        row.appendChild(identity);
        appendText(row, "strong", "marketcap-value", formatMarketCapBillions(asset.marketCap));
        list.appendChild(row);
      });
      body.appendChild(list);
    }
    article.appendChild(body);
    appendText(article, "p", "research-note", card.note);
    appendResearchFooter(card, article);
    return article;
  }

  function makeCompanyLeadersCard(card) {
    var article = document.createElement("article");
    article.className = "research-card status-" + card.status;
    article.setAttribute("role", "listitem");

    var head = document.createElement("div");
    head.className = "research-card-head";
    var titleBox = document.createElement("div");
    appendText(titleBox, "h3", "research-name", card.name);
    appendText(titleBox, "span", "research-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "research-symbol", card.symbol);
    article.appendChild(head);
    appendQualitySummary(article, card.quality);
    appendSourceHealth(article, card.sourceHealth);

    var body = document.createElement("div");
    body.className = "research-body company-body";
    if (card.status === "error") {
      appendText(body, "div", "research-empty", "数据不可用，未显示公司市值或涨跌。");
    } else {
      var total = document.createElement("div");
      total.className = "research-kpi";
      appendText(total, "strong", "research-kpi-value", formatMarketCapBillions(card.listedMarketCap));
      appendText(total, "span", "research-kpi-label", card.listedCount + "家上市公司合计 · 排除" + card.privateCount + "家未上市估值");
      body.appendChild(total);

      var topList = document.createElement("ol");
      topList.className = "marketcap-list company-top-list";
      card.topCompanies.forEach(function (company) {
        var row = document.createElement("li");
        row.className = "marketcap-row";
        appendText(row, "span", "marketcap-rank", String(company.rank).padStart(2, "0"));
        var identity = document.createElement("span");
        identity.className = "marketcap-identity";
        appendText(identity, "span", "marketcap-name", company.name);
        appendText(identity, "span", "marketcap-category", company.symbol + " · " + company.dataLabel);
        row.appendChild(identity);
        appendText(row, "strong", "marketcap-value", formatMarketCapBillions(company.marketCap));
        topList.appendChild(row);
      });
      body.appendChild(topList);

      var movers = document.createElement("div");
      movers.className = "mover-grid";
      [
        { title: "今日领涨", company: card.gainer, direction: "positive" },
        { title: "今日领跌", company: card.laggard, direction: "negative" }
      ].forEach(function (item) {
        var box = document.createElement("div");
        box.className = "mover-box " + item.direction;
        appendText(box, "span", "mover-label", item.title);
        appendText(box, "strong", "mover-name", item.company ? item.company.name : "—");
        appendText(box, "span", "mover-value", item.company ? formatSignedPercent(item.company.changePct) : "—");
        appendText(box, "span", "mover-symbol", item.company
          ? item.company.symbol + " · " + item.company.dataLabel
          : "逐条状态待确认");
        movers.appendChild(box);
      });
      body.appendChild(movers);
    }
    article.appendChild(body);
    appendText(article, "p", "research-note", card.note);
    appendResearchFooter(card, article);
    return article;
  }

  function renderResearchCards(cards) {
    researchGrid.textContent = "";
    cards.forEach(function (card) {
      if (card.id === "cross-asset") researchGrid.appendChild(makeCrossAssetCard(card));
      if (card.id === "asset-ranking") researchGrid.appendChild(makeAssetRankingCard(card));
      if (card.id === "company-leaders") researchGrid.appendChild(makeCompanyLeadersCard(card));
    });
    researchGrid.setAttribute("aria-busy", "false");
    var ok = cards.filter(function (card) { return card.status === "ok"; }).length;
    var partial = cards.filter(function (card) { return card.status === "partial"; }).length;
    var stale = cards.filter(function (card) { return card.status === "stale"; }).length;
    var errors = cards.filter(function (card) { return card.status === "error"; }).length;
    researchSummary.textContent = ok + " ACTIVE · " + partial + " PARTIAL · " + stale + " STALE · " + errors + " ERROR";
  }

  function informationStatusLabel(card) {
    if (card.status === "stale") return { className: "stale-chip", text: "STALE" };
    if (card.status === "error") return { className: "error-chip", text: "ERROR" };
    if (card.status === "partial") return { className: "partial-chip", text: "PARTIAL" };
    return { className: "official-chip", text: "ACTIVE" };
  }

  function appendInformationFooter(card, parent) {
    var meta = document.createElement("div");
    meta.className = "information-meta";
    appendText(meta, "span", "", "数据日 · " + formatDate(card.asOf, false));
    appendText(meta, "span", "", card.frequency || "频率未提供");
    parent.appendChild(meta);

    var footer = document.createElement("div");
    footer.className = "information-footer";
    var sourceBox = document.createElement("div");
    sourceBox.className = "information-source";
    appendSource(sourceBox, card);
    footer.appendChild(sourceBox);
    var time = appendText(footer, "time", "", "更新 · " + formatTimestamp(card.updatedAt, false));
    if (card.updatedAt) time.dateTime = card.updatedAt;
    var chip = informationStatusLabel(card);
    appendText(footer, "span", "status-chip " + chip.className, chip.text);
    if (isSafeHref(card.detailUrl)) {
      var detail = appendText(footer, "a", "detail-link", "查看完整页面 →");
      detail.href = card.detailUrl;
    }
    parent.appendChild(footer);
  }

  function formatEventTime(value) {
    var time = new Date(value);
    if (Number.isNaN(time.getTime())) return "时间不可用";
    return new Intl.DateTimeFormat("zh-CN", {
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    }).format(time) + " 本地";
  }

  function eventImpactLabel(value) {
    if (value === "high") return "高影响";
    if (value === "medium") return "中影响";
    if (value === "holiday") return "假日";
    return "低影响";
  }

  function makeEconomicCalendarCard(card) {
    var article = document.createElement("article");
    article.className = "information-card calendar-card status-" + card.status;
    article.setAttribute("role", "listitem");

    var head = document.createElement("div");
    head.className = "information-card-head";
    var titleBox = document.createElement("div");
    appendText(titleBox, "h3", "information-name", card.name);
    appendText(titleBox, "span", "information-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "information-symbol", card.symbol);
    article.appendChild(head);

    var overview = document.createElement("div");
    overview.className = "information-overview";
    appendText(overview, "strong", "information-kpi", card.highCount + "项高影响");
    appendText(overview, "span", "information-context", card.selectionLabel + " · 本周共" + card.count + "项");
    article.appendChild(overview);

    var body = document.createElement("div");
    body.className = "information-body";
    if (card.status === "error" || !card.events.length) {
      appendText(body, "div", "information-empty", "经济日历不可用，未显示事件或默认值。");
    } else {
      var list = document.createElement("ol");
      list.className = "event-list";
      card.events.forEach(function (event) {
        var row = document.createElement("li");
        row.className = "event-row impact-" + event.impact;
        var marker = appendText(row, "span", "event-impact", eventImpactLabel(event.impact));
        marker.setAttribute("aria-label", eventImpactLabel(event.impact));
        var time = appendText(row, "time", "event-time", formatEventTime(event.ts));
        time.dateTime = event.ts;
        var identity = document.createElement("span");
        identity.className = "event-identity";
        appendText(identity, "strong", "event-title", event.title);
        appendText(identity, "span", "event-country", (event.flag || "🌐") + " " + event.country + " · " + event.ccy);
        row.appendChild(identity);
        var values = document.createElement("span");
        values.className = "event-values";
        appendText(values, "span", event.actual ? "actual" : "", "实际 " + (event.actual || "—"));
        appendText(values, "span", "", "预测 " + (event.forecast || "—"));
        appendText(values, "span", "", "前值 " + (event.previous || "—"));
        row.appendChild(values);
        list.appendChild(row);
      });
      body.appendChild(list);
    }
    article.appendChild(body);
    appendText(article, "p", "information-note", card.note);
    if (card.sourceHealth) appendSupportingHealth(article, card.sourceHealth);
    appendInformationFooter(card, article);
    return article;
  }

  function formatNewsTime(value) {
    var time = new Date(value);
    if (Number.isNaN(time.getTime())) return "时间不可用";
    return new Intl.DateTimeFormat("zh-CN", {
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    }).format(time) + " 本地";
  }

  function makeFinanceNewsCard(card) {
    var article = document.createElement("article");
    article.className = "information-card news-card status-" + card.status;
    article.setAttribute("role", "listitem");

    var head = document.createElement("div");
    head.className = "information-card-head";
    var titleBox = document.createElement("div");
    appendText(titleBox, "h3", "information-name", card.name);
    appendText(titleBox, "span", "information-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "information-symbol", card.symbol);
    article.appendChild(head);

    var overview = document.createElement("div");
    overview.className = "information-overview";
    appendText(overview, "strong", "information-kpi", card.articles.length + "条最新市场新闻");
    appendText(overview, "span", "information-context", "有效市场板块共" + card.count + "条 · 按发布时间排序");
    article.appendChild(overview);

    var body = document.createElement("div");
    body.className = "information-body";
    if (card.status === "error" || !card.articles.length) {
      appendText(body, "div", "information-empty", "财经新闻不可用，未显示标题或默认内容。");
    } else {
      var list = document.createElement("ol");
      list.className = "news-list";
      card.articles.forEach(function (item) {
        var row = document.createElement("li");
        row.className = "news-row";
        var link = document.createElement("a");
        link.className = "news-link";
        link.href = item.link;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.setAttribute("aria-label", item.title + "（" + item.sourceName + "，在新窗口打开）");
        appendText(link, "strong", "news-title", item.title);
        var meta = document.createElement("span");
        meta.className = "news-meta";
        appendText(meta, "span", "news-source-name", item.sourceName);
        var time = appendText(meta, "time", "", formatNewsTime(item.publishedAt));
        time.dateTime = item.publishedAt;
        link.appendChild(meta);
        row.appendChild(link);
        list.appendChild(row);
      });
      body.appendChild(list);
    }
    article.appendChild(body);
    appendText(article, "p", "information-note", card.note);
    if (card.sourceHealth) appendSupportingHealth(article, card.sourceHealth);
    appendInformationFooter(card, article);
    return article;
  }

  function renderInformationCards(cards) {
    informationGrid.textContent = "";
    cards.forEach(function (card) {
      if (card.id === "economic-calendar") informationGrid.appendChild(makeEconomicCalendarCard(card));
      if (card.id === "finance-news") informationGrid.appendChild(makeFinanceNewsCard(card));
    });
    informationGrid.classList.toggle("single", cards.length === 1);
    informationGrid.setAttribute("aria-busy", "false");
    var ok = cards.filter(function (card) { return card.status === "ok"; }).length;
    var partial = cards.filter(function (card) { return card.status === "partial"; }).length;
    var stale = cards.filter(function (card) { return card.status === "stale"; }).length;
    var errors = cards.filter(function (card) { return card.status === "error"; }).length;
    informationSummary.textContent = ok + " ACTIVE · " + partial + " PARTIAL · " + stale + " STALE · " + errors + " ERROR";
  }

  function operationStatusLabel(card) {
    if (card.status === "healthy") return { className: "official-chip", text: "HEALTHY" };
    if (card.status === "degraded") return { className: "partial-chip", text: "DEGRADED" };
    if (card.status === "stale") return { className: "stale-chip", text: "STALE" };
    if (card.status === "failed") return { className: "error-chip", text: "FAILED" };
    return { className: "error-chip", text: "UNKNOWN" };
  }

  function operationCountLabel(card) {
    var published = Number.isInteger(card.publishedRecords) ? card.publishedRecords : "—";
    return published + " / " + card.expectedRecords;
  }

  function operationFailureLabel(card) {
    return card.historyKnown && Number.isInteger(card.consecutiveFailures)
      ? card.consecutiveFailures + "次" : "历史待建立";
  }

  function operationSnapshotLabel(card) {
    if (!card.historyKnown) return "历史待建立";
    if (card.snapshotPreserved === true) return "已保留旧快照";
    if (card.snapshotPreserved === false) return "本轮未触发";
    return "状态不可用";
  }

  function makeOperationCard(card) {
    var article = document.createElement("article");
    article.className = "operation-card status-" + card.status;
    article.setAttribute("role", "listitem");

    var head = document.createElement("div");
    head.className = "operation-card-head";
    var titleBox = document.createElement("div");
    appendText(titleBox, "h3", "operation-name", card.name);
    appendText(titleBox, "span", "operation-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "operation-symbol", card.symbol);
    article.appendChild(head);

    var kpi = document.createElement("div");
    kpi.className = "operation-kpi";
    appendText(kpi, "strong", "operation-kpi-value", operationCountLabel(card));
    appendText(kpi, "span", "operation-kpi-label", "可展示" + card.unit);
    article.appendChild(kpi);

    var metrics = document.createElement("div");
    metrics.className = "operation-metrics";
    var coverageMetrics = [
      ["可用覆盖", formatHealthCoverage(card.availableCoveragePct)],
      ["本轮新鲜", formatHealthCoverage(card.freshCoveragePct)],
      [card.slowRecords ? "慢频估值" : "已验证覆盖", card.slowRecords
        ? (card.slowEstimateRecords + " / " + card.slowRecords)
        : formatHealthCoverage(card.verifiedCoveragePct)],
      ["连续失败", operationFailureLabel(card)]
    ];
    coverageMetrics.forEach(function (item) {
      var metric = document.createElement("span");
      metric.className = "operation-metric";
      appendText(metric, "span", "operation-metric-label", item[0]);
      appendText(metric, "strong", "operation-metric-value", item[1]);
      metrics.appendChild(metric);
    });
    article.appendChild(metrics);

    var times = document.createElement("div");
    times.className = "operation-times";
    [
      ["最近尝试", formatTimestamp(card.lastAttemptAt, false)],
      ["最后成功", formatTimestamp(card.lastSuccessfulAt, false)],
      ["失败回退", operationSnapshotLabel(card)]
    ].forEach(function (item) {
      var row = document.createElement("span");
      appendText(row, "span", "", item[0]);
      appendText(row, "strong", "", item[1]);
      times.appendChild(row);
    });
    article.appendChild(times);
    if (card.readiness) {
      var evidence = document.createElement("div");
      evidence.className = "operation-readiness evidence-" + card.readiness.status;
      var evidenceHead = document.createElement("div");
      evidenceHead.className = "operation-readiness-head";
      appendText(evidenceHead, "span", "operation-readiness-label", "STABLE V1 EVIDENCE");
      appendText(evidenceHead, "strong", "operation-readiness-state", card.readiness.label);
      evidence.appendChild(evidenceHead);
      var evidenceValue = Number.isInteger(card.readiness.consecutiveSuccessfulCycles)
        ? card.readiness.consecutiveSuccessfulCycles + " / 7 DAYS" : "— / 7 DAYS";
      appendText(evidence, "strong", "operation-readiness-value", evidenceValue);
      var progress = document.createElement("div");
      progress.className = "operation-readiness-progress";
      progress.setAttribute("role", "progressbar");
      progress.setAttribute("aria-label", card.name + "稳定V1连续成功周期");
      progress.setAttribute("aria-valuemin", "0");
      progress.setAttribute("aria-valuemax", "7");
      progress.setAttribute("aria-valuenow", Number.isInteger(card.readiness.consecutiveSuccessfulCycles)
        ? String(Math.min(7, card.readiness.consecutiveSuccessfulCycles)) : "0");
      var progressFill = document.createElement("span");
      progressFill.style.width = Number.isInteger(card.readiness.consecutiveSuccessfulCycles)
        ? Math.min(100, card.readiness.consecutiveSuccessfulCycles / 7 * 100) + "%" : "0%";
      progress.appendChild(progressFill);
      evidence.appendChild(progress);
      appendText(evidence, "p", "operation-readiness-note", card.readiness.note);
      if (card.readiness.latestCycleDate) {
        appendText(evidence, "span", "operation-readiness-date", "最近周期 " + card.readiness.latestCycleDate);
      }
      if (card.readiness.latestRunUrl) {
        var runLink = appendText(evidence, "a", "operation-readiness-link", "查看本轮运行 ↗");
        runLink.href = card.readiness.latestRunUrl;
        runLink.target = "_blank";
        runLink.rel = "noopener noreferrer";
      }
      article.appendChild(evidence);
    }
    appendText(article, "p", "operation-note", card.note || "运行状态说明不可用。");

    var footer = document.createElement("div");
    footer.className = "operation-footer";
    var chip = operationStatusLabel(card);
    appendText(footer, "span", "status-chip " + chip.className, chip.text);
    if (isSafeHref(card.detailUrl)) {
      var detail = appendText(footer, "a", "detail-link", "查看数据页面 →");
      detail.href = card.detailUrl;
    }
    article.appendChild(footer);
    return article;
  }

  function renderOperationsCards(cards) {
    operationsGrid.textContent = "";
    cards.forEach(function (card) { operationsGrid.appendChild(makeOperationCard(card)); });
    operationsGrid.setAttribute("aria-busy", "false");
    var healthy = cards.filter(function (card) { return card.status === "healthy"; }).length;
    var degraded = cards.filter(function (card) { return card.status === "degraded"; }).length;
    var stale = cards.filter(function (card) { return card.status === "stale"; }).length;
    var failed = cards.filter(function (card) { return card.status === "failed"; }).length;
    var unknown = cards.filter(function (card) { return card.status === "unknown"; }).length;
    var evidenceCards = cards.filter(function (card) { return card.readiness; });
    var evidenceSummary = evidenceCards.length ? " · V1 " + Math.min.apply(null, evidenceCards.map(function (card) {
      return Number.isInteger(card.readiness.consecutiveSuccessfulCycles)
        ? card.readiness.consecutiveSuccessfulCycles : 0;
    })) + "/7" : "";
    operationsSummary.textContent = healthy + " HEALTHY · " + degraded + " DEGRADED · "
      + stale + " STALE · " + failed + " FAILED · " + unknown + " UNKNOWN" + evidenceSummary;
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
    card.appendChild(top);

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
    var official = data.assets.filter(function (asset) { return asset.demo === false; });
    var demos = data.assets.filter(function (asset) { return asset.demo === true; });
    var ok = official.filter(function (asset) { return asset.status === "ok"; });
    var partial = official.filter(function (asset) { return asset.status === "partial"; });
    var stale = official.filter(function (asset) { return asset.status === "stale"; });
    var errors = official.filter(function (asset) { return asset.status === "error"; });
    var breakdown = ok.length + "项真实正常 · " + partial.length + "项降级 · " + stale.length
      + "项过期 · " + errors.length + "项不可用 · " + demos.length + "项演示";

    if (errors.length > 0) {
      banner.className = "data-banner status-error";
      bannerLabel.textContent = "PARTIAL";
      bannerTitle.textContent = "部分真实数据暂不可用";
      bannerCopy.textContent = errors.map(function (asset) { return asset.symbol; }).join("、") + "已隐藏无效数值；其他卡片保留各自的来源和状态。";
      bannerNote.textContent = ok.length + " REAL · " + partial.length + " PARTIAL · " + stale.length
        + " STALE · " + errors.length + " ERROR · " + demos.length + " DEMO";
      dataStatus.textContent = breakdown;
      marketState.textContent = "PARTIAL DATA";
    } else if (stale.length > 0) {
      banner.className = "data-banner status-stale";
      bannerLabel.textContent = "STALE";
      bannerTitle.textContent = stale.length === 1 ? stale[0].symbol + "数据已过期" : "部分真实数据已过期";
      bannerCopy.textContent = "页面保留同一标的最后有效值并醒目标记；没有使用演示值冒充真实行情。";
      bannerNote.textContent = ok.length + " REAL · " + partial.length + " PARTIAL · " + stale.length
        + " STALE · " + demos.length + " DEMO";
      dataStatus.textContent = breakdown;
      marketState.textContent = "STALE DATA";
    } else if (partial.length > 0) {
      banner.className = "data-banner status-stale";
      bannerLabel.textContent = "PARTIAL";
      bannerTitle.textContent = "部分真实数据使用明确降级来源";
      bannerCopy.textContent = partial.map(function (asset) { return asset.symbol; }).join("、")
        + "已在卡片内同步显示来源、时间与涨跌口径；没有静默切换。";
      bannerNote.textContent = ok.length + " REAL · " + partial.length + " PARTIAL · " + demos.length + " DEMO";
      dataStatus.textContent = breakdown;
      marketState.textContent = "PARTIAL DATA";
    } else {
      banner.className = "data-banner";
      bannerLabel.textContent = "PARTIAL";
      bannerTitle.textContent = "当前为部分演示数据";
      bannerCopy.textContent = "DGS10、DTWEXBGS、EIA RWTC与BTC/USD均读取站内每日数据；其余4项仍为演示数据。";
      bannerNote.textContent = "4 REAL · 4 DEMO";
      dataStatus.textContent = breakdown;
      marketState.textContent = "PARTIAL DATA";
    }
  }

  function render(data) {
    var official = data.assets.filter(function (asset) { return asset.demo === false; });
    var demos = data.assets.filter(function (asset) { return asset.demo === true; });
    var unavailable = official.filter(function (asset) { return asset.status === "error"; });
    grid.textContent = "";
    data.assets.forEach(function (asset) {
      grid.appendChild(makeCard(asset));
    });
    grid.setAttribute("aria-busy", "false");
    pageUpdated.textContent = data.updatedAt ? formatTimestamp(data.updatedAt, false) : "真实数据更新时间不可用";
    if (data.updatedAt) pageUpdated.dateTime = data.updatedAt;
    pageSource.textContent = data.source;
    assetCount.textContent = "8项资产 · " + (official.length - unavailable.length) + "项官方可用 / " + unavailable.length + "项不可用 / " + demos.length + "项演示";
    updateSummary(data);
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
    var official = experience.market.assets.filter(function (asset) { return asset.demo === false; });
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
    pageAnnouncer.textContent = "金融终端加载完成。8项核心资产，"
      + marketIssues + "项官方行情需要注意；其他模块中"
      + grouped.partial + "项部分数据，" + grouped.stale + "项过期，"
      + grouped.error + "项不可用；四条数据管道中" + operationIssues + "条需要注意。";
  }

  function elementIsRendered(element) {
    if (!element) return false;
    var style = window.getComputedStyle(element);
    var rect = element.getBoundingClientRect();
    return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
  }

  function renderedGridColumns(element) {
    if (!element) return 0;
    return window.getComputedStyle(element).gridTemplateColumns.split(/\s+/).filter(Boolean).length;
  }

  function runBrowserRegressionProbe() {
    var params = new URLSearchParams(window.location.search);
    if (params.get("regression") !== "1") return;

    var width = window.innerWidth;
    var expectedColumns = width <= 620
      ? { market: 1, risk: 1, research: 1, information: 1, operations: 1 }
      : width <= 1040
        ? { market: 2, risk: 2, research: 2, information: 1, operations: 2 }
        : { market: 4, risk: 3, research: 3, information: 2, operations: 4 };
    var cards = Array.prototype.slice.call(document.querySelectorAll(
      ".asset-card, .risk-card, .research-card, .information-card, .operation-card"
    ));
    var focusables = Array.prototype.slice.call(document.querySelectorAll(
      'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'
    )).filter(elementIsRendered);
    var targetMinimum = width <= 620 ? 44 : 24;
    var targetElements = Array.prototype.slice.call(document.querySelectorAll(
      ".brand, .back-link, .period-tab, .source-link, .detail-link, .news-link, .operation-action"
    )).filter(elementIsRendered);
    var supportingHealthPanels = Array.prototype.slice.call(document.querySelectorAll(
      "#risk-grid .pipeline-health, #information-grid .pipeline-health"
    ));
    var officialHealthPanels = Array.prototype.slice.call(document.querySelectorAll(
      "#market-grid .official-update-health"
    ));
    var officialTrendPanels = Array.prototype.slice.call(document.querySelectorAll(
      "#market-grid .official-trend"
    ));
    var undersizedTargets = targetElements.map(function (element) {
      var rect = element.getBoundingClientRect();
      return {
        selector: element.className,
        text: element.textContent.trim().slice(0, 60),
        width: Math.round(rect.width * 10) / 10,
        height: Math.round(rect.height * 10) / 10
      };
    }).filter(function (target) {
      return target.width + 0.5 < targetMinimum || target.height + 0.5 < targetMinimum;
    });
    var tabs = Array.prototype.slice.call(document.querySelectorAll('[role="tab"]'));
    var selectedBefore = tabs.filter(function (tab) { return tab.getAttribute("aria-selected") === "true"; });
    var keyboardTabs = selectedBefore.length === 1;
    if (keyboardTabs) {
      var previousId = selectedBefore[0].id;
      selectedBefore[0].focus();
      selectedBefore[0].dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
      var moved = document.activeElement;
      keyboardTabs = moved && moved.getAttribute("role") === "tab"
        && moved.id !== previousId && moved.getAttribute("aria-selected") === "true";
      if (keyboardTabs) {
        moved.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true }));
        keyboardTabs = document.activeElement && document.activeElement.id === previousId;
      }
    }

    var checks = {
      dataLoaded: [grid, riskGrid, researchGrid, informationGrid, operationsGrid].every(function (item) {
        return item && item.getAttribute("aria-busy") === "false";
      }) && !document.querySelector(".load-error"),
      supportingHealthResources: supportingHealthPanels.length === 4
        && supportingHealthPanels.every(function (panel) {
          return panel.textContent.indexOf("更新链健康不可用") === -1;
        }),
      officialHealthResources: officialHealthPanels.length === 4
        && officialHealthPanels.every(function (panel) {
          return panel.textContent.indexOf("逐源更新链健康不可用") === -1;
        }),
      officialObservationTrends: officialTrendPanels.length === 3
        && officialTrendPanels.every(function (panel) {
          var count = panel.querySelector(".official-trend-count");
          var match = count && count.textContent.match(/^(\d+)\s*\/\s*8$/);
          var observationCount = match ? Number(match[1]) : null;
          return panel.textContent.indexOf("RECENT OBSERVATIONS") !== -1
            && observationCount !== null && observationCount >= 1 && observationCount <= 8
            && Boolean(panel.querySelector(".sparkline")) === (observationCount >= 2);
        }),
      cardCounts: document.querySelectorAll(".asset-card").length === 8
        && document.querySelectorAll(".risk-card").length === 3
        && document.querySelectorAll(".research-card").length === 3
        && document.querySelectorAll(".information-card").length === 2
        && document.querySelectorAll(".operation-card").length === 4,
      noHorizontalOverflow: document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1
        && cards.every(function (card) {
          var rect = card.getBoundingClientRect();
          return rect.left >= -1 && rect.right <= document.documentElement.clientWidth + 1;
        }),
      responsiveColumns: renderedGridColumns(grid) === expectedColumns.market
        && renderedGridColumns(riskGrid) === expectedColumns.risk
        && renderedGridColumns(researchGrid) === expectedColumns.research
        && renderedGridColumns(informationGrid) === expectedColumns.information
        && renderedGridColumns(operationsGrid) === expectedColumns.operations,
      focusOrder: focusables.length > 6
        && focusables[0].classList.contains("skip-link")
        && !focusables.some(function (element) {
          return element.matches(".asset-card, .risk-card, .research-card, .information-card, .operation-card");
        }),
      keyboardTabs: keyboardTabs,
      tabSemantics: tabs.length === 5
        && tabs.filter(function (tab) { return tab.tabIndex === 0; }).length === 1
        && tabs.every(function (tab) {
          var panel = document.getElementById(tab.getAttribute("aria-controls"));
          return panel && panel.getAttribute("role") === "tabpanel";
        }),
      targetSizes: targetElements.length > 8 && undersizedTargets.length === 0,
      externalLinkSafety: Array.prototype.slice.call(document.querySelectorAll('a[target="_blank"]')).every(function (link) {
        return /(^|\s)noopener(\s|$)/.test(link.rel) && /(^|\s)noreferrer(\s|$)/.test(link.rel);
      }),
      liveSummary: pageAnnouncer && pageAnnouncer.textContent.indexOf("金融终端加载完成") === 0,
      uniqueIds: (function () {
        var ids = Array.prototype.slice.call(document.querySelectorAll("[id]")).map(function (element) { return element.id; });
        return ids.length === new Set(ids).size;
      })()
    };
    var failures = Object.keys(checks).filter(function (name) { return !checks[name]; });
    var result = {
      status: failures.length ? "fail" : "pass",
      requestedWidth: Number(params.get("width")) || null,
      viewport: { width: width, height: window.innerHeight },
      scrollWidth: document.documentElement.scrollWidth,
      focusableCount: focusables.length,
      targetCount: targetElements.length,
      supportingHealthPanelCount: supportingHealthPanels.length,
      officialHealthPanelCount: officialHealthPanels.length,
      officialObservationTrendCount: officialTrendPanels.length,
      undersizedTargets: undersizedTargets,
      layout: {
        market: renderedGridColumns(grid),
        risk: renderedGridColumns(riskGrid),
        research: renderedGridColumns(researchGrid),
        information: renderedGridColumns(informationGrid),
        operations: renderedGridColumns(operationsGrid)
      },
      checks: checks,
      failures: failures
    };
    var output = document.createElement("pre");
    output.id = "finance-terminal-regression-result";
    output.hidden = true;
    output.textContent = JSON.stringify(result);
    document.body.appendChild(output);
    document.documentElement.setAttribute("data-regression-status", result.status);
  }

  function fetchJson(path) {
    return fetch(path + "?t=" + Date.now(), { cache: "no-store" }).then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.json();
    });
  }

  function fetchSource(path) {
    return fetchJson(path).then(function (data) {
      return { data: data, error: null };
    }).catch(function (error) {
      return { data: null, error: error };
    });
  }

  fetchJson("data.json")
    .then(function (config) {
      return Promise.all([
        fetchSource(MACRO_DATA_URL),
        fetchSource(MACRO_HEALTH_URL),
        fetchSource(FEAR_GREED_DATA_URL),
        fetchSource(FEAR_GREED_HEALTH_URL),
        fetchSource(OFR_DATA_URL),
        fetchSource(OFR_HEALTH_URL),
        fetchSource(ASSET_TRACKER_DATA_URL),
        fetchSource(ASSET_TRACKER_HEALTH_URL),
        fetchSource(ASSET_RANKING_DATA_URL),
        fetchSource(ASSET_RANKING_HEALTH_URL),
        fetchSource(COMPANIES_DATA_URL),
        fetchSource(COMPANIES_HEALTH_URL),
        fetchSource(ECON_CALENDAR_DATA_URL),
        fetchSource(ECON_CALENDAR_HEALTH_URL),
        fetchSource(FINANCE_NEWS_DATA_URL),
        fetchSource(FINANCE_NEWS_HEALTH_URL),
        fetchSource(READINESS_DATA_URL)
      ]).then(function (sources) {
        var macroSource = sources[0];
        var macroHealthSource = sources[1];
        var fearGreedSource = sources[2];
        var fearGreedHealthSource = sources[3];
        var ofrSource = sources[4];
        var ofrHealthSource = sources[5];
        var assetTrackerSource = sources[6];
        var assetTrackerHealthSource = sources[7];
        var assetRankingSource = sources[8];
        var assetRankingHealthSource = sources[9];
        var companiesSource = sources[10];
        var companiesHealthSource = sources[11];
        var calendarSource = sources[12];
        var calendarHealthSource = sources[13];
        var newsSource = sources[14];
        var newsHealthSource = sources[15];
        var readinessSource = sources[16];
        var marketData = macroSource.error
          ? buildPageDataWithMacroError(
            config, macroSource.error, undefined, macroHealthSource, assetRankingSource, assetRankingHealthSource
          )
          : buildPageData(
            config, macroSource.data, undefined, null, macroHealthSource, assetRankingSource, assetRankingHealthSource
          );
        return {
          market: marketData,
          risks: buildRiskCards({
            macro: macroSource,
            fearGreed: fearGreedSource,
            fearGreedHealth: fearGreedHealthSource,
            ofr: ofrSource,
            ofrHealth: ofrHealthSource
          }),
          research: buildResearchCards({
            assetTracker: assetTrackerSource,
            assetTrackerHealth: assetTrackerHealthSource,
            assetRanking: assetRankingSource,
            assetRankingHealth: assetRankingHealthSource,
            companies: companiesSource,
            companiesHealth: companiesHealthSource
          }),
          information: buildInformationCards({
            calendar: calendarSource,
            calendarHealth: calendarHealthSource,
            news: newsSource,
            newsHealth: newsHealthSource
          }),
          operations: buildOperationsCards({
            macro: macroSource,
            macroHealth: macroHealthSource,
            assetTracker: assetTrackerSource,
            assetTrackerHealth: assetTrackerHealthSource,
            companies: companiesSource,
            companiesHealth: companiesHealthSource,
            assetRanking: assetRankingSource,
            assetRankingHealth: assetRankingHealthSource,
            readiness: readinessSource
          })
        };
      });
    })
    .then(function (experience) {
      render(experience.market);
      renderRiskCards(experience.risks);
      renderResearchCards(experience.research);
      renderInformationCards(experience.information);
      renderOperationsCards(experience.operations);
      announceExperience(experience);
      window.setTimeout(runBrowserRegressionProbe, 0);
    })
    .catch(function (error) {
      renderError(error);
      window.setTimeout(runBrowserRegressionProbe, 0);
    });
})(typeof globalThis !== "undefined" ? globalThis : this);

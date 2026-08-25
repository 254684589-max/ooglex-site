/* 运行证据分区的数据适配：按需加载。

   宏观逐源健康校验、稳定V1资格快照与七条管线的运行卡片，只有「V1运行证据」这一个
   分区用得上，此前却和首屏代码一起装在 app.js 里，每个访客都得下载 19KB。搬到这里
   之后行为不变——函数体逐字照搬，只把 app.js 里仍要共用的助手与常量改为注入。 */

const READINESS_MAX_AGE_HOURS = 72;

function requireDependency(dependencies, name) {
  const value = dependencies && dependencies[name];
  if (value === undefined || value === null) {
    throw new Error(`运行证据数据层缺少依赖：${name}`);
  }
  return value;
}

export function createOperationsData(dependencies = {}) {
  const adaptSourceHealth = requireDependency(dependencies, "adaptSourceHealth");
  const hoursSince = requireDependency(dependencies, "hoursSince");
  const isNumber = requireDependency(dependencies, "isNumber");
  const macroPublishedRecords = requireDependency(dependencies, "macroPublishedRecords");
  const sameStringArray = requireDependency(dependencies, "sameStringArray");
  const sourceHealthPercent = requireDependency(dependencies, "sourceHealthPercent");
  const sourceHealthRows = requireDependency(dependencies, "sourceHealthRows");
  const unavailableSourceHealth = requireDependency(dependencies, "unavailableSourceHealth");
  const MACRO_HEALTH_MODES = requireDependency(dependencies, "MACRO_HEALTH_MODES");
  const MACRO_HEALTH_SOURCE_STATUSES = requireDependency(dependencies, "MACRO_HEALTH_SOURCE_STATUSES");
  const PIPELINE_HEALTH_STATUSES = requireDependency(dependencies, "PIPELINE_HEALTH_STATUSES");
  const PIPELINE_HISTORY_STATUSES = requireDependency(dependencies, "PIPELINE_HISTORY_STATUSES");
  const SOURCE_HEALTH_MAX_AGE_HOURS = requireDependency(dependencies, "SOURCE_HEALTH_MAX_AGE_HOURS");

  var PIPELINE_OPERATION_SPECS = {
    "macro-radar": {
      name: "宏观官方序列", nameEn: "Macro Official Series", symbol: "3 SERIES",
      expectedRecords: 3, unit: "项官方序列", detailUrl: "../macro-radar/",
      workflow: "macro_radar.yml", readinessEnabled: true
    },
    /* 跨资产清单随取数脚本扩容，条数以健康文件与快照实际发布的为准：
       symbolSuffix 让标签跟着已发布条数走，expectedRecords 只是健康文件缺该字段时的兜底。 */
    "asset-tracker": {
      name: "跨资产强弱", nameEn: "Cross-Asset Strength", symbol: "CROSS ASSET",
      symbolSuffix: "ASSETS",
      expectedRecords: 55, unit: "项资产", detailUrl: "../asset-tracker/",
      workflow: "asset_tracker.yml", readinessEnabled: true
    },
    companies: {
      name: "全球公司榜", nameEn: "Global Companies", symbol: "500 COMPANIES",
      expectedRecords: 500, unit: "家公司", detailUrl: "../companies/",
      workflow: "companies.yml", readinessEnabled: true
    },
    "asset-ranking": {
      name: "全球资产榜", nameEn: "Global Asset Ranking", symbol: "250 ASSETS",
      expectedRecords: 250, unit: "项资产", detailUrl: "../asset-ranking/",
      workflow: "asset_ranking.yml", readinessEnabled: true
    }
  };

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

  function pipelineOperationCard(dataset, state, data, health) {
    var spec = PIPELINE_OPERATION_SPECS[dataset];
    if (!spec) throw new Error("未知数据管道");
    var publishedRecords = dataset === "macro-radar"
      ? health.coverage.publishedSeries : sourceHealthRows(dataset, data).length;
    return Object.assign({}, state, {
      id: dataset,
      name: spec.name,
      nameEn: spec.nameEn,
      symbol: spec.symbolSuffix && Number.isInteger(publishedRecords)
        ? publishedRecords + " " + spec.symbolSuffix : spec.symbol,
      expectedRecords: Number.isInteger(state.expectedRecords)
        ? state.expectedRecords : spec.expectedRecords,
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

  return {
    adaptMacroSourceHealth: adaptMacroSourceHealth,
    adaptPipelineOperation: adaptPipelineOperation,
    adaptReadinessSnapshot: adaptReadinessSnapshot,
    buildOperationsCards: buildOperationsCards
  };
}

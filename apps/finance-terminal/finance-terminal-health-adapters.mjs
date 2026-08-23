/* 辅助来源健康适配层：仅服务「市场状态」分区，按需加载，不进入首屏预算。
   函数体自 app.js 原样迁移，共享辅助（isNumber/hoursSince/sameStringArray/
   sourceHealthPercent）与历史状态常量由调用方注入，行为与迁移前完全一致。 */

export function createSupportingHealthAdapter(helpers) {
  var isNumber = helpers.isNumber;
  var hoursSince = helpers.hoursSince;
  var sameStringArray = helpers.sameStringArray;
  var sourceHealthPercent = helpers.sourceHealthPercent;
  var PIPELINE_HISTORY_STATUSES = helpers.PIPELINE_HISTORY_STATUSES;

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

  return { adaptSupportingSourceHealth: adaptSupportingSourceHealth };
}

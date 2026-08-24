/* 事件资讯分区的数据适配：按需加载。

   经济日历与财经新闻两条管线的适配、周历口径、过期判定与空态，只有事件资讯分区
   用得上，此前却和首屏代码一起装在 app.js 里，每个访客都得下载。搬到这里之后行为
   不变——函数体逐字照搬，只把 app.js 里仍要共用的四个助手改为注入。 */

const ECON_CALENDAR_MAX_AGE_HOURS = 36;
const FINANCE_NEWS_MAX_AGE_HOURS = 12;
const FINANCE_NEWS_ITEM_MAX_AGE_HOURS = 36;

function requireDependency(dependencies, name) {
  const value = dependencies && dependencies[name];
  if (typeof value !== "function") throw new Error(`事件资讯数据层缺少依赖：${name}`);
  return value;
}

export function createInformationData(dependencies = {}) {
  const attachSupportingHealth = requireDependency(dependencies, "attachSupportingHealth");
  const hoursSince = requireDependency(dependencies, "hoursSince");
  const isNumber = requireDependency(dependencies, "isNumber");
  const parseIsoDate = requireDependency(dependencies, "parseIsoDate");

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

    /* 周六周日通常没有经济数据发布，声明的周范围往往在周五结束。若直接用该范围判断，
       周六跑出来的文件会落在自己声明的范围外而被误判为过期，因此按 Forex Factory 的
       周日~周六整周口径判断；"文件来自上一周"这一真正要拦的情况仍然会被拦下。 */
    var weekStart = new Date(week.start.getTime());
    weekStart.setUTCDate(weekStart.getUTCDate() - weekStart.getUTCDay());
    var weekEnd = new Date(weekStart.getTime());
    weekEnd.setUTCDate(weekEnd.getUTCDate() + 6);
    if (week.end > weekEnd) weekEnd = week.end;
    var outsideWeek = current < weekStart || current > weekEnd;
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

  return {
    isSafeGoogleNewsUrl: isSafeGoogleNewsUrl,
    adaptEconomicCalendar: adaptEconomicCalendar,
    adaptFinanceNews: adaptFinanceNews,
    buildInformationCards: buildInformationCards
  };
}

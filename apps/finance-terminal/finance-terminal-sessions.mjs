/* 交易时段状态：按各所常规交易时段与周末纯日历计算，不读取任何行情数据。
   刻意不计入交易所假日——假日表需逐年维护且会临时调整，一旦过期就会谎报开盘；
   因此对外措辞统一为「常规时段」，页面另行披露该口径。 */

/* 时段以当地时间的“当日第几分钟”表示；含中日两市的午间休市。 */
const SESSIONS = Object.freeze({
  "America/New_York": [[570, 960]],
  "Europe/London": [[480, 990]],
  "Asia/Shanghai": [[570, 690], [780, 900]],
  "Asia/Tokyo": [[540, 690], [750, 900]]
});

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/* 取某时区的当地星期与分钟数，失败返回 null（不猜测）。 */
export function localClock(timeZone, now) {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone, weekday: "short", hour: "2-digit", minute: "2-digit", hour12: false
    }).formatToParts(now);
    const pick = (type) => parts.find((part) => part.type === type)?.value;
    const weekday = WEEKDAYS.indexOf(pick("weekday"));
    const hour = Number(pick("hour"));
    const minute = Number(pick("minute"));
    if (weekday < 0 || !Number.isFinite(hour) || !Number.isFinite(minute)) return null;
    return { weekday, minutes: (hour % 24) * 60 + minute };
  } catch {
    return null;
  }
}

function describe(remaining) {
  if (!Number.isFinite(remaining) || remaining <= 0) return "";
  const hours = Math.floor(remaining / 60);
  return hours ? `${hours}h${String(remaining % 60).padStart(2, "0")}m` : `${remaining}m`;
}

/* 返回 { state, label, detail }；state ∈ open | lunch | pre | closed | weekend | unknown。 */
export function sessionState(timeZone, now) {
  const ranges = SESSIONS[timeZone];
  const clock = localClock(timeZone, now || new Date());
  if (!ranges || !clock) return { state: "unknown", label: "时段未知", detail: "" };
  if (clock.weekday === 0 || clock.weekday === 6) {
    return { state: "weekend", label: "周末休市", detail: "" };
  }
  const { minutes } = clock;
  for (let index = 0; index < ranges.length; index += 1) {
    const [start, end] = ranges[index];
    if (minutes >= start && minutes < end) {
      const next = ranges[index + 1];
      /* 处于上半场且当天还有下半场时，收盘其实是午休。 */
      const closing = next ? "午休" : "收盘";
      return { state: "open", label: "常规时段", detail: `${describe(end - minutes)}后${closing}` };
    }
    if (minutes < start) {
      const lunch = index > 0;
      return {
        state: lunch ? "lunch" : "pre",
        label: lunch ? "午间休市" : "待开盘",
        detail: `${describe(start - minutes)}后${lunch ? "续盘" : "开盘"}`
      };
    }
  }
  return { state: "closed", label: "已收盘", detail: "" };
}

/* 把状态写进各城市牌；符号与文字由CSS按 session-* 类补足，颜色不作为唯一信号。 */
export function renderSessions(document, now) {
  document.querySelectorAll("[data-market-session]").forEach((element) => {
    const { state, label, detail } = sessionState(element.getAttribute("data-market-session"), now);
    element.className = `orbit-session session-${state}`;
    element.textContent = detail ? `${label} · ${detail}` : label;
  });
}

export const SESSION_TIME_ZONES = Object.freeze(Object.keys(SESSIONS));

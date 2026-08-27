/* Market link arcs for the overview globe.
   The four city labels are laid out in screen space, so the connecting arcs are drawn in the
   same space: they always meet the marker dots instead of drifting with the rotating sphere.
   Purely decorative — no quote, source or freshness contract touches this file. */

const ANCHORS = Object.freeze({
  "clock-new-york": 1,
  "clock-london": 1,
  "clock-shanghai": 0,
  "clock-tokyo": 0
});

const LINKS = Object.freeze([
  ["orbit-link-a", "clock-new-york", "clock-london", -13],
  ["orbit-link-b", "clock-london", "clock-shanghai", -11],
  ["orbit-link-c", "clock-shanghai", "clock-tokyo", 7],
  ["orbit-link-d", "clock-new-york", "clock-tokyo", 21]
]);

/* 标记点由 .orbit-clock::before 画出：纽约与伦敦贴右缘，上海与东京贴左缘，纵向都在 45% 处。 */
export function anchorPoint(box, host, side) {
  if (!host.width || !host.height) return null;
  const x = box.left - host.left + box.width * side;
  const y = box.top - host.top + box.height * 0.45;
  return { x: (x / host.width) * 100, y: (y / host.height) * 100 };
}

export function arcPath(from, to, bow) {
  if (!from || !to) return "";
  const cx = (from.x + to.x) / 2;
  const cy = (from.y + to.y) / 2 + bow;
  return `M${from.x.toFixed(2)} ${from.y.toFixed(2)}Q${cx.toFixed(2)} ${cy.toFixed(2)} ${to.x.toFixed(2)} ${to.y.toFixed(2)}`;
}

export function initOrbitLinks(options = {}) {
  const { document = globalThis.document, window = globalThis.window } = options;
  const figure = document?.querySelector(".market-orbit");
  const overlay = document?.querySelector(".orbit-links");
  if (!figure || !overlay || !window) return Object.freeze({ destroy() {} });

  const clocks = new Map();
  Object.keys(ANCHORS).forEach((name) => {
    const node = figure.querySelector(`.${name}`);
    if (node) clocks.set(name, node);
  });
  const paths = LINKS.map(([id, from, to, bow]) => [document.getElementById(id), from, to, bow])
    .filter(([path, from, to]) => path && clocks.has(from) && clocks.has(to));
  if (paths.length === 0) return Object.freeze({ destroy() {} });

  let frame = 0;
  let observer = null;

  function paint() {
    frame = 0;
    const host = figure.getBoundingClientRect();
    const points = new Map();
    clocks.forEach((node, name) => {
      points.set(name, anchorPoint(node.getBoundingClientRect(), host, ANCHORS[name]));
    });
    paths.forEach(([path, from, to, bow]) => {
      path.setAttribute("d", arcPath(points.get(from), points.get(to), bow));
    });
    overlay.classList.add("orbit-links-ready");
  }

  function schedule() {
    if (frame) return;
    frame = window.requestAnimationFrame(paint);
  }

  if (typeof window.ResizeObserver === "function") {
    observer = new window.ResizeObserver(schedule);
    observer.observe(figure);
  } else window.addEventListener("resize", schedule, { passive: true });
  schedule();

  return Object.freeze({
    refresh: schedule,
    destroy() {
      if (frame) window.cancelAnimationFrame(frame);
      frame = 0;
      observer?.disconnect();
      if (!observer) window.removeEventListener("resize", schedule);
    }
  });
}

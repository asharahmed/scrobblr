// Motion for the Scrobblr site (shared with the Screenshotr site).
//
// Springs are solved here (the damped harmonic oscillator SwiftUI uses, described by `response` in
// seconds and `dampingFraction`) and handed to CSS as linear() curves, so transitions in stylesheets
// and one-off animations from script move the same way. Everything is skipped with Reduce Motion.
(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  // WebKit freezes animations in windows that are hidden or fully covered. Starting one there would
  // leave elements stuck at their first keyframe, so motion only runs when the page is visible.
  const still = () => reduce.matches || document.visibilityState !== "visible";

  function spring(response, damping) {
    const omega = (2 * Math.PI) / response;
    const position = (t) => {
      if (damping >= 1) return 1 - Math.exp(-omega * t) * (1 + omega * t);
      const damped = omega * Math.sqrt(1 - damping * damping);
      const decay = Math.exp(-damping * omega * t);
      return 1 - decay * (Math.cos(damped * t) + ((damping * omega) / damped) * Math.sin(damped * t));
    };
    // Run until the motion stays within 0.1% of rest.
    let settle = 0.1;
    for (let t = 0; t < 2.5; t += 0.004) if (Math.abs(1 - position(t)) > 0.001) settle = t;
    const steps = 60;
    const points = [];
    for (let i = 0; i <= steps; i += 1) points.push(i === steps ? 1 : +position((settle * i) / steps).toFixed(4));
    return { easing: `linear(${points.join(", ")})`, duration: Math.round(settle * 1000) };
  }

  const springs = {
    // Controls: quick, no visible overshoot.
    snappy: spring(0.3, 0.88),
    // Navigation and layout: unhurried and settled.
    smooth: spring(0.42, 1),
    // Things that arrive or confirm: a little life.
    bouncy: spring(0.4, 0.66),
    // Larger moments, like the welcome entrance.
    gentle: spring(0.62, 0.86),
  };

  const root = document.documentElement.style;
  for (const [name, curve] of Object.entries(springs)) {
    root.setProperty(`--spring-${name}`, curve.easing);
    root.setProperty(`--spring-${name}-duration`, `${curve.duration}ms`);
  }

  function animate(node, keyframes, options = {}) {
    if (!node || still() || !node.animate) return null;
    const { spring: name, ...rest } = options;
    const curve = springs[name || "snappy"];
    return node.animate(keyframes, { duration: curve.duration, easing: curve.easing, fill: "backwards", ...rest });
  }

  /** Brings items in one after another. */
  function cascade(nodes, { from = "translateY(8px)", step = 22, spring: name = "smooth", delay = 0 } = {}) {
    [...nodes].forEach((node, index) =>
      animate(node, [{ opacity: 0, transform: from }, { opacity: 1, transform: "none" }], { spring: name, delay: delay + index * step })
    );
  }

  /** Moves `node` from a previously measured rect to where it is now (FLIP). */
  function flyFrom(node, from, options = {}) {
    if (!node || !from) return null;
    const to = node.getBoundingClientRect();
    if (!to.width || !to.height) return null;
    const dx = from.left - to.left;
    const dy = from.top - to.top;
    const sx = from.width / to.width;
    const sy = from.height / to.height;
    return animate(
      node,
      [
        { transformOrigin: "0 0", transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})` },
        { transformOrigin: "0 0", transform: "none" },
      ],
      { spring: "bouncy", ...options }
    );
  }

  /** A short horizontal shake, for input that can't be accepted. */
  function shake(node) {
    if (!node || still()) return;
    node.animate(
      [
        { transform: "translateX(0)" },
        { transform: "translateX(-7px)" },
        { transform: "translateX(6px)" },
        { transform: "translateX(-4px)" },
        { transform: "translateX(2px)" },
        { transform: "translateX(0)" },
      ],
      { duration: 420, easing: "ease-out" }
    );
  }

  /**
   * Swaps text by rolling: a copy of the old value lifts away while the new one rises into place,
   * at the same time, so the line is never empty. `onSwap` runs at the moment the text changes.
   */
  function roll(node, text, onSwap) {
    if (!node) return;
    if (node.textContent === text) {
      if (onSwap) onSwap();
      return;
    }
    const container = node.parentElement;
    if (still() || !node.animate || !node.textContent || !container) {
      node.textContent = text;
      if (onSwap) onSwap();
      return;
    }
    // Place the copy exactly over the original, measured on screen, so ancestors' transforms and
    // offset parents during other animations can't throw it off.
    if (getComputedStyle(container).position === "static") container.style.position = "relative";
    const box = node.getBoundingClientRect();
    const frame = container.getBoundingClientRect();
    const leaving = node.cloneNode(true);
    leaving.removeAttribute("id");
    leaving.setAttribute("aria-hidden", "true");
    Object.assign(leaving.style, {
      position: "absolute",
      left: `${box.left - frame.left - container.clientLeft}px`,
      top: `${box.top - frame.top - container.clientTop}px`,
      width: `${box.width}px`,
      margin: "0",
      pointerEvents: "none",
    });
    container.append(leaving);
    node.textContent = text;
    if (onSwap) onSwap();
    leaving
      // Blurring as the values cross makes the overlap read as one line changing, not two.
      .animate([{ opacity: 1, transform: "none", filter: "blur(0)" }, { opacity: 0, transform: "translateY(-9px)", filter: "blur(4px)" }], {
        duration: 220,
        easing: "cubic-bezier(0.4, 0, 1, 1)",
        fill: "forwards",
      })
      .finished.then(() => leaving.remove(), () => leaving.remove());
    setTimeout(() => leaving.remove(), 400);
    animate(node, [{ opacity: 0, transform: "translateY(9px)", filter: "blur(4px)" }, { opacity: 1, transform: "none", filter: "blur(0)" }], {
      spring: "snappy",
      delay: 60,
    });
  }

  /** Draws a stroked SVG path from start to end, like an SF Symbols "draw on" effect. */
  function draw(path, options = {}) {
    if (!path || still() || !path.getTotalLength) return;
    const length = path.getTotalLength();
    path.animate([{ strokeDasharray: length, strokeDashoffset: length }, { strokeDasharray: length, strokeDashoffset: 0 }], {
      duration: 360,
      easing: "cubic-bezier(0.65, 0, 0.35, 1)",
      fill: "backwards",
      ...options,
    });
  }

  /** A check mark glyph whose path can be drawn on. */
  function checkmark(className = "check") {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 16 16");
    svg.setAttribute("class", className);
    svg.setAttribute("aria-hidden", "true");
    svg.innerHTML = '<path d="M3.5 8.5 6.5 11.5 12.5 4.5"/>';
    return svg;
  }

  window.Motion = { springs, animate, cascade, flyFrom, shake, roll, draw, checkmark, get reduced() { return still(); } };
})();

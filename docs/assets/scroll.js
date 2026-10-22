// Inertial scrolling for the Scrobblr site.
//
// Wheel and trackpad input moves a target; the page eases toward it on every frame with
// frame-rate independent exponential smoothing, so scrolling glides to a stop instead of
// stepping. In-page links and keyboard paging use the same engine with a timed ease-out.
// Native scrolling stays untouched for touch screens, Reduce Motion, pinch zoom, and
// anything that drags the scrollbar.
(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  const coarse = window.matchMedia("(pointer: coarse)");
  const root = document.documentElement;

  // Larger is slower and floatier. At 60 fps this is roughly a 0.12 lerp per frame.
  const SMOOTHING_MS = 120;
  const NAV_OFFSET = 72;

  let current = window.scrollY;
  let target = current;
  let tween = null; // { from, to, start, duration } for links and keys
  let raf = 0;
  let last = 0;

  const enabled = () => !reduce.matches && !coarse.matches;
  const limit = () => Math.max(0, root.scrollHeight - window.innerHeight);
  const clamp = (y) => Math.min(limit(), Math.max(0, y));
  const easeOut = (t) => 1 - Math.pow(1 - t, 4);

  function apply() {
    root.classList.toggle("smooth-scroll", enabled());
  }

  function write(y) {
    window.scrollTo({ top: y, behavior: "instant" });
  }

  function frame(now) {
    const dt = last ? Math.min(64, now - last) : 16.7;
    last = now;
    if (tween) {
      const t = Math.min(1, (now - tween.start) / tween.duration);
      current = tween.from + (tween.to - tween.from) * easeOut(t);
      target = current;
      if (t >= 1) tween = null;
    } else {
      current += (target - current) * (1 - Math.exp(-dt / SMOOTHING_MS));
      if (Math.abs(target - current) < 0.4) current = target;
    }
    write(current);
    if (tween || current !== target) {
      raf = requestAnimationFrame(frame);
    } else {
      raf = 0;
      last = 0;
    }
  }

  function run() {
    if (!raf) raf = requestAnimationFrame(frame);
  }

  function stop() {
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
    last = 0;
    tween = null;
    current = target = window.scrollY;
  }

  /** Glides to `y` over a duration that grows gently with distance. */
  function glideTo(y) {
    const to = clamp(y);
    if (!enabled()) {
      window.scrollTo({ top: to, behavior: reduce.matches ? "instant" : "smooth" });
      return;
    }
    const distance = Math.abs(to - current);
    tween = { from: current, to, start: performance.now(), duration: Math.min(1400, 520 + distance * 0.35) };
    run();
  }

  // Whether something under the pointer can scroll in this direction itself.
  function scrollableAncestor(node, dy) {
    for (let el = node; el && el !== document.body && el !== root; el = el.parentElement) {
      if (el.scrollHeight <= el.clientHeight) continue;
      const overflow = getComputedStyle(el).overflowY;
      if (overflow !== "auto" && overflow !== "scroll") continue;
      if ((dy > 0 && el.scrollTop + el.clientHeight < el.scrollHeight) || (dy < 0 && el.scrollTop > 0)) return true;
    }
    return false;
  }

  window.addEventListener(
    "wheel",
    (event) => {
      if (!enabled() || event.ctrlKey || event.defaultPrevented) return;
      if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) return;
      let dy = event.deltaY;
      if (event.deltaMode === 1) dy *= 16;
      else if (event.deltaMode === 2) dy *= window.innerHeight;
      if (scrollableAncestor(event.target, dy)) return;
      event.preventDefault();
      if (tween) {
        // A wheel during a link glide takes over from wherever the glide had reached.
        tween = null;
        target = current;
      }
      target = clamp(target + dy);
      run();
    },
    { passive: false }
  );

  // Scrollbar drags, find-in-page and anything else that moves the page directly. Our own
  // writes land within a pixel of `current`, so only a real jump hands control back.
  window.addEventListener(
    "scroll",
    () => {
      if (Math.abs(window.scrollY - current) > 2) stop();
    },
    { passive: true }
  );

  document.addEventListener("click", (event) => {
    const link = event.target.closest('a[href^="#"]');
    if (!link || event.defaultPrevented || event.metaKey || event.ctrlKey || event.shiftKey) return;
    const id = decodeURIComponent(link.getAttribute("href").slice(1));
    const destination = id ? document.getElementById(id) : document.body;
    if (!destination) return;
    event.preventDefault();
    const y = id === "top" || !id ? 0 : destination.getBoundingClientRect().top + window.scrollY - NAV_OFFSET;
    glideTo(y);
    history.pushState(null, "", id ? `#${id}` : location.pathname);
    // Move focus for keyboard and screen reader users without a second jump.
    if (!destination.hasAttribute("tabindex")) destination.setAttribute("tabindex", "-1");
    destination.focus({ preventScroll: true });
  });

  const KEYS = {
    ArrowDown: () => 90,
    ArrowUp: () => -90,
    PageDown: () => window.innerHeight * 0.85,
    PageUp: () => -window.innerHeight * 0.85,
    " ": (event) => (event.shiftKey ? -1 : 1) * window.innerHeight * 0.85,
  };

  document.addEventListener("keydown", (event) => {
    if (!enabled() || event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return;
    const focus = document.activeElement;
    if (focus && focus.closest('input, textarea, select, button, a, [contenteditable], [role="radio"], [role="slider"]')) return;
    let y = null;
    if (event.key === "Home") y = 0;
    else if (event.key === "End") y = limit();
    else if (KEYS[event.key]) y = (tween ? tween.to : target) + KEYS[event.key](event);
    if (y === null) return;
    event.preventDefault();
    glideTo(y);
  });

  window.addEventListener("resize", () => {
    target = clamp(target);
  });

  reduce.addEventListener("change", () => {
    stop();
    apply();
  });
  coarse.addEventListener("change", () => {
    stop();
    apply();
  });
  apply();

  window.SmoothScroll = { glideTo, get y() { return current; } };
})();

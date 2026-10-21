(() => {
  "use strict";
  const parameters = new URLSearchParams(location.search);
  const enabled = parameters.get("background") === "1";
  const motion = matchMedia("(prefers-reduced-motion: reduce)");
  const artwork = location.pathname.split("/").pop();
  const durationSeconds = Number(parameters.get("duration") || 45);
  let paused = false, hidden = false, dirty = true, lastPaint = 0;
  const themeListeners = [];
  function notify(type, message) {
    if (enabled) parent.postMessage({type, artwork, message}, location.origin);
  }
  if (enabled && (!Number.isFinite(durationSeconds) || durationSeconds <= 0)) {
    const message = "The decorative artwork duration must be a positive number.";
    notify("artwork-error", message);
    throw new Error(message);
  }
  window.artworkBackground = {
    enabled,
    durationSeconds,
    invalidate() { dirty = true; },
    onThemeChange(listener) { themeListeners.push(listener); },
    ready() { notify("artwork-ready"); },
    fail(message) { notify("artwork-error", message); },
    tick(now) {
      if (hidden || document.hidden) { lastPaint = now; return null; }
      const animate = !paused && !motion.matches;
      if (!animate && !dirty) { lastPaint = now; return null; }
      if (lastPaint && now - lastPaint < 1000 / 24) return null;
      const dt = animate && lastPaint ? Math.min((now - lastPaint) / 1000, 0.1) : 0;
      lastPaint = now;
      dirty = false;
      return {dt, animate};
    }
  };
  if (!enabled) return;
  document.documentElement.dataset.background = "true";
  addEventListener("message", event => {
    if (event.source !== parent || event.origin !== location.origin || event.data?.type !== "artwork-settings") return;
    paused = event.data.paused === true;
    hidden = event.data.hidden === true;
    const theme = event.data.theme;
    if ((theme === "light" || theme === "dark") && document.documentElement.dataset.theme !== theme) {
      document.documentElement.dataset.theme = theme;
      themeListeners.forEach(listener => listener());
    }
    dirty = true;
  });
  motion.addEventListener("change", () => {
    dirty = true;
    notify("artwork-motion-preference");
  });
  document.addEventListener("visibilitychange", () => { dirty = true; lastPaint = 0; });
})();

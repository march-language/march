// scroll.js: which card of a scrolling story is under the trigger line.
//
// Part of docs/protocol-to-cluster.md (the scrolling explainer). The decision of what the
// reader is looking at is two pure functions over plain rectangles, so it is tested
// without a browser (test/explainer/scroll.test.js). observeSteps wraps them in one
// scroll listener, throttled to animation frames. There is no IntersectionObserver:
// its thresholds fire late on a fast flick and give no progress through a step.
(function (root) {
  'use strict';

  // The trigger line sits at `trigger` of the way down the viewport. The active step is
  // the last one whose top is at or above the line; -1 before the first step reaches it.
  function activeStep(rects, viewportHeight, trigger) {
    var line = viewportHeight * trigger, active = -1;
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].top <= line) active = i;
    }
    return active;
  }

  // How far the line has travelled through one step, clamped to 0..1.
  function stepProgress(rect, viewportHeight, trigger) {
    var line = viewportHeight * trigger, height = rect.bottom - rect.top;
    if (height <= 0) return line >= rect.top ? 1 : 0;
    return Math.max(0, Math.min(1, (line - rect.top) / height));
  }

  // Watch `elements` and report the active step. `opts.onStep(i)` fires once at start and
  // then only when the step changes; `opts.onProgress(i, p)` fires on later frames, never
  // in the frame where the step changed (a redraw there would cancel the step's own
  // transition). Returns a function that stops watching. `opts.env` stands in for
  // `window` under test.
  function observeSteps(elements, opts) {
    var env = opts.env || root;
    var trigger = opts.trigger === undefined ? 0.6 : opts.trigger;
    var current = null, pending = false, stopped = false;

    function measure() {
      pending = false;
      if (stopped) return;
      var rects = [];
      for (var i = 0; i < elements.length; i++) rects.push(elements[i].getBoundingClientRect());
      var step = activeStep(rects, env.innerHeight, trigger);
      if (step !== current) {
        current = step;
        opts.onStep(step);
      } else if (opts.onProgress && step >= 0) {
        opts.onProgress(step, stepProgress(rects[step], env.innerHeight, trigger));
      }
    }

    function schedule() {
      if (pending || stopped) return;
      pending = true;
      env.requestAnimationFrame(measure);
    }

    env.addEventListener('scroll', schedule, { passive: true });
    env.addEventListener('resize', schedule);
    schedule();

    return function stop() {
      stopped = true;
      env.removeEventListener('scroll', schedule);
      env.removeEventListener('resize', schedule);
    };
  }

  var api = { activeStep: activeStep, stepProgress: stepProgress, observeSteps: observeSteps };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.scroll = api;
})(typeof window !== 'undefined' ? window : globalThis);

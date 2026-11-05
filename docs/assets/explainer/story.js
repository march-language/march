// story.js: the figure registry of docs/protocol-to-cluster.md (the scrolling explainer).
//
// The page marks each graphic up as
//
//   <section class="mx-scrolly" data-figure="NAME">
//     <div class="mx-figure"><div class="mx-stage"><img class="mx-fallback" ...></div></div>
//     <div class="mx-steps">
//       <div class="mx-step" data-state="STATE"> ...card... </div>
//
// A figure registers a mount function under NAME. mountAll mounts every section's figure
// into its stage and maps the active card to a figure state. A state is ABSOLUTE: the
// figure must be able to show any state without having shown the ones before it, because
// a reader can land mid-page (an anchor, a reload, a fast flick).
//
// A figure that throws, while mounting or on its first card, gets a short located error
// box and keeps its static image; its section stays laid out as an article (no `mx-on`).
// One that fails later reports once and keeps its last drawing. Other sections carry on.
(function (root) {
  'use strict';
  var ME = root.MarchExplainer = root.MarchExplainer || {};
  var figures = {};

  function escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function showError(host, name, err) {
    host.insertAdjacentHTML('beforeend',
      '<p class="mx-error">' + escapeHtml(name + ': ' + (err && err.message ? err.message : err)) + '</p>');
  }

  // mount(host, data) -> { setState(state, progress) }
  ME.registerFigure = function (name, mount) { figures[name] = mount; };
  // The registered mount function, so a figure can be driven without a page (tests).
  ME.figureForTest = function (name) { return figures[name]; };

  ME.reducedMotion = function () {
    return typeof root.matchMedia === 'function' && root.matchMedia('(prefers-reduced-motion: reduce)').matches;
  };

  // Mount every `.mx-scrolly` under `rootEl`. `env` stands in for `window` under test;
  // with no scroll events to listen to (no `env`, no window) only the first state is applied.
  ME.mountAll = function (rootEl, data, env) {
    env = env || (typeof root.addEventListener === 'function' ? root : null);
    var sections = rootEl.querySelectorAll('.mx-scrolly');
    Array.prototype.forEach.call(sections, function (section) {
      var name = section.dataset.figure;
      var host = section.querySelector('.mx-stage');
      var steps = Array.prototype.slice.call(section.querySelectorAll('.mx-step'));
      var figure, failed = false;

      try {
        if (!figures[name]) throw new Error('no such figure');
        figure = figures[name](host, data);
      } catch (err) {
        showError(host, name, err);
        return;
      }

      function apply(i, progress) {
        if (failed || i < 0 || i >= steps.length) return;
        try {
          figure.setState(steps[i].dataset.state, progress);
        } catch (err) {
          failed = true;                       // report once; the last good drawing stays
          showError(host, name, err);
        }
      }

      if (steps.length) apply(0, 0);
      if (failed) return;                      // it could not draw: its static image stays, as an article
      host.classList.add('mx-live');           // hides the static image
      section.classList.add('mx-on');          // switches this section to the scrolling layout
      if (!env || !ME.scroll) return;
      ME.scroll.observeSteps(steps, {
        env: env,
        onStep: function (i) {
          steps.forEach(function (el, k) { el.classList.toggle('mx-active', k === i); });
          apply(Math.max(i, 0), 0);
        },
        onProgress: function (i, p) { apply(i, p); },
      });
    });
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = ME;
})(typeof window !== 'undefined' ? window : globalThis);

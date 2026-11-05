// chapters.js: the figures of docs/protocol-to-cluster.md, one registration per graphic.
//
// Each figure maps a card's `data-state` to a drawing. A state is absolute: setState can
// be called with any state at any time (a reader can land mid-page), and calling it again
// with the same state changes nothing, since the story repeats it while the card scrolls.
// The drawings themselves come from figures.js (SVG) and draw.js (canvas simulations).
(function (root) {
  'use strict';
  var ME = root.MarchExplainer, F = ME.figures;

  // Draw an SVG figure into `host` at the host's own width, and again when it resizes.
  // render(width) -> svg string.
  function svgFigure(host, render) {
    var box = host.ownerDocument.createElement('div');
    box.className = 'mx-svg';
    host.appendChild(box);
    var api = { draw: function () { box.innerHTML = render(Math.max(280, host.clientWidth || 680)); } };
    if (typeof root.ResizeObserver === 'function') new root.ResizeObserver(function () { api.draw(); }).observe(host);
    return api;
  }
  ME.svgFigure = svgFigure;

  // ── chapter 1: the state map ───────────────────────────────────────────────────
  // empty: every cell, none lit. path: the reachable cells light in the order the
  // protocol reaches them. all: every reachable cell lit. skip / offer / turn: all lit,
  // plus the cell where one wrong program is stopped.
  var WRONG = { skip: 'skip_step', offer: 'offer_misses_branch', turn: 'send_out_of_turn' };

  ME.registerFigure('state-map', function (host, data) {
    var sm = data.state_map, total = sm.path.length;
    var lit = 0, wrong = null, current = null, timer = null;
    var fig = svgFigure(host, function (w) { return F.stateMap(sm, { width: w, lit: lit, wrong: wrong }); });

    function stop() { if (timer !== null) { root.clearInterval(timer); timer = null; } }

    return {
      setState: function (state) {
        if (state === current) return;
        stop();
        if (state === 'empty') { lit = 0; wrong = null; }
        else if (state === 'all') { lit = total; wrong = null; }
        else if (state === 'path') {
          wrong = null;
          if (ME.reducedMotion()) lit = total;
          else {
            lit = 1;
            timer = root.setInterval(function () {
              lit += 1;
              if (lit >= total) stop();
              fig.draw();
            }, 220);
            if (timer && typeof timer.unref === 'function') timer.unref();
          }
        } else if (WRONG[state]) {
          lit = total;
          wrong = data.programs[WRONG[state]].cell;
        } else throw new Error('unknown state ' + state);
        current = state;
        fig.draw();
      },
    };
  });
})(typeof window !== 'undefined' ? window : globalThis);

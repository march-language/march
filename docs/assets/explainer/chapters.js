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

  // ── chapter 2: from the declaration to four machines ───────────────────────────
  // source: the declaration. project: each role's own view, a segment per step (the
  // role's linear types, drawn). modules / functions: what the compiler generates.
  // typecheck: Stock stopped at its choice. grants, main: the generated code again.
  // hosts: the machines the binaries land on.
  function caption(s) { return '<p class="mx-caption">' + s + '</p>'; }

  ME.registerFigure('fan-out', function (host, data) {
    var order = data.order, current = null;
    var views = {
      source: function (w) { return F.fanOut(order, { width: w, stage: 'source' }); },
      project: function (w) {
        return order.roles.map(function (role) {
          return caption(role) + F.strip({ labels: order.strips[role] }, { width: w, at: -1 });
        }).join('');
      },
      modules: function (w) { return F.fanOut(order, { width: w, stage: 'modules' }); },
      functions: function (w) { return F.fanOut(order, { width: w, stage: 'functions' }); },
      typecheck: function (w) {
        return caption('Stock, after it has received the order') +
          F.strip({ labels: order.strips.Stock }, { width: w, at: 1 });
      },
      hosts: function (w) { return F.hosts(data.topology, { width: w }); },
    };
    views.grants = views.functions;
    views.main = views.functions;

    var fig = svgFigure(host, function (w) { return views[current](Math.min(w, 760)); });
    return {
      setState: function (state) {
        if (state === current) return;
        if (!views[state]) throw new Error('unknown state ' + state);
        current = state;
        fig.draw();
      },
    };
  });
})(typeof window !== 'undefined' ? window : globalThis);

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

  // A small figure inside a card: <div data-mx-inline="timeline:silent"></div>.
  var inline = {
    'timeline:silent': function (w, data) {
      return F.detectionTimeline(data.timings, { width: w, mode: 'silent', elapsed: data.timings.silent_timeout_s });
    },
    'timeline:crash': function (w, data) {
      return F.detectionTimeline(data.timings, { width: w, mode: 'crash', elapsed: 0 });
    },
  };
  ME.mountInline = function (rootEl, data) {
    Array.prototype.forEach.call(rootEl.querySelectorAll('[data-mx-inline]'), function (el) {
      var name = el.dataset.mxInline;
      el.innerHTML = inline[name] ? inline[name](Math.max(260, el.clientWidth || 320), data)
        : '<p class="mx-error">no such inline figure: ' + name + '</p>';
    });
  };

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

  // ── simulations: built from scratch for each card, then left running ───────────
  //
  // A simulation state is defined by a SCRIPT: a config, timed actions, and how long to
  // run before the card shows it. buildState runs the script on a fresh simulation, so a
  // card always opens on the same picture whatever the reader saw before it.
  var builders = {};

  ME.buildState = function (figure, state, data) {
    if (!builders[figure]) throw new Error('unknown figure ' + figure);
    return builders[figure](state, data);
  };

  function runScript(sim, s, script) {
    script.actions.forEach(function (a) {
      sim.advance(s, a.at - s.t);
      a.run(s);
    });
    sim.advance(s, script.until - s.t);
    return s;
  }

  // A canvas figure: a "Simulation" label, a row of counters, and a canvas that redraws
  // every animation frame while it is on screen. `parts` is
  // { build(state) -> sim state, step(s, dt), draw(ctx, s, size, colors), counters(s) -> [[label, value, hot]] }.
  function canvasFigure(host, parts) {
    var doc = host.ownerDocument;
    var label = doc.createElement('span'); label.className = 'mx-sim-label'; label.textContent = 'Simulation';
    var counters = doc.createElement('div'); counters.className = 'mx-counters';
    var canvas = doc.createElement('canvas');
    host.appendChild(label); host.appendChild(counters); host.appendChild(canvas);
    var ctx = canvas.getContext('2d'), sim = null, current = null, last = null, size = { width: 0, height: 0 };

    function colors() {
      var cs = root.getComputedStyle(host);
      return { ink: cs.getPropertyValue('--mx-ink').trim() || '#cce5f5',
        dim: cs.getPropertyValue('--mx-dim').trim() || '#3f6f94',
        accent: cs.getPropertyValue('--mx-accent').trim() || '#ff6b5e' };
    }
    function measure() {
      var box = canvas.getBoundingClientRect(), dpr = root.devicePixelRatio || 1;
      if (box.width === size.width && box.height === size.height) return;
      size = { width: box.width, height: box.height };
      canvas.width = Math.round(box.width * dpr); canvas.height = Math.round(box.height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    function paint() {
      if (!sim) return;
      measure();
      if (size.width < 10 || size.height < 10) return;
      parts.draw(ctx, sim, size, colors());
      counters.innerHTML = parts.counters(sim).map(function (c) {
        return '<span' + (c[2] ? ' class="mx-hot"' : '') + '>' + c[0] + ' <b>' + c[1] + '</b></span>';
      }).join('');
    }
    function onScreen() {
      var r = host.getBoundingClientRect();
      return r.bottom > 0 && r.top < (root.innerHeight || 800);
    }
    function frame(t) {
      if (last !== null && sim && onScreen()) { parts.step(sim, (t - last) / 1000); paint(); }
      last = t;
      root.requestAnimationFrame(frame);
    }
    if (typeof root.ResizeObserver === 'function') new root.ResizeObserver(paint).observe(host);
    if (!ME.reducedMotion()) root.requestAnimationFrame(frame);

    return {
      setState: function (state) {
        if (state === current) return;
        sim = parts.build(state);            // throws on an unknown state
        current = state;
        if (ME.reducedMotion()) parts.settle(sim);
        paint();
      },
    };
  }
  ME.canvasFigure = canvasFigure;

  // ── chapter 3: inside one node, the Ledger actor ───────────────────────────────
  function mailboxConfig(data, more) {
    var m = data.sim.mailbox;
    return Object.assign({ seed: data.sim.seed, arrivalS: m.arrival_s, serviceS: m.service_s,
      migrateS: m.migrate_s, backlog: m.backlog, parked: m.parked, restartS: m.restart_s, holds: false }, more || {});
  }

  builders.mailbox = function (state, data) {
    var sim = ME.simMailbox, cfg = mailboxConfig(data), crashAt = 7;
    function crash(s) { sim.crash(s); }
    var scripts = {
      idle: { until: 1.5, actions: [] },
      'one-at-a-time': { until: 4, actions: [] },
      sessions: { until: crashAt, actions: [] },
      crash: { until: crashAt + 0.5, actions: [{ at: crashAt, run: crash }] },
      restart: { until: crashAt + cfg.restartS + 1, actions: [{ at: crashAt, run: crash }] },
      'lost-total': { until: crashAt + cfg.restartS + 4, actions: [{ at: crashAt, run: crash }] },
    };
    if (!scripts[state]) throw new Error('unknown state ' + state);
    // The crash card holds the actor down for as long as the reader stays on it; the
    // restart belongs to the next card.
    if (state === 'crash') cfg = mailboxConfig(data, { restartS: Infinity });
    return runScript(sim, sim.create(cfg), scripts[state]);
  };

  ME.registerFigure('mailbox', function (host, data) {
    var sim = ME.simMailbox;
    return canvasFigure(host, {
      build: function (state) { return ME.buildState('mailbox', state, data); },
      step: sim.step,
      settle: function (s) { sim.advance(s, 2); },
      draw: ME.draw.mailbox,
      counters: function (s) {
        return [['Handled', s.total], ['Waiting', s.queue.length], ['Dropped', s.dropped, s.dropped > 0]];
      },
    });
  });

  // ── chapter 4: the cluster ─────────────────────────────────────────────────────
  // Each script starts from the same seed. Host indices follow topology.stock_hosts;
  // the Ledger starts on the last `books` host.
  function clusterConfig(data, load) {
    var t = data.topology;
    return {
      seed: data.sim.seed, loadPerS: load || data.sim.load_per_s, sessionS: data.sim.session_s,
      stockCapacity: t.stock_capacity, ledgerCapacity: t.ledger_capacity,
      hosts: t.stock_hosts.map(function (id) { return { id: id, books: t.books_hosts.indexOf(id) >= 0 }; }),
      suspectS: data.timings.suspect_s, silentS: data.timings.silent_timeout_s,
      settleS: data.timings.settle_s, restartS: data.sim.restart_s, ingress: t.ingress,
    };
  }

  builders.cluster = function (state, data) {
    var sim = ME.simCluster, cfg = clusterConfig(data);
    var books = [];
    cfg.hosts.forEach(function (h, i) { if (h.books) books.push(i); });
    var ledger = books[books.length - 1];
    function kill(i, mode) { return function (s) { sim.kill(s, i, mode); }; }
    function revive(i) { return function (s) { sim.revive(s, i); }; }
    var scripts = {
      steady: { until: 8, actions: [] },
      // enough callers that the Ledger, the smallest capacity in the path, runs out of slots
      full: { load: Math.ceil(cfg.ledgerCapacity / cfg.sessionS[0]) + 8, until: 10, actions: [] },
      'stock-crash': { until: 9.5, actions: [{ at: 8, run: kill(0, 'crash') }] },
      silent: { until: 8 + cfg.suspectS + 1, actions: [{ at: 8, run: kill(0, 'silent') }] },
      'ledger-stop': { until: 8 + cfg.suspectS + 1.5, actions: [{ at: 8, run: kill(ledger, 'crash') }] },
      'return': { until: 8 + cfg.suspectS + cfg.restartS + 4,
        actions: [{ at: 8, run: kill(ledger, 'crash') }, { at: 8 + cfg.suspectS + 2, run: revive(ledger) }] },
      'no-offer': { until: 11, actions: [{ at: 8, run: function (s) { books.forEach(function (i) { sim.kill(s, i, 'crash'); }); } }] },
    };
    var script = scripts[state];
    if (!script) throw new Error('unknown state ' + state);
    if (script.load) cfg = clusterConfig(data, script.load);
    return runScript(sim, sim.create(cfg), script);
  };

  ME.registerFigure('cluster', function (host, data) {
    var sim = ME.simCluster;
    return canvasFigure(host, {
      build: function (state) { return ME.buildState('cluster', state, data); },
      step: sim.step,
      settle: function (s) { sim.advance(s, 6); },
      draw: ME.draw.cluster,
      counters: function (s) {
        var c = s.counters;
        return [['Completed', c.completed], ['In flight', s.sessions.length],
          ['Cancelled', c.cancelled, c.cancelled > 0], ['Refused', c.refused, c.refused > 0]];
      },
    });
  });
})(typeof window !== 'undefined' ? window : globalThis);

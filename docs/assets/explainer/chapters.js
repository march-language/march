// chapters.js: the figures of docs/protocol-to-cluster.md, one registration per graphic.
//
// Each figure maps a card's `data-state` to a drawing. A state is absolute: setState can
// be called with any state at any time (a reader can land mid-page), and calling it again
// with the same state changes nothing, since the story repeats it while the card scrolls.
// The drawings themselves come from figures.js (SVG) and draw.js (canvas simulations).
//
// Moving from one card to the next is a transition, not a cut:
//   - An SVG figure is not replaced. Its new drawing is compared with the one on screen,
//     element by element: what is in both stays where it is (and may change colour),
//     what is new enters, what is gone leaves (svgParts, diffParts, svgFigure).
//   - A simulation is not rebuilt when the reader moves on to the NEXT card: that card's
//     event happens to the simulation already running (liveTransition). Going back, or
//     landing on a card from elsewhere, rebuilds the card's picture from scratch
//     (buildState) and fades it in.
(function (root) {
  'use strict';
  var ME = root.MarchExplainer, F = ME.figures;
  var SVG_NS = 'http://www.w3.org/2000/svg';

  // ── SVG figures: change in place ───────────────────────────────────────────────

  var GEOMETRY = { rect: ['x', 'y', 'width', 'height'], text: ['x', 'y'], line: ['x1', 'y1', 'x2', 'y2'], circle: ['cx', 'cy', 'r'] };

  // The elements of a figure builder's <svg>, each with a key made from where it is
  // (and, for text, what it says), never from its class: a cell that lights up is the
  // same element in a new colour.
  ME.svgParts = function (svg) {
    var parts = [], seen = {}, m, re = /<(rect|text|line|circle)\b([^>]*?)(?:\/>|>([^<]*)<\/\1>)/g;
    while ((m = re.exec(svg)) !== null) {
      var attrs = {}, a, attrRe = /([\w:-]+)="([^"]*)"/g;
      while ((a = attrRe.exec(m[2])) !== null) attrs[a[1]] = a[2];
      var text = m[3] === undefined ? '' : m[3].replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
      var key = m[1] + '|' + GEOMETRY[m[1]].map(function (k) { return attrs[k]; }).join(',') + (m[1] === 'text' ? '|' + text : '');
      seen[key] = (seen[key] || 0) + 1;
      if (seen[key] > 1) key += '#' + seen[key];
      parts.push({ key: key, tag: m[1], attrs: attrs, text: text, cls: attrs['class'] || '' });
    }
    return parts;
  };

  // What changes between two drawings: parts to add, parts to remove, parts that stay
  // but change class, and parts that stay as they are.
  ME.diffParts = function (before, after) {
    var old = {}, now = {}, d = { enter: [], exit: [], recolour: [], keep: [] };
    before.forEach(function (p) { old[p.key] = p; });
    after.forEach(function (p) {
      now[p.key] = p;
      if (!old[p.key]) d.enter.push(p);
      else if (old[p.key].cls !== p.cls) d.recolour.push(p);
      else d.keep.push(p);
    });
    before.forEach(function (p) { if (!now[p.key]) d.exit.push(p); });
    return d;
  };

  function later(fn, ms) {
    var t = root.setTimeout(fn, ms);
    if (t && typeof t.unref === 'function') t.unref();
  }

  // An SVG figure in `host`. view(width) -> [{ id, caption?, svg }]: one or more slots,
  // stacked. A slot that is in both the old and the new view keeps its <svg> and is
  // changed in place; draw() animates only when the figure has been drawn before.
  function svgFigure(host, view, opts) {
    var doc = host.ownerDocument, box = doc.createElement('div');
    box.className = 'mx-svg';
    host.appendChild(box);
    if (opts && opts.top) host.classList.add('mx-top');
    var slots = {}, drawnAt = null;

    function makeSlot(spec, animate) {
      var wrap = doc.createElement('div');
      wrap.className = animate ? 'mx-slot mx-enter' : 'mx-slot';
      if (spec.caption) {
        var cap = doc.createElement('p');
        cap.className = 'mx-caption'; cap.textContent = spec.caption;
        wrap.appendChild(cap);
      }
      var svg = doc.createElementNS(SVG_NS, 'svg');
      wrap.appendChild(svg);
      return { wrap: wrap, svg: svg, cap: cap || null, parts: [], els: {} };
    }

    function apply(slot, markup, animate) {
      var head = (markup.match(/^<svg\b([^>]*)>/) || ['', ''])[1], a, re = /([\w:-]+)="([^"]*)"/g;
      while ((a = re.exec(head)) !== null) if (a[1] !== 'xmlns') slot.svg.setAttribute(a[1], a[2]);
      var parts = ME.svgParts(markup), d = ME.diffParts(slot.parts, parts);
      d.exit.forEach(function (p) {
        var el = slot.els[p.key];
        delete slot.els[p.key];
        if (!animate) { el.remove(); return; }
        el.classList.add('mx-exit');
        later(function () { el.remove(); }, 240);
      });
      d.recolour.forEach(function (p) { slot.els[p.key].setAttribute('class', p.cls); });
      d.enter.forEach(function (p, i) {
        var el = doc.createElementNS(SVG_NS, p.tag);
        Object.keys(p.attrs).forEach(function (k) { el.setAttribute(k, p.attrs[k]); });
        if (p.tag === 'text') el.textContent = p.text;
        if (animate) {
          el.setAttribute('class', (p.cls ? p.cls + ' ' : '') + 'mx-enter');
          el.style.animationDelay = Math.min(i * 3, 450) + 'ms';   // a sweep, not a pop
          // back to its plain class once it has arrived, so a later recolour is clean
          later(function () { if (slot.els[p.key] === el) el.setAttribute('class', slot.parts.filter(function (q) { return q.key === p.key; }).map(function (q) { return q.cls; })[0] || p.cls); }, 900);
        }
        slot.svg.appendChild(el);
        slot.els[p.key] = el;
      });
      slot.parts = parts;
    }

    var api = {
      draw: function () {
        var width = Math.max(280, host.clientWidth || 680);
        var resized = drawnAt !== null && drawnAt !== width;
        if (resized) { box.innerHTML = ''; slots = {}; }            // a new width is a new drawing
        var animate = drawnAt !== null && !resized && !ME.reducedMotion();
        var specs = view(width), keep = {};
        specs.forEach(function (spec) { keep[spec.id] = true; });
        Object.keys(slots).forEach(function (id) { if (!keep[id]) { slots[id].wrap.remove(); delete slots[id]; } });
        specs.forEach(function (spec) {
          var fresh = !slots[spec.id];
          if (fresh) slots[spec.id] = makeSlot(spec, animate);
          box.appendChild(slots[spec.id].wrap);                       // keeps the slots in view order
          if (slots[spec.id].cap && spec.caption) slots[spec.id].cap.textContent = spec.caption;
          apply(slots[spec.id], spec.svg, animate && !fresh);
        });
        drawnAt = width;
        fit();
      },
    };

    // A short stage (a phone on its side, a small window) may be lower than the drawing.
    // Scale the drawing down to fit rather than let it run over the cards below.
    function fit() {
      if (!box.style || typeof host.clientHeight !== 'number') return;
      box.style.transform = '';
      var room = host.clientHeight - 22, tall = box.scrollHeight;
      if (room > 40 && tall > room) {
        box.style.transformOrigin = 'top center';
        box.style.transform = 'scale(' + Math.max(0.4, room / tall).toFixed(3) + ')';
      }
    }
    if (typeof root.ResizeObserver === 'function') new root.ResizeObserver(function () { if (drawnAt !== null) api.draw(); }).observe(host);
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
    var fig = svgFigure(host, function (w) {
      return [{ id: 'map', svg: F.stateMap(sm, { width: w, lit: lit, wrong: wrong }) }];
    });

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
            lit = Math.min(lit, 1) || 1;
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
  //
  // The declaration stays on screen from `source` to `main`, and each card adds to it.
  // A phone's stage has no room for the declaration and the strips together, so there
  // the strips stand alone.
  ME.fanOutView = function (state, data, width) {
    var order = data.order, w = Math.min(width, 760), wide = w >= 600;
    function code(stage) { return { id: 'code', svg: F.fanOut(order, { width: w, stage: stage }) }; }
    function strip(role, at, caption) {
      return { id: 'strip-' + role, caption: caption || role, svg: F.strip({ labels: order.strips[role] }, { width: w, at: at }) };
    }
    var strips = order.roles.map(function (role) { return strip(role, -1); });
    var stopped = strip('Stock', 1, 'Stock, after it has received the order');
    switch (state) {
      case 'source': return [code('source')];
      case 'project': return wide ? [code('source')].concat(strips) : strips;
      case 'modules': return [code('modules')];
      case 'functions': case 'grants': case 'main': return [code('functions')];
      case 'typecheck': return wide ? [code('functions'), stopped] : [stopped];
      case 'hosts': return [{ id: 'hosts', svg: F.hosts(data.topology, { width: w }) }];
      default: throw new Error('unknown state ' + state);
    }
  };

  ME.registerFigure('fan-out', function (host, data) {
    var current = null;
    var fig = svgFigure(host, function (w) { return ME.fanOutView(current, data, w); }, { top: true });
    return {
      setState: function (state) {
        if (state === current) return;
        ME.fanOutView(state, data, 680);         // throws on an unknown state, before anything changes
        current = state;
        fig.draw();
      },
    };
  });

  // ── simulations ────────────────────────────────────────────────────────────────
  //
  // Landing on a card: its picture is defined by a SCRIPT (a config, timed actions, and
  // how long to run), which buildState runs on a fresh simulation, so the card opens on
  // the same picture whatever the reader saw before.
  //
  // Moving on to the next card: liveTransition makes that card's event happen to the
  // simulation on screen, now or a few seconds from now (`todo`), and the reader watches
  // it happen. Only the next card in page order is reached this way.
  var builders = {}, live = {}, sims = {};

  ME.buildState = function (figure, state, data) {
    if (!builders[figure]) throw new Error('unknown figure ' + figure);
    return builders[figure](state, data);
  };

  ME.liveTransition = function (figure, from, to, s, data) {
    return !!(live[figure] && live[figure](from, to, s, data));
  };

  function runScript(sim, s, script) {
    script.actions.forEach(function (a) {
      sim.advance(s, a.at - s.t);
      a.run(s);
    });
    sim.advance(s, script.until - s.t);
    return s;
  }

  function isNext(order, from, to) {
    var i = order.indexOf(from);
    return i >= 0 && order.indexOf(to) === i + 1;
  }

  // Do `run` to the simulation `after` seconds of its own time from now.
  function soon(s, after, run) { (s.todo = s.todo || []).push({ at: s.t + after, run: run }); }

  function runTodo(s) {
    if (!s.todo || !s.todo.length) return;
    var due = s.todo.filter(function (a) { return s.t >= a.at; });
    s.todo = s.todo.filter(function (a) { return s.t < a.at; });
    due.forEach(function (a) { a.run(s); });
  }

  // Step a simulation and whatever is waiting to happen to it.
  function stepLive(figure, s, dt) { sims[figure].step(s, dt); runTodo(s); }

  ME.runLive = function (figure, s, seconds) {
    var steps = Math.round(seconds / 0.05);
    for (var i = 0; i < steps; i++) stepLive(figure, s, 0.05);
  };

  // A canvas figure: a "Simulation" label, a row of counters, and a canvas that redraws
  // every animation frame while it is on screen. `parts` is
  // { figure, data, draw(ctx, s, size, colors), counters(s) -> [[label, value, hot]], settle (seconds) }.
  function canvasFigure(host, parts) {
    var doc = host.ownerDocument;
    var label = doc.createElement('span'); label.className = 'mx-sim-label'; label.textContent = 'Simulation';
    var counters = doc.createElement('div'); counters.className = 'mx-counters';
    var canvas = doc.createElement('canvas');
    host.appendChild(label); host.appendChild(counters); host.appendChild(canvas);
    var ctx = canvas.getContext('2d'), sim = null, current = null, last = null, size = { width: 0, height: 0 }, fade = 0;

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
      if (last !== null && sim && onScreen()) { stepLive(parts.figure, sim, (t - last) / 1000); paint(); }
      last = t;
      root.requestAnimationFrame(frame);
    }
    if (typeof root.ResizeObserver === 'function') new root.ResizeObserver(paint).observe(host);
    if (!ME.reducedMotion()) root.requestAnimationFrame(frame);

    return {
      setState: function (state) {
        if (state === current) return;
        var still = ME.reducedMotion();
        // the next card: its event happens to what is on screen
        if (sim && current !== null && ME.liveTransition(parts.figure, current, state, sim, parts.data)) {
          current = state;
          if (still) ME.runLive(parts.figure, sim, parts.settle);
          paint();
          return;
        }
        var next = ME.buildState(parts.figure, state, parts.data);    // throws on an unknown state
        var first = sim === null;
        current = state;
        if (first || still) {
          sim = next;
          if (still) ME.runLive(parts.figure, sim, parts.settle);
          paint();
          return;
        }
        // anywhere else: a different picture, so fade the old one out and the new one in
        var mine = ++fade;
        canvas.style.opacity = '0'; counters.style.opacity = '0';
        later(function () {
          if (mine !== fade) return;                                  // a later card got there first
          sim = next;
          paint();
          canvas.style.opacity = '1'; counters.style.opacity = '1';
        }, 170);
      },
    };
  }
  ME.canvasFigure = canvasFigure;

  // ── chapter 3: inside one node, the Ledger actor ───────────────────────────────
  var MAILBOX = ['idle', 'one-at-a-time', 'sessions', 'crash', 'restart', 'lost-total'];
  sims.mailbox = ME.simMailbox;

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

  // The first three cards are the same actor seen three ways; the fourth crashes it;
  // the fifth lets it come back.
  live.mailbox = function (from, to, s, data) {
    if (!isNext(MAILBOX, from, to)) return false;
    var normal = mailboxConfig(data).restartS;
    if (to === 'crash') {
      s.cfg = Object.assign({}, s.cfg, { restartS: Infinity });
      ME.simMailbox.crash(s);
    } else if (to === 'restart') {
      s.cfg = Object.assign({}, s.cfg, { restartS: normal });
      s.downFor = Math.max(0, normal - 0.8);      // it comes back a moment after the card arrives
    }
    return true;
  };

  ME.registerFigure('mailbox', function (host, data) {
    return canvasFigure(host, {
      figure: 'mailbox', data: data, settle: 2,
      draw: ME.draw.mailbox,
      counters: function (s) {
        return [['Handled', s.total], ['Waiting', s.queue.length], ['Dropped', s.dropped, s.dropped > 0]];
      },
    });
  });

  // ── chapter 4: the cluster ─────────────────────────────────────────────────────
  // Each script starts from the same seed. Host indices follow topology.stock_hosts;
  // the Ledger starts on the last `books` host.
  var CLUSTER = ['steady', 'full', 'stock-crash', 'silent', 'ledger-stop', 'return', 'no-offer'];
  sims.cluster = ME.simCluster;

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

  function booksHosts(cfg) {
    var books = [];
    cfg.hosts.forEach(function (h, i) { if (h.books) books.push(i); });
    return books;
  }

  // enough callers that the Ledger, the smallest capacity in the path, runs out of slots
  function fullLoad(cfg) { return Math.ceil(cfg.ledgerCapacity / cfg.sessionS[0]) + 8; }

  builders.cluster = function (state, data) {
    var sim = ME.simCluster, cfg = clusterConfig(data), books = booksHosts(cfg);
    var ledger = books[books.length - 1];
    function kill(i, mode) { return function (s) { sim.kill(s, i, mode); }; }
    function revive(i) { return function (s) { sim.revive(s, i); }; }
    var scripts = {
      steady: { until: 8, actions: [] },
      full: { load: fullLoad(cfg), until: 10, actions: [] },
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

  // The next card's event, done to the running cluster. Where the last card left a host
  // down that this card needs up, it is brought back first, and the event follows once
  // it has restarted. The counters start again when the event happens, so they count
  // what this card is about.
  live.cluster = function (from, to, s, data) {
    if (!isNext(CLUSTER, from, to)) return false;
    var sim = ME.simCluster, base = clusterConfig(data), books = booksHosts(base);
    var ledger0 = books[books.length - 1];

    function load(n) { s.cfg = Object.assign({}, s.cfg, { loadPerS: n }); }
    function fresh() { s.counters = { started: s.sessions.length, completed: 0, cancelled: 0, refused: 0 }; }
    // Bring every host back; how long until they are all up.
    function heal() {
      var wait = 0;
      s.hosts.forEach(function (h, i) {
        if (h.status === 'up') return;
        if (h.status !== 'restarting') sim.revive(s, i);
        wait = Math.max(wait, s.cfg.restartS - (s.t - h.since) + 1.5);
      });
      return wait;
    }

    if (to === 'full') { load(fullLoad(base)); fresh(); }
    else if (to === 'stock-crash') {
      load(base.loadPerS);                                    // let the queue for the Ledger drain first
      soon(s, 2.5, function () { fresh(); sim.kill(s, 0, 'crash'); });
    } else if (to === 'silent') {
      soon(s, heal(), function () { fresh(); sim.kill(s, 0, 'silent'); });
    } else if (to === 'ledger-stop') {
      if (s.ledger.host !== ledger0) return false;
      soon(s, heal(), function () { fresh(); sim.kill(s, ledger0, 'crash'); });
    } else if (to === 'return') {
      if (s.hosts[ledger0].status !== 'dead') return false;
      // not before the Ledger has moved: the card is about a host returning to find it gone
      var moved = s.ledger.host === null && s.ledger.moveAt !== null ? s.ledger.moveAt - s.t + 0.5 : 0;
      soon(s, Math.max(0, moved), function () { fresh(); sim.revive(s, ledger0); });
    } else if (to === 'no-offer') {
      soon(s, heal(), function () { fresh(); books.forEach(function (i) { sim.kill(s, i, 'crash'); }); });
    }
    return true;
  };

  ME.registerFigure('cluster', function (host, data) {
    return canvasFigure(host, {
      figure: 'cluster', data: data, settle: 6,
      draw: ME.draw.cluster,
      counters: function (s) {
        var c = s.counters;
        return [['Completed', c.completed], ['In flight', s.sessions.length],
          ['Cancelled', c.cancelled, c.cancelled > 0], ['Refused', c.refused, c.refused > 0]];
      },
    });
  });
})(typeof window !== 'undefined' ? window : globalThis);

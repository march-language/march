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

  // How big a figure is before any scaling: its widest slot, by all its slots stacked
  // (a caption is a line of text, and slots are 4px apart).
  ME.naturalSize = function (specs) {
    var w = 0, h = 0;
    specs.forEach(function (spec, i) {
      var m = /^<svg[^>]* width="([\d.]+)" height="([\d.]+)"/.exec(spec.svg) || [0, 0, 0];
      w = Math.max(w, Number(m[1]));
      h += Number(m[2]) + (spec.caption ? 26 : 0) + (i ? 4 : 0);
    });
    return { w: w, h: h };
  };

  // The scale that makes a figure of `natural` size fill a stage of `room`, between
  // 0.4x and 2.2x. A stage with no size yet (not laid out) leaves the figure alone.
  ME.fitScale = function (natural, room) {
    if (!(room.w > 40) || !(room.h > 40) || !(natural.w > 0) || !(natural.h > 0)) return 1;
    return Math.max(0.4, Math.min(2.2, room.w / natural.w, room.h / natural.h));
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
    var slots = {}, drawnAt = null, natural = { w: 0, h: 0 };

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
        var width = Math.max(280, host.clientWidth || 680), height = host.clientHeight || 0;
        var stageSize = width + 'x' + height;
        var resized = drawnAt !== null && drawnAt !== stageSize;
        if (resized) { box.innerHTML = ''; slots = {}; }            // a new stage is a new drawing
        var animate = drawnAt !== null && !resized && !ME.reducedMotion();
        var specs = view(width, Math.max(0, height - 24)), keep = {};
        specs.forEach(function (spec) { keep[spec.id] = true; });
        Object.keys(slots).forEach(function (id) { if (!keep[id]) { slots[id].wrap.remove(); delete slots[id]; } });
        specs.forEach(function (spec) {
          var fresh = !slots[spec.id];
          if (fresh) slots[spec.id] = makeSlot(spec, animate);
          box.appendChild(slots[spec.id].wrap);                       // keeps the slots in view order
          if (slots[spec.id].cap && spec.caption) slots[spec.id].cap.textContent = spec.caption;
          apply(slots[spec.id], spec.svg, animate && !fresh);
        });
        drawnAt = stageSize;
        natural = opts && opts.frame ? opts.frame(width, Math.max(0, height - 24)) : ME.naturalSize(specs);
        fit();
      },
    };

    // A figure is drawn at its own design size and then scaled, up or down, to fill
    // the stage it is in: bigger on a desk, smaller on a phone held sideways, and never
    // running over the cards below.
    function fit() {
      if (!box.style || typeof host.clientHeight !== 'number') return;
      var k = ME.fitScale(natural, { w: host.clientWidth, h: host.clientHeight - 24 });
      box.style.transformOrigin = opts && opts.top ? 'top center' : 'center';
      box.style.transform = k === 1 ? '' : 'scale(' + k.toFixed(3) + ')';
    }
    if (typeof root.ResizeObserver === 'function') new root.ResizeObserver(function () { if (drawnAt !== null) api.draw(); }).observe(host);
    return api;
  }
  ME.svgFigure = svgFigure;

  // A small figure inside a card: <div data-mx-inline="timeline:silent"></div>.
  var inline = {
    'timeline:silent': function (w, data) { return F.detectionTimeline(data.timings, { width: w, mode: 'silent' }); },
    'timeline:crash': function (w, data) { return F.detectionTimeline(data.timings, { width: w, mode: 'crash' }); },
  };
  ME.mountInline = function (rootEl, data) {
    Array.prototype.forEach.call(rootEl.querySelectorAll('[data-mx-inline]'), function (el) {
      var name = el.dataset.mxInline;
      el.innerHTML = inline[name] ? inline[name](Math.max(260, el.clientWidth || 320), data)
        : '<p class="mx-error">no such inline figure: ' + name + '</p>';
    });
  };

  // ── the opening: the declaration, read a few lines at a time ───────────────────
  // A card's state is `lines:A-B` (or `lines:A`), the lines of the protocol it is
  // about, or `all`.
  ME.registerFigure('declaration', function (host, data) {
    var total = data.order.source.length, from = 0, to = 0, current = null;
    var fig = svgFigure(host, function (w) {
      return [{ id: 'code', svg: F.declaration(data.order, { width: w, from: from, to: to }) }];
    });
    return {
      setState: function (state) {
        if (state === current) return;
        var m = /^lines:(\d+)(?:-(\d+))?$/.exec(state);
        if (state !== 'all' && !m) throw new Error('unknown state ' + state);
        var a = m ? Number(m[1]) : 0, b = m ? Number(m[2] || m[1]) : 0;
        if (m && (a < 1 || b > total || a > b)) {
          throw new Error('lines ' + a + '-' + b + ' are not in a protocol of ' + total + ' lines');
        }
        from = a; to = b; current = state;
        fig.draw();
      },
    };
  });

  // ── chapter 1: the state map ───────────────────────────────────────────────────
  // empty: every cell, none lit. path: the reachable cells light in the order the
  // protocol reaches them. all: every reachable cell lit. skip / offer / turn: all lit,
  // plus the cell where one wrong program is stopped.
  var WRONG = { skip: 'skip_step', offer: 'offer_misses_branch', turn: 'send_out_of_turn' };

  ME.registerFigure('state-map', function (host, data) {
    var sm = data.state_map, total = sm.path.length;
    var lit = 0, wrong = null, current = null, timer = null;
    var fig = svgFigure(host, function (w, h) {
      return [{ id: 'map', svg: F.stateMap(sm, { width: w, height: h, lit: lit, wrong: wrong }) }];
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
  // How to draw the fan-out for a stage of this shape. Under 520 px wide: the compact
  // drawing, at the stage's own width. Otherwise the full drawing at a design size the
  // page then scales: five modules in a row (680 wide), or three to a row (416 wide)
  // when that can be scaled up further, as it can in a stage that is nearly square.
  function fanOutLayout(data, width, height) {
    if (width < 520) return { width: width, perRow: 0, wide: false };
    var best = { width: 680, perRow: data.order.modules.length, wide: true };
    if (!height) return best;
    var bestK = -1;
    [{ width: 680, perRow: data.order.modules.length }, { width: 416, perRow: 3 }].forEach(function (c) {
      var m = /width="([\d.]+)" height="([\d.]+)"/.exec(F.fanOut(data.order, { width: c.width, perRow: c.perRow, stage: 'functions' }));
      var k = Math.min(width / Number(m[1]), height / (Number(m[2]) + 60));    // room for a strip beneath
      if (k > bestK + 1e-9) { bestK = k; best = { width: c.width, perRow: c.perRow, wide: true }; }
    });
    return best;
  }

  ME.fanOutView = function (state, data, width, height) {
    var order = data.order, lay = fanOutLayout(data, width, height), wide = lay.wide, w = lay.width;
    function code(stage) { return { id: 'code', svg: F.fanOut(order, { width: w, perRow: lay.perRow || undefined, stage: stage }) }; }
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

  // The size the fan-out is scaled by: the largest any of its cards needs, so that the
  // drawing is one size from the first card to the last.
  var FAN_STATES = ['source', 'project', 'modules', 'functions', 'typecheck', 'grants', 'main', 'hosts'];
  ME.fanOutFrame = function (data, width, height) {
    var frame = { w: 0, h: 0 };
    FAN_STATES.forEach(function (state) {
      var size = ME.naturalSize(ME.fanOutView(state, data, width, height));
      frame.w = Math.max(frame.w, size.w); frame.h = Math.max(frame.h, size.h);
    });
    return frame;
  };

  ME.registerFigure('fan-out', function (host, data) {
    var current = null;
    var fig = svgFigure(host, function (w, h) { return ME.fanOutView(current, data, w, h); },
      { top: true, frame: function (w, h) { return ME.fanOutFrame(data, w, h); } });
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

  // A simulation defined outside this file (chapters-authority.js): its core, how to
  // build the picture a card opens on, and how to move on to the next card.
  ME.registerSim = function (figure, parts) {
    sims[figure] = parts.sim; builders[figure] = parts.build; live[figure] = parts.live;
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
      // A drawing with a design size is drawn at that size and scaled to fill the canvas,
      // centred, so it is as big as the stage allows.
      var design = parts.design ? parts.design(size) : null;
      if (design) {
        var k = Math.min(2.2, size.width / design.width, size.height / design.height);
        ctx.clearRect(0, 0, size.width, size.height);
        ctx.save();
        ctx.translate((size.width - design.width * k) / 2, (size.height - design.height * k) / 2);
        ctx.scale(k, k);
        parts.draw(ctx, sim, design, colors());
        ctx.restore();
      } else parts.draw(ctx, sim, size, colors());
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
      // drawn small and scaled up: one queue and one actor do not need many pixels
      // The drawing is 230 high by design and takes whatever width that leaves it: the
      // actor is scaled to the height of the stage and the mailbox gets the rest.
      design: function (size) {
        var k = Math.min(2.2, size.height / 230);
        return { width: Math.max(343, size.width / k), height: 230 };
      },
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
      // one failure detector, the node's: a probe and its ack to notice, then the suspect timeout
      noticeS: data.timings.swim_probe_s + data.timings.swim_ack_ms / 1000,
      suspectS: data.timings.suspect_s,
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
      // shown once the host is under suspicion, its sessions frozen and not yet cancelled
      silent: { until: 8 + cfg.noticeS + 1, actions: [{ at: 8, run: kill(0, 'silent') }] },
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

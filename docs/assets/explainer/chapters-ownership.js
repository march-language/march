// chapters-ownership.js: the figures of docs/one-owner.md, one registration per graphic.
// It uses the machinery of chapters.js (svgFigure, canvasFigure, registerSim): a card's
// `data-state` is absolute, and moving on to the NEXT card makes that card's event
// happen to the simulation already on screen.
//
//   heap      one tree of heap cells and `inc_leaves` walking it: rewritten in place,
//             copied when shared (by a second use, or a Vault), two halves on two tasks
//   token     the excerpt's lines with a token beside the line the linear value is on
//   contract  the allocation ledger: cells per call against the contract's line
(function (root) {
  'use strict';
  var ME = root.MarchExplainer, F = ME.figures, H = ME.simHeap;

  // ── the heap ───────────────────────────────────────────────────────────────────
  ME.heapConfig = function (data) {
    var vault = /Vault\.new\("([^"]*)"\)/.exec(data.runs.vault.excerpt || '');
    return {
      seed: data.sim.seed, depth: data.tree.depth, visitS: data.sim.visit_s, holdS: data.sim.hold_s,
      plumbing: data.runs.parallel.allocs.plumbing || 0,
      view: {
        holder: 't', second: 'sum_leaves(t)', vault: 'Vault "' + (vault ? vault[1] : 'trees') + '"',
        vaultNote: String(data.runs.vault.why_copies || '').split('\n')[0].split(':')[0],   // its headline clause
      },
    };
  };

  // Each card: what happens when the reader arrives, and how long it takes to settle.
  // Every run starts from the tree as `build` left it, so arriving at a card restarts
  // `inc_leaves` under that card's conditions.
  function settle(mode) { return function (s) { return H.runLength(s, mode); }; }
  var HEAP = [
    { name: 'built', settle: function () { return 0.6; }, enter: function (s) { H.reset(s); } },
    { name: 'owned', settle: settle('owned'), enter: function (s) { H.start(s, 'owned'); } },
    { name: 'shared', settle: settle('shared'), enter: function (s) { H.start(s, 'shared'); } },
    { name: 'vault', settle: settle('vault'), enter: function (s) { H.start(s, 'vault'); } },
    { name: 'parallel', settle: settle('parallel'), enter: function (s) { H.start(s, 'parallel'); } },
  ];
  var HEAP_NAMES = HEAP.map(function (c) { return c.name; });

  ME.registerSim('heap', {
    sim: H,
    build: function (state, data) {
      var k = HEAP_NAMES.indexOf(state);
      if (k < 0) throw new Error('unknown state ' + state);
      var s = H.create(ME.heapConfig(data));
      for (var i = 0; i <= k; i++) { HEAP[i].enter(s); H.advance(s, HEAP[i].settle(s)); }
      return s;
    },
    live: function (from, to, s) {
      var k = HEAP_NAMES.indexOf(to);
      if (k < 1 || HEAP_NAMES[k - 1] !== from) return false;
      HEAP[k].enter(s);
      return true;
    },
  });
  ME.HEAP_STATES = HEAP_NAMES;

  ME.heapCounters = function (s) {
    var c = s.counters, mode = s.mode || 'built';
    var out = [['Cells', c.cells], ['Allocated by inc_leaves', c.allocs, c.allocs > 0], ['Holders', s.holders]];
    if (mode === 'shared' || mode === 'vault') out.push(['Count increments', c.incs]);
    if (mode === 'parallel') out.push(['Tasks', c.tasks], ['Other cells', c.plumbing]);
    return out;
  };

  ME.registerFigure('heap', function (host, data) {
    var longest = 0;
    HEAP.forEach(function (card) { longest = Math.max(longest, card.settle(H.create(ME.heapConfig(data)))); });
    return ME.canvasFigure(host, {
      figure: 'heap', data: data, settle: longest, draw: ME.draw.heap, design: ME.draw.heapDesign,
      counters: ME.heapCounters,
    });
  });

  // ── the token ──────────────────────────────────────────────────────────────────
  // A card's state names a verdict of the linear check; the data's entry for it.
  var TOKEN_ENTRY = { 'linear-ok': 'ok', 'linear-twice': 'twice', 'linear-never': 'never', 'affine-ok': 'affine_ok', 'affine-twice': 'affine_twice' };
  ME.tokenEntry = function (data, state) {
    var key = TOKEN_ENTRY[state];
    if (!key || !data.linear[key]) throw new Error('unknown state ' + state);
    return data.linear[key];
  };
  function tokenView(data, state, width) {
    return [{ id: 'token', svg: F.token(ME.tokenEntry(data, state), { width: width, kind: state.indexOf('affine') === 0 ? 'affine' : 'linear' }) }];
  }

  // The largest any card needs at this width, so the drawing is one size throughout.
  ME.tokenFrame = function (data, width) {
    var frame = { w: 0, h: 0 };
    F.TOKEN_STATES.forEach(function (state) {
      var size = ME.naturalSize(tokenView(data, state, width));
      frame.w = Math.max(frame.w, size.w); frame.h = Math.max(frame.h, size.h);
    });
    return frame;
  };

  ME.registerFigure('token', function (host, data) {
    var current = null;
    var fig = ME.svgFigure(host, function (w) { return tokenView(data, current, Math.min(w, 560)); },
      { top: true, frame: function (w) { return ME.tokenFrame(data, Math.min(w, 560)); } });
    return {
      setState: function (state) {
        if (state === current) return;
        ME.tokenEntry(data, state);                 // throws on an unknown state, before anything changes
        current = state;
        fig.draw();
      },
    };
  });
  ME.TOKEN_STATES = F.TOKEN_STATES;

  // ── the contract ───────────────────────────────────────────────────────────────
  function contractView(data, stage, width) {
    return [{ id: 'contract', svg: F.contract(data.contracts, { width: width, stage: stage }) }];
  }
  ME.contractFrame = function (data, width) {
    var frame = { w: 0, h: 0 };
    F.CONTRACT_STATES.forEach(function (stage) {
      var size = ME.naturalSize(contractView(data, stage, width));
      frame.w = Math.max(frame.w, size.w); frame.h = Math.max(frame.h, size.h);
    });
    return frame;
  };

  ME.registerFigure('contract', function (host, data) {
    var current = null;
    var fig = ME.svgFigure(host, function (w) { return contractView(data, current, w); },
      { top: true, frame: function (w) { return ME.contractFrame(data, w); } });
    return {
      setState: function (state) {
        if (state === current) return;
        if (F.CONTRACT_STATES.indexOf(state) < 0) throw new Error('unknown state ' + state);
        current = state;
        fig.draw();
      },
    };
  });
  ME.CONTRACT_STATES = F.CONTRACT_STATES;
})(typeof window !== 'undefined' ? window : globalThis);

// sim-heap.js: one binary tree on the heap, and `inc_leaves` walking it, as a simulation
// core.
//
// For docs/one-owner.md. No DOM, no clock, no Math.random (tests:
// test/explainer/ownership.test.js). It is a SIMULATION, labelled as one on the page;
// draw-ownership.js draws it. The counts it ends on are the measured ones from
// docs/_data/ownership.json: 31 cells built, 0 or 31 allocated by `inc_leaves`, 30
// reference-count increments when the tree is shared.
//
// The rules, from the Memory Model chapter:
//   - The tree is a complete binary tree of `depth`: 2^depth leaves and 2^depth - 1
//     nodes, one heap cell each, every cell with a reference count. `inc_leaves` visits
//     it in pre-order (node, left, right), one cell per `visitS`.
//   - `owned`: the call is the last use of the tree, so each cell visited is rewritten in
//     place. Nothing is allocated.
//   - `shared`: a second holder keeps the tree, so the root's count is 2. Each node
//     visited hands a shared reference to each child (two increments) and `inc_leaves`
//     allocates a copy of every cell it visits: a second tree.
//   - `vault`: the same as `shared`, except the second holder is a Vault the static
//     report cannot see.
//   - `parallel`: the root is opened once, and the two halves are each walked by their
//     own task, in place; the plumbing around the two tasks (list cells, thunks) is the
//     only allocation.
(function (root) {
  'use strict';
  var MAX_DT = 0.1, FLASH_S = 0.45, GROW_S = 0.3;
  var MODES = ['owned', 'shared', 'vault', 'parallel'];

  // Cells are heap-indexed: cell i has children 2i+1 and 2i+2, and sits in row
  // floor(log2(i+1)). The root is 0.
  function rowOf(i) { return Math.floor(Math.log2(i + 1)); }
  function cellCount(depth) { return Math.pow(2, depth + 1) - 1; }
  function children(s, i) { return 2 * i + 2 < s.cells.length ? [2 * i + 1, 2 * i + 2] : []; }

  // The order `inc_leaves` visits the subtree under `i`: the node, then its left, then
  // its right.
  function preorder(s, i) {
    var out = [];
    (function walk(k) {
      out.push(k);
      children(s, k).forEach(walk);
    })(i);
    return out;
  }

  // cfg: { seed, depth, visitS, holdS, plumbing, view: what the renderer shows (the
  //        holder labels, the Vault's name, the static report's line) }
  function create(cfg) {
    var s = { cfg: cfg, t: 0, mode: null, cells: [], copies: [], cursors: [], holders: 1,
      startedAt: 0, counters: {} };
    for (var i = 0; i < cellCount(cfg.depth); i++) s.cells.push({ rc: 1, row: rowOf(i), visitedAt: null, rewritten: false });
    reset(s);
    return s;
  }

  // The tree as `build` left it: every count 1, nothing visited, no copy, one holder.
  // The clock keeps running: a reset on screen is a new run of the program, not a cut.
  function reset(s) {
    s.mode = null; s.cursors = []; s.copies = []; s.holders = 1; s.startedAt = s.t;
    s.cells.forEach(function (c) { c.rc = 1; c.visitedAt = null; c.rewritten = false; c.incAt = null; });
    s.counters = { cells: s.cells.length, allocs: 0, incs: 0, tasks: 0, plumbing: 0 };
  }

  function cursor(s, from) {
    return { order: preorder(s, from), k: -1, t: 0, done: false, at: from, prev: from };
  }

  // Begin a run of `inc_leaves` in one of the modes. The cursor waits `holdS` at its
  // start before it moves, so the reader sees where it begins.
  function start(s, mode) {
    if (MODES.indexOf(mode) < 0) throw new Error('unknown mode ' + mode);
    reset(s);
    s.mode = mode;
    if (mode === 'shared' || mode === 'vault') { s.holders = 2; s.cells[0].rc = 2; }
    if (mode === 'parallel') {
      s.counters.tasks = 2; s.counters.plumbing = s.cfg.plumbing || 0;
      children(s, 0).forEach(function (i) { s.cursors.push(cursor(s, i)); });
    } else s.cursors.push(cursor(s, 0));
  }

  // What happens to the cell a cursor arrives at.
  function visit(s, i) {
    var c = s.cells[i];
    c.visitedAt = s.t;
    if (s.mode === 'shared' || s.mode === 'vault') {
      s.copies[i] = { bornAt: s.t };
      s.counters.allocs += 1;
      children(s, i).forEach(function (k) { s.cells[k].rc += 1; s.cells[k].incAt = s.t; s.counters.incs += 1; });
    } else c.rewritten = true;
  }

  function stepCursor(s, cur, dt) {
    if (cur.done) return;
    cur.t += dt;
    if (cur.k < 0) {
      if (cur.t < s.cfg.holdS) return;
      cur.t -= s.cfg.holdS; cur.k = 0;
      cur.prev = cur.at; cur.at = cur.order[0];
      visit(s, cur.at);
    }
    while (cur.t >= s.cfg.visitS) {
      cur.t -= s.cfg.visitS;
      cur.k += 1;
      if (cur.k >= cur.order.length) { cur.done = true; cur.t = 0; return; }
      cur.prev = cur.at; cur.at = cur.order[cur.k];
      visit(s, cur.at);
    }
  }

  function step(s, dt) {
    dt = Math.min(dt, MAX_DT);
    s.t += dt;
    if (!s.mode) return;
    s.cursors.forEach(function (cur) { stepCursor(s, cur, dt); });
    // the root of a parallel run is rebuilt in place once both halves are back
    if (s.mode === 'parallel' && s.cursors.length && s.cursors.every(function (c) { return c.done; }) && !s.cells[0].rewritten) {
      visit(s, 0);
    }
  }

  function advance(s, seconds) {
    var steps = Math.round(seconds / 0.05);
    for (var i = 0; i < steps; i++) step(s, 0.05);
  }

  // How far the run has got: cells visited, cells in all, and whether it is over.
  function progress(s) {
    var visited = 0;
    s.cells.forEach(function (c) { if (c.visitedAt !== null) visited += 1; });
    return { visited: visited, total: s.cells.length, done: !!s.mode && s.cursors.every(function (c) { return c.done; }) };
  }

  // Where a cursor is between the last cell and this one: 0 just left, 1 arrived. A
  // cursor still waiting at its start is at its first cell, and a finished one is gone.
  function cursorAt(s, cur) {
    if (cur.done) return null;
    if (cur.k < 0) return { from: cur.order[0], to: cur.order[0], u: 1 };
    return { from: cur.prev, to: cur.at, u: Math.min(1, cur.t / (s.cfg.visitS * 0.7)) };
  }

  // How bright a cell's flash is right now: 1 as the cursor lands, 0 once it has faded.
  function flash(s, i) {
    var c = s.cells[i];
    if (c.visitedAt === null) return 0;
    return Math.max(0, 1 - (s.t - c.visitedAt) / FLASH_S);
  }

  // How far a copy cell has grown: 0 not there, 1 full size.
  function grown(s, i) {
    var k = s.copies[i];
    if (!k) return 0;
    return Math.min(1, (s.t - k.bornAt) / GROW_S);
  }

  // How long a run takes from start to the last cell visited, plus its fade.
  function runLength(s, mode) {
    var cells = mode === 'parallel' ? (s.cells.length - 1) / 2 : s.cells.length;
    return s.cfg.holdS + cells * s.cfg.visitS + FLASH_S + 0.3;
  }

  var api = { create: create, reset: reset, start: start, step: step, advance: advance, progress: progress,
    preorder: preorder, children: children, rowOf: rowOf, cellCount: cellCount, cursorAt: cursorAt,
    flash: flash, grown: grown, runLength: runLength, MODES: MODES, FLASH_S: FLASH_S, GROW_S: GROW_S };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.simHeap = api;
})(typeof window !== 'undefined' ? window : globalThis);

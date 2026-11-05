// sim-cluster.js: the cluster of docs/protocol-to-cluster.md, as a simulation core.
//
// No DOM, no clock, no Math.random: create() builds a state from a config and a seed, and
// step() advances it, so a state can be rebuilt exactly (test/explainer/sim-cluster.test.js)
// and drawn by draw.js. It is a SIMULATION, labelled as one on the page. Its rules are the
// ones the March chapters document; its load and session lengths are chosen for legibility.
//
// The rules:
//   - Every session takes one Stock slot on some host and one slot on the Ledger.
//   - A caller tries the hosts in turn. A host that is full or not answering is passed
//     over and the next one is tried; a host under suspicion is still tried, once, and the
//     attempt bounces. With no Stock host left, or no Ledger, the session is refused.
//   - A host that crashes loses its sessions at once (its connections close). A host that
//     goes silent is on two clocks: membership declares it dead after `suspectS`, which
//     stops callers trying it and moves the Ledger; the sessions already on it stay,
//     frozen, until their own heartbeat gives up after `silentS` (default: `suspectS`),
//     and are cancelled then. Cancelled sessions are not resumed.
//   - The Ledger starts on the last `books` host. If that host dies, the role moves to
//     another live `books` host `suspectS` after the failure. A returning host does not
//     take it back.
//   - A revived host is up again after `restartS`, as its next incarnation, empty.
(function (root) {
  'use strict';
  var rngApi = (typeof require === 'function' && typeof module !== 'undefined')
    ? require('./rng.js') : root.MarchExplainer.rng;

  var MAX_DT = 0.1;          // a hidden tab's first frame can carry minutes: never simulate that
  var TRAVEL = 0.4, BOUNCE = 0.2;

  function slots(n) { var a = []; for (var i = 0; i < n; i++) a.push(null); return a; }

  function create(cfg) {
    var hosts = cfg.hosts.map(function (h) {
      return { id: h.id, books: !!h.books, status: 'up', incarnation: 1, silent: false,
        since: 0, stock: slots(cfg.stockCapacity) };
    });
    var ledgerHost = null;
    hosts.forEach(function (h, i) { if (h.books) ledgerHost = i; });
    return {
      cfg: cfg, t: 0, rand: rngApi.mulberry32(cfg.seed), acc: 0, nextId: 1, rr: 0,
      hosts: hosts,
      ledger: { host: ledgerHost, slots: slots(cfg.ledgerCapacity), moveAt: null },
      sessions: [],
      counters: { started: 0, completed: 0, cancelled: 0, refused: 0 },
    };
  }

  function answering(h) { return h.status === 'up'; }
  function tryable(h) { return h.status === 'up' || h.status === 'suspect'; }

  function ledgerReady(s) {
    return s.ledger.host !== null && answering(s.hosts[s.ledger.host]) && s.ledger.slots.indexOf(null) >= 0;
  }

  function remove(s, sess) {
    var i = s.sessions.indexOf(sess);
    if (i >= 0) s.sessions.splice(i, 1);
  }

  // Give back the session's slots, if they are still its own (a host that restarted, or
  // a Ledger that moved, has fresh slots that may already belong to another session).
  function release(s, sess) {
    var stock = s.hosts[sess.host].stock;
    if (sess.stockSlot !== null && stock[sess.stockSlot] === sess.id) stock[sess.stockSlot] = null;
    if (sess.ledgerSlot !== null && s.ledger.slots[sess.ledgerSlot] === sess.id) s.ledger.slots[sess.ledgerSlot] = null;
    sess.stockSlot = null; sess.ledgerSlot = null;
  }

  function refuse(s, sess) { s.counters.refused += 1; remove(s, sess); }

  // Send the session towards the next host worth trying, or refuse it.
  function route(s, sess, from) {
    while (sess.next < sess.order.length && !tryable(s.hosts[sess.order[sess.next]])) sess.next += 1;
    if (sess.next >= sess.order.length) { refuse(s, sess); return; }
    sess.host = sess.order[sess.next];
    sess.phase = 'out'; sess.from = from; sess.elapsed = 0;
    sess.dur = from === null ? TRAVEL : BOUNCE;
  }

  function arrive(s, sess) {
    var h = s.hosts[sess.host], slot = answering(h) ? h.stock.indexOf(null) : -1;
    if (slot < 0) { sess.next += 1; route(s, sess, sess.host); return; }
    if (!ledgerReady(s)) { refuse(s, sess); return; }
    sess.stockSlot = slot; h.stock[slot] = sess.id;
    sess.ledgerSlot = s.ledger.slots.indexOf(null); s.ledger.slots[sess.ledgerSlot] = sess.id;
    sess.ledgerHost = s.ledger.host;
    sess.phase = 'serve'; sess.elapsed = 0;
    sess.dur = s.cfg.sessionS[0] + s.rand() * (s.cfg.sessionS[1] - s.cfg.sessionS[0]);
  }

  // Cancel every session being served by host `i`, as its Stock or as its Ledger.
  function cancelOn(s, i) {
    s.sessions.slice().forEach(function (sess) {
      if (sess.phase === 'serve' && (sess.host === i || sess.ledgerHost === i)) {
        release(s, sess); remove(s, sess); s.counters.cancelled += 1;
      }
    });
  }

  // Membership's verdict: no caller tries the host again, and the Ledger leaves it.
  function declareDead(s, i) {
    s.hosts[i].status = 'dead';
    if (s.ledger.host === i) { s.ledger.host = null; s.ledger.slots = slots(s.cfg.ledgerCapacity); }
  }

  // The sessions' own verdict: whatever the host still held is cancelled.
  function dropSessions(s, i) {
    s.hosts[i].silent = false;
    cancelOn(s, i);
  }

  function silentLimit(s) { return s.cfg.silentS === undefined ? s.cfg.suspectS : s.cfg.silentS; }

  function kill(s, i, mode) {
    var h = s.hosts[i];
    if (h.status !== 'up') return;
    h.since = s.t;
    if (s.ledger.host === i) s.ledger.moveAt = s.t + s.cfg.suspectS;
    if (mode === 'silent') { h.status = 'suspect'; h.silent = true; }
    else { declareDead(s, i); dropSessions(s, i); }
  }

  function revive(s, i) {
    var h = s.hosts[i];
    if (h.status === 'up' || h.status === 'restarting') return;
    if (h.status === 'suspect') declareDead(s, i);
    if (h.silent) dropSessions(s, i);
    h.status = 'restarting'; h.since = s.t;
  }

  function placeLedger(s) {
    for (var i = s.hosts.length - 1; i >= 0; i--) {
      if (s.hosts[i].books && answering(s.hosts[i])) { s.ledger.host = i; s.ledger.moveAt = null; return; }
    }
  }

  function step(s, dt) {
    dt = Math.min(dt, MAX_DT);
    s.t += dt;

    s.hosts.forEach(function (h, i) {
      if (h.status === 'suspect' && s.t - h.since >= s.cfg.suspectS) declareDead(s, i);
      if (h.silent && s.t - h.since >= silentLimit(s)) dropSessions(s, i);
      if (h.status === 'restarting' && s.t - h.since >= s.cfg.restartS) {
        h.status = 'up'; h.incarnation += 1; h.stock = slots(s.cfg.stockCapacity);
      }
    });
    if (s.ledger.host === null && (s.ledger.moveAt === null || s.t >= s.ledger.moveAt)) placeLedger(s);

    s.acc += dt * s.cfg.loadPerS;
    while (s.acc >= 1) {
      s.acc -= 1;
      var n = s.hosts.length, start = s.rr++ % n, order = [];
      for (var k = 0; k < n; k++) order.push((start + k) % n);
      var sess = { id: s.nextId++, order: order, next: 0, host: null, ledgerHost: null,
        stockSlot: null, ledgerSlot: null, phase: 'out', from: null, elapsed: 0, dur: TRAVEL };
      s.counters.started += 1;
      s.sessions.push(sess);
      route(s, sess, null);
    }

    s.sessions.slice().forEach(function (sess) {
      if (sess.phase === 'serve' && (s.hosts[sess.host].silent || s.hosts[sess.ledgerHost].silent)) return;
      sess.elapsed += dt;
      if (sess.elapsed < sess.dur) return;
      if (sess.phase === 'out') arrive(s, sess);
      else if (sess.phase === 'serve') { release(s, sess); sess.phase = 'back'; sess.elapsed = 0; sess.dur = TRAVEL; }
      else { s.counters.completed += 1; remove(s, sess); }
    });
  }

  function advance(s, seconds) {
    var steps = Math.round(seconds / 0.05);
    for (var i = 0; i < steps; i++) step(s, 0.05);
  }

  var api = { create: create, step: step, advance: advance, kill: kill, revive: revive };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.simCluster = api;
})(typeof window !== 'undefined' ? window : globalThis);

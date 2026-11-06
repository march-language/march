// sim-mailbox.js: one actor and its mailbox, as a simulation core.
//
// Used twice on docs/protocol-to-cluster.md: for the Ledger actor inside one node, and
// for what a hot deploy does to a running actor. No DOM, no clock, no Math.random
// (tests: test/explainer/sim-mailbox.test.js). It is a SIMULATION, labelled as one.
//
// The rules, which are the actor chapter's and the hot-reload chapter's:
//   - Messages queue in arrival order and are handled one at a time, to completion.
//     The message being handled stays at the head of the queue until it is done.
//   - Each handled message adds one to `total`, the actor's state.
//   - A deploy lands in the mailbox as a marker. Messages ahead of it finish on the old
//     code; at the marker the state is migrated, once, with nothing handled meanwhile;
//     everything after runs on the new code.
//   - An actor that holds work from the old code (a session party) waits at its marker
//     and moves only when the hold is released.
//   - A crash loses the mailbox, the state and the parked sessions. Messages sent to a
//     crashed actor are dropped. A fresh actor is up after `restartS`, from zero.
(function (root) {
  'use strict';
  var rngApi = (typeof require === 'function' && typeof module !== 'undefined')
    ? require('./rng.js') : root.MarchExplainer.rng;
  var MAX_DT = 0.1;

  function create(cfg) {
    var s = {
      cfg: cfg, t: 0, rand: rngApi.mulberry32(cfg.seed),
      queue: [], nextArrival: cfg.arrivalS, service: 0,
      version: 1, epoch: 1, deployed: false, migrating: false, migrateLeft: 0, held: false,
      status: 'up', downFor: 0, restarts: 0, dropped: 0,
      total: 0, parked: cfg.parked || 0, serving: -1,
      handled: { old: 0, 'new': 0 },
    };
    for (var i = 0; i < (cfg.backlog || 0); i++) s.queue.push({ kind: 'msg', epoch: 1 });
    return s;
  }

  function deploy(s) {
    if (s.deployed || s.status !== 'up') return;
    s.deployed = true; s.epoch = 2;
    s.queue.push({ kind: 'marker', epoch: 2 });
  }

  function releaseHold(s) { s.cfg = Object.assign({}, s.cfg, { holds: false }); }

  function crash(s) {
    if (s.status !== 'up') return;
    s.status = 'crashed'; s.downFor = 0;
    s.queue = []; s.service = 0; s.total = 0; s.parked = 0; s.serving = -1;
    s.migrating = false; s.held = false;
    s.handled = { old: 0, 'new': 0 };
  }

  function step(s, dt) {
    dt = Math.min(dt, MAX_DT);
    s.t += dt;

    s.nextArrival -= dt;
    while (s.nextArrival <= 0) {
      s.nextArrival += s.cfg.arrivalS * (0.8 + 0.4 * s.rand());
      if (s.status === 'up') s.queue.push({ kind: 'msg', epoch: s.epoch });
      else s.dropped += 1;
    }

    if (s.status !== 'up') {
      s.downFor += dt;
      if (s.downFor >= (s.cfg.restartS === undefined ? 1 : s.cfg.restartS)) { s.status = 'up'; s.restarts += 1; }
      return;
    }

    if (s.migrating) {
      s.migrateLeft -= dt;
      if (s.migrateLeft <= 0) { s.migrating = false; s.version = 2; s.queue.shift(); }
      return;
    }
    if (!s.queue.length) return;

    var head = s.queue[0];
    if (head.kind === 'marker') {
      if (s.cfg.holds) { s.held = true; return; }      // waits here, on the old code
      s.held = false; s.migrating = true; s.migrateLeft = s.cfg.migrateS;
      return;
    }
    if (s.serving < 0 && s.parked > 0) s.serving = Math.floor(s.rand() * s.parked);
    s.service += dt;
    if (s.service >= s.cfg.serviceS) {
      s.service = 0; s.serving = -1; s.queue.shift();
      s.total += 1;
      s.handled[s.version === 1 ? 'old' : 'new'] += 1;
      if (s.parked < (s.cfg.parked || 0)) s.parked += 1;   // after a restart, sessions form again
    }
  }

  function advance(s, seconds) {
    var steps = Math.round(seconds / 0.05);
    for (var i = 0; i < steps; i++) step(s, 0.05);
  }

  var api = { create: create, step: step, advance: advance, deploy: deploy, crash: crash, releaseHold: releaseHold };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.simMailbox = api;
})(typeof window !== 'undefined' ? window : globalThis);

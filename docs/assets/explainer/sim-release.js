// sim-release.js: one hot deploy rolling through a cluster, as a simulation core.
//
// For the deploy chapter of docs/protocol-to-cluster.md. No DOM, no clock, no Math.random
// (tests: test/explainer/sim-release.test.js). It is a SIMULATION, labelled as one.
//
// The rules, from the hot-reload chapter's "Through the in-cluster control plane":
//   - forge signs one release on the developer's machine and sends it to any control-plane
//     candidate, which passes it to the leader.
//   - Step 1 is a canary: the leader orders `canary` hosts to take the patch, and they
//     must stay healthy for the whole window before anyone else follows.
//   - Step 2 is the rest. If the canary fails its gate the release halts: the canary
//     keeps the new code, the others keep the old, and nothing is rolled back.
//   - Calls keep flowing throughout. A reply comes from whichever code the host was
//     running when it began the call. A call a host is serving at the moment it takes
//     the patch ends early, at a loop boundary: it is drained, which is not a failure.
(function (root) {
  'use strict';
  var rngApi = (typeof require === 'function' && typeof module !== 'undefined')
    ? require('./rng.js') : root.MarchExplainer.rng;
  var MAX_DT = 0.1, TRAVEL = 0.4;
  var HOP = { send: 0.9, forward: 0.6, canary: 0.6, rest: 0.6 };   // how long each message is in the air

  function create(cfg) {
    var canaryHost = -1;
    cfg.hosts.forEach(function (_, i) { if (i !== cfg.leader) canaryHost = i; });
    return {
      cfg: cfg, t: 0, rand: rngApi.mulberry32(cfg.seed), acc: 0, rr: 0,
      phase: 'idle', phaseT: 0, canaryFails: false, canaryHost: canaryHost,
      // the candidate that first receives the release: a host that is neither leader nor canary, if any
      entryHost: cfg.hosts.length > 2 ? cfg.hosts.map(function (_, i) { return i; })
        .filter(function (i) { return i !== cfg.leader && i !== canaryHost; })[0] : cfg.leader,
      hosts: cfg.hosts.map(function (id) { return { id: id, version: 1 }; }),
      calls: [],
      counters: { started: 0, oldReplies: 0, newReplies: 0, drained: 0, failed: 0 },
    };
  }

  function start(s, opts) {
    if (s.phase !== 'idle') return;
    s.canaryFails = !!(opts && opts.canaryFails);
    s.phase = 'send'; s.phaseT = 0;
  }

  // Host `i` takes the patch: what it was serving ends at a loop boundary.
  function patch(s, i) {
    s.hosts[i].version = 2;
    s.calls = s.calls.filter(function (c) {
      if (c.host === i && c.phase === 'serve') { s.counters.drained += 1; return false; }
      return true;
    });
  }

  function enter(s, phase) { s.phase = phase; s.phaseT = 0; }

  function stepRelease(s, dt) {
    if (s.phase === 'idle' || s.phase === 'complete' || s.phase === 'halted') return;
    s.phaseT += dt;
    if (s.phase === 'send' && s.phaseT >= HOP.send) enter(s, 'forward');
    else if (s.phase === 'forward' && s.phaseT >= HOP.forward) enter(s, 'canary');
    else if (s.phase === 'canary' && s.phaseT >= HOP.canary) { patch(s, s.canaryHost); enter(s, 'gate'); }
    else if (s.phase === 'gate' && s.phaseT >= s.cfg.windowS) enter(s, s.canaryFails ? 'halted' : 'rest');
    else if (s.phase === 'rest' && s.phaseT >= HOP.rest) {
      s.hosts.forEach(function (h, i) { if (h.version === 1) patch(s, i); });
      enter(s, 'complete');
    }
  }

  function step(s, dt) {
    dt = Math.min(dt, MAX_DT);
    s.t += dt;
    stepRelease(s, dt);

    s.acc += dt * s.cfg.loadPerS;
    while (s.acc >= 1) {
      s.acc -= 1;
      s.counters.started += 1;
      s.calls.push({ host: s.rr++ % s.hosts.length, phase: 'out', elapsed: 0, dur: TRAVEL, version: 1 });
    }
    for (var i = s.calls.length - 1; i >= 0; i--) {
      var c = s.calls[i];
      c.elapsed += dt;
      if (c.elapsed < c.dur) continue;
      if (c.phase === 'out') {
        c.phase = 'serve'; c.elapsed = 0; c.version = s.hosts[c.host].version;
        c.dur = s.cfg.sessionS[0] + s.rand() * (s.cfg.sessionS[1] - s.cfg.sessionS[0]);
      } else if (c.phase === 'serve') { c.phase = 'back'; c.elapsed = 0; c.dur = TRAVEL; }
      else {
        s.counters[c.version === 2 ? 'newReplies' : 'oldReplies'] += 1;
        s.calls.splice(i, 1);
      }
    }
  }

  function advance(s, seconds) {
    var steps = Math.round(seconds / 0.05);
    for (var i = 0; i < steps; i++) step(s, 0.05);
  }

  // Where the release or an order is in the air, for the renderer: {from, to, u}, with
  // 'forge' or a host index at each end; null when nothing is travelling.
  function packet(s) {
    if (s.phase === 'send') return { from: 'forge', to: s.entryHost, u: s.phaseT / HOP.send };
    if (s.phase === 'forward') return { from: s.entryHost, to: s.cfg.leader, u: s.phaseT / HOP.forward };
    if (s.phase === 'canary') return { from: s.cfg.leader, to: s.canaryHost, u: s.phaseT / HOP.canary };
    if (s.phase === 'rest') return { from: s.cfg.leader, to: s.entryHost, u: s.phaseT / HOP.rest };
    return null;
  }

  var api = { create: create, start: start, step: step, advance: advance, packet: packet };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.simRelease = api;
})(typeof window !== 'undefined' ? window : globalThis);

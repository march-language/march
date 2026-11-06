// sim-topology.js: a topology placing roles on machines, and one patch trying to reach
// them, as a simulation core.
//
// For docs/deploy-authority.md. No DOM, no clock, no Math.random
// (tests: test/explainer/authority.test.js). It is a SIMULATION, labelled as one on the
// page; draw-authority.js draws it.
//
// The rules, from the Topology and Hot Code Reload chapters:
//   - A role is a chip. The pool that initiates a role holds it on its host; a role with
//     no placement rule is offered on every host of the pool that serves it; a role
//     placed `{ on = LABEL, count = 1 }` is held by one host carrying the label.
//   - A session is a run of messages between the hosts holding its roles. It needs every
//     role before it starts, and it is cancelled when a host it runs on stops.
//   - A stopped host is given up on after the suspect time; a single-holder role it held
//     then moves to another host carrying the label. A host that returns offers its
//     every-host roles again at once. The single-holder role stays where it went: a
//     returning host counts for placement only after a settle period this simulation
//     does not wait out.
//   - A patch leaves the developer's machine only if forge's widening gate lets it:
//     it must be granted by name. It then goes to the control leader and from there to
//     every host, and each host checks it against its own policy before activating it.
(function (root) {
  'use strict';
  var rngApi = (typeof require === 'function' && typeof module !== 'undefined')
    ? require('./rng.js') : root.MarchExplainer.rng;
  var MAX_DT = 0.1, CHIP_S = 0.7, STAGGER = 0.22;
  var HOP = { toGate: 0.9, bounce: 0.7, toLeader: 0.8, fanOut: 0.9 };

  // cfg: { seed, sessionsPerS, legS, suspectS,
  //        hosts: [{ id, pool, labels }], initiator: host index, initiates: its role,
  //        serves: pool name, every: role offered on every serving host,
  //        single: { role, on: label }, view: what the renderer shows of the pools }
  function create(cfg) {
    var s = {
      cfg: cfg, t: 0, rand: rngApi.mulberry32(cfg.seed), acc: 0, rr: 0,
      hosts: cfg.hosts.map(function (h) {
        return { id: h.id, pool: h.pool, labels: h.labels.slice(), status: 'up', since: 0, code: 1 };
      }),
      chips: [], flow: false, sessions: [],
      show: {},                       // flag -> the time it was turned on
      patch: null, leader: -1,
      counters: { finished: 0, cancelled: 0, refused: 0 },
    };
    s.hosts.forEach(function (h, i) { if (s.leader < 0 && h.labels.indexOf('control') >= 0) s.leader = i; });
    return s;
  }

  function serving(s) {
    var out = [];
    s.hosts.forEach(function (h, i) { if (h.pool === s.cfg.serves) out.push(i); });
    return out;
  }

  // The host that should hold the single-holder role: the last host carrying the label
  // that is up. -1 when none is.
  function rankSingle(s) {
    var best = -1;
    serving(s).forEach(function (i) {
      if (s.hosts[i].status === 'up' && s.hosts[i].labels.indexOf(s.cfg.single.on) >= 0) best = i;
    });
    return best;
  }

  function chipOf(s, role) { return s.chips.filter(function (c) { return c.role === role; })[0] || null; }
  function settled(s, c) { return c && s.t >= c.movedAt + CHIP_S; }

  // The roles leave the topology file and land where it places them, one after another.
  function place(s) {
    if (s.chips.length) return;
    var n = 0;
    function chip(role, host) { s.chips.push({ role: role, host: host, from: -1, movedAt: s.t + STAGGER * n++ }); }
    chip(s.cfg.initiates, s.cfg.initiator);
    serving(s).forEach(function (i) { chip(s.cfg.every, i); });
    chip(s.cfg.single.role, rankSingle(s));
  }

  function show(s, flag) { if (s.show[flag] === undefined) s.show[flag] = s.t; }
  function hide(s, flag) { delete s.show[flag]; }

  function stop(s, i) {
    var h = s.hosts[i];
    if (h.status !== 'up') return;
    h.status = 'down'; h.since = s.t;
    s.sessions = s.sessions.filter(function (x) {
      if (x.stock !== i && x.single !== i) return true;
      s.counters.cancelled += 1;
      return false;
    });
  }

  function start(s, i) {
    var h = s.hosts[i];
    if (h.status === 'up') return;
    h.status = 'up'; h.since = s.t;
    s.chips.forEach(function (c) { if (c.host === i && c.role === s.cfg.every) { c.from = i; c.movedAt = s.t; } });
  }

  // A patch sets out from the developer's machine. `grant`: was the widening granted by
  // name? Without it the patch never leaves.
  function sendPatch(s, opts) {
    s.patch = { phase: 'toGate', t: 0, grant: !!(opts && opts.grant), verdict: null };
  }

  // What the nodes decide once the patch reaches them: admit it or refuse it.
  function resolveNodes(s, admit) {
    if (!s.patch) return;
    s.patch.verdict = admit ? 'admit' : 'refuse';
    if (s.patch.phase === 'atNodes') decide(s);
  }

  function decide(s) {
    var p = s.patch;
    if (p.verdict === 'admit') {
      p.phase = 'activated'; p.t = 0;
      s.hosts.forEach(function (h) { if (h.status === 'up') h.code = 2; });
    } else if (p.verdict === 'refuse') { p.phase = 'nodeRefused'; p.t = 0; }
  }

  function stepPatch(s, dt) {
    var p = s.patch;
    if (!p) return;
    p.t += dt;
    if (p.phase === 'toGate' && p.t >= HOP.toGate) { p.phase = p.grant ? 'toLeader' : 'refused'; p.t = 0; }
    else if (p.phase === 'toLeader' && p.t >= HOP.toLeader) { p.phase = 'fanOut'; p.t = 0; }
    else if (p.phase === 'fanOut' && p.t >= HOP.fanOut) { p.phase = 'atNodes'; p.t = 0; if (p.verdict) decide(s); }
  }

  function newSession(s) {
    var single = chipOf(s, s.cfg.single.role), from = s.cfg.initiator;
    var up = serving(s).filter(function (i) {
      var c = s.chips.filter(function (x) { return x.role === s.cfg.every && x.host === i; })[0];
      return s.hosts[i].status === 'up' && settled(s, c);
    });
    if (s.hosts[from].status !== 'up' || !up.length || !single || single.host < 0 ||
        s.hosts[single.host].status !== 'up' || !settled(s, single)) {
      s.counters.refused += 1;
      return;
    }
    var stock = up[s.rr++ % up.length], led = single.host;
    // want, have, book, booked: the `have` branch of the Order protocol
    var legs = [[from, stock], [stock, from], [stock, led], [led, from]]
      .filter(function (l) { return l[0] !== l[1]; });
    s.sessions.push({ stock: stock, single: led, legs: legs, leg: 0, elapsed: 0 });
  }

  function step(s, dt) {
    dt = Math.min(dt, MAX_DT);
    s.t += dt;

    // a single-holder role whose host has been given up on moves to the next host
    var single = chipOf(s, s.cfg.single.role);
    if (single && single.host >= 0) {
      var h = s.hosts[single.host];
      if (h.status === 'down' && s.t - h.since >= s.cfg.suspectS) {
        var next = rankSingle(s);
        if (next >= 0) { single.from = single.host; single.host = next; single.movedAt = s.t; }
      }
    }

    if (s.flow) {
      s.acc += dt * s.cfg.sessionsPerS;
      while (s.acc >= 1) { s.acc -= 1; newSession(s); }
    }
    for (var i = s.sessions.length - 1; i >= 0; i--) {
      var x = s.sessions[i];
      x.elapsed += dt;
      if (x.elapsed < s.cfg.legS) continue;
      x.elapsed = 0; x.leg += 1;
      if (x.leg >= x.legs.length) { s.counters.finished += 1; s.sessions.splice(i, 1); }
    }
    stepPatch(s, dt);
  }

  function advance(s, seconds) {
    var steps = Math.round(seconds / 0.05);
    for (var i = 0; i < steps; i++) step(s, 0.05);
  }

  // Where a chip is on its way from one place to another: 0 at the start, 1 once landed.
  function chipProgress(s, c) { return Math.max(0, Math.min(1, (s.t - c.movedAt) / CHIP_S)); }

  var api = { create: create, place: place, show: show, hide: hide, stop: stop, start: start,
    sendPatch: sendPatch, resolveNodes: resolveNodes, step: step, advance: advance,
    chipProgress: chipProgress, rankSingle: rankSingle, serving: serving, HOP: HOP };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.simTopology = api;
})(typeof window !== 'undefined' ? window : globalThis);

// chapters-authority.js: the figures of docs/deploy-authority.md, one registration per
// graphic. It uses the machinery of chapters.js (svgFigure, canvasFigure, registerSim):
// a card's `data-state` is absolute, and moving on to the NEXT card makes that card's
// event happen to the simulation already on screen.
//
//   reach     the program's modules as squares, grouped by what each can reach
//   topology  the lab's two pools: roles placed, sessions flowing, a host stopped, what
//             each pool may reach, the generated firewall, each node's policy
//   rollout   the same machines, and one patch that asks for more
(function (root) {
  'use strict';
  var ME = root.MarchExplainer, F = ME.figures, T = ME.simTopology;

  // ── what a program may touch ───────────────────────────────────────────────────
  // The width the squares are drawn at before the page scales them to the stage. A
  // phone gets the compact drawing at its own width. Otherwise it is whichever of a wide
  // drawing (680) and a tall one (430) can be scaled up further in a stage of this shape.
  ME.reachWidth = function (data, width, height) {
    if (width < 520) return width;
    if (!height) return 680;
    var best = 680, bestK = -1;
    [680, 430].forEach(function (w) {
      var size = ME.reachFrame(data, w), k = Math.min(width / size.w, height / size.h);
      if (k > bestK + 1e-9) { bestK = k; best = w; }
    });
    return best;
  };

  // The largest any card needs at this design width, so the drawing is one size throughout.
  ME.reachFrame = function (data, width) {
    var frame = { w: 0, h: 0 };
    F.REACH_STAGES.forEach(function (stage) {
      var size = ME.naturalSize([{ svg: F.reach(data.modules, { width: width, stage: stage, dep: data.dep, compact: width < 400 }) }]);
      frame.w = Math.max(frame.w, size.w); frame.h = Math.max(frame.h, size.h);
    });
    return frame;
  };

  ME.registerFigure('reach', function (host, data) {
    var current = null;
    var fig = ME.svgFigure(host, function (w, h) {
      return [{ id: 'reach', svg: F.reach(data.modules, { width: ME.reachWidth(data, w, h), stage: current, dep: data.dep, compact: w < 520 }) }];
    }, { top: true, frame: function (w, h) { return ME.reachFrame(data, ME.reachWidth(data, w, h)); } });
    return {
      setState: function (state) {
        if (state === current) return;
        if (F.REACH_STAGES.indexOf(state) < 0) throw new Error('unknown state ' + state);
        current = state;
        fig.draw();
      },
    };
  });

  // ── the topology, and the patch ────────────────────────────────────────────────
  ME.topologyConfig = function (data) {
    var t = data.topology, hosts = [];
    t.pools.forEach(function (p) {
      p.hosts.forEach(function (h) { hosts.push({ id: h.name, pool: p.name, labels: h.labels }); });
    });
    var starts = t.pools.filter(function (p) { return p.initiates.length; })[0];
    var serves = t.pools.filter(function (p) { return p.serves.length; })[0];
    var single = t.roles.filter(function (r) { return r.place && r.place.count === 1; })[0];
    var every = t.roles.filter(function (r) { return !r.place; })[0];
    var initiator = -1;
    hosts.forEach(function (h, i) { if (initiator < 0 && h.pool === starts.name) initiator = i; });
    return {
      seed: data.sim.seed, sessionsPerS: data.sim.sessions_per_s, legS: data.sim.leg_s,
      suspectS: data.sim.suspect_s,
      hosts: hosts, initiator: initiator, initiates: starts.initiates[0].split('.').pop(),
      serves: serves.name, every: every.role, single: { role: single.role, on: single.place.on },
      view: {
        pools: t.pools.map(function (p) { return { name: p.name, caps: p.caps, added: data.widening.added[p.name] || [] }; }),
        clusterPort: t.cluster_port, controlPort: t.control_port, grant: data.widening.grant_flags,
      },
    };
  };

  function holder(s) { return s.chips.filter(function (c) { return c.role === s.cfg.single.role; })[0].host; }
  function startAll(s) { s.hosts.forEach(function (h, i) { T.start(s, i); }); }

  // Each card: what happens when the reader arrives, and how long it takes to settle.
  var TOPOLOGY = [
    { name: 'hosts', settle: 0.6, enter: function () {} },
    { name: 'placed', settle: 2.4, enter: function (s) { T.place(s); } },
    { name: 'flow', settle: 4, enter: function (s) { s.flow = true; } },
    { name: 'stop', settle: 6, enter: function (s) { T.stop(s, holder(s)); } },
    { name: 'caps', settle: 2, enter: function (s) { startAll(s); T.show(s, 'caps'); } },
    { name: 'firewall', settle: 1.5, enter: function (s) { T.show(s, 'firewall'); } },
    { name: 'policy', settle: 1.5, enter: function (s) { T.hide(s, 'firewall'); T.show(s, 'policy'); } },
  ];
  var ROLLOUT = [
    { name: 'widen', settle: 1.5, enter: function (s) {
      T.place(s); T.advance(s, 2.4); s.flow = true; T.advance(s, 3);
      ['caps', 'policy', 'forge', 'widened'].forEach(function (f) { T.show(s, f); });
    } },
    { name: 'refused', settle: 2.4, enter: function (s) { T.sendPatch(s, { grant: false }); } },
    { name: 'granted', settle: 3.2, enter: function (s) { T.sendPatch(s, { grant: true }); } },
    { name: 'node', settle: 3.2, enter: function (s) {
      if (!s.patch || !s.patch.grant) T.sendPatch(s, { grant: true });
      T.resolveNodes(s, false);
    } },
    { name: 'admitted', settle: 3.6, enter: function (s) { T.sendPatch(s, { grant: true }); T.resolveNodes(s, true); } },
  ];

  function register(figure, cards) {
    var names = cards.map(function (c) { return c.name; });
    ME.registerSim(figure, {
      sim: T,
      build: function (state, data) {
        var k = names.indexOf(state);
        if (k < 0) throw new Error('unknown state ' + state);
        var s = T.create(ME.topologyConfig(data));
        for (var i = 0; i <= k; i++) { cards[i].enter(s); T.advance(s, cards[i].settle); }
        return s;
      },
      live: function (from, to, s) {
        var k = names.indexOf(to);
        if (k < 1 || names[k - 1] !== from) return false;
        cards[k].enter(s);
        return true;
      },
    });
  }
  register('topology', TOPOLOGY);
  register('rollout', ROLLOUT);
  ME.TOPOLOGY_STATES = TOPOLOGY.map(function (c) { return c.name; });
  ME.ROLLOUT_STATES = ROLLOUT.map(function (c) { return c.name; });

  var PATCH = { toGate: 'leaving forge', refused: 'stopped by forge', toLeader: 'on its way', fanOut: 'on its way',
    atNodes: 'at the nodes', nodeRefused: 'refused by the nodes', activated: 'running' };
  ME.patchLabel = function (s) { return s.patch ? PATCH[s.patch.phase] : 'not sent'; };

  ME.registerFigure('topology', function (host, data) {
    return ME.canvasFigure(host, {
      figure: 'topology', data: data, settle: 6, draw: ME.draw.topology, design: ME.draw.topologyDesign,
      counters: function (s) {
        var c = s.counters;
        return [['Finished', c.finished], ['In flight', s.sessions.length], ['Cancelled', c.cancelled, c.cancelled > 0],
          ['Refused', c.refused, c.refused > 0]];
      },
    });
  });

  ME.registerFigure('rollout', function (host, data) {
    return ME.canvasFigure(host, {
      figure: 'rollout', data: data, settle: 4, draw: ME.draw.topology, design: ME.draw.topologyDesign,
      counters: function (s) {
        var bad = !!s.patch && (s.patch.phase === 'refused' || s.patch.phase === 'nodeRefused');
        var moved = s.hosts.filter(function (h) { return h.code === 2; }).length;
        return [['Patch', ME.patchLabel(s), bad], ['On new code', moved + ' of ' + s.hosts.length + ' machines']];
      },
    });
  });
})(typeof window !== 'undefined' ? window : globalThis);

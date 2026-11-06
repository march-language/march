// draw-authority.js: the canvas renderer for the topology simulation of
// docs/deploy-authority.md.
//
// topology(ctx, s, size, colors): `s` is a sim-topology.js state whose `cfg.view` says
// what the page knows about the pools ({ pools: [{ name, caps, added }], clusterPort,
// controlPort, grant }). It only reads the state. Everything is drawn with rectangles,
// straight segments, circles and text, so the same code renders the static fallback
// image (scripts/render-explainer-fallbacks.js replays it into SVG).
//
// What is in the drawing: one box per machine inside its pool, one chip per role a
// machine holds, one dot per message in the air, one line per pair of machines the
// generated firewall opens the cluster port between, the capabilities each pool may
// reach, and the patch on its way from the developer's machine.
(function (root) {
  'use strict';
  var sim = (typeof require === 'function' && typeof module !== 'undefined')
    ? require('./sim-topology.js') : root.MarchExplainer.simTopology;

  function font(ctx, px, weight, mono) {
    ctx.font = (weight || '') + ' ' + px + 'px ' + (mono ? '"JetBrains Mono", ui-monospace, monospace' : 'system-ui, -apple-system, sans-serif');
  }
  function ease(u) { return u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2; }
  function fade(s, flag, over) {
    if (s.show[flag] === undefined) return 0;
    return Math.max(0, Math.min(1, (s.t - s.show[flag]) / (over || 0.5)));
  }

  // The size the drawing is designed at, for a stage of this shape. Both are wider than
  // tall, as a pinned stage is; the phone's is the same picture drawn denser.
  var WIDE = { width: 560, height: 470, poolY: 78, poolH: 152, first: 128, gap: 18, padX: 12, hostGap: 12,
    hostY: 96, hostH: 118, capsY: 318, forge: { w: 140, h: 52, y: 408 }, gateGap: 70, file: { w: 118, h: 24 },
    big: 13, small: 11, nameY: 18, tagY: 33, chipY: 46, chipPitch: 25, chipH: 20, legendY: 304 };
  var PHONE = { width: 380, height: 304, poolY: 46, poolH: 110, first: 92, gap: 8, padX: 6, hostGap: 6,
    hostY: 56, hostH: 92, capsY: 192, forge: { w: 112, h: 40, y: 258 }, gateGap: 52, file: { w: 96, h: 20 },
    big: 11, small: 9, nameY: 14, tagY: 26, chipY: 34, chipPitch: 19, chipH: 16, legendY: 186 };
  function designSize(size) { return size.width < 520 ? PHONE : WIDE; }

  // Where everything goes: the pools side by side, the first one narrow (it has one
  // machine), each pool's capabilities under it, the developer's machine bottom right.
  function layout(s, W) {
    var D = W < 520 ? PHONE : WIDE, L = { narrow: D === PHONE, D: D, hosts: [], pools: [], caps: [] };
    var names = [];
    s.hosts.forEach(function (h) { if (names.indexOf(h.pool) < 0) names.push(h.pool); });
    var x = 0;
    names.forEach(function (name, k) {
      var idx = [];
      s.hosts.forEach(function (h, i) { if (h.pool === name) idx.push(i); });
      var bw = k === 0 ? D.first : (W - x - (names.length - 1 - k) * D.gap) / (names.length - k);
      var hw = (bw - 2 * D.padX - (idx.length - 1) * D.hostGap) / idx.length;
      idx.forEach(function (i, n) { L.hosts[i] = { x: x + D.padX + n * (hw + D.hostGap), y: D.hostY, w: hw, h: D.hostH }; });
      L.caps.push({ x: x + 2, y: D.capsY, w: bw - 4, per: k === 0 ? 1 : 3 });
      L.pools.push({ name: name, box: { x: x, y: D.poolY, w: bw, h: D.poolH } });
      x += bw + D.gap;
    });
    L.file = { x: 0, y: 0, w: D.file.w, h: D.file.h };
    L.forge = { x: W - D.forge.w, y: D.forge.y, w: D.forge.w, h: D.forge.h };
    L.gate = { x: L.forge.x - D.gateGap, y: L.forge.y - 5, h: L.forge.h + 10 };
    return L;
  }

  function top(b) { return { x: b.x + b.w / 2, y: b.y }; }
  function bottom(b) { return { x: b.x + b.w / 2, y: b.y + b.h }; }
  function quad(a, c, b, u) {
    return { x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * b.x,
      y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * b.y };
  }
  function curve(ctx, a, c, b) {
    ctx.beginPath(); ctx.moveTo(a.x, a.y);
    for (var k = 1; k <= 14; k++) { var p = quad(a, c, b, k / 14); ctx.lineTo(p.x, p.y); }
    ctx.stroke();
  }

  // The path of a message between two hosts: over the top when they share a row, straight
  // across the gap when they do not.
  function messagePath(L, i, j) {
    var a = L.hosts[i], b = L.hosts[j];
    if (Math.abs(a.y - b.y) < 1) {
      var p = top(a), q = top(b);
      return [p, { x: (p.x + q.x) / 2, y: p.y - Math.min(L.narrow ? 40 : 62, (L.narrow ? 12 : 18) + Math.abs(p.x - q.x) * 0.16) }, q];
    }
    var up = a.y < b.y ? a : b, down = a.y < b.y ? b : a, from = bottom(up), to = top(down);
    var ends = a.y < b.y ? [from, to] : [to, from];
    return [ends[0], { x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 }, ends[1]];
  }

  // The path of a firewall link: under the row for two hosts that share one.
  function linkPath(L, i, j) {
    var a = L.hosts[i], b = L.hosts[j];
    if (Math.abs(a.y - b.y) < 1) {
      var p = bottom(a), q = bottom(b);
      // the control point is twice as deep as the curve gets: a far pair dips furthest
      return [p, { x: (p.x + q.x) / 2, y: p.y + Math.min(L.narrow ? 60 : 160, (L.narrow ? 16 : 40) + Math.abs(p.x - q.x) * (L.narrow ? 0.16 : 0.3)) }, q];
    }
    return messagePath(L, i, j);
  }

  function chipSlot(L, s, c) {
    var b = L.hosts[c.host], k = 0;
    for (var i = 0; i < s.chips.length; i++) {
      if (s.chips[i] === c) break;
      if (s.chips[i].host === c.host) k += 1;
    }
    var pad = L.narrow ? 5 : 8;
    return { x: b.x + pad, y: b.y + L.D.chipY + k * L.D.chipPitch, w: b.w - 2 * pad, h: L.D.chipH };
  }

  function pill(ctx, x, y, w, h, label, color, px) {
    ctx.strokeStyle = color; ctx.lineWidth = 1;
    ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
    font(ctx, px, '600'); ctx.fillStyle = color; ctx.textAlign = 'center';
    ctx.fillText(label, x + w / 2, y + h / 2 + px * 0.36);
    ctx.textAlign = 'left';
  }

  // `widened`: how far the new capability has faded in (0: not asked for yet).
  // `settled`: the patch is running, so the capability is one the pool now has.
  function capsList(ctx, pool, at, alpha, widened, settled, c, px) {
    var lh = px + 4, x = at.x, y = at.y;
    ctx.globalAlpha = alpha;
    font(ctx, px); ctx.fillStyle = c.dim;
    ctx.fillText(at.w < 110 ? 'may reach' : 'pool ' + pool.name + ' may reach', x, y + px);
    var caps = pool.caps.map(function (n) { return { n: n, hot: false }; });
    if (settled) (pool.added || []).forEach(function (n) { caps.push({ n: n, hot: false }); });
    else if (widened > 0) (pool.added || []).forEach(function (n) { caps.push({ n: '+ ' + n, hot: true }); });
    var colW = at.w / at.per;
    caps.forEach(function (cap, i) {
      font(ctx, px, cap.hot ? '600' : '', true);
      ctx.fillStyle = cap.hot ? c.accent : c.ink;
      ctx.globalAlpha = cap.hot ? alpha * widened : alpha;
      ctx.fillText(cap.n, x + (i % at.per) * colW, y + px + lh * (1 + Math.floor(i / at.per)));
    });
    ctx.globalAlpha = 1;
  }

  function topology(ctx, s, size, c) {
    var W = size.width, H = size.height, L = layout(s, W), narrow = L.narrow, view = s.cfg.view || { pools: [] };
    var D = L.D, small = D.small, big = D.big;
    ctx.clearRect(0, 0, W, H);
    ctx.lineWidth = 1; ctx.textAlign = 'left';

    // the topology file the roles come from
    ctx.strokeStyle = c.dim; ctx.strokeRect(L.file.x + 0.5, L.file.y + 0.5, L.file.w - 1, L.file.h - 1);
    font(ctx, small, '', true); ctx.fillStyle = c.ink;
    ctx.fillText('topology.toml', L.file.x + 6, L.file.y + L.file.h - 7);

    // pools
    L.pools.forEach(function (p) {
      ctx.strokeStyle = c.dim; ctx.setLineDash([5, 4]);
      ctx.strokeRect(p.box.x + 0.5, p.box.y + 0.5, p.box.w - 1, p.box.h - 1);
      ctx.setLineDash([]);
      font(ctx, small); ctx.fillStyle = c.dim;
      ctx.fillText('pool ' + p.name, p.box.x + 4, p.box.y - 6);
    });

    // the firewall: the cluster port between every pair of machines, the control port
    // between control candidates
    var fw = fade(s, 'firewall');
    if (fw > 0) {
      ctx.globalAlpha = 0.55 * fw; ctx.strokeStyle = c.ink;
      for (var i = 0; i < s.hosts.length; i++) {
        for (var j = i + 1; j < s.hosts.length; j++) {
          var lp = linkPath(L, i, j);
          curve(ctx, lp[0], lp[1], lp[2]);
          var both = s.hosts[i].labels.indexOf('control') >= 0 && s.hosts[j].labels.indexOf('control') >= 0;
          if (both) {
            ctx.setLineDash([2, 3]); ctx.strokeStyle = c.accent;
            ctx.globalAlpha = fw;
            curve(ctx, { x: lp[0].x + 9, y: lp[0].y }, { x: lp[1].x, y: lp[1].y - 18 }, { x: lp[2].x - 9, y: lp[2].y });
            ctx.globalAlpha = 0.55 * fw;
            ctx.setLineDash([]); ctx.strokeStyle = c.ink;
          }
        }
      }
      ctx.globalAlpha = fw;
      font(ctx, small); ctx.fillStyle = c.dim;
      var lx = L.pools[L.pools.length - 1].box.x + 4;
      ctx.fillText('solid: cluster port ' + view.clusterPort + ', every pair', lx, D.legendY);
      ctx.fillStyle = c.accent;
      ctx.fillText('dotted: control port ' + view.controlPort, lx + (narrow ? 150 : 230), D.legendY);
      ctx.globalAlpha = 1;
    }

    // machines
    var policy = fade(s, 'policy'), refusing = s.patch && s.patch.phase === 'nodeRefused';
    s.hosts.forEach(function (h, i) {
      var b = L.hosts[i], down = h.status !== 'up';
      ctx.strokeStyle = down ? c.accent : c.ink;
      ctx.lineWidth = h.code === 2 ? 2.5 : 1;
      ctx.setLineDash(down ? [4, 3] : []);
      ctx.strokeRect(b.x + 0.5, b.y + 0.5, b.w - 1, b.h - 1);
      ctx.setLineDash([]); ctx.lineWidth = 1;
      font(ctx, big, '600'); ctx.fillStyle = down ? c.accent : c.ink;
      ctx.fillText(h.id, b.x + (narrow ? 5 : 8), b.y + D.nameY);
      font(ctx, small); ctx.fillStyle = down ? c.accent : c.dim;
      var tag = down ? 'stopped' : h.labels.join(', ');
      if (tag) ctx.fillText(tag, b.x + (narrow ? 5 : 8), b.y + D.tagY);
      if (policy > 0 && !down) {
        // the node's own gate: its policy file
        ctx.globalAlpha = policy;
        ctx.fillStyle = refusing ? c.accent : c.ink;
        ctx.fillRect(b.x, b.y + b.h - 3, b.w, 3);
        font(ctx, small); ctx.fillStyle = refusing ? c.accent : c.dim;
        ctx.fillText(refusing ? (narrow ? 'refused' : 'refused by policy') : h.code === 2 ? 'new code' : 'policy', b.x + (narrow ? 5 : 8), b.y + b.h - 7);
        ctx.globalAlpha = 1;
      }
    });

    // role chips, in flight or landed
    s.chips.forEach(function (chip) {
      if (chip.host < 0) return;
      var u = sim.chipProgress(s, chip);
      if (u <= 0 && chip.from === -1) return;                       // not yet out of the file
      var to = chipSlot(L, s, chip), from = chip.from === -1 ? { x: L.file.x + 6, y: L.file.y + 2, w: to.w, h: to.h }
        : chip.from === chip.host ? to : chipSlot(L, s, { role: chip.role, host: chip.from });
      var e = ease(u), lift = Math.sin(Math.PI * u) * (chip.from === -1 ? 26 : 44);
      var x = from.x + (to.x - from.x) * e, y = from.y + (to.y - from.y) * e - lift;
      var single = chip.role === s.cfg.single.role;
      var dim = s.hosts[chip.host].status !== 'up' && u >= 1;
      ctx.globalAlpha = dim ? 0.3 : 1;
      pill(ctx, x, y, to.w, to.h, chip.role, single ? c.accent : c.ink, small);
      ctx.globalAlpha = 1;
    });

    // messages in the air
    s.sessions.forEach(function (x) {
      var leg = x.legs[x.leg];
      if (!leg) return;
      var path = messagePath(L, leg[0], leg[1]), p = quad(path[0], path[1], path[2], Math.min(1, x.elapsed / s.cfg.legS));
      ctx.fillStyle = c.ink;
      ctx.beginPath(); ctx.arc(p.x, p.y, narrow ? 2.2 : 2.8, 0, Math.PI * 2); ctx.fill();
    });

    // what each pool may reach
    var caps = fade(s, 'caps'), widened = fade(s, 'widened');
    if (caps > 0) {
      var settled = !!(s.patch && s.patch.phase === 'activated');
      view.pools.forEach(function (pool, k) { capsList(ctx, pool, L.caps[k], caps, widened, settled, c, small); });
    }

    // the developer's machine, its gate, and the patch
    var forge = fade(s, 'forge');
    if (forge > 0) {
      var f = L.forge, g = L.gate, p = s.patch;
      ctx.globalAlpha = forge;
      ctx.strokeStyle = c.ink; ctx.strokeRect(f.x + 0.5, f.y + 0.5, f.w - 1, f.h - 1);
      font(ctx, big, '600'); ctx.fillStyle = c.ink; ctx.fillText('forge', f.x + 8, f.y + (narrow ? 15 : 19));
      font(ctx, small); ctx.fillStyle = c.dim; ctx.fillText('your machine', f.x + 8, f.y + (narrow ? 29 : 35));
      var shut = !p || !p.grant || p.phase === 'toGate';
      var stopped = p && p.phase === 'refused';
      ctx.fillStyle = stopped ? c.accent : c.ink;
      if (shut) ctx.fillRect(g.x - 1.5, g.y, 3, g.h);
      else { ctx.fillRect(g.x - 1.5, g.y, 3, 10); ctx.fillRect(g.x - 1.5, g.y + g.h - 10, 3, 10); }
      font(ctx, small); ctx.fillStyle = stopped ? c.accent : c.dim; ctx.textAlign = 'right';
      ctx.fillText(stopped ? 'needs ' + view.grant : shut ? 'widening gate' : 'granted by name', g.x - 8, g.y + g.h / 2 + 4);
      ctx.textAlign = 'left';
      ctx.globalAlpha = 1;

      if (p) {
        var home = { x: f.x - 4, y: f.y + f.h / 2 }, gate = { x: g.x + 8, y: f.y + f.h / 2 };
        var pts = [];
        if (p.phase === 'toGate') pts.push(mix(home, gate, ease(Math.min(1, p.t / sim.HOP.toGate))));
        else if (p.phase === 'refused') {
          var back = Math.min(1, p.t / sim.HOP.bounce);
          pts.push(mix(gate, mix(gate, home, 0.55), Math.sin(Math.PI * Math.min(1, back) / 2)));
        } else if (p.phase === 'toLeader') {
          pts.push(mix({ x: g.x - 8, y: gate.y }, bottom(L.hosts[s.leader]), ease(Math.min(1, p.t / sim.HOP.toLeader))));
        } else {
          var u = p.phase === 'fanOut' ? ease(Math.min(1, p.t / sim.HOP.fanOut)) : 1;
          s.hosts.forEach(function (h, i) {
            if (h.status !== 'up') return;
            var end = bottom(L.hosts[i]);
            if (p.phase === 'nodeRefused') end = { x: end.x, y: end.y + 12 + 8 * Math.abs(Math.sin(Math.min(1, p.t / 0.6) * Math.PI)) };
            else if (p.phase === 'atNodes') end = { x: end.x, y: end.y + 10 };
            if (p.phase === 'activated') return;
            pts.push(mix(bottom(L.hosts[s.leader]), end, u));
          });
        }
        var bad = p.phase === 'refused' || p.phase === 'nodeRefused';
        pts.forEach(function (pt) {
          ctx.fillStyle = bad ? c.accent : c.ink;
          ctx.fillRect(pt.x - 5, pt.y - 5, 10, 10);
        });
      }
    }
  }

  function mix(a, b, u) { return { x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u }; }

  var api = { topology: topology, topologyDesign: designSize, topologyLayout: layout };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.draw = Object.assign(root.MarchExplainer.draw || {}, api);
})(typeof window !== 'undefined' ? window : globalThis);

// draw.js: canvas renderers for the simulations of docs/protocol-to-cluster.md.
//
// Each renderer takes a 2D context, a simulation state (sim-cluster.js, sim-mailbox.js,
// sim-release.js), the size to draw at in CSS pixels, and three colours (ink, dim,
// accent) the caller reads from the page's `mx-` custom properties. They only read the
// state. Quantities are in the drawing: one square per session slot, one dot per session
// in transit.
(function (root) {
  'use strict';

  function font(ctx, px, weight) { ctx.font = (weight || '') + ' ' + px + 'px system-ui, -apple-system, sans-serif'; }

  function hatch(ctx, x, y, w, h, color) {
    ctx.save();
    ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip();
    ctx.strokeStyle = color; ctx.globalAlpha = 0.35; ctx.lineWidth = 1;
    ctx.beginPath();
    for (var k = -h; k < w; k += 8) { ctx.moveTo(x + k, y); ctx.lineTo(x + k + h, y + h); }
    ctx.stroke();
    ctx.restore();
  }

  // A row-major grid of slots: filled when held, outlined when free.
  function slotGrid(ctx, slots, x, y, perRow, pitch, c, live) {
    var size = pitch - 2;
    for (var i = 0; i < slots.length; i++) {
      var sx = x + (i % perRow) * pitch, sy = y + Math.floor(i / perRow) * pitch;
      if (slots[i] !== null) { ctx.fillStyle = c.ink; ctx.fillRect(sx, sy, size, size); }
      else { ctx.strokeStyle = c.dim; ctx.globalAlpha = live ? 0.6 : 0.25; ctx.strokeRect(sx + 0.5, sy + 0.5, size - 1, size - 1); ctx.globalAlpha = 1; }
    }
    return Math.ceil(slots.length / perRow) * pitch;
  }

  function hostTag(s, h, i) {
    var role = s.ledger.host === i ? 'Stock + Ledger' : 'Stock';
    if (h.status === 'up' && h.silent) return 'not answering';
    if (h.status === 'up') return role + ', incarnation ' + h.incarnation;
    if (h.status === 'suspect') return 'suspected, silent ' + Math.floor(s.t - h.since) + ' s';
    if (h.status === 'restarting') return 'restarting';
    return 'dead';
  }

  // The cluster: the calling node on the left, the serving hosts on the right, each
  // with a square per Stock slot (and per Ledger slot, on the host that holds the Ledger).
  function cluster(ctx, s, size, c) {
    var W = size.width, H = size.height, narrow = W < 560;
    ctx.clearRect(0, 0, W, H);
    var n = s.hosts.length, gap = narrow ? 6 : 10;
    var leftW = narrow ? 54 : 96, hostX = narrow ? leftW + 46 : Math.max(leftW + 90, W * 0.3);
    var hostW = W - hostX - 2, hostH = (H - 2 - gap * (n - 1)) / n;
    // Sixteen slots to a row. The pitch is the largest that fits the box both ways: a
    // host holding the Ledger needs its Stock rows and its Ledger rows under its name.
    var perRow = 16, header = narrow ? 19 : 26;
    var rows = Math.ceil(s.cfg.stockCapacity / perRow) + Math.ceil(s.cfg.ledgerCapacity / perRow) + 0.4;
    var pitch = Math.max(4, Math.min(30, Math.floor(Math.min((hostW - 16) / perRow, (hostH - header - 6) / rows))));
    var ledgerPerRow = perRow, stockPerRow = perRow;

    // the caller
    var cy = H / 2;
    ctx.strokeStyle = c.ink; ctx.lineWidth = 1;
    ctx.strokeRect(0.5, cy - 24.5, leftW - 1, 49);
    font(ctx, narrow ? 11 : 13, '600'); ctx.fillStyle = c.ink; ctx.textAlign = 'left';
    ctx.fillText(s.cfg.ingress || 'caller', 8, cy - 4);
    font(ctx, narrow ? 10 : 12); ctx.fillStyle = c.dim;
    ctx.fillText('starts Shop', 8, cy + 12);

    var entry = [];
    s.hosts.forEach(function (h, i) {
      var y = 1 + i * (hostH + gap), bad = h.status === 'dead' || h.status === 'suspect' || h.silent;
      entry.push({ x: hostX - 6, y: y + hostH / 2 });
      ctx.strokeStyle = bad ? c.accent : h.status === 'restarting' ? c.dim : c.ink;
      ctx.setLineDash(h.status === 'up' && !h.silent ? [] : [4, 3]);
      ctx.strokeRect(hostX + 0.5, y + 0.5, hostW - 1, hostH - 1);
      ctx.setLineDash([]);
      if (h.status === 'dead') hatch(ctx, hostX, y, hostW, hostH, c.accent);

      font(ctx, narrow ? 11 : 13, '600'); ctx.fillStyle = bad ? c.accent : c.ink;
      ctx.fillText(h.id, hostX + 8, y + (narrow ? 13 : 17));
      var nameW = ctx.measureText(h.id).width;
      font(ctx, narrow ? 10 : 12); ctx.fillStyle = bad ? c.accent : c.dim;
      ctx.fillText(hostTag(s, h, i), hostX + 16 + nameW, y + (narrow ? 13 : 17));

      var gy = y + header;
      gy += slotGrid(ctx, h.stock, hostX + 8, gy, stockPerRow, pitch, c, h.status === 'up') + 3;
      if (s.ledger.host === i) slotGrid(ctx, s.ledger.slots, hostX + 8, gy, ledgerPerRow, pitch, c, true);
    });

    // sessions on their way out, bouncing between hosts, or on their way back
    var from = { x: leftW + 4, y: cy };
    s.sessions.forEach(function (sess) {
      if (sess.phase === 'serve') return;
      var u = Math.min(1, sess.elapsed / sess.dur), a, b, color = c.ink, r = narrow ? 1.8 : 2.4;
      if (sess.phase === 'out') { a = sess.from === null ? from : entry[sess.from]; b = entry[sess.host]; }
      else { a = entry[sess.host]; b = from; color = c.dim; r -= 0.6; }
      ctx.fillStyle = color;
      ctx.beginPath(); ctx.arc(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, r, 0, Math.PI * 2); ctx.fill();
    });
  }

  // One actor: its mailbox on the left, flowing right, and the actor itself with its
  // code version, its state, and a square per session parked inside it.
  function mailbox(ctx, s, size, c) {
    var W = size.width, H = size.height, narrow = W < 560;
    ctx.clearRect(0, 0, W, H);
    var boxW = narrow ? 150 : 230, boxH = Math.min(H - 2, narrow ? 150 : 190);
    var bx = W - boxW - 1, by = Math.max(1, (H - boxH) / 2), laneY = by + boxH / 2;
    var down = s.status !== 'up', sq = narrow ? 12 : 16, pitch = sq + (narrow ? 5 : 7);

    // the mailbox lane
    font(ctx, narrow ? 11 : 13); ctx.fillStyle = c.dim; ctx.textAlign = 'left';
    ctx.fillText('mailbox', 2, laneY - sq - 8);
    ctx.strokeStyle = c.dim; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(2, laneY + sq / 2 + 6.5); ctx.lineTo(bx - 8, laneY + sq / 2 + 6.5); ctx.stroke();
    var head = bx - 14 - sq;
    s.queue.forEach(function (m, i) {
      var x = head - i * pitch;
      if (x < 2) return;
      if (m.kind === 'marker') {
        ctx.strokeStyle = c.accent; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(x + sq / 2, laneY - sq - 4); ctx.lineTo(x + sq / 2, laneY + sq / 2 + 4); ctx.stroke();
        ctx.lineWidth = 1; ctx.fillStyle = c.accent; ctx.textAlign = 'center';
        ctx.fillText('deploy', Math.max(22, x + sq / 2), laneY - sq - 10); ctx.textAlign = 'left';
      } else if (m.epoch === 1) { ctx.fillStyle = c.ink; ctx.fillRect(x, laneY - sq / 2, sq, sq); }
      else { ctx.strokeStyle = c.ink; ctx.strokeRect(x + 0.5, laneY - sq / 2 + 0.5, sq - 1, sq - 1); }
    });

    // the actor
    ctx.strokeStyle = down || s.migrating ? c.accent : c.ink;
    ctx.setLineDash(down ? [4, 3] : []);
    ctx.strokeRect(bx + 0.5, by + 0.5, boxW - 1, boxH - 1);
    ctx.setLineDash([]);
    if (s.status === 'crashed') hatch(ctx, bx, by, boxW, boxH, c.accent);
    var tx = bx + 12, ty = by + (narrow ? 20 : 26), lh = narrow ? 17 : 21;
    font(ctx, narrow ? 12 : 14, '600'); ctx.fillStyle = down ? c.accent : c.ink;
    ctx.fillText('Ledger actor', tx, ty);
    font(ctx, narrow ? 11 : 13); ctx.fillStyle = down || s.migrating ? c.accent : c.dim;
    ctx.fillText(s.status === 'crashed' ? 'crashed' : s.migrating ? 'migrating its state'
      : s.held ? 'holding sessions: old code' : 'code version ' + s.version, tx, ty + lh);
    ctx.fillStyle = c.ink;
    ctx.fillText('total: ' + s.total, tx, ty + 2 * lh + 4);
    if (s.restarts > 0 && !down) { ctx.fillStyle = c.dim; ctx.fillText('started again from 0', tx, ty + 3 * lh + 4); }

    // the sessions parked inside it; the one being served is drawn in the accent
    var cap = s.cfg.parked || 0, p = narrow ? 9 : 12, perRow = Math.max(1, Math.floor((boxW - 24) / p));
    var py = by + boxH - 10 - Math.ceil(cap / perRow) * p;
    if (cap) {
      ctx.fillStyle = c.dim;
      ctx.fillText('sessions parked: ' + s.parked, tx, py - 6);
      for (var i = 0; i < cap; i++) {
        var x = tx + (i % perRow) * p, y = py + Math.floor(i / perRow) * p;
        if (i < s.parked) { ctx.fillStyle = i === s.serving ? c.accent : c.ink; ctx.fillRect(x, y, p - 3, p - 3); }
        else { ctx.strokeStyle = c.dim; ctx.globalAlpha = 0.4; ctx.strokeRect(x + 0.5, y + 0.5, p - 4, p - 4); ctx.globalAlpha = 1; }
      }
    }
  }

  // A release rolling out: the developer's machine, the calling node, and the hosts, each
  // labelled with the code it runs. `packet` is simRelease.packet.
  function release(ctx, s, size, c, packet) {
    var W = size.width, H = size.height, narrow = W < 560;
    ctx.clearRect(0, 0, W, H);
    var n = s.hosts.length, gap = narrow ? 6 : 12;
    var leftW = narrow ? 62 : 104, hostW = narrow ? Math.min(190, W - leftW - 50) : Math.min(260, W * 0.4);
    var hostX = W - hostW - 1, hostH = Math.min(narrow ? 50 : 64, (H - 2 - gap * (n - 1)) / n);
    var top = Math.max(1, (H - (n * hostH + (n - 1) * gap)) / 2);
    var small = narrow ? 10 : 12, big = narrow ? 11 : 13;

    function box(x, y, w, h, title, sub, color) {
      ctx.strokeStyle = color; ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
      font(ctx, big, '600'); ctx.fillStyle = color === c.dim ? c.ink : color; ctx.textAlign = 'left';
      ctx.fillText(title, x + 8, y + (narrow ? 15 : 20));
      font(ctx, small); ctx.fillStyle = color === c.ink ? c.dim : color;
      ctx.fillText(sub, x + 8, y + (narrow ? 29 : 38));
    }

    var caller = { x: 0, y: top + 4, w: leftW, h: 46 }, forge = { x: 0, y: H - 47, w: leftW, h: 46 };
    ctx.lineWidth = 1;
    box(caller.x, caller.y, caller.w, caller.h, s.cfg.ingress || 'caller', 'starts calls', c.ink);
    box(forge.x, forge.y, forge.w, forge.h, 'forge', 'your machine', c.dim);

    var anchor = [];
    s.hosts.forEach(function (h, i) {
      var y = top + i * (hostH + gap), halted = s.phase === 'halted' && i === s.canaryHost;
      anchor.push({ x: hostX - 6, y: y + hostH / 2, right: hostX + hostW - 10, top: y, bottom: y + hostH });
      ctx.lineWidth = h.version === 2 ? 2.5 : 1;
      var title = h.id + (i === s.cfg.leader ? ' · leader' : '');
      box(hostX, y, hostW, hostH, title, halted ? 'failed its gate' : h.version === 2 ? 'new code' : 'old code',
        halted ? c.accent : h.version === 2 ? c.ink : c.dim);
      ctx.lineWidth = 1;
      if (i === s.canaryHost && (s.phase === 'gate' || s.phase === 'halted')) {
        var u = s.phase === 'halted' ? 1 : Math.min(1, s.phaseT / s.cfg.windowS);
        ctx.fillStyle = s.phase === 'halted' ? c.accent : c.ink;
        ctx.fillRect(hostX, y + hostH - 3, hostW * u, 3);
      }
    });

    var from = { x: leftW + 4, y: caller.y + caller.h / 2 };
    s.calls.forEach(function (call) {
      if (call.phase === 'serve') return;
      var u = Math.min(1, call.elapsed / call.dur), a = from, b = anchor[call.host], out = call.phase === 'out';
      if (!out) { a = anchor[call.host]; b = from; }
      ctx.fillStyle = out ? c.dim : call.version === 2 ? c.ink : c.dim;
      ctx.beginPath();
      ctx.arc(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u + (out ? -3 : 4), out ? 1.5 : call.version === 2 ? 3 : 2, 0, Math.PI * 2);
      ctx.fill();
    });

    if (packet) {
      var fromPt = packet.from === 'forge' ? { x: leftW + 2, y: forge.y + forge.h / 2 }
        : { x: anchor[packet.from].right, y: packet.to > packet.from ? anchor[packet.from].bottom : anchor[packet.from].top };
      var toPt = packet.from === 'forge' ? { x: anchor[packet.to].x, y: anchor[packet.to].y + 12 }
        : { x: anchor[packet.to].right, y: packet.to > packet.from ? anchor[packet.to].top : anchor[packet.to].bottom };
      var pu = Math.min(1, packet.u);
      ctx.fillStyle = c.ink;
      ctx.fillRect(fromPt.x + (toPt.x - fromPt.x) * pu - 4, fromPt.y + (toPt.y - fromPt.y) * pu - 4, 8, 8);
    }
  }

  var api = { cluster: cluster, mailbox: mailbox, release: release };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.draw = Object.assign(root.MarchExplainer.draw || {}, api);
})(typeof window !== 'undefined' ? window : globalThis);

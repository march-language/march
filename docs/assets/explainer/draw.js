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
    if (h.status === 'up') return role + ', incarnation ' + h.incarnation;
    if (h.status === 'suspect') return 'silent ' + Math.floor(s.t - h.since) + ' s';
    if (h.status === 'restarting') return 'restarting';
    return h.silent ? 'dead to the cluster; its sessions still wait' : 'dead';
  }

  // The cluster: the calling node on the left, the serving hosts on the right, each
  // with a square per Stock slot (and per Ledger slot, on the host that holds the Ledger).
  function cluster(ctx, s, size, c) {
    var W = size.width, H = size.height, narrow = W < 560;
    ctx.clearRect(0, 0, W, H);
    var n = s.hosts.length, gap = narrow ? 6 : 10;
    var leftW = narrow ? 54 : 96, hostX = narrow ? leftW + 46 : Math.max(leftW + 120, W * 0.42);
    var hostW = W - hostX - 2, hostH = (H - 2 - gap * (n - 1)) / n;
    // Sixteen slots to a row. The pitch is the largest that fits the box both ways: a
    // host holding the Ledger needs its Stock rows and its Ledger rows under its name.
    var perRow = 16, header = narrow ? 19 : 26;
    var rows = Math.ceil(s.cfg.stockCapacity / perRow) + Math.ceil(s.cfg.ledgerCapacity / perRow) + 0.4;
    var pitch = Math.max(4, Math.min(20, Math.floor(Math.min((hostW - 16) / perRow, (hostH - header - 6) / rows))));
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
      var y = 1 + i * (hostH + gap), bad = h.status === 'dead' || h.status === 'suspect';
      entry.push({ x: hostX - 6, y: y + hostH / 2 });
      ctx.strokeStyle = bad ? c.accent : h.status === 'restarting' ? c.dim : c.ink;
      ctx.setLineDash(h.status === 'up' ? [] : [4, 3]);
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

  var api = { cluster: cluster };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.draw = Object.assign(root.MarchExplainer.draw || {}, api);
})(typeof window !== 'undefined' ? window : globalThis);

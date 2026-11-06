// draw-ownership.js: the canvas renderer for the heap simulation of docs/one-owner.md.
//
// heap(ctx, s, size, colors): `s` is a sim-heap.js state whose `cfg.view` says what the
// page knows ({ holder, second, vault, notes: { mode: line } }). It only reads the
// state. Everything is drawn with rectangles, straight segments, filled circles and
// text, so the same code renders the static fallback image
// (scripts/render-explainer-fallbacks.js replays it into SVG).
//
// What is in the drawing: one rounded box per heap cell with its reference count, laid
// out as the tree; the holders of the tree (the binding `t`, a second use, or a Vault)
// with an arrow to the root; a cursor for each `inc_leaves` walking the cells it visits,
// which flash as they are rewritten; the copy tree growing beside (or, on a phone,
// below) the original when the tree is shared; and a lane behind each half when the two
// halves are walked by two tasks.
(function (root) {
  'use strict';
  var sim = (typeof require === 'function' && typeof module !== 'undefined')
    ? require('./sim-heap.js') : root.MarchExplainer.simHeap;

  function font(ctx, px, weight, mono) {
    ctx.font = (weight || '') + ' ' + px + 'px ' + (mono ? '"JetBrains Mono", ui-monospace, monospace' : 'system-ui, -apple-system, sans-serif');
  }
  function ease(u) { return u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2; }
  function mix(a, b, u) { return { x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u }; }
  function centre(b) { return { x: b.x + b.w / 2, y: b.y + b.h / 2 }; }

  // The size the drawing is designed at, for a stage of this shape. Wide: the copy tree
  // grows beside the original. Phone: the same tree drawn denser, the copy below it.
  var WIDE = { width: 560, height: 340, treeX: 8, treeW: 264, rowY: 46, rowPitch: 54, cellW: 15, cellH: 14,
    copy: { dx: 280, dy: 0 }, beside: true, noteY: 14, tagY: 38, tagPitch: 20, tagH: 16, legendY: 322,
    big: 12, small: 11, digit: 9, cursorR: 5 };
  var PHONE = { width: 380, height: 310, treeX: 4, treeW: 372, rowY: 36, rowPitch: 26, cellW: 18, cellH: 14,
    copy: { dx: 0, dy: 146 }, beside: false, noteY: 13, tagY: 26, tagPitch: 17, tagH: 14, legendY: 304,
    big: 11, small: 10, digit: 9, cursorR: 4.5 };
  function designSize(size) { return size.width < 520 ? PHONE : WIDE; }

  // Where everything goes: each cell centred over its children, the holders to the left
  // of the root, the copy tree offset by `copy`, a lane behind each half.
  function layout(s, W) {
    var D = W < 520 ? PHONE : WIDE, L = { narrow: D === PHONE, D: D, cells: [], lanes: [] };
    s.cells.forEach(function (c, i) {
      var inRow = Math.pow(2, c.row), p = i - (inRow - 1);
      var cx = D.treeX + (p + 0.5) * (D.treeW / inRow);
      L.cells.push({ x: cx - D.cellW / 2, y: D.rowY + c.row * D.rowPitch, w: D.cellW, h: D.cellH });
    });
    var depth = s.cells[s.cells.length - 1].row, rowsBottom = D.rowY + depth * D.rowPitch + D.cellH;
    L.tags = [0, 1].map(function (k) { return { x: D.treeX + 2, y: D.tagY + k * D.tagPitch, h: D.tagH }; });
    sim.children(s, 0).forEach(function (i, k) {
      var half = D.treeW / 2, x0 = D.treeX + k * half;
      L.lanes.push({ x: x0 - 2, y: D.rowY + D.rowPitch - 8, w: half + 4, h: rowsBottom - (D.rowY + D.rowPitch - 8) + 20, root: i });
    });
    // where the run's summary goes when there is no copy tree: beside the tree, or on a
    // phone in the room the copy would take
    L.panel = D.beside ? { x: D.treeX + D.copy.dx, y: D.rowY + 10, w: D.treeW } : { x: D.treeX + 4, y: D.rowY + D.copy.dy + 10, w: D.treeW };
    L.copyLabel = { x: D.treeX + D.copy.dx + 2, y: D.rowY + D.copy.dy - 8 };
    return L;
  }

  // A rounded box as a path of straight segments (three per corner), so the fallback
  // renderer can replay it.
  function rounded(ctx, b, rad, k) {
    var cx = b.x + b.w / 2, cy = b.y + b.h / 2, w = b.w * (k === undefined ? 1 : k), h = b.h * (k === undefined ? 1 : k);
    var x = cx - w / 2, y = cy - h / 2, r = Math.min(rad, w / 2, h / 2);
    var corner = function (ox, oy, a0) {
      for (var i = 0; i <= 3; i++) {
        var a = a0 + (i / 3) * Math.PI / 2;
        ctx.lineTo(ox + Math.cos(a) * r, oy + Math.sin(a) * r);
      }
    };
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    corner(x + w - r, y + r, -Math.PI / 2);
    corner(x + w - r, y + h - r, 0);
    corner(x + r, y + h - r, Math.PI / 2);
    corner(x + r, y + r, Math.PI);
    ctx.lineTo(x + r, y);
  }

  function digit(ctx, b, s, color, px, weight) {
    font(ctx, px, weight || '', true); ctx.fillStyle = color; ctx.textAlign = 'center';
    ctx.fillText(s, b.x + b.w / 2, b.y + b.h / 2 + px * 0.36);
    ctx.textAlign = 'left';
  }

  function arrow(ctx, from, to, color) {
    ctx.strokeStyle = color; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(from.x, from.y); ctx.lineTo(to.x, to.y); ctx.stroke();
    var dx = to.x - from.x, dy = to.y - from.y, len = Math.sqrt(dx * dx + dy * dy) || 1, ux = dx / len, uy = dy / len;
    ctx.beginPath();
    ctx.moveTo(to.x, to.y); ctx.lineTo(to.x - ux * 6 - uy * 3, to.y - uy * 6 + ux * 3);
    ctx.moveTo(to.x, to.y); ctx.lineTo(to.x - ux * 6 + uy * 3, to.y - uy * 6 - ux * 3);
    ctx.stroke();
  }

  // Text cut to a width, with an ellipsis.
  function fit(ctx, text, width) {
    if (ctx.measureText(text).width <= width) return text;
    var cut = text;
    while (cut.length > 1 && ctx.measureText(cut + '…').width > width) cut = cut.slice(0, -1);
    return cut.replace(/[\s:,;]+$/, '') + '…';
  }

  function tag(ctx, at, label, color, px, mono, alpha) {
    font(ctx, px, '', mono);
    var w = ctx.measureText(label).width + 10, b = { x: at.x, y: at.y, w: w, h: at.h };
    ctx.globalAlpha = alpha;
    ctx.strokeStyle = color; ctx.lineWidth = 1;
    rounded(ctx, b, 3); ctx.stroke();
    ctx.fillStyle = color; ctx.textAlign = 'left';
    ctx.fillText(label, b.x + 5, b.y + b.h / 2 + px * 0.36);
    ctx.globalAlpha = 1;
    return b;
  }

  var NOTES = {
    built: function (s) { return s.cells.length + ' cells, one holder'; },
    owned: function () { return 'inc_leaves(t) is the last use of t: rewritten in place'; },
    shared: function () { return 't is used again afterwards: inc_leaves builds a copy'; },
    parallel: function () { return 'one task per half, each rewriting its half in place'; },
  };

  function heap(ctx, s, size, c) {
    var W = size.width, H = size.height, L = layout(s, W), D = L.D, narrow = L.narrow, view = s.cfg.view || {};
    var mode = s.mode || 'built', sharing = mode === 'shared' || mode === 'vault';
    var since = s.t - s.startedAt;
    ctx.clearRect(0, 0, W, H);
    ctx.lineWidth = 1; ctx.textAlign = 'left';

    // the line at the top: what this run is, or what the static report said of it
    font(ctx, D.small); ctx.fillStyle = c.dim;
    var note = mode === 'vault' ? 'static report (--why-copies): ' + (view.vaultNote || 'No copies found') : ((view.notes || {})[mode] || NOTES[mode](s));
    ctx.fillText(fit(ctx, note, W - 2 * D.treeX), D.treeX, D.noteY);

    // the lanes of the two tasks, behind the halves
    if (mode === 'parallel') {
      var up = Math.min(1, since / 0.5);
      L.lanes.forEach(function (lane, k) {
        ctx.globalAlpha = 0.1 * up; ctx.fillStyle = c.dim; ctx.fillRect(lane.x, lane.y, lane.w, lane.h);
        ctx.globalAlpha = 0.7 * up; ctx.strokeStyle = c.dim; ctx.setLineDash([4, 3]);
        ctx.strokeRect(lane.x + 0.5, lane.y + 0.5, lane.w - 1, lane.h - 1); ctx.setLineDash([]);
        ctx.globalAlpha = up; font(ctx, D.small); ctx.fillStyle = c.dim;
        ctx.fillText('task ' + (k + 1), lane.x + 5, lane.y + lane.h - 5);
        ctx.globalAlpha = 1;
      });
    }

    // the edges of the original tree
    ctx.strokeStyle = c.dim; ctx.globalAlpha = 0.7;
    s.cells.forEach(function (cell, i) {
      sim.children(s, i).forEach(function (k) {
        var a = L.cells[i], b = L.cells[k];
        ctx.beginPath(); ctx.moveTo(a.x + a.w / 2, a.y + a.h); ctx.lineTo(b.x + b.w / 2, b.y); ctx.stroke();
      });
    });
    ctx.globalAlpha = 1;

    // the cells: count, rewritten fill, the flash as the cursor lands
    s.cells.forEach(function (cell, i) {
      var b = L.cells[i], fl = sim.flash(s, i);
      if (cell.rewritten) { ctx.globalAlpha = 0.55; ctx.fillStyle = c.dim; rounded(ctx, b, 3); ctx.fill(); ctx.globalAlpha = 1; }
      if (fl > 0) { ctx.globalAlpha = 0.85 * fl; ctx.fillStyle = c.ink; rounded(ctx, b, 3); ctx.fill(); ctx.globalAlpha = 1; }
      ctx.strokeStyle = cell.rewritten || cell.visitedAt !== null ? c.ink : c.dim; ctx.lineWidth = cell.rewritten ? 1.5 : 1;
      rounded(ctx, b, 3); ctx.stroke(); ctx.lineWidth = 1;
      var bumped = cell.incAt !== null && s.t - cell.incAt < sim.FLASH_S;
      if (bumped) { ctx.globalAlpha = 0.5 * (1 - (s.t - cell.incAt) / sim.FLASH_S); ctx.fillStyle = c.ink; rounded(ctx, b, 3); ctx.fill(); ctx.globalAlpha = 1; }
      digit(ctx, b, String(cell.rc), fl > 0.5 ? c.dim : c.ink, D.digit, cell.rc > 1 ? '700' : '');
    });

    // the holders: the binding, and a second use or a Vault once the tree is shared
    var rootBox = L.cells[0], rootIn = { x: rootBox.x - 2, y: rootBox.y + rootBox.h / 2 };
    var t0 = tag(ctx, L.tags[0], view.holder || 't', c.ink, D.small, true, 1);
    arrow(ctx, { x: t0.x + t0.w + 1, y: t0.y + t0.h / 2 }, rootIn, c.ink);
    if (sharing) {
      var second = Math.min(1, since / 0.5), isVault = mode === 'vault';
      var t1 = tag(ctx, L.tags[1], isVault ? (view.vault || 'Vault "trees"') : (view.second || 'sum_leaves(t)'), c.ink, D.small, true, second);
      ctx.globalAlpha = second;
      arrow(ctx, { x: t1.x + t1.w + 1, y: t1.y + t1.h / 2 }, rootIn, c.ink);
      ctx.globalAlpha = 1;
    }

    // the copy tree: a cell for each one `inc_leaves` allocated, growing in as it is made
    if (sharing) {
      var any = false;
      s.cells.forEach(function (cell, i) {
        var u = sim.grown(s, i);
        if (u <= 0) return;
        any = true;
        var b = { x: L.cells[i].x + D.copy.dx, y: L.cells[i].y + D.copy.dy, w: L.cells[i].w, h: L.cells[i].h };
        var parent = i > 0 ? Math.floor((i - 1) / 2) : -1;
        if (parent >= 0 && s.copies[parent]) {
          var a = L.cells[parent];
          ctx.strokeStyle = c.accent; ctx.globalAlpha = 0.6 * u;
          ctx.beginPath(); ctx.moveTo(a.x + a.w / 2 + D.copy.dx, a.y + a.h + D.copy.dy); ctx.lineTo(b.x + b.w / 2, b.y); ctx.stroke();
          ctx.globalAlpha = 1;
        }
        var k = 0.3 + 0.7 * ease(u);
        ctx.globalAlpha = 0.2 * u; ctx.fillStyle = c.accent; rounded(ctx, b, 3, k); ctx.fill();
        ctx.globalAlpha = u; ctx.strokeStyle = c.accent; rounded(ctx, b, 3, k); ctx.stroke();
        if (u >= 1) digit(ctx, b, '1', c.accent, D.digit);
        ctx.globalAlpha = 1;
      });
      if (any) {
        font(ctx, D.small); ctx.fillStyle = c.accent;
        ctx.fillText('the copy: ' + s.counters.allocs + (narrow ? '' : ' of ' + s.cells.length) + ' cells', L.copyLabel.x, L.copyLabel.y);
      }
    }

    // the panel beside the tree when there is no copy: what the run came to
    if (L.panel && !sharing && (mode !== 'built' || !narrow)) {
      var p = L.panel, pr = sim.progress(s);
      font(ctx, D.big, '600'); ctx.fillStyle = c.ink;
      if (mode === 'built') {
        ctx.fillText(s.cells.length + ' cells', p.x, p.y + 10);
        font(ctx, D.small); ctx.fillStyle = c.dim;
        ctx.fillText(s.cells.length - (s.cells.length + 1) / 2 + ' nodes, ' + (s.cells.length + 1) / 2 + ' leaves, every count 1', p.x, p.y + 28);
      } else if (mode === 'owned') {
        ctx.fillText('rewritten in place: ' + pr.visited + ' of ' + pr.total, p.x, p.y + 10);
        font(ctx, D.small); ctx.fillStyle = c.dim;
        ctx.fillText('new cells: 0', p.x, p.y + 28);
      } else if (mode === 'parallel') {
        ctx.fillText('rewritten in place: ' + pr.visited + ' of ' + pr.total, p.x, p.y + 10);
        font(ctx, D.small); ctx.fillStyle = c.dim;
        ctx.fillText('around the two tasks: ' + s.counters.plumbing + ' small cells', p.x, p.y + 28);
        ctx.fillStyle = c.dim; ctx.globalAlpha = 0.8;
        for (var n = 0; n < s.counters.plumbing; n++) ctx.fillRect(p.x + (n % 7) * 11, p.y + 36 + Math.floor(n / 7) * 11, 8, 8);
        ctx.globalAlpha = 1;
        font(ctx, D.small); ctx.fillStyle = c.dim;
        ctx.fillText('(the list of halves, two thunks)', p.x, p.y + 36 + Math.ceil(s.counters.plumbing / 7) * 11 + 12);
      }
    }

    // the cursors: where each `inc_leaves` is, with a short trail behind it
    s.cursors.forEach(function (cur) {
      var at = sim.cursorAt(s, cur);
      if (!at) return;
      var a = centre(L.cells[at.from]), b = centre(L.cells[at.to]);
      [0.5, 0.25, 0].forEach(function (back, k) {
        var u = at.u - back;
        if (u < 0) return;
        var pt = mix(a, b, ease(u));
        ctx.globalAlpha = [0.2, 0.4, 0.95][k]; ctx.fillStyle = c.accent;
        ctx.beginPath(); ctx.arc(pt.x, pt.y, D.cursorR * (k === 2 ? 1 : 0.7), 0, Math.PI * 2); ctx.fill();
      });
      ctx.globalAlpha = 1;
    });

    // the legend
    if (!narrow) {
      var lx = D.treeX, ly = D.legendY;
      font(ctx, D.small); ctx.fillStyle = c.dim;
      if (mode !== 'built') {
        ctx.fillStyle = c.accent; ctx.beginPath(); ctx.arc(lx + 5, ly - 4, 4, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = c.dim; ctx.fillText('inc_leaves, cell by cell', lx + 14, ly);
        lx += 150;
      }
      if (!sharing && mode !== 'built') {
        ctx.globalAlpha = 0.55; ctx.fillStyle = c.dim; ctx.fillRect(lx, ly - 9, 10, 10); ctx.globalAlpha = 1;
        ctx.strokeStyle = c.ink; ctx.strokeRect(lx + 0.5, ly - 8.5, 9, 9);
        ctx.fillStyle = c.dim; ctx.fillText('rewritten in place', lx + 16, ly);
      } else if (sharing) {
        ctx.strokeStyle = c.accent; ctx.strokeRect(lx + 0.5, ly - 8.5, 9, 9);
        ctx.fillStyle = c.dim; ctx.fillText('allocated by inc_leaves', lx + 16, ly);
        lx += 160;
        font(ctx, D.digit, '700', true); ctx.fillStyle = c.ink; ctx.fillText('2', lx, ly);
        font(ctx, D.small); ctx.fillStyle = c.dim; ctx.fillText('held twice: the count went up', lx + 10, ly);
      } else {
        ctx.fillText('each box is one heap cell, with its reference count', lx, ly);
      }
    }
  }

  var api = { heap: heap, heapDesign: designSize, heapLayout: layout };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.draw = Object.assign(root.MarchExplainer.draw || {}, api);
})(typeof window !== 'undefined' ? window : globalThis);

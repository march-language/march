// figures.js: the static figures of docs/protocol-to-cluster.md, as SVG strings.
//
// Each builder takes a piece of docs/_data/explainer.json and the width to draw at, and
// returns one <svg>. They are pure (no DOM), so they are tested under node
// (test/explainer/figures.test.js) and can render the page's static fallback images.
// Quantities are in the drawing: one bar per source line at its real length, one square
// per generated state type and per function, one cell per combination of role positions,
// a time axis in real seconds. Colour comes only from the `mx-` classes in
// docs/_includes/explainer.html; nothing here names a colour.
(function (root) {
  'use strict';

  function r(n) { return Math.round(n * 10) / 10; }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  function open(w, h, label) {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="' + r(w) + '" height="' + r(h) +
      '" viewBox="0 0 ' + r(w) + ' ' + r(h) + '" role="img" aria-label="' + esc(label) + '">';
  }
  function rect(cls, x, y, w, h) {
    return '<rect class="' + cls + '" x="' + r(x) + '" y="' + r(y) + '" width="' + r(w) + '" height="' + r(h) + '"/>';
  }
  function text(cls, x, y, s, anchor) {
    return '<text class="' + cls + '" x="' + r(x) + '" y="' + r(y) + '"' +
      (anchor ? ' text-anchor="' + anchor + '"' : '') + '>' + esc(s) + '</text>';
  }
  function line(cls, x1, y1, x2, y2) {
    return '<line class="' + cls + '" x1="' + r(x1) + '" y1="' + r(y1) + '" x2="' + r(x2) + '" y2="' + r(y2) + '"/>';
  }
  function circle(cls, cx, cy, rad) {
    return '<circle class="' + cls + '" cx="' + r(cx) + '" cy="' + r(cy) + '" r="' + r(rad) + '"/>';
  }
  function plural(n, word) { return n + ' ' + word + (n === 1 ? '' : 's'); }

  // ── the fan-out: source lines -> generated modules -> state types -> functions ──
  var STAGES = ['source', 'modules', 'states', 'functions'];

  function fanOut(order, opts) {
    var W = opts.width, stage = STAGES.indexOf(opts.stage);
    if (stage < 0) stage = STAGES.length - 1;
    var M = W < 600 ? 8 : 16, out = [], src = order.source;

    // The declaration, one bar per line at its real length and indent. Under 600 px the
    // whole figure is compact (thinner bars, one row of squares per module, no counts),
    // so it fits a phone's pinned stage.
    var wide = W >= 600, barH = wide ? 4 : 3, barPitch = wide ? 7 : 5;
    var longest = 0;
    src.forEach(function (l) { longest = Math.max(longest, l.length); });
    var cw = Math.min(4, (W - 2 * M) * 0.5 / longest);
    var x0 = wide ? (W - longest * cw) / 2 : M;
    out.push(text('mx-label-strong', x0, 14, 'protocol Order: ' + plural(src.length, 'line')));
    src.forEach(function (l, i) {
      var indent = l.length - l.replace(/^ +/, '').length;
      out.push(rect('mx-srcline', x0 + indent * cw, 24 + i * barPitch, Math.max(cw, (l.length - indent) * cw), barH));
    });
    var y = 24 + src.length * barPitch + 6;

    if (stage >= 1 && wide) {
      var mods = order.modules, gap = 12;
      var colW = (W - 2 * M - (mods.length - 1) * gap) / mods.length;
      var perRow = Math.max(1, Math.floor(colW / 10));
      var top = y + 26, bottom = top;
      // Every part of a column has a fixed place, whatever the stage, so a later stage
      // only ever adds to what is already drawn: name, two caption lines, the state
      // squares, then the function squares.
      mods.forEach(function (m, k) {
        var x = M + k * (colW + gap), yy = top;
        out.push(line('mx-line', W / 2, y, x + colW / 2, y + 20));
        out.push(text('mx-label mx-mono', x, yy + 12, m.name));
        if (stage >= 2 && m.linear_states) out.push(text('mx-label', x, yy + 28, plural(m.linear_states, 'state type')));
        if (stage >= 3) out.push(text('mx-label', x, yy + 43, plural(m.functions, 'function')));
        yy += 52;
        if (stage >= 2) {
          for (var s = 0; s < m.linear_states; s++) out.push(rect('mx-state', x + s * 15, yy, 12, 12));
        }
        yy += 18;
        if (stage >= 3) {
          for (var f = 0; f < m.functions; f++) {
            out.push(rect('mx-fn', x + (f % perRow) * 10, yy + Math.floor(f / perRow) * 10, 8, 8));
          }
          yy += Math.ceil(m.functions / perRow) * 10;
        }
        bottom = Math.max(bottom, stage >= 3 ? yy : stage >= 2 ? top + 70 : top + 20);
      });
      y = bottom + 6;
    } else if (stage >= 1) {
      var nPerRow = Math.max(1, Math.floor((W - 2 * M) / 7));
      order.modules.forEach(function (m) {
        y += 6;
        out.push(text('mx-label mx-mono', M, y + 11, m.name));
        if (stage >= 2) {
          for (var s = 0; s < m.linear_states; s++) out.push(rect('mx-state', M + 100 + s * 13, y + 1, 10, 10));
        }
        y += 16;
        if (stage >= 3) {
          for (var f = 0; f < m.functions; f++) {
            out.push(rect('mx-fn', M + (f % nPerRow) * 7, y + Math.floor(f / nPerRow) * 7, 5, 5));
          }
          y += Math.ceil(m.functions / nPerRow) * 7 + 2;
        }
      });
      y += 4;
    }
    return open(W, y, 'The Order protocol and what the compiler generates from it') + out.join('') + '</svg>';
  }

  // ── the state map: one cell per combination of the roles' positions ────────────
  function stateMap(sm, opts) {
    var W = opts.width, roles = sm.roles || Object.keys(sm.axes);
    var dims = roles.map(function (role) { return sm.axes[role]; });
    var three = dims.length >= 3;
    var blocks = three ? dims[0] : 1, cols = three ? dims[1] : dims[0], rows = three ? dims[2] : dims[1];
    var M = 8, blockGap = 14, labelH = three ? 18 : 0;

    function pitchFor(perRow) {
      return Math.min(36, (W - 2 * M - (perRow - 1) * blockGap) / (perRow * cols));
    }
    var perRow = blocks, pitch = pitchFor(perRow);
    // Two rows of blocks when one row would leave the cells small.
    if (pitch < 26 && blocks > 2) { perRow = Math.ceil(blocks / 2); pitch = pitchFor(perRow); }
    var cell = pitch - 3;

    var litKeys = {};
    (sm.path || sm.reachable).slice(0, opts.lit).forEach(function (c) { litKeys[c.join(',')] = true; });
    var wrongKey = opts.wrong ? opts.wrong.join(',') : null;

    var out = [], blockH = rows * pitch + labelH + 10;
    for (var b = 0; b < blocks; b++) {
      var bx = M + (b % perRow) * (cols * pitch + blockGap), by = Math.floor(b / perRow) * blockH;
      if (three) out.push(text('mx-label', bx, by + 12, roles[0] + ' at step ' + b));
      for (var c = 0; c < cols; c++) {
        for (var rw = 0; rw < rows; rw++) {
          var key = (three ? [b, c, rw] : [c, rw]).join(',');
          var cls = key === wrongKey ? 'mx-cell mx-wrong' : litKeys[key] ? 'mx-cell mx-lit' : 'mx-cell';
          out.push(rect(cls, bx + c * pitch, by + labelH + rw * pitch, cell, cell));
        }
      }
    }
    var h = Math.ceil(blocks / perRow) * blockH;
    var colRole = three ? roles[1] : roles[0], rowRole = three ? roles[2] : roles[1];
    out.push(text('mx-label', M, h + 10, 'Across: ' + colRole + "'s step. Down: " + rowRole + "'s step."));
    return open(W, h + 18, 'Every combination of the roles\' positions; the filled cells can happen') + out.join('') + '</svg>';
  }

  // ── one role's remaining steps: the linear type, drawn ─────────────────────────
  function strip(automaton, opts) {
    var W = opts.width, out = [], x = 0, y = 0, h = 22, gap = 5;
    automaton.labels.forEach(function (label, i) {
      var w = Math.min(W, label.length * 7.4 + 18);     // 12px monospace is about 7.2px a character
      if (x + w > W) { x = 0; y += h + gap; }
      var cls = i < opts.at ? 'mx-seg mx-done' : i === opts.at ? 'mx-seg mx-next' : 'mx-seg';
      out.push(rect(cls, x, y, w, h));
      out.push(text('mx-label mx-mono', x + 8, y + 15, label));
      x += w + gap;
    });
    return open(W, y + h, 'The steps this role may still take') + out.join('') + '</svg>';
  }

  // ── how long a failed peer goes unnoticed, to scale ────────────────────────────
  function detectionTimeline(timings, opts) {
    var W = opts.width, T = timings.silent_timeout_s, hb = timings.heartbeat_s;
    var M = 28, x0 = M, x1 = W - M, y = 44, scale = (x1 - x0) / T, out = [];
    out.push(line('mx-line', x0, y, x1, y));
    out.push(circle('mx-ink', x0, y, 4));
    out.push(text('mx-label', x0, y + 24, '0 s', 'middle'));
    out.push(text('mx-label', x1, y + 24, T + ' s', 'middle'));
    if (opts.mode === 'crash') {
      out.push(text('mx-label', x0 - 4, 16, 'Connection closes: noticed at once'));
      out.push(line('mx-failed', x0, y - 16, x0, y + 16));
    } else {
      out.push(text('mx-label', x0 - 4, 16, 'Peer goes silent'));
      for (var k = 1; k * hb < T && k * hb <= opts.elapsed; k++) out.push(circle('mx-ping', x0 + k * hb * scale, y, 3.5));
      if (opts.elapsed >= T) {
        out.push(text('mx-label mx-accent-text', x1 + 4, 16, 'Declared failed', 'end'));
        out.push(line('mx-failed', x1, y - 16, x1, y + 16));
      }
    }
    return open(W, y + 34, 'Time from a peer failing to its being declared failed') + out.join('') + '</svg>';
  }

  // ── every function in the binary, and the ones a deploy changes ────────────────
  function functionSquares(deploy, opts) {
    var W = opts.width, total = deploy.total_functions, M = 8;
    var pitch = total > 1500 ? 6 : 10, size = pitch - 2;
    var perRow = Math.max(1, Math.floor((W - 2 * M) / pitch));
    var changed = opts.showChanged ? deploy.changed_functions.length : 0, out = [];
    for (var i = 0; i < total; i++) {
      out.push(rect(i < changed ? 'mx-fn mx-changed' : 'mx-fn',
        M + (i % perRow) * pitch, Math.floor(i / perRow) * pitch, size, size));
    }
    return open(W, Math.ceil(total / perRow) * pitch, 'One square per function in the binary') + out.join('') + '</svg>';
  }

  // ── the machines the programs land on ──────────────────────────────────────────
  function hosts(topology, opts) {
    var W = opts.width, M = 8, names = [topology.ingress].concat(topology.stock_hosts);
    var perRow = W >= 600 ? names.length : 2, gap = 12;
    var bw = (W - 2 * M - (perRow - 1) * gap) / perRow, bh = 70, out = [];
    names.forEach(function (name, i) {
      var x = M + (i % perRow) * (bw + gap), y = Math.floor(i / perRow) * (bh + gap);
      out.push(rect('mx-host', x + 0.5, y + 0.5, bw - 1, bh - 1));
      out.push(text('mx-label-strong', x + 10, y + 20, name));
      out.push(text('mx-label', x + 10, y + 38, name === topology.ingress ? 'starts Shop' : 'offers Stock'));
      if (topology.books_hosts.indexOf(name) >= 0) out.push(text('mx-label', x + 10, y + 55, 'may hold Ledger'));
    });
    return open(W, Math.ceil(names.length / perRow) * (bh + gap) - gap, 'The machines of the lab and the roles each one runs') + out.join('') + '</svg>';
  }

  var api = { fanOut: fanOut, stateMap: stateMap, strip: strip, hosts: hosts,
    detectionTimeline: detectionTimeline, functionSquares: functionSquares };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.figures = api;
})(typeof window !== 'undefined' ? window : globalThis);

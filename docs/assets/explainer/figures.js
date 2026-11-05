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

  // ── the declaration itself, with some of its lines picked out ──────────────────
  // One <text> per source line, indented as written. Lines `from`..`to` (1-based) are
  // picked out and the rest dimmed; `from: 0` picks out none. Picking out lines moves
  // nothing, so going from card to card only changes colours. The type shrinks to keep
  // the longest line inside `width`.
  function declaration(order, opts) {
    var src = order.source, longest = 0;
    src.forEach(function (l) { longest = Math.max(longest, l.length); });
    var fs = Math.max(9, Math.min(15, Math.floor((opts.width - 26) / (longest * 0.6))));
    var cw = fs * 0.6, lh = Math.round(fs * 1.62), pad = 13, out = [];
    var any = opts.from >= 1;
    if (any) out.push(rect('mx-hlbar', 0, (opts.from - 1) * lh + 3, 3, (opts.to - opts.from + 1) * lh));
    src.forEach(function (l, i) {
      var indent = l.length - l.replace(/^ +/, '').length;
      var on = any && i + 1 >= opts.from && i + 1 <= opts.to;
      out.push('<text class="mx-codeline' + (on ? ' mx-hl' : any ? ' mx-off' : '') + '" x="' + r(pad + indent * cw) +
        '" y="' + r((i + 1) * lh - 3) + '" font-size="' + fs + '">' + esc(l.replace(/^ +/, '')) + '</text>');
    });
    return open(pad * 2 + longest * cw, src.length * lh + 6, 'The Order protocol, line by line') + out.join('') + '</svg>';
  }

  // ── the fan-out: source lines -> generated modules -> state types -> functions ──
  var STAGES = ['source', 'modules', 'states', 'functions'];

  function fanOut(order, opts) {
    var W = opts.width, stage = STAGES.indexOf(opts.stage);
    if (stage < 0) stage = STAGES.length - 1;
    var M = W < 600 ? 8 : 16, out = [], src = order.source;

    // The declaration, one bar per line at its real length and indent. Under 600 px the
    // whole figure is compact (thinner bars, one row of squares per module, no counts),
    // so it fits a phone's pinned stage.
    var wide = W >= 600 || !!opts.perRow, barH = wide ? 4 : 3, barPitch = wide ? 7 : 5;
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
      // Modules sit `perRow` to a row: all in one row for a wide stage, three to a row
      // for one that is nearly square. Every part of a module has a fixed place whatever
      // the stage, so a later stage only ever adds to what is already drawn: name, two
      // caption lines, the state squares, then the function squares.
      var mods = order.modules, gap = 12, per = opts.perRow || mods.length;
      var colW = (W - 2 * M - (per - 1) * gap) / per;
      var perRowSq = Math.max(1, Math.floor(colW / 10)), most = 0;
      mods.forEach(function (m) { most = Math.max(most, Math.ceil(m.functions / perRowSq)); });
      var blockH = 70 + most * 10 + 12, top = y + 26, bottom = top;
      if (per === mods.length) {
        mods.forEach(function (m, k) { out.push(line('mx-line', W / 2, y, M + k * (colW + gap) + colW / 2, y + 20)); });
      } else out.push(line('mx-line', W / 2, y, W / 2, y + 14));
      mods.forEach(function (m, k) {
        var x = M + (k % per) * (colW + gap), yy = top + Math.floor(k / per) * blockH;
        out.push(text('mx-label mx-mono', x, yy + 12, m.name));
        if (stage >= 2 && m.linear_states) out.push(text('mx-label', x, yy + 28, plural(m.linear_states, 'state type')));
        if (stage >= 3) out.push(text('mx-label', x, yy + 43, plural(m.functions, 'function')));
        if (stage >= 2) {
          for (var s = 0; s < m.linear_states; s++) out.push(rect('mx-state', x + s * 15, yy + 52, 12, 12));
        }
        if (stage >= 3) {
          for (var f = 0; f < m.functions; f++) {
            out.push(rect('mx-fn', x + (f % perRowSq) * 10, yy + 70 + Math.floor(f / perRowSq) * 10, 8, 8));
          }
        }
        var rowTop = top + Math.floor(k / per) * blockH;
        bottom = Math.max(bottom, stage >= 3 ? rowTop + 70 + Math.ceil(m.functions / perRowSq) * 10
          : stage >= 2 ? rowTop + 66 : rowTop + 18);
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
  // Drawn at one design size (the page scales a figure to fill its stage), exactly as
  // wide as its cells. The blocks are arranged in whichever number of rows lets the
  // figure be scaled up most in a stage of `opts.width` by `opts.height`.
  function stateMap(sm, opts) {
    var roles = sm.roles || Object.keys(sm.axes);
    var dims = roles.map(function (role) { return sm.axes[role]; });
    var three = dims.length >= 3;
    var blocks = three ? dims[0] : 1, cols = three ? dims[1] : dims[0], rows = three ? dims[2] : dims[1];
    var M = 8, P = 36, cell = P - 3, blockGap = 16, labelH = three ? 18 : 0, blockH = rows * P + labelH + 10;
    var room = { w: opts.width, h: opts.height || opts.width * 0.75 };

    function size(perRow) {
      return { w: 2 * M + perRow * cols * P - 3 + (perRow - 1) * blockGap, h: Math.ceil(blocks / perRow) * blockH + 18 };
    }
    var perRow = blocks, best = -1;
    [blocks, Math.ceil(blocks / 2), 1].forEach(function (n) {
      var sz = size(n), k = Math.min(room.w / sz.w, room.h / sz.h);
      if (k > best + 1e-9) { best = k; perRow = n; }
    });

    var litKeys = {};
    (sm.path || sm.reachable).slice(0, opts.lit).forEach(function (c) { litKeys[c.join(',')] = true; });
    var wrongKey = opts.wrong ? opts.wrong.join(',') : null;

    var out = [];
    for (var b = 0; b < blocks; b++) {
      var bx = M + (b % perRow) * (cols * P + blockGap), by = Math.floor(b / perRow) * blockH;
      if (three) out.push(text('mx-label', bx, by + 12, roles[0] + ' at step ' + b));
      for (var c = 0; c < cols; c++) {
        for (var rw = 0; rw < rows; rw++) {
          var key = (three ? [b, c, rw] : [c, rw]).join(',');
          var cls = key === wrongKey ? 'mx-cell mx-wrong' : litKeys[key] ? 'mx-cell mx-lit' : 'mx-cell';
          out.push(rect(cls, bx + c * P, by + labelH + rw * P, cell, cell));
        }
      }
    }
    var sz = size(perRow);
    var colRole = three ? roles[1] : roles[0], rowRole = three ? roles[2] : roles[1];
    out.push(text('mx-label', M, sz.h - 8, 'Across: ' + colRole + "'s step. Down: " + rowRole + "'s step."));
    return open(Math.max(sz.w, 290), sz.h, 'Every combination of the roles\' positions; the filled cells can happen') + out.join('') + '</svg>';
  }

  // ── one role's remaining steps: the linear type, drawn ─────────────────────────
  function strip(automaton, opts) {
    // A 12px monospace character is 7.2px wide. Each label is centred in its segment
    // with 13px to spare on either side, and `textLength` holds it to that width even
    // if the reader's monospace font is wider than the one this was measured with.
    var W = opts.width, out = [], x = 0, y = 0, h = 28, gap = 9, CHAR = 7.2, right = 0;
    automaton.labels.forEach(function (label, i) {
      var w = Math.min(W, Math.ceil(label.length * 7.3) + 26);
      if (x > 0 && x + w > W) { x = 0; y += h + gap; }
      var cls = i < opts.at ? 'mx-seg mx-done' : i === opts.at ? 'mx-seg mx-next' : 'mx-seg';
      out.push(rect(cls, x, y, w, h));
      out.push('<text class="mx-label mx-mono" x="' + r(x + w / 2) + '" y="' + r(y + h / 2 + 4) +
        '" text-anchor="middle" textLength="' + r(Math.min(w - 12, label.length * CHAR)) +
        '" lengthAdjust="spacingAndGlyphs">' + esc(label) + '</text>');
      right = Math.max(right, x + w);
      x += w + gap;
    });
    return open(right, y + h, 'The steps this role may still take') + out.join('') + '</svg>';
  }

  // ── how long a failed host goes unnoticed, to scale ────────────────────────────
  // The cluster's failure detector is the node's own (SWIM): it probes each peer every
  // `swim_probe_s`, waits `swim_ack_ms` for the ack, and gives a suspect `suspect_s` to
  // refute before declaring it dead. A crash needs none of that: the connection closes.
  function detectionTimeline(timings, opts) {
    var W = opts.width, probe = timings.swim_probe_s, ack = timings.swim_ack_ms / 1000;
    var suspectAt = probe + ack, T = suspectAt + timings.suspect_s;
    var M = 28, x0 = M, x1 = W - M, y = 44, scale = (x1 - x0) / T, out = [];
    function secs(n) { return (Math.round(n * 10) / 10) + ' s'; }
    out.push(line('mx-line', x0, y, x1, y));
    out.push(circle('mx-ink', x0, y, 4));
    out.push(text('mx-label', x0, y + 24, '0 s', 'middle'));
    if (opts.mode === 'crash') {
      out.push(text('mx-label', x0 - 4, 16, 'Connection closes: noticed at once'));
      out.push(line('mx-failed', x0, y - 16, x0, y + 16));
    } else {
      out.push(text('mx-label', x0 - 4, 16, 'Hangs'));
      out.push(circle('mx-ping', x0 + probe * scale, y, 3.5));
      out.push(circle('mx-ping', x0 + suspectAt * scale, y, 3.5));
      out.push(text('mx-label', x0 + suspectAt * scale - 4, 16, 'Suspected'));
      out.push(text('mx-label', x0 + suspectAt * scale, y + 24, secs(suspectAt), 'middle'));
      out.push(text('mx-label mx-accent-text', x1 + 4, 16, 'Declared dead', 'end'));
      out.push(line('mx-failed', x1, y - 16, x1, y + 16));
      out.push(text('mx-label', x1, y + 24, secs(T), 'middle'));
    }
    return open(W, y + 34, 'Time from a host failing to its being declared dead') + out.join('') + '</svg>';
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

  var api = { declaration: declaration, fanOut: fanOut, stateMap: stateMap, strip: strip, hosts: hosts,
    detectionTimeline: detectionTimeline, functionSquares: functionSquares };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.figures = api;
})(typeof window !== 'undefined' ? window : globalThis);

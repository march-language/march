// figures-ownership.js: the static figures of docs/one-owner.md, as SVG strings.
//
// token(entry, opts): the lines of one excerpt from docs/_data/ownership.json
// (`linear.*`), with a token (a small circle marked `t`) beside the line that binds the
// linear or affine value and one beside each line that uses it, hollow once it has been
// consumed. The verdict is drawn as one accent token: the use too many, the use that
// never came, or (affine) the leftover that is allowed to be dropped.
//
// contract(contracts, opts): an allocation ledger. One column per function under
// contract (`contracts.*`), a bar of the cells it allocates, and the contract's line
// at "allowed: 0" once one is pinned; a column over the line is the accent.
//
// Both are pure (no DOM): tested under node (test/explainer/ownership.test.js) and used
// for the static fallback images. Colour comes only from the `mx-` classes in
// docs/_includes/explainer.html.
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
  function text(cls, x, y, s, anchor, size) {
    return '<text class="' + cls + '" x="' + r(x) + '" y="' + r(y) + '"' +
      (anchor ? ' text-anchor="' + anchor + '"' : '') + (size ? ' font-size="' + size + '"' : '') + '>' + esc(s) + '</text>';
  }
  function line(cls, x1, y1, x2, y2) {
    return '<line class="' + cls + '" x1="' + r(x1) + '" y1="' + r(y1) + '" x2="' + r(x2) + '" y2="' + r(y2) + '"/>';
  }
  function circle(cls, cx, cy, rad) {
    return '<circle class="' + cls + '" cx="' + r(cx) + '" cy="' + r(cy) + '" r="' + r(rad) + '"/>';
  }

  // ── the token: where the value lives, line by line ─────────────────────────────
  var TOKEN_STATES = ['linear-ok', 'linear-twice', 'linear-never', 'affine-ok', 'affine-twice'];

  // opts: { width, kind } where kind is 'linear' or 'affine' (the entry's own `kind`
  // wins when it has one). Each token's label sits at the end of its line; the type
  // shrinks until the longest line, and every labelled line with its label, fits
  // `width` less the token gutter. Under 420 px (a phone) only the verdict's label is
  // drawn, so the code keeps a readable size. The figure is as tall as its lines plus
  // the verdict row.
  function token(entry, opts) {
    var src = String(entry.excerpt).replace(/\n+$/, '').split('\n'), kind = entry.kind || opts.kind || 'linear';
    var verdict = entry.verdict, uses = (entry.uses || []).slice(), binder = entry.binder;
    if (['ok', 'twice', 'never'].indexOf(verdict) < 0) throw new Error('unknown verdict ' + verdict);
    var W = opts.width, compact = W < 420, gutter = 34, pad = 8, labelPx = 6.6;
    var longest = 0;
    src.forEach(function (l) { longest = Math.max(longest, l.length); });

    // the tokens: on which line, in which colour, and what each says
    var tokens = [], perLine = {};
    var put = function (n, cls, label) {
      var k = perLine[n] || 0;
      perLine[n] = k + 1;
      tokens.push({ n: n, cls: cls, slot: k, label: label || '' });
    };
    if (binder >= 1) put(binder, 'mx-held', compact ? '' : kind === 'affine' ? 'at most once' : 'exactly once');
    uses.forEach(function (n, k) {
      var last = k === uses.length - 1;
      if (verdict === 'twice' && last) put(n, 'mx-hot', 'used again');
      else put(n, 'mx-spent', !compact && k === 0 && verdict === 'ok' && kind !== 'affine' ? 'consumed' : '');
    });
    var tail = src.length + 1;
    if (verdict === 'never') put(tail, 'mx-hot', 'never used');
    else if (verdict === 'ok' && kind === 'affine') put(tail, 'mx-dim', 'dropped (allowed)');

    // the type size: the longest line fits, and so does each labelled line with its label
    var fs = Math.min(14, (W - gutter - 14) / (longest * 0.6));
    tokens.forEach(function (t) {
      if (!t.label || t.n > src.length) return;
      fs = Math.min(fs, (W - gutter - 10 - t.label.length * labelPx) / (src[t.n - 1].length * 0.6));
    });
    fs = Math.max(9, Math.floor(fs));
    var cw = fs * 0.6, lh = Math.round(fs * 1.7), rad = Math.max(6, Math.min(8, lh * 0.34)), out = [], width = W;
    var lineY = function (n) { return n * lh - 3; };           // the baseline of 1-based line n

    // the line the diagnostic points at
    var at = entry.at || (verdict === 'never' ? binder : 0);
    if (verdict !== 'ok' && at >= 1) out.push(rect('mx-hlbar', gutter - 4, (at - 1) * lh + 3, 3, lh));

    src.forEach(function (l, i) {
      var indent = l.length - l.replace(/^ +/, '').length, n = i + 1;
      var dim = verdict !== 'ok' && at >= 1 && n !== at && n !== binder && uses.indexOf(n) < 0;
      out.push('<text class="mx-codeline' + (dim ? ' mx-off' : '') + '" x="' + r(gutter + indent * cw) +
        '" y="' + r(lineY(n)) + '" font-size="' + fs + '">' + esc(l.replace(/^ +/, '')) + '</text>');
    });

    tokens.forEach(function (t) {
      var cx = pad + rad + t.slot * (rad * 2 + 3), cy = lineY(t.n) - fs * 0.36, hollow = t.cls === 'mx-spent' || t.cls === 'mx-dim';
      out.push(circle('mx-token ' + t.cls, cx, cy, rad));
      out.push(text('mx-token-text' + (hollow ? ' mx-hollow' : ''), cx, cy + fs * 0.3, 't', 'middle', Math.max(8, fs - 3)));
      if (!t.label) return;
      var lineEnd = t.n <= src.length ? gutter + src[t.n - 1].length * cw : gutter;
      out.push(text('mx-label ' + (t.cls === 'mx-hot' ? 'mx-accent-text' : 'mx-token-note'), lineEnd + 10, lineY(t.n), t.label));
      width = Math.max(width, lineEnd + 10 + t.label.length * labelPx + 4);
    });

    var H = tail * lh + 4;
    if (verdict === 'ok' && kind !== 'affine') { out.push(text('mx-label', gutter, lineY(tail), 'consumed exactly once')); H += lh; }
    else if (verdict === 'twice' && entry.slug) { out.push(text('mx-label mx-mono mx-accent-text', gutter, lineY(tail), '[' + entry.slug + ']')); H += lh; }
    else H += lh;
    return open(width, H, 'The ' + kind + ' value t, line by line: where it is bound, where it is used') + out.join('') + '</svg>';
  }

  // ── the contract: an allocation ledger ─────────────────────────────────────────
  var CONTRACT_STATES = ['candidate', 'pinned', 'bare', 'transient', 'boxed', 'caller', 'bound'];

  // The function a state's excerpt puts under contract: the `fn` directly under an
  // `@[...]` line, else the last `fn` in the excerpt.
  function attributed(excerpt) {
    var lines = String(excerpt || '').replace(/\n+$/, '').split('\n'), name = null;
    lines.forEach(function (l, i) {
      var m = /^fn\s+([A-Za-z_]\w*)/.exec(l);
      if (!m) return;
      if (i > 0 && /^@\[/.test(lines[i - 1])) name = m[1];
      else if (name === null) name = m[1];
    });
    return name;
  }
  function named(s) { return (/`([^`]+)`/.exec(String(s || '')) || [, ''])[1]; }

  // What each state shows: the columns (name, cells made, cells kept, pass/fail,
  // ghost), the lines drawn, and the text under the chart.
  function ledger(C, stage) {
    var pinnedName = attributed(C.pinned && C.pinned.excerpt) || named(C.candidate && C.candidate.message) || 'inc_leaves';
    var L = { cols: [], lines: [], notes: [] };
    switch (stage) {
      case 'candidate':
        L.cols.push({ name: named(C.candidate.message) || pinnedName, made: 0, kept: 0, verdict: 'none' });
        L.notes.push({ cls: 'mx-label', s: C.candidate.message });
        L.notes.push({ cls: 'mx-label mx-mono', s: String(C.candidate.fix).trim() + '  ← the fix, verbatim' });
        break;
      case 'pinned':
        L.cols.push({ name: pinnedName, made: 0, kept: 0, verdict: 'pass' });
        L.lines.push({ at: 0, label: 'allowed: 0', cls: '' });
        L.notes.push({ cls: 'mx-label', s: '@[no_alloc] pinned: every build checks it' });
        break;
      case 'bare':
        L.cols.push({ name: attributed(C.bare.excerpt), made: 1, kept: 1, verdict: 'fail' });
        L.lines.push({ at: 0, label: 'allowed: 0', cls: '' });
        L.notes.push({ cls: 'mx-label mx-accent-text', s: C.bare.reason });
        break;
      case 'transient':
        L.cols.push({ name: attributed(C.transient.excerpt), made: 1, kept: 0, verdict: 'pass', transient: true });
        L.lines.push({ at: 0, label: 'kept: 0', cls: '' });
        L.notes.push({ cls: 'mx-label', s: '@[no_alloc(transient)]: it may allocate, but nothing it makes may outlive the call' });
        break;
      case 'boxed':
        L.cols.push({ name: attributed(C.boxed.excerpt), made: 1, kept: 1, verdict: 'fail', what: named(C.boxed.reason.replace(/^In `[^`]*`:/, '')) });
        L.lines.push({ at: 0, label: 'allowed: 0', cls: '' });
        L.notes.push({ cls: 'mx-label mx-accent-text', s: C.boxed.reason });
        break;
      case 'caller': {
        var n = C.caller.allocs[Object.keys(C.caller.allocs)[0]], name = Object.keys(C.caller.allocs)[0];
        L.cols.push({ name: name, made: 0, kept: 0, verdict: 'pass' });
        L.cols.push({ name: name, made: n, kept: n, verdict: 'ghost', label: 'at run time, with a sharing caller: ' + n });
        L.lines.push({ at: 0, label: 'allowed: 0', cls: '' });
        L.notes.push({ cls: 'mx-label', s: 'the contract is about the function\'s own code, not its callers: it still holds' });
        break;
      }
      case 'bound': {
        var bound = (C.bound && C.bound.n) || 3;
        L.cols.push({ name: pinnedName, made: 0, kept: 0, verdict: 'pass' });
        L.lines.push({ at: 0, label: 'allowed: 0', cls: '' });
        L.lines.push({ at: bound, label: 'allowed: ' + bound + ' (design, not shipped)', cls: 'mx-design' });
        L.notes.push({ cls: 'mx-label', s: '@[alloc_bound(' + bound + ')]: a bound above zero, designed and not yet built' });
        break;
      }
      default: throw new Error('unknown stage ' + stage);
    }
    return L;
  }

  // opts: { width, stage }
  function contract(contracts, opts) {
    if (CONTRACT_STATES.indexOf(opts.stage) < 0) throw new Error('unknown stage ' + opts.stage);
    var W = Math.min(opts.width, 560), L = ledger(contracts, opts.stage), out = [];
    var compact = W < 420, M = compact ? 8 : 14, top = 30, plotH = compact ? 120 : 150, base = top + plotH;
    var most = 5;
    L.cols.forEach(function (c) { most = Math.max(most, c.made); });
    L.lines.forEach(function (l) { most = Math.max(most, l.at); });
    var unit = plotH / (most + 1), axisX = M + 36, colW = compact ? 48 : 72, gap = compact ? 40 : 72;
    var plotW = W - M - axisX, colsW = L.cols.length * colW + (L.cols.length - 1) * gap, col0 = axisX + Math.max(16, (plotW - colsW) / 2);
    var yOf = function (cells) { return base - cells * unit; };

    out.push(text('mx-label-strong', M, 14, compact ? 'cells allocated per call' : 'the allocation ledger: cells allocated per call'));
    // the axis, with a tick per cell
    out.push(line('mx-line', axisX, top, axisX, base));
    out.push(line('mx-line', axisX, base, W - M, base));
    for (var k = 0; k <= most; k++) {
      out.push(line('mx-line', axisX - 3, yOf(k), axisX, yOf(k)));
      out.push(text('mx-label', axisX - 6, yOf(k) + 4, String(k), 'end'));
    }

    L.cols.forEach(function (col, i) {
      var x = col0 + i * (colW + gap), over = col.verdict === 'fail';
      if (col.transient) {
        out.push(rect('mx-bar mx-made', x, yOf(col.made), colW / 2 - 2, base - yOf(col.made)));
        out.push(rect('mx-bar', x + colW / 2 + 2, yOf(col.kept) - 2, colW / 2 - 2, 2));
        out.push(text('mx-label', x + colW / 2, yOf(Math.max(col.made, col.kept)) - 5, 'made ' + col.made + ', kept ' + col.kept, 'middle'));
      } else if (col.verdict === 'ghost') {
        out.push(rect('mx-bar mx-ghost', x, yOf(col.made), colW, base - yOf(col.made)));
        out.push(text('mx-label', x + colW / 2, yOf(col.made) - 5, String(col.made), 'middle'));
      } else if (col.made > 0) {
        out.push(rect('mx-bar' + (over ? ' mx-over' : ''), x, yOf(col.made), colW, base - yOf(col.made)));
        out.push(text(over ? 'mx-label mx-accent-text' : 'mx-label', x + colW / 2, yOf(col.made) - 5, col.made + (col.what ? ' (' + col.what + ')' : ''), 'middle'));
      } else {
        out.push(rect('mx-bar', x, base - 2, colW, 2));
        out.push(text('mx-label', x + colW / 2, base - 6, '0', 'middle'));
      }
      var tick = col.verdict === 'pass' ? ' ✓' : col.verdict === 'fail' ? ' ✗' : '';
      out.push(text((over ? 'mx-label-strong mx-mono mx-accent-text' : 'mx-label-strong mx-mono') + (col.verdict === 'ghost' ? ' mx-ghost-text' : ''),
        x + colW / 2, base + 16, col.name + tick, 'middle'));
      if (col.label) out.push(text('mx-label mx-ghost-text', x + colW / 2, base + 30, compact ? col.label.replace('at run time, ', '') : col.label, 'middle'));
    });

    // the contract's line(s)
    L.lines.forEach(function (l) {
      out.push(line('mx-contract ' + l.cls, axisX, yOf(l.at), W - M, yOf(l.at)));
      out.push(text('mx-label' + (l.cls ? '' : ' mx-contract-text'), W - M, yOf(l.at) - 5, l.label, 'end'));
    });

    // what the compiler said, wrapped to the width
    var y = base + 48, perLine = Math.max(30, Math.floor((W - 2 * M) / 6.6));
    L.notes.forEach(function (note) {
      var words = note.s.split(' '), lines = [''];
      words.forEach(function (w) {
        var last = lines[lines.length - 1];
        if (last && (last + ' ' + w).length > perLine) lines.push(w);
        else lines[lines.length - 1] = last ? last + ' ' + w : w;
      });
      lines.forEach(function (l) { out.push(text(note.cls, M, y, l)); y += 16; });
      y += 4;
    });
    return open(W, y, 'An allocation ledger: one column per function under contract, its cells per call against the line the contract allows') + out.join('') + '</svg>';
  }

  var api = { token: token, contract: contract, contractLedger: ledger, attributed: attributed,
    TOKEN_STATES: TOKEN_STATES, CONTRACT_STATES: CONTRACT_STATES };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.figures = Object.assign(root.MarchExplainer.figures || {}, api);
})(typeof window !== 'undefined' ? window : globalThis);

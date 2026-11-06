// figures-authority.js: the static figure of docs/deploy-authority.md, as an SVG string.
//
// reach(modules, opts): one square per module the lab app's program links, grouped by
// what the module declares it can reach (docs/_data/authority.json, `modules`), and
// under the grid the app's own modules with their `needs` lines. Pure (no DOM): tested
// under node (test/explainer/authority.test.js) and used for the static fallback image.
// Colour comes only from the `mx-` classes in docs/_includes/explainer.html.
//
// Every square has a fixed place whatever the stage, and each group keeps one empty
// place at its end for the dependency, so moving from card to card only recolours
// squares, or adds the dependency's one square.
(function (root) {
  'use strict';

  function r(n) { return Math.round(n * 10) / 10; }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  function rect(cls, x, y, w, h) {
    return '<rect class="' + cls + '" x="' + r(x) + '" y="' + r(y) + '" width="' + r(w) + '" height="' + r(h) + '"/>';
  }
  function text(cls, x, y, s) { return '<text class="' + cls + '" x="' + r(x) + '" y="' + r(y) + '">' + esc(s) + '</text>'; }

  var STAGES = ['all', 'none', 'inside', 'outside', 'own', 'undeclared', 'ceiling', 'dep', 'dep-update', 'dep-accepted'];
  var GROUPS = ['none', 'inside', 'outside'];
  var HEADING = {
    none: function (n) { return n + ' reach nothing'; },
    inside: function (n) { return n + ' reach only the process they run in, or a session they are handed'; },
    outside: function (n) { return n + ' can reach files, the network or another process'; },
  };
  var SHORT = {
    none: function (n) { return n + ' reach nothing'; },
    inside: function (n) { return n + ' reach only the process'; },
    outside: function (n) { return n + ' reach files, network, processes'; },
  };

  // opts: { width, stage, dep, compact } where dep is the page's dependency ({name, v1,
  // v2}) and compact is the phone drawing: smaller squares, short headings, no table.
  function reach(modules, opts) {
    var W = opts.width, stage = STAGES.indexOf(opts.stage);
    if (stage < 0) throw new Error('unknown stage ' + opts.stage);
    var at = function (name) { return stage >= STAGES.indexOf(name); };
    var wide = !opts.compact, M = wide ? 8 : 4, P = wide ? 17 : 11, size = P - (wide ? 4 : 3);
    var perRow = Math.max(8, Math.floor((W - 2 * M) / P)), out = [], y = 0;
    var dep = opts.dep, depStage = opts.stage.indexOf('dep') === 0 ? opts.stage : null;

    out.push(text('mx-label-strong', M, 13, modules.total + (W >= 600 ? ' modules: the lab app and the library code it links' : ' modules in the lab app\'s program')));
    y = 24;
    GROUPS.forEach(function (cls) {
      var mods = modules.list.filter(function (m) { return m.cls === cls; });
      var shown = at(cls);                                   // has this group been picked out yet?
      if (shown) out.push(text('mx-label', M, y + 11, (W >= 600 ? HEADING : SHORT)[cls](mods.length)));
      y += 18;
      mods.forEach(function (m, i) {
        var c = 'mx-sq';
        if (shown) c += ' mx-' + (cls === 'none' ? 'quiet' : cls);
        if (opts.stage === 'undeclared' && m.name === 'Probe') c += ' mx-hot';
        else if (at('own') && !depStage && m.own) c += ' mx-own';
        out.push(rect(c, M + (i % perRow) * P, y + Math.floor(i / perRow) * P, size, size));
      });
      // the dependency's square, in the place kept for it
      var slot = mods.length, sx = M + (slot % perRow) * P, sy = y + Math.floor(slot / perRow) * P;
      if (cls === 'none' && depStage === 'dep') out.push(rect('mx-sq mx-quiet mx-own', sx, sy, size, size));
      if (cls === 'outside' && depStage === 'dep-update') out.push(rect('mx-sq mx-hot', sx, sy, size, size));
      if (cls === 'outside' && depStage === 'dep-accepted') out.push(rect('mx-sq mx-outside mx-own', sx, sy, size, size));
      y += Math.ceil((mods.length + 1) / perRow) * P + 8;
    });

    // The app's own modules and what each declares, wrapped to the width. Not on a
    // phone: the cards say it.
    if (wide) {
      var perLine = Math.max(20, Math.floor((W - M - 96) / 7.3));
      var wrap = function (words) {
        var lines = [''];
        words.forEach(function (w) {
          var last = lines[lines.length - 1];
          if (last && (last + '  ' + w).length > perLine) lines.push(w);
          else lines[lines.length - 1] = last ? last + '  ' + w : w;
        });
        return lines;
      };
      var rows = modules.own.map(function (m) { return { name: m.name, lines: wrap(m.needs), hot: false }; });
      if (dep) {
        // the dependency's row has room for either version, so the grid never moves
        rows.push(depStage === 'dep' ? { name: dep.name + ' ' + dep.v1.version, lines: ['declares nothing'], hot: false }
          : { name: dep.name + ' ' + dep.v2.version, lines: wrap(dep.v2.needs), hot: depStage === 'dep-update' });
      }
      y += 6;
      if (at('own')) out.push(text('mx-label', M, y + 11, 'Written for this app, and what each declares'));
      y += 20;
      rows.forEach(function (row, i) {
        var isDep = dep && i === rows.length - 1, on = isDep ? !!depStage : at('own');
        if (on) out.push(text('mx-label-strong mx-mono', M, y + 11, row.name));
        row.lines.forEach(function (l) {
          if (on) out.push(text('mx-label mx-mono' + (row.hot ? ' mx-accent-text' : ''), M + 96, y + 11, l));
          y += 16;
        });
        y += 4;
      });
    }
    return '<svg xmlns="http://www.w3.org/2000/svg" width="' + r(W) + '" height="' + r(y + 4) + '" viewBox="0 0 ' + r(W) + ' ' + r(y + 4) +
      '" role="img" aria-label="One square for each module of the program, grouped by what it can reach">' + out.join('') + '</svg>';
  }

  var api = { reach: reach, REACH_STAGES: STAGES };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.figures = Object.assign(root.MarchExplainer.figures || {}, api);
})(typeof window !== 'undefined' ? window : globalThis);

// Tests for the third explainer, docs/one-owner.md: its heap simulation (sim-heap.js)
// and renderer (draw-ownership.js), its token and ledger figures (figures-ownership.js),
// the card states the page asks its figures for (chapters-ownership.js), and its static
// fallback images. They run on docs/_data/ownership.json when the generator has written
// it, and on the hand-written sample under fixtures/ until then.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
for (const f of ['scroll', 'story', 'rng', 'figures', 'figures-authority', 'figures-ownership', 'sim-cluster', 'sim-mailbox',
  'sim-release', 'sim-topology', 'sim-heap', 'draw', 'draw-authority', 'draw-ownership', 'chapters', 'chapters-authority',
  'chapters-ownership']) {
  require('../../docs/assets/explainer/' + f + '.js');
}
const ME = globalThis.MarchExplainer, F = ME.figures, H = ME.simHeap;
const ROOT = path.join(__dirname, '../..');
const DATA = path.join(ROOT, 'docs/_data/ownership.json'), SAMPLE = path.join(__dirname, 'fixtures/ownership.sample.json');
const generated = fs.existsSync(DATA);
const data = JSON.parse(fs.readFileSync(generated ? DATA : SAMPLE, 'utf8'));
const sample = JSON.parse(fs.readFileSync(SAMPLE, 'utf8'));
const PAGE = path.join(ROOT, 'docs/one-owner.md');
const count = (svg, re) => (svg.match(re) || []).length;
const { stage } = require('./fake-dom.js');
const fb = require('../../scripts/render-explainer-fallbacks.js');

// ── the sample follows the schema ──────────────────────────────────────────────

test('the sample carries the measured values of the brief', () => {
  assert.deepEqual(sample.tree, { depth: 4, leaves: 16, nodes: 15, cells: 31 });
  assert.equal(sample.runs.owned.allocs.inc_leaves, 0);
  assert.equal(sample.runs.shared.allocs.inc_leaves, 31);
  assert.equal(sample.runs.shared.incs.inc_leaves, 30);
  assert.equal(sample.runs.vault.allocs.inc_leaves, 31);
  assert.equal(sample.runs.parallel.allocs.tasks, 2);
  assert.equal(sample.contracts.caller.allocs.inc_leaves, 5);
  for (const k of ['ok', 'twice', 'never', 'affine_ok', 'affine_twice']) {
    const e = sample.linear[k], lines = e.excerpt.split('\n').length;
    assert.ok(e.binder >= 1 && e.binder <= lines, k);
    for (const u of e.uses) assert.ok(u >= 1 && u <= lines, k + ' use ' + u);
    assert.ok(/\bt\b/.test(e.excerpt.split('\n')[e.binder - 1]), k + ': the binder line names t');
  }
});

// ── the heap simulation ────────────────────────────────────────────────────────

const cfg = () => ME.heapConfig(data);

test('heap: the tree is the generated one, and the walk is pre-order over every cell once', () => {
  const s = H.create(cfg());
  assert.equal(s.cells.length, data.tree.cells);
  assert.equal(s.cells.filter((c) => H.children(s, s.cells.indexOf(c)).length === 0).length, data.tree.leaves);
  const order = H.preorder(s, 0);
  assert.equal(order.length, data.tree.cells);
  assert.equal(new Set(order).size, data.tree.cells, 'each cell once');
  assert.deepEqual(order.slice(0, 6), [0, 1, 3, 7, 15, 16]);   // root, left, left, left, leaf, leaf
  const left = H.preorder(s, 1), right = H.preorder(s, 2);
  assert.equal(left.length + right.length + 1, data.tree.cells);
  assert.ok(left.every((i) => !right.includes(i)));
});

test('heap: owned rewrites every cell in place and allocates nothing', () => {
  const s = ME.buildState('heap', 'owned', data);
  assert.equal(s.counters.allocs, data.runs.owned.allocs.inc_leaves);
  assert.equal(s.counters.allocs, 0);
  assert.equal(s.counters.incs, 0);
  assert.ok(s.cells.every((c) => c.rewritten && c.rc === 1));
  assert.equal(H.progress(s).done, true);
  assert.equal(s.holders, 1);
});

test('heap: shared copies the whole tree and bumps a count for every child handed down', () => {
  const s = ME.buildState('heap', 'shared', data);
  assert.equal(s.counters.allocs, data.runs.shared.allocs.inc_leaves);
  assert.equal(s.counters.allocs, data.tree.cells);
  assert.equal(s.counters.incs, data.runs.shared.incs.inc_leaves);
  assert.equal(s.copies.filter(Boolean).length, data.tree.cells);
  assert.ok(s.cells.every((c) => c.rc === 2 && !c.rewritten));
  assert.equal(s.holders, 2);
});

test('heap: the Vault run is the shared run with a different second holder', () => {
  const v = ME.buildState('heap', 'vault', data), sh = ME.buildState('heap', 'shared', data);
  assert.equal(v.counters.allocs, data.runs.vault.allocs.inc_leaves);
  assert.equal(v.counters.allocs, sh.counters.allocs);
  assert.equal(v.counters.incs, sh.counters.incs);
  assert.equal(v.mode, 'vault');
  assert.ok(cfg().view.vaultNote.startsWith('No copies found'));
});

test('heap: parallel walks the two halves at once on two tasks, in place', () => {
  const s = ME.buildState('heap', 'parallel', data);
  assert.equal(s.counters.allocs, 0);
  assert.equal(s.counters.tasks, data.runs.parallel.allocs.tasks);
  assert.equal(s.counters.plumbing, data.runs.parallel.allocs.plumbing);
  assert.equal(s.cursors.length, 2);
  assert.ok(s.cells.every((c) => c.rewritten));
  // both cursors move at the same time
  const live = H.create(cfg());
  H.start(live, 'parallel');
  H.advance(live, live.cfg.holdS + live.cfg.visitS * 3);
  const visited = live.cells.filter((c) => c.visitedAt !== null).length;
  assert.ok(visited >= 6 && visited <= 8, 'two cursors, three cells each: ' + visited);
  assert.ok(live.cells[0].visitedAt === null, 'the root is rebuilt last');
});

test('heap: the cursor waits, then visits one cell per visit_s, and the run ends', () => {
  const s = H.create(cfg());
  H.start(s, 'owned');
  H.advance(s, s.cfg.holdS - 0.05);
  assert.equal(H.progress(s).visited, 0, 'nothing before the hold');
  H.advance(s, 0.1);
  assert.equal(H.progress(s).visited, 1);
  H.advance(s, s.cfg.visitS * 10);
  assert.ok(Math.abs(H.progress(s).visited - 11) <= 1);
  H.advance(s, H.runLength(s, 'owned'));
  assert.equal(H.progress(s).done, true);
  assert.equal(H.cursorAt(s, s.cursors[0]), null, 'a finished cursor is gone');
});

test('heap: every card state builds, and the same card is the same picture twice', () => {
  for (const st of ME.HEAP_STATES) {
    const a = ME.buildState('heap', st, data), b = ME.buildState('heap', st, data);
    const key = (s) => JSON.stringify([s.t, s.mode, s.cells, s.copies, s.counters, s.holders]);
    assert.equal(key(a), key(b), st);
  }
  assert.throws(() => ME.buildState('heap', 'nope', data), /unknown state/);
  assert.throws(() => H.start(H.create(cfg()), 'nope'), /unknown mode/);
});

test('heap: moving on to the next card restarts inc_leaves on the simulation on screen', () => {
  const s = ME.buildState('heap', 'owned', data), t = s.t;
  assert.equal(ME.liveTransition('heap', 'owned', 'shared', s, data), true);
  assert.equal(s.t, t, 'nothing is rebuilt');
  assert.equal(s.mode, 'shared');
  assert.equal(s.counters.allocs, 0, 'the copy is not there yet');
  assert.equal(s.cells[0].rc, 2, 'the second holder is');
  assert.equal(ME.liveTransition('heap', 'owned', 'parallel', s, data), false, 'only the next card');
  H.advance(s, H.runLength(s, 'shared'));
  assert.equal(s.counters.allocs, data.tree.cells);
});

test('heap: the counters name what each card is about', () => {
  const names = (st) => ME.heapCounters(ME.buildState('heap', st, data)).map((c) => c[0]);
  assert.deepEqual(names('built'), ['Cells', 'Allocated by inc_leaves', 'Holders']);
  assert.ok(names('shared').includes('Count increments'));
  assert.ok(names('parallel').includes('Tasks') && names('parallel').includes('Other cells'));
  const hot = ME.heapCounters(ME.buildState('heap', 'shared', data)).find((c) => c[0] === 'Allocated by inc_leaves');
  assert.equal(hot[1], data.tree.cells); assert.equal(hot[2], true);
});

// A canvas context that records what was drawn.
function fakeCtx() {
  const calls = { fillRect: 0, strokeRect: 0, arc: 0, fill: 0, fillText: [] };
  const noop = () => {};
  return {
    calls, font: '', fillStyle: '', strokeStyle: '', lineWidth: 1, globalAlpha: 1, textAlign: 'left',
    fillRect: () => { calls.fillRect += 1; }, strokeRect: () => { calls.strokeRect += 1; },
    arc: () => { calls.arc += 1; }, fill: () => { calls.fill += 1; }, fillText: (t) => { calls.fillText.push(String(t)); },
    clearRect: noop, beginPath: noop, closePath: noop, moveTo: noop, lineTo: noop, stroke: noop,
    save: noop, restore: noop, rect: noop, clip: noop, setLineDash: noop, setTransform: noop,
    measureText: (t) => ({ width: String(t).length * 6 }),
  };
}
const colors = { ink: '#fff', dim: '#888', accent: '#f00' };

test('heap drawing: every state draws at both design sizes, with a count on every cell', () => {
  for (const st of ME.HEAP_STATES) {
    for (const width of [900, 360]) {
      const ctx = fakeCtx(), d = ME.draw.heapDesign({ width }), s = ME.buildState('heap', st, data);
      assert.doesNotThrow(() => ME.draw.heap(ctx, s, d, colors), st);
      const digits = ctx.calls.fillText.filter((t) => /^[12]$/.test(t)).length;
      assert.ok(digits >= data.tree.cells, st + ' at ' + width + ': ' + digits + ' counts');
      assert.ok(ctx.calls.fillText.some((t) => t === 't'), 'the holder t');
    }
  }
  const vault = fakeCtx();
  ME.draw.heap(vault, ME.buildState('heap', 'vault', data), ME.draw.heapDesign({ width: 900 }), colors);
  assert.ok(vault.calls.fillText.some((t) => t.startsWith('Vault')), 'the Vault is a holder');
  assert.ok(vault.calls.fillText.some((t) => t.startsWith('static report (--why-copies): No copies found')), 'the static report line');
  const par = fakeCtx();
  ME.draw.heap(par, ME.buildState('heap', 'parallel', data), ME.draw.heapDesign({ width: 900 }), colors);
  assert.ok(par.calls.fillText.includes('task 1') && par.calls.fillText.includes('task 2'));
});

test('heap drawing: the layout fits its design size, and the copy goes beside or below', () => {
  for (const width of [900, 360]) {
    const d = ME.draw.heapDesign({ width }), s = ME.buildState('heap', 'shared', data);
    const L = ME.draw.heapLayout(s, d.width);
    const inside = (b) => b.x >= 0 && b.x + b.w <= d.width + 0.5 && b.y >= 0 && b.y + b.h <= d.height;
    for (const b of L.cells) {
      assert.ok(inside(b), JSON.stringify(b));
      assert.ok(inside({ x: b.x + d.copy.dx, y: b.y + d.copy.dy, w: b.w, h: b.h }), 'copy of ' + JSON.stringify(b));
    }
    for (const lane of L.lanes) assert.ok(inside(lane), JSON.stringify(lane));
    assert.ok(width < 520 ? d.copy.dy > 0 && d.copy.dx === 0 : d.copy.dx > 0 && d.copy.dy === 0);
    // leaves do not overlap
    const leaves = L.cells.filter((b, i) => H.children(s, i).length === 0).sort((a, b) => a.x - b.x);
    for (let i = 1; i < leaves.length; i++) assert.ok(leaves[i].x >= leaves[i - 1].x + leaves[i - 1].w, 'leaf overlap at ' + width);
    assert.ok(d.digit >= 9 && d.small >= 10, 'legible type');
  }
});

// ── the token ──────────────────────────────────────────────────────────────────

const tokenSvg = (st, width) => F.token(ME.tokenEntry(data, st), { width: width || 560, kind: st.split('-')[0] });
const tokens = (svg) => [...svg.matchAll(/<circle class="mx-token ([\w-]+)"/g)].map((m) => m[1]);

test('token: one token for the binder and one per use, and the verdict\'s accent', () => {
  for (const st of ME.TOKEN_STATES) {
    const e = ME.tokenEntry(data, st), svg = tokenSvg(st), ts = tokens(svg);
    const extra = e.verdict === 'never' || (e.verdict === 'ok' && e.kind === 'affine') ? 1 : 0;
    assert.equal(ts.length, 1 + e.uses.length + extra, st);
    assert.equal(ts[0], 'mx-held', st + ': the binder holds it');
    assert.equal(ts.filter((c) => c === 'mx-hot').length, e.verdict === 'ok' ? 0 : 1, st + ': one accent token at most');
    assert.equal(count(svg, /<text class="mx-codeline/g), e.excerpt.replace(/\n+$/, '').split('\n').length, st + ': every line');
    assert.ok(svg.includes('t</text>'));
  }
});

test('token: what each verdict says', () => {
  assert.ok(tokenSvg('linear-twice').includes('used again'));
  assert.ok(tokenSvg('linear-twice').includes('[linear_used_twice]'));
  assert.ok(tokenSvg('linear-never').includes('never used'));
  assert.ok(tokenSvg('affine-ok').includes('dropped (allowed)'));
  assert.ok(tokenSvg('linear-ok').includes('consumed exactly once'));
  assert.ok(tokens(tokenSvg('affine-twice')).slice(-1)[0] === 'mx-hot');
  assert.equal(count(tokenSvg('affine-ok'), /mx-hlbar/g), 0, 'nothing is pointed at when it passes');
  assert.equal(count(tokenSvg('linear-twice'), /mx-hlbar/g), 1);
  const dimmed = count(tokenSvg('linear-twice'), /mx-off/g), lines = data.linear.twice.excerpt.trim().split('\n').length;
  assert.ok(dimmed > 0 && dimmed < lines, 'the lines not about t are dimmed');
});

test('token: the figure fits its width on a desk and on a phone, and a hollow token keeps its letter readable', () => {
  for (const width of [560, 380]) {
    for (const st of ME.TOKEN_STATES) {
      const svg = tokenSvg(st, width), size = ME.naturalSize([{ svg }]);
      assert.ok(size.w <= width + 0.5, st + ' at ' + width + ' is ' + size.w);
      assert.ok(size.h > 60);
      assert.ok(Number(/font-size="(\d+)"/.exec(svg)[1]) >= 9, 'legible code');
    }
  }
  const svg = tokenSvg('linear-twice');
  assert.equal(count(svg, /mx-token-text mx-hollow/g), tokens(svg).filter((c) => c === 'mx-spent').length);
  assert.throws(() => F.token({ excerpt: 'x', verdict: 'maybe', binder: 1, uses: [] }, { width: 500 }), /unknown verdict/);
});

test('token: the figure mounts, changes state in place, and refuses an unknown one', () => {
  const host = stage(680), fig = ME.figureForTest('token')(host, data);
  fig.setState('linear-ok', 0);
  assert.ok(host.innerHTML.includes('mx-held'));
  fig.setState('linear-twice', 0);
  assert.ok(host.innerHTML.includes('mx-hot'));
  assert.throws(() => fig.setState('nope', 0), /unknown state/);
  const frame = ME.tokenFrame(data, 560);
  assert.ok(frame.w <= 560 && frame.h > 100);
});

// ── the contract ───────────────────────────────────────────────────────────────

const ledger = (st, width) => F.contract(data.contracts, { width: width || 560, stage: st });

test('contract: one column per function in the state, with the right name', () => {
  const names = (st) => [...ledger(st).matchAll(/mx-label-strong mx-mono[^"]*" [^>]*>([\w]+)/g)].map((m) => m[1]);
  assert.deepEqual(names('candidate'), ['inc_leaves']);
  assert.deepEqual(names('pinned'), ['inc_leaves']);
  assert.deepEqual(names('bare'), ['width_bare']);
  assert.deepEqual(names('transient'), ['width']);
  assert.deepEqual(names('boxed'), ['record']);
  assert.deepEqual(names('caller'), ['inc_leaves', 'inc_leaves']);
  assert.deepEqual(names('bound'), ['inc_leaves']);
  assert.equal(F.attributed(data.contracts.bare.excerpt), 'width_bare');
  assert.equal(F.attributed('fn a() do\nend\n\nfn b() do\nend'), 'a');
});

test('contract: the lines and their labels', () => {
  assert.equal(count(ledger('candidate'), /mx-contract /g), 0, 'no contract yet');
  assert.ok(ledger('candidate').includes(data.contracts.candidate.message.slice(0, 30)));
  assert.ok(ledger('candidate').includes('@[no_alloc]'));
  for (const st of ['pinned', 'bare', 'boxed', 'caller']) {
    assert.equal(count(ledger(st), /mx-contract /g), 1, st);
    assert.ok(ledger(st).includes('>allowed: 0<'), st);
  }
  assert.ok(ledger('transient').includes('>kept: 0<'));
  assert.ok(ledger('transient').includes('>made 1, kept 0<'));
  assert.equal(count(ledger('bound'), /mx-contract /g), 2);
  assert.equal(count(ledger('bound'), /mx-contract mx-design/g), 1);
  assert.ok(ledger('bound').includes('(design, not shipped)'));
});

test('contract: a column over the line is the accent, with the compiler\'s reason; a passing one has a tick', () => {
  for (const st of ['bare', 'boxed']) {
    const svg = ledger(st);
    assert.equal(count(svg, /mx-bar mx-over/g), 1, st);
    assert.ok(svg.includes(data.contracts[st].reason.replace(/`/g, '`').slice(0, 20)), st);
    assert.ok(svg.includes('✗'), st);
  }
  assert.ok(ledger('boxed').includes('(Hit)'));
  for (const st of ['pinned', 'transient', 'caller', 'bound']) {
    assert.equal(count(ledger(st), /mx-over/g), 0, st);
    assert.ok(ledger(st).includes('✓'), st);
  }
  assert.equal(count(ledger('candidate'), /✓|✗/g), 0);
  const caller = ledger('caller');
  assert.equal(count(caller, /mx-bar mx-ghost/g), 1);
  assert.ok(caller.includes('with a sharing caller: ' + data.contracts.caller.allocs.inc_leaves));
});

test('contract: every state fits its width, and the figure mounts', () => {
  for (const width of [560, 380]) {
    for (const st of ME.CONTRACT_STATES) {
      const size = ME.naturalSize([{ svg: ledger(st, width) }]);
      assert.ok(size.w <= width + 0.5 && size.h > 150, st + ' at ' + width + ': ' + JSON.stringify(size));
    }
  }
  assert.throws(() => ledger('nope'), /unknown stage/);
  const host = stage(680), fig = ME.figureForTest('contract')(host, data);
  fig.setState('pinned', 0);
  assert.ok(host.innerHTML.includes('mx-contract'));
  assert.throws(() => fig.setState('nope', 0), /unknown state/);
});

// ── the page and its data ──────────────────────────────────────────────────────

test('every card on the page asks its figure for a state the figure has', { skip: fs.existsSync(PAGE) ? false : 'docs/one-owner.md is not written yet' }, () => {
  const page = fs.readFileSync(PAGE, 'utf8');
  const known = { heap: ME.HEAP_STATES, token: ME.TOKEN_STATES, contract: ME.CONTRACT_STATES };
  const body = page.replace(/<!--[\s\S]*?-->/g, '');
  const sections = body.split('<section class="mx-scrolly"').slice(1);
  assert.ok(sections.length >= 3);
  let cards = 0;
  for (const sec of sections) {
    const fig = /data-figure="([^"]+)"/.exec(sec)[1];
    assert.ok(known[fig], 'no such figure ' + fig);
    assert.ok(ME.figureForTest(fig), fig + ' is registered');
    for (const m of sec.split('</section>')[0].matchAll(/class="mx-step" data-state="([^"]+)"/g)) {
      assert.ok(known[fig].includes(m[1]), fig + ' has no state ' + m[1]);
      cards += 1;
    }
  }
  assert.ok(cards >= 12);
  for (const m of page.matchAll(/assets\/explainer\/fallback\/([\w-]+\.svg)/g)) {
    assert.ok(fs.existsSync(path.join(ROOT, 'docs/assets/explainer/fallback', m[1])), m[1]);
  }
  assert.ok(page.includes('figures="ownership"'));
});

test('the fallback posters stand alone and are what the renderers produce today', () => {
  const all = fb.renderOwnership(data);
  assert.deepEqual(Object.keys(all).sort(), ['contract', 'heap', 'token']);
  for (const [name, svg] of Object.entries(all)) {
    assert.ok(svg.startsWith('<svg'), name);
    assert.equal(svg.includes('var('), false, name + ' uses a page variable an <img> cannot resolve');
    assert.ok(svg.includes(fb.PALETTE.paper), name + ' has no background');
    const style = (svg.match(/<style>([\s\S]*?)<\/style>/) || [, ''])[1];
    for (const m of svg.matchAll(/class="([^"]+)"/g)) {
      for (const cls of m[1].split(' ')) assert.ok(style.includes('.' + cls), `${name}: no style for .${cls}`);
    }
    const file = path.join(ROOT, 'docs/assets/explainer/fallback', name + '.svg');
    assert.ok(fs.existsSync(file), name + '.svg is missing; run node scripts/render-explainer-fallbacks.js');
    if (generated) assert.equal(fs.readFileSync(file, 'utf8'), svg, name + '.svg is stale; run node scripts/render-explainer-fallbacks.js');
  }
  // the heap poster is the shared run: the copy tree's cells are drawn in the accent
  const heap = all.heap;
  assert.ok(count(heap, new RegExp('<path [^>]*stroke="' + fb.PALETTE.accent + '"', 'g')) >= data.tree.cells, 'a copy cell per cell');
  assert.ok(heap.includes('>sum_leaves(t)<'));
  assert.equal(fb.OWNERSHIP_POSTER.heap, 'shared');
});

test('the older pages\' fallback images are untouched by the new renderer', () => {
  const page1 = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/_data/explainer.json'), 'utf8'));
  const authority = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/_data/authority.json'), 'utf8'));
  const images = Object.assign({}, fb.renderAll(page1), fb.renderAuthority(authority));
  for (const [name, svg] of Object.entries(images)) {
    assert.equal(fs.readFileSync(path.join(ROOT, 'docs/assets/explainer/fallback', name + '.svg'), 'utf8'), svg, name);
  }
});

test('the data tells one story: one owner means no copy, a second holder means a whole one', () => {
  const r = data.runs;
  assert.equal(r.owned.allocs.inc_leaves, 0);
  assert.equal(r.shared.allocs.inc_leaves, data.tree.cells);
  assert.equal(r.vault.allocs.inc_leaves, data.tree.cells);
  assert.equal(r.parallel.allocs.inc_leaves, 0);
  assert.ok(r.owned.why_copies.startsWith('No copies found'));
  assert.ok(r.shared.why_copies.includes('[copy_shared]'));
  assert.ok(r.vault.why_copies.startsWith('No copies found'), 'the static view cannot see the Vault');
  assert.equal(r.shared.incs.inc_leaves, data.tree.nodes * 2);
  assert.equal(data.linear.twice.exit, 1); assert.equal(data.linear.never.exit, 1); assert.equal(data.linear.ok.exit, 0);
  assert.equal(data.contracts.bare.exit, 1); assert.equal(data.contracts.pinned.exit, 0); assert.equal(data.contracts.caller.exit, 0);
  assert.ok(data.contracts.caller.allocs.inc_leaves > 0, 'the contract holds while a sharing caller still sees allocation');
});

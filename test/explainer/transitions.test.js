// Tests for how figures change from one card to the next (docs/assets/explainer/chapters.js).
//
// An SVG figure is not replaced when its card changes: the new drawing is compared with
// the old one, element by element. What is in both stays put (and may change colour),
// what is new enters, what is gone leaves. A simulation is not rebuilt when the reader
// moves to the next card: the next card's event happens to the simulation on screen.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
for (const f of ['scroll', 'story', 'rng', 'figures', 'sim-cluster', 'sim-mailbox', 'sim-release', 'draw', 'chapters']) {
  require('../../docs/assets/explainer/' + f + '.js');
}
const ME = globalThis.MarchExplainer;
const data = JSON.parse(fs.readFileSync(path.join(__dirname, '../../docs/_data/explainer.json'), 'utf8'));
const used = (slots) => slots.filter((x) => x !== null).length;

// ── SVG figures ─────────────────────────────────────────────────────────────────
test('parts: every drawn element gets a key from where it is, not from how it looks', () => {
  const parts = ME.svgParts('<svg width="10" height="10"><rect class="mx-cell" x="1" y="2" width="3" height="4"/>' +
    '<text class="mx-label" x="5" y="6">Shop</text><line class="mx-line" x1="0" y1="0" x2="9" y2="9"/>' +
    '<circle class="mx-ping" cx="4" cy="4" r="2"/></svg>');
  assert.deepEqual(parts.map((p) => p.tag), ['rect', 'text', 'line', 'circle']);
  assert.equal(parts[0].cls, 'mx-cell');
  assert.equal(parts[1].text, 'Shop');
  const lit = ME.svgParts('<svg><rect class="mx-cell mx-lit" x="1" y="2" width="3" height="4"/></svg>');
  assert.equal(lit[0].key, parts[0].key);            // same place, different class: the same element
  assert.equal(new Set(parts.map((p) => p.key)).size, 4);
});

test('parts: two elements in the same place still get different keys', () => {
  const parts = ME.svgParts('<svg><rect class="a" x="1" y="1" width="2" height="2"/><rect class="b" x="1" y="1" width="2" height="2"/></svg>');
  assert.notEqual(parts[0].key, parts[1].key);
});

test('diff: lighting a cell is a recolour, not a redraw', () => {
  const F = ME.figures, sm = data.state_map;
  const before = ME.svgParts(F.stateMap(sm, { width: 680, lit: 3 }));
  const after = ME.svgParts(F.stateMap(sm, { width: 680, lit: 4 }));
  const d = ME.diffParts(before, after);
  assert.equal(d.enter.length, 0);
  assert.equal(d.exit.length, 0);
  assert.equal(d.recolour.length, 1);
  assert.equal(d.recolour[0].cls, 'mx-cell mx-lit');
});

test('diff: the fan-out only ever adds between its stages, in the wide layout', () => {
  const F = ME.figures, stages = ['source', 'modules', 'states', 'functions'];
  for (let i = 1; i < stages.length; i++) {
    const a = ME.svgParts(F.fanOut(data.order, { width: 680, stage: stages[i - 1] }));
    const b = ME.svgParts(F.fanOut(data.order, { width: 680, stage: stages[i] }));
    const d = ME.diffParts(a, b);
    assert.equal(d.exit.length, 0, stages[i] + ' removes something the reader was looking at');
    assert.ok(d.enter.length > 0, stages[i]);
  }
  const last = ME.diffParts(ME.svgParts(F.fanOut(data.order, { width: 680, stage: 'states' })),
    ME.svgParts(F.fanOut(data.order, { width: 680, stage: 'functions' })));
  assert.equal(last.enter.filter((p) => p.cls === 'mx-fn').length, data.order.functions);
});

test('diff: going back removes exactly what going forward added', () => {
  const F = ME.figures;
  const a = ME.svgParts(F.fanOut(data.order, { width: 680, stage: 'modules' }));
  const b = ME.svgParts(F.fanOut(data.order, { width: 680, stage: 'functions' }));
  const fwd = ME.diffParts(a, b), back = ME.diffParts(b, a);
  assert.deepEqual(back.exit.map((p) => p.key).sort(), fwd.enter.map((p) => p.key).sort());
  assert.equal(back.enter.length, 0);
});

test('fan-out views: the declaration stays on screen through the generation cards', () => {
  const slots = (state, w) => ME.fanOutView(state, data, w).map((s) => s.id);
  assert.deepEqual(slots('source', 680), ['code']);
  assert.deepEqual(slots('project', 680), ['code', 'strip-Shop', 'strip-Stock', 'strip-Ledger']);
  assert.deepEqual(slots('modules', 680), ['code']);
  assert.deepEqual(slots('typecheck', 680), ['code', 'strip-Stock']);
  assert.deepEqual(slots('hosts', 680), ['hosts']);
  // a phone's stage has no room for both, so the strips stand alone there
  assert.deepEqual(slots('project', 343), ['strip-Shop', 'strip-Stock', 'strip-Ledger']);
  assert.deepEqual(slots('typecheck', 343), ['strip-Stock']);
  assert.throws(() => ME.fanOutView('nope', data, 680), /unknown state/);
});

// The figure itself, on a stand-in DOM: elements that stay are the SAME elements.
const { stage } = require('./fake-dom.js');
const cells = (host) => {
  const out = [];
  (function walk(el) { if (el.tag === 'rect') out.push(el); el.children.forEach(walk); })(host);
  return out;
};

test('state map: changing card keeps every cell element and only changes classes', () => {
  const host = stage(680), fig = ME.figureForTest('state-map')(host, data);
  fig.setState('empty', 0);
  const before = cells(host);
  assert.equal(before.length, data.state_map.cells);
  fig.setState('all', 0);
  const after = cells(host);
  assert.equal(after.length, before.length);
  assert.ok(after.every((el, i) => el === before[i]), 'a cell was replaced instead of recoloured');
  assert.equal(after.filter((el) => el.className === 'mx-cell mx-lit').length, data.state_map.reachable.length);
});

test('fan-out: the source bars are the same elements from card to card, and new ones enter', () => {
  const host = stage(680), fig = ME.figureForTest('fan-out')(host, data);
  fig.setState('source', 0);
  const bars = cells(host).filter((el) => el.className === 'mx-srcline');
  assert.equal(bars.length, data.order.source.length);
  fig.setState('functions', 0);
  const now = cells(host);
  assert.ok(bars.every((el) => now.includes(el)), 'the declaration was redrawn');
  const fns = now.filter((el) => el.className.split(' ').includes('mx-fn'));
  assert.equal(fns.length, data.order.functions);
  assert.ok(fns.every((el) => el.className.split(' ').includes('mx-enter')), 'new squares should animate in');
  assert.ok(bars.every((el) => !el.className.split(' ').includes('mx-enter')), 'what stays should not animate');
});

test('fan-out: a strip that stays between two cards takes the new card\'s caption', () => {
  const host = stage(680), fig = ME.figureForTest('fan-out')(host, data);
  fig.setState('project', 0);
  assert.ok(host.innerHTML.includes('<p class="mx-caption">Stock</p>'));
  fig.setState('typecheck', 0);                       // straight from one to the other: the Stock strip stays
  assert.ok(host.innerHTML.includes('Stock, after it has received the order'));
  assert.equal(host.innerHTML.includes('<p class="mx-caption">Stock</p>'), false);
});

test('fan-out: the first drawing does not animate', () => {
  const host = stage(680), fig = ME.figureForTest('fan-out')(host, data);
  fig.setState('functions', 0);
  assert.equal(cells(host).filter((el) => el.className.split(' ').includes('mx-enter')).length, 0);
});

// ── simulations ─────────────────────────────────────────────────────────────────
const CLUSTER = ['steady', 'full', 'stock-crash', 'silent', 'ledger-stop', 'return', 'no-offer'];
const books = (s) => s.hosts.map((h, i) => (h.books ? i : -1)).filter((i) => i >= 0);
const holds = {
  steady: (s) => assert.ok(s.hosts.every((h) => h.status === 'up')),
  full: (s) => { assert.ok(used(s.ledger.slots) >= 0.9 * s.ledger.slots.length); assert.ok(s.counters.refused > 0); },
  'stock-crash': (s) => { assert.equal(s.hosts[0].status, 'dead'); assert.ok(s.counters.cancelled > 0);
    assert.ok(s.hosts.slice(1).every((h) => h.status === 'up')); },
  silent: (s) => { assert.ok(['suspect', 'dead'].includes(s.hosts[0].status)); assert.ok(used(s.hosts[0].stock) > 0);
    assert.equal(s.counters.cancelled, 0); },
  'ledger-stop': (s) => { const b = books(s); assert.equal(s.hosts[b[b.length - 1]].status, 'dead'); assert.equal(s.ledger.host, b[0]); },
  'return': (s) => { const last = s.hosts.length - 1; assert.equal(s.hosts[last].status, 'up');
    assert.ok(s.hosts[last].incarnation >= 2); assert.notEqual(s.ledger.host, last); },
  'no-offer': (s) => { assert.equal(s.ledger.host, null); assert.ok(s.counters.refused > 0); },
};
// how long after arriving on a card its picture must hold
const SETTLE = { full: 6, 'stock-crash': 5, silent: 7, 'ledger-stop': 8, 'return': 5, 'no-offer': 4 };

test('cluster: moving to the next card happens to the simulation on screen', () => {
  for (let i = 1; i < CLUSTER.length; i++) {
    const from = CLUSTER[i - 1], to = CLUSTER[i];
    const s = ME.buildState('cluster', from, data), t0 = s.t, started = s.counters.started;
    assert.equal(ME.liveTransition('cluster', from, to, s, data), true, `${from} -> ${to}`);
    ME.runLive('cluster', s, SETTLE[to]);
    assert.ok(s.t > t0, 'the same simulation carried on');
    holds[to](s);
    assert.ok(started >= 0);
  }
});

test('cluster: a live arrival ends in the same kind of picture as landing on the card', () => {
  for (let i = 1; i < CLUSTER.length; i++) {
    const to = CLUSTER[i];
    holds[to](ME.buildState('cluster', to, data));           // landing directly
  }
});

test('cluster: going back, or skipping a card, is not done live', () => {
  const s = ME.buildState('cluster', 'silent', data);
  assert.equal(ME.liveTransition('cluster', 'silent', 'stock-crash', s, data), false);
  assert.equal(ME.liveTransition('cluster', 'steady', 'silent', ME.buildState('cluster', 'steady', data), data), false);
  assert.equal(ME.liveTransition('cluster', 'steady', 'nope', ME.buildState('cluster', 'steady', data), data), false);
});

test('cluster: the counters start again when a card\'s event happens, and still add up', () => {
  const s = ME.buildState('cluster', 'full', data);
  assert.ok(s.counters.refused > 0);
  ME.liveTransition('cluster', 'full', 'stock-crash', s, data);
  ME.runLive('cluster', s, SETTLE['stock-crash']);
  const c = s.counters;
  assert.equal(c.refused, 0);                               // the refusals belonged to the last card
  assert.equal(c.started, c.completed + c.cancelled + c.refused + s.sessions.length);
});

const MAILBOX = ['idle', 'one-at-a-time', 'sessions', 'crash', 'restart', 'lost-total'];
test('mailbox: each card carries on from the one before', () => {
  let s = ME.buildState('mailbox', 'idle', data);
  for (let i = 1; i < MAILBOX.length; i++) {
    const t0 = s.t;
    assert.equal(ME.liveTransition('mailbox', MAILBOX[i - 1], MAILBOX[i], s, data), true, MAILBOX[i]);
    if (MAILBOX[i] === 'crash') { assert.equal(s.status, 'crashed'); ME.runLive('mailbox', s, 30); assert.equal(s.status, 'crashed'); }
    else ME.runLive('mailbox', s, 4);
    assert.ok(s.t > t0);
  }
  assert.equal(s.status, 'up');
  assert.equal(s.restarts, 1);
  assert.ok(s.total > 0);
});

test('mailbox: going back is not done live', () => {
  const s = ME.buildState('mailbox', 'restart', data);
  assert.equal(ME.liveTransition('mailbox', 'restart', 'crash', s, data), false);
});

// Tests for docs/assets/explainer/chapters.js: each chapter's figure, state by state.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
require('../../docs/assets/explainer/scroll.js');
require('../../docs/assets/explainer/story.js');
require('../../docs/assets/explainer/figures.js');
require('../../docs/assets/explainer/rng.js');
require('../../docs/assets/explainer/sim-cluster.js');
require('../../docs/assets/explainer/sim-mailbox.js');
require('../../docs/assets/explainer/sim-release.js');
require('../../docs/assets/explainer/draw.js');
require('../../docs/assets/explainer/chapters.js');
const ME = globalThis.MarchExplainer;
const data = JSON.parse(fs.readFileSync(path.join(__dirname, '../../docs/_data/explainer.json'), 'utf8'));
const count = (svg, cls) => (svg.match(new RegExp('class="' + cls + '"', 'g')) || []).length;

// A stage to mount into (test/explainer/fake-dom.js): read back what the figure built.
const { stage } = require('./fake-dom.js');
function mount(name, width) {
  const host = stage(width);
  const fig = ME.figureForTest(name)(host, data);
  return { fig, host, svg: () => host.innerHTML };
}

test('state map: empty shows every cell and none lit', () => {
  const m = mount('state-map'); m.fig.setState('empty', 0);
  assert.equal(count(m.svg(), 'mx-cell'), data.state_map.cells);
  assert.equal(count(m.svg(), 'mx-cell mx-lit'), 0);
});

test('state map: all lights exactly the reachable cells', () => {
  const m = mount('state-map'); m.fig.setState('all', 0);
  assert.equal(count(m.svg(), 'mx-cell mx-lit'), data.state_map.reachable.length);
});

test('state map: path, without motion, ends with every reachable cell lit', () => {
  const was = ME.reducedMotion; ME.reducedMotion = () => true;
  try {
    const m = mount('state-map'); m.fig.setState('path', 0);
    assert.equal(count(m.svg(), 'mx-cell mx-lit'), data.state_map.reachable.length);
  } finally { ME.reducedMotion = was; }
});

test('state map: each wrong program marks one cell, whatever state came before', () => {
  for (const state of ['skip', 'offer', 'turn']) {
    const m = mount('state-map'); m.fig.setState(state, 0);       // straight to it, no earlier state
    assert.equal(count(m.svg(), 'mx-cell mx-wrong'), 1, state);
    assert.equal(count(m.svg(), 'mx-cell') + count(m.svg(), 'mx-cell mx-lit') + 1, data.state_map.cells, state);
  }
});

test('state map: an unknown state is an error the story can report', () => {
  const m = mount('state-map');
  assert.throws(() => m.fig.setState('nope', 0), /unknown state/);
});

test('state map: repeating a state does not redraw from scratch', () => {
  const m = mount('state-map'); m.fig.setState('all', 0);
  const first = m.svg(); m.fig.setState('all', 0.5);
  assert.equal(m.svg(), first);
});

// ── chapter 2: the fan-out ──────────────────────────────────────────────────────
const total = (svg, classes) => classes.reduce((n, c) => n + count(svg, c), 0);

test('fan-out: source shows the declaration and nothing generated', () => {
  const m = mount('fan-out'); m.fig.setState('source', 0);
  assert.equal(count(m.svg(), 'mx-srcline'), data.order.source.length);
  assert.equal(count(m.svg(), 'mx-fn') + count(m.svg(), 'mx-state'), 0);
});

test('fan-out: project shows one strip per role, a segment per step', () => {
  const m = mount('fan-out'); m.fig.setState('project', 0);
  const steps = Object.values(data.order.strips).reduce((n, s) => n + s.length, 0);
  assert.equal(count(m.svg(), 'mx-seg'), steps);
  for (const role of data.order.roles) assert.ok(m.svg().includes('>' + role + '<'), role);
});

test('fan-out: modules, then every state type and function', () => {
  const m = mount('fan-out'); m.fig.setState('modules', 0);
  assert.equal(count(m.svg(), 'mx-fn') + count(m.svg(), 'mx-state'), 0);
  assert.ok(m.svg().includes('Order_Run'));
  m.fig.setState('functions', 0);
  // what has just been added carries `mx-enter` beside its own class while it animates in
  const has = (cls) => (m.svg().match(new RegExp('class="' + cls + '( mx-enter)?"', 'g')) || []).length;
  assert.equal(has('mx-state'), data.order.linear_states);
  assert.equal(has('mx-fn'), data.order.functions);
});

test('fan-out: typecheck shows Stock stopped at its choice', () => {
  const m = mount('fan-out'); m.fig.setState('typecheck', 0);
  assert.equal(count(m.svg(), 'mx-seg mx-done'), 1);
  assert.equal(count(m.svg(), 'mx-seg mx-next'), 1);
  assert.equal(total(m.svg(), ['mx-seg', 'mx-seg mx-done', 'mx-seg mx-next']), data.order.strips.Stock.length);
});

test('fan-out: hosts shows the four machines', () => {
  const m = mount('fan-out'); m.fig.setState('hosts', 0);
  assert.equal(count(m.svg(), 'mx-host'), 4);
});

test('fan-out: every card state draws something, in any order', () => {
  for (const state of ['hosts', 'grants', 'main', 'typecheck', 'functions', 'modules', 'project', 'source']) {
    const m = mount('fan-out', 343); m.fig.setState(state, 0);
    assert.ok(m.svg().includes('<svg'), state);
  }
  assert.throws(() => mount('fan-out').fig.setState('nope', 0), /unknown state/);
});

// ── chapter 4: the cluster ──────────────────────────────────────────────────────
const CLUSTER_STATES = ['steady', 'full', 'stock-crash', 'silent', 'ledger-stop', 'return', 'no-offer'];
const usedSlots = (slots) => slots.filter((x) => x !== null).length;

test('cluster: every state is reachable from scratch and reproducible', () => {
  for (const name of CLUSTER_STATES) {
    const a = ME.buildState('cluster', name, data), b = ME.buildState('cluster', name, data);
    assert.deepEqual(a.counters, b.counters, name);
    assert.ok(a.counters.started > 0, name);
  }
  assert.throws(() => ME.buildState('cluster', 'nope', data), /unknown state/);
});

test('cluster: the simulation is configured from the data file, not from literals', () => {
  const s = ME.buildState('cluster', 'steady', data);
  assert.deepEqual(s.hosts.map((h) => h.id), data.topology.stock_hosts);
  assert.equal(s.hosts[0].stock.length, data.topology.stock_capacity);
  assert.equal(s.ledger.slots.length, data.topology.ledger_capacity);
  assert.equal(s.cfg.suspectS, data.timings.suspect_s);
  assert.equal(s.cfg.silentS, data.timings.silent_timeout_s);
  assert.equal(s.cfg.loadPerS, data.sim.load_per_s);
  assert.deepEqual(s.hosts.filter((h) => h.books).map((h) => h.id), data.topology.books_hosts);
});

test('cluster: steady has no cancelled or refused session', () => {
  const s = ME.buildState('cluster', 'steady', data);
  assert.equal(s.counters.cancelled + s.counters.refused, 0);
  assert.ok(s.hosts.every((h) => h.status === 'up'));
});

test('cluster: full means the ledger is out of slots and callers are refused', () => {
  const s = ME.buildState('cluster', 'full', data);
  // slots free and refill between frames, so "full" is a level, not an instant
  assert.ok(usedSlots(s.ledger.slots) >= 0.9 * data.topology.ledger_capacity);
  assert.ok(usedSlots(s.ledger.slots) <= data.topology.ledger_capacity);
  assert.ok(s.counters.refused > 0);
  assert.equal(s.counters.cancelled, 0);
});

test('cluster: a stock crash cancels sessions and leaves two hosts serving', () => {
  const s = ME.buildState('cluster', 'stock-crash', data);
  assert.equal(s.hosts[0].status, 'dead');
  assert.ok(s.counters.cancelled > 0);
  assert.ok(s.hosts.slice(1).every((h) => h.status === 'up'));
});

test('cluster: a silent host is still holding its sessions when the card shows it', () => {
  const s = ME.buildState('cluster', 'silent', data);
  assert.ok(['suspect', 'dead'].includes(s.hosts[0].status));
  assert.ok(usedSlots(s.hosts[0].stock) > 0);
  assert.equal(s.counters.cancelled, 0);
});

test('cluster: when the ledger host stops, the role is on the other books host', () => {
  const s = ME.buildState('cluster', 'ledger-stop', data);
  const books = s.hosts.map((h, i) => (h.books ? i : -1)).filter((i) => i >= 0);
  assert.equal(s.hosts[books[books.length - 1]].status, 'dead');
  assert.equal(s.ledger.host, books[0]);
});

test('cluster: the returning host is a new incarnation and does not take the ledger back', () => {
  const s = ME.buildState('cluster', 'return', data);
  const last = s.hosts.length - 1;
  assert.equal(s.hosts[last].status, 'up');
  assert.equal(s.hosts[last].incarnation, 2);
  assert.notEqual(s.ledger.host, last);
});

test('cluster: with no books host left there is no ledger and every caller is refused', () => {
  const s = ME.buildState('cluster', 'no-offer', data);
  assert.equal(s.ledger.host, null);
  assert.ok(s.counters.refused > 0);
});

// A canvas context that records what was drawn.
function fakeCtx() {
  const calls = { fillRect: 0, strokeRect: 0, arc: 0, fillText: [] };
  const noop = () => {};
  return {
    calls,
    fillRect: () => { calls.fillRect += 1; }, strokeRect: () => { calls.strokeRect += 1; },
    arc: () => { calls.arc += 1; }, fillText: (t) => { calls.fillText.push(String(t)); },
    clearRect: noop, beginPath: noop, closePath: noop, moveTo: noop, lineTo: noop, stroke: noop, fill: noop,
    save: noop, restore: noop, rect: noop, clip: noop, setLineDash: noop, setTransform: noop,
    measureText: (t) => ({ width: String(t).length * 6 }),
  };
}
const colors = { ink: '#fff', dim: '#888', accent: '#f00' };

test('cluster drawing: one filled square per occupied slot, at phone and desktop sizes', () => {
  const s = ME.buildState('cluster', 'steady', data);
  const occupied = s.hosts.reduce((n, h) => n + usedSlots(h.stock), 0) + usedSlots(s.ledger.slots);
  for (const size of [{ width: 343, height: 250 }, { width: 700, height: 480 }]) {
    const ctx = fakeCtx();
    ME.draw.cluster(ctx, s, size, colors);
    assert.ok(ctx.calls.fillRect >= occupied, `${ctx.calls.fillRect} >= ${occupied} at ${size.width}`);
    for (const h of s.hosts) assert.ok(ctx.calls.fillText.some((t) => t.includes(h.id)), h.id);
  }
});

test('cluster drawing: every state draws without error and names a dead host as dead', () => {
  for (const name of CLUSTER_STATES) {
    const ctx = fakeCtx();
    assert.doesNotThrow(() => ME.draw.cluster(ctx, ME.buildState('cluster', name, data), { width: 343, height: 250 }, colors), name);
  }
  const ctx = fakeCtx();
  ME.draw.cluster(ctx, ME.buildState('cluster', 'stock-crash', data), { width: 700, height: 480 }, colors);
  assert.ok(ctx.calls.fillText.some((t) => /dead/.test(t)));
});

test('inline figures are drawn into their placeholders', () => {
  const el = { dataset: { mxInline: 'timeline:silent' }, clientWidth: 400, innerHTML: '' };
  const crash = { dataset: { mxInline: 'timeline:crash' }, clientWidth: 400, innerHTML: '' };
  const bad = { dataset: { mxInline: 'nope' }, clientWidth: 400, innerHTML: '' };
  ME.mountInline({ querySelectorAll: () => [el, crash, bad] }, data);
  assert.equal(count(el.innerHTML, 'mx-ping'), data.timings.silent_timeout_s / data.timings.heartbeat_s - 1);
  assert.equal(count(el.innerHTML, 'mx-failed'), 1);
  assert.equal(count(crash.innerHTML, 'mx-ping'), 0);
  assert.match(bad.innerHTML, /mx-error/);
});

// ── chapter 3: the mailbox ──────────────────────────────────────────────────────
const MAILBOX_STATES = ['idle', 'one-at-a-time', 'sessions', 'crash', 'restart', 'lost-total'];

test('mailbox: every state is reachable from scratch and reproducible', () => {
  for (const name of MAILBOX_STATES) {
    const a = ME.buildState('mailbox', name, data), b = ME.buildState('mailbox', name, data);
    assert.deepEqual([a.total, a.queue.length, a.status], [b.total, b.queue.length, b.status], name);
  }
  assert.throws(() => ME.buildState('mailbox', 'nope', data), /unknown state/);
});

test('mailbox: the crash card shows the actor down with nothing left', () => {
  const s = ME.buildState('mailbox', 'crash', data);
  assert.equal(s.status, 'crashed');
  assert.equal(s.total + s.queue.length + s.parked, 0);
});

test('mailbox: the crash card stays crashed however long the reader stays on it', () => {
  const s = ME.buildState('mailbox', 'crash', data);
  ME.simMailbox.advance(s, 60);
  assert.equal(s.status, 'crashed');           // the restart is the next card's to show
});

test('mailbox: after the restart the total is below what it was before the crash', () => {
  const before = ME.buildState('mailbox', 'sessions', data);
  const after = ME.buildState('mailbox', 'lost-total', data);
  assert.equal(after.status, 'up');
  assert.equal(after.restarts, 1);
  assert.ok(after.total > 0 && after.total < before.total);
});

test('mailbox drawing: every state draws, and shows the total', () => {
  for (const name of MAILBOX_STATES) {
    for (const size of [{ width: 343, height: 230 }, { width: 700, height: 420 }]) {
      const ctx = fakeCtx(), s = ME.buildState('mailbox', name, data);
      assert.doesNotThrow(() => ME.draw.mailbox(ctx, s, size, colors), name);
      assert.ok(ctx.calls.fillText.some((t) => t.includes('total')), name);
    }
  }
});

// ── the release rollout (drawn in chapter 5) ────────────────────────────────────
test('release drawing: every phase draws at phone and desktop sizes and names its hosts', () => {
  const cfg = { seed: 1, hosts: data.topology.stock_hosts, leader: 0, canary: 1, windowS: 3, loadPerS: 8, sessionS: [0.8, 1.6] };
  for (const fails of [false, true]) {
    const s = ME.simRelease.create(cfg); ME.simRelease.advance(s, 2); ME.simRelease.start(s, { canaryFails: fails });
    const seen = new Set();
    for (let i = 0; i < 400; i++) {
      ME.simRelease.step(s, 0.05);
      if (seen.has(s.phase)) continue;
      seen.add(s.phase);
      for (const size of [{ width: 343, height: 240 }, { width: 700, height: 460 }]) {
        const ctx = fakeCtx();
        assert.doesNotThrow(() => ME.draw.release(ctx, s, size, colors, ME.simRelease.packet(s)), s.phase);
        for (const id of cfg.hosts) assert.ok(ctx.calls.fillText.some((t) => t.includes(id)), id);
      }
    }
    assert.ok(seen.has(fails ? 'halted' : 'complete'));
  }
});

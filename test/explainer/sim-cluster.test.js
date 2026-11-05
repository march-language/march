// Tests for docs/assets/explainer/sim-cluster.js (and rng.js). No DOM, no clock.
const test = require('node:test');
const assert = require('node:assert');
const { mulberry32 } = require('../../docs/assets/explainer/rng.js');
const sim = require('../../docs/assets/explainer/sim-cluster.js');

const cfg = { seed: 1, loadPerS: 14, sessionS: [1.2, 2.8], stockCapacity: 32, ledgerCapacity: 64,
  hosts: [{ id: 'lab-2', books: false }, { id: 'lab-3', books: true }, { id: 'lab-4', books: true }],
  suspectS: 3, settleS: 15, restartS: 1 };
const live = (s) => s.sessions.length;
const used = (slots) => slots.filter((x) => x !== null).length;

test('the generator is seeded: same seed, same numbers; different seed, different numbers', () => {
  const a = mulberry32(7), b = mulberry32(7), c = mulberry32(8);
  const xs = [a(), a(), a()], ys = [b(), b(), b()], zs = [c(), c(), c()];
  assert.deepEqual(xs, ys);
  assert.notDeepEqual(xs, zs);
  assert.ok(xs.every((x) => x >= 0 && x < 1));
});

test('same seed, same history', () => {
  const a = sim.create(cfg), b = sim.create(cfg); sim.advance(a, 30); sim.advance(b, 30);
  assert.deepEqual(a.counters, b.counters);
  assert.ok(a.counters.completed > 100);
});

test('every started session is accounted for', () => {
  const s = sim.create(cfg); sim.advance(s, 20); sim.kill(s, 0, 'crash'); sim.advance(s, 20);
  const c = s.counters; assert.equal(c.started, c.completed + c.cancelled + c.refused + live(s));
});

test('no host ever holds more than its capacity, even after a long pause', () => {
  const s = sim.create({ ...cfg, loadPerS: 200 }); sim.step(s, 60); sim.advance(s, 10);
  assert.ok(s.t < 11);                                  // the 60 s step was clamped, not simulated
  for (const h of s.hosts) assert.ok(used(h.stock) <= 32);
  assert.ok(used(s.ledger.slots) <= 64);
  assert.ok(s.counters.refused > 0);                    // past capacity, callers are told so
});

test('a full host is skipped and the next one takes the session', () => {
  const s = sim.create({ ...cfg, stockCapacity: 2, ledgerCapacity: 64, loadPerS: 5 }); sim.advance(s, 20);
  assert.ok(s.hosts.every((h) => used(h.stock) <= 2));
  assert.ok(s.counters.completed > 0);
});

test('a crashed host loses its sessions at once and takes no new ones', () => {
  const s = sim.create(cfg); sim.advance(s, 10); const before = s.counters.cancelled;
  assert.ok(used(s.hosts[0].stock) > 0);
  sim.kill(s, 0, 'crash');
  assert.ok(s.counters.cancelled > before);
  assert.equal(used(s.hosts[0].stock), 0);
  sim.advance(s, 5); assert.equal(used(s.hosts[0].stock), 0);
  assert.equal(s.hosts[0].status, 'dead');
});

test('a silent host keeps its sessions until the suspect timeout', () => {
  const s = sim.create(cfg); sim.advance(s, 10); const before = s.counters.cancelled;
  sim.kill(s, 0, 'silent'); sim.advance(s, 2.5);
  assert.equal(s.counters.cancelled, before);
  assert.equal(s.hosts[0].status, 'suspect');
  sim.advance(s, 1);
  assert.ok(s.counters.cancelled > before);
  assert.equal(s.hosts[0].status, 'dead');
});

test('the ledger starts on the last books host', () => {
  assert.equal(sim.create(cfg).ledger.host, 2);
});

test('the ledger moves to the other books host, and not back within the settle period', () => {
  const s = sim.create(cfg); sim.advance(s, 5); const first = s.ledger.host;
  sim.kill(s, first, 'crash'); sim.advance(s, 4); assert.notEqual(s.ledger.host, first); assert.notEqual(s.ledger.host, null);
  const second = s.ledger.host; sim.revive(s, first); sim.advance(s, 10); assert.equal(s.ledger.host, second);
});

test('while the ledger is moving, sessions are refused, and they resume after', () => {
  const s = sim.create(cfg); sim.advance(s, 5);
  sim.kill(s, s.ledger.host, 'crash'); sim.advance(s, 1);
  assert.equal(s.ledger.host, null);
  const refused = s.counters.refused; sim.advance(s, 1.5); assert.ok(s.counters.refused > refused);
  sim.advance(s, 2); const done = s.counters.completed; sim.advance(s, 6); assert.ok(s.counters.completed > done);
});

test('a revived host comes back as the next incarnation', () => {
  const s = sim.create(cfg); sim.kill(s, 0, 'crash'); sim.revive(s, 0);
  assert.equal(s.hosts[0].status, 'restarting');
  sim.advance(s, 2);
  assert.equal(s.hosts[0].status, 'up'); assert.equal(s.hosts[0].incarnation, 2);
});

test('with every stock host down, sessions are refused', () => {
  const s = sim.create(cfg); [0, 1, 2].forEach((i) => sim.kill(s, i, 'crash')); sim.advance(s, 6);
  const r = s.counters.refused; sim.advance(s, 3); assert.ok(s.counters.refused > r);
});

test('killing a dead host or reviving a live one changes nothing', () => {
  const s = sim.create(cfg); sim.advance(s, 3);
  sim.revive(s, 0); assert.equal(s.hosts[0].status, 'up'); assert.equal(s.hosts[0].incarnation, 1);
  sim.kill(s, 0, 'crash'); const c = s.counters.cancelled; sim.kill(s, 0, 'crash'); assert.equal(s.counters.cancelled, c);
});

// Two different clocks: membership declares a silent host dead after `suspectS`, which
// stops new sessions going there; the sessions already on it are cancelled by their own
// heartbeat, after `silentS`.
test('a silent host stops taking sessions at the suspect timeout but holds its own until the heartbeat cutoff', () => {
  const s = sim.create({ ...cfg, silentS: 10 }); sim.advance(s, 10); const before = s.counters.cancelled;
  sim.kill(s, 0, 'silent'); sim.advance(s, 3.5);
  assert.equal(s.hosts[0].status, 'dead');
  assert.equal(s.counters.cancelled, before);           // still held, frozen
  assert.ok(used(s.hosts[0].stock) > 0);
  sim.advance(s, 7);
  assert.ok(s.counters.cancelled > before);
  assert.equal(used(s.hosts[0].stock), 0);
});

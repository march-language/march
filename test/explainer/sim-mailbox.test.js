// Tests for docs/assets/explainer/sim-mailbox.js: one actor, one mailbox. No DOM, no clock.
const test = require('node:test');
const assert = require('node:assert');
const sim = require('../../docs/assets/explainer/sim-mailbox.js');

const base = { seed: 1, arrivalS: 0.4, serviceS: 0.4, migrateS: 1, holds: false };

test('messages are handled one at a time, in order, and each adds to the total', () => {
  const s = sim.create({ ...base, backlog: 5 });
  assert.equal(s.queue.length, 5);
  sim.advance(s, 0.3); assert.equal(s.total, 0);          // the first is still being handled
  sim.advance(s, 0.2); assert.equal(s.total, 1);
  sim.advance(s, 10); assert.ok(s.total > 20);
  assert.equal(s.total, s.handled.old + s.handled.new);
});

test('same seed, same history', () => {
  const a = sim.create({ ...base, backlog: 4 }), b = sim.create({ ...base, backlog: 4 });
  sim.advance(a, 12); sim.advance(b, 12);
  assert.deepEqual([a.total, a.queue.length, a.parked], [b.total, b.queue.length, b.parked]);
});

test('messages ahead of the marker run on the old code', () => {
  const s = sim.create({ ...base, backlog: 6 });
  sim.advance(s, 4); const ahead = s.queue.length; sim.deploy(s); const oldBefore = s.handled.old;
  assert.ok(ahead > 0);
  while (s.version === 1) sim.step(s, 0.05);
  assert.equal(s.handled.old - oldBefore, ahead);
});

test('nothing is handled while the state is migrating', () => {
  const s = sim.create(base);
  sim.advance(s, 2); sim.deploy(s);
  while (!s.migrating) sim.step(s, 0.05);
  const h = s.handled.old + s.handled.new; while (s.migrating) sim.step(s, 0.05);
  assert.equal(s.handled.old + s.handled.new, h);
  assert.equal(s.version, 2);
});

test('after the migration every message runs on the new code', () => {
  const s = sim.create(base); sim.advance(s, 2); sim.deploy(s); sim.advance(s, 6);
  const old = s.handled.old; sim.advance(s, 6);
  assert.equal(s.handled.old, old);
  assert.ok(s.handled.new > 0);
});

test('a second deploy before the first has landed is ignored', () => {
  const s = sim.create({ ...base, backlog: 6 }); sim.deploy(s); sim.deploy(s);
  assert.equal(s.queue.filter((m) => m.kind === 'marker').length, 1);
});

test('an actor holding sessions stays on the old code until released', () => {
  const s = sim.create({ ...base, holds: true });
  sim.advance(s, 2); sim.deploy(s); sim.advance(s, 20); assert.equal(s.version, 1);
  assert.equal(s.held, true);
  sim.releaseHold(s); sim.advance(s, 5); assert.equal(s.version, 2);
  assert.equal(s.held, false);
});

test('a crash empties the state and the restart begins from zero', () => {
  const s = sim.create({ ...base, backlog: 4, parked: 6 });
  sim.advance(s, 5); assert.ok(s.total > 0); assert.equal(s.parked, 6);
  sim.crash(s);
  assert.equal(s.total, 0); assert.equal(s.queue.length, 0); assert.equal(s.parked, 0);
  assert.equal(s.status, 'crashed');
  sim.advance(s, 3); assert.ok(s.total > 0);
  assert.equal(s.status, 'up'); assert.equal(s.restarts, 1);
});

test('messages sent to a crashed actor are dropped, not kept for later', () => {
  const s = sim.create({ ...base, restartS: 2 });
  sim.advance(s, 2); sim.crash(s); sim.advance(s, 1.5);
  assert.equal(s.queue.length, 0);
  assert.ok(s.dropped > 0);
});

test('a long pause is clamped, not simulated', () => {
  const s = sim.create(base); sim.step(s, 60);
  assert.ok(s.t <= 0.11);
});

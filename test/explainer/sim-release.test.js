// Tests for docs/assets/explainer/sim-release.js: one signed release rolling through a
// cluster while calls keep flowing. No DOM, no clock.
const test = require('node:test');
const assert = require('node:assert');
const sim = require('../../docs/assets/explainer/sim-release.js');

const cfg = { seed: 1, hosts: ['lab-2', 'lab-3', 'lab-4'], leader: 0, canary: 1, windowS: 3, loadPerS: 8, sessionS: [0.8, 1.6] };
const v2 = (s) => s.hosts.filter((h) => h.version === 2).length;

test('nothing changes until a release is started', () => {
  const s = sim.create(cfg); sim.advance(s, 10);
  assert.equal(s.phase, 'idle'); assert.equal(v2(s), 0);
  assert.ok(s.counters.oldReplies > 0); assert.equal(s.counters.newReplies, 0);
});

test('same seed, same history', () => {
  const a = sim.create(cfg), b = sim.create(cfg);
  for (const s of [a, b]) { sim.advance(s, 3); sim.start(s, { canaryFails: false }); sim.advance(s, 30); }
  assert.deepEqual(a.counters, b.counters);
});

test('a clean release ends with every host on the new code and no failed session', () => {
  const s = sim.create(cfg); sim.advance(s, 3); sim.start(s, { canaryFails: false }); sim.advance(s, 30);
  assert.equal(s.phase, 'complete'); assert.deepEqual(s.hosts.map((h) => h.version), [2, 2, 2]);
  assert.equal(s.counters.failed, 0); assert.ok(s.counters.newReplies > 0);
});

test('the release reaches the leader before any host changes', () => {
  const s = sim.create(cfg); sim.start(s, { canaryFails: false });
  while (s.phase === 'send' || s.phase === 'forward') { assert.equal(v2(s), 0); sim.step(s, 0.05); }
  assert.equal(s.phase, 'canary');
});

test('only the canary changes before the gate closes, and it is not the leader', () => {
  const s = sim.create(cfg); sim.start(s, { canaryFails: false });
  while (s.phase !== 'gate') sim.step(s, 0.05);
  assert.equal(v2(s), 1);
  assert.equal(s.hosts[cfg.leader].version, 1);
  assert.equal(s.hosts[s.canaryHost].version, 2);
  assert.equal(s.canaryHost, 2);                       // the last host that is not the leader
});

test('the gate holds for its whole window', () => {
  const s = sim.create(cfg); sim.start(s, { canaryFails: false });
  while (s.phase !== 'gate') sim.step(s, 0.05);
  sim.advance(s, 2.8); assert.equal(s.phase, 'gate'); assert.equal(v2(s), 1);
  sim.advance(s, 1.5); assert.notEqual(s.phase, 'gate');
});

test('a failed gate halts the release and rolls nothing back', () => {
  const s = sim.create(cfg); sim.start(s, { canaryFails: true }); sim.advance(s, 30);
  assert.equal(s.phase, 'halted'); assert.equal(v2(s), 1);
  sim.advance(s, 30); assert.equal(s.phase, 'halted'); assert.equal(v2(s), 1);
});

test('sessions in flight on a host when it takes the patch are drained, not failed', () => {
  const s = sim.create(cfg); sim.advance(s, 5); sim.start(s, { canaryFails: false }); sim.advance(s, 30);
  assert.ok(s.counters.drained > 0); assert.equal(s.counters.failed, 0);
});

test('after completion no reply comes from the old code', () => {
  const s = sim.create(cfg); sim.start(s, { canaryFails: false }); sim.advance(s, 40);
  const old = s.counters.oldReplies; sim.advance(s, 10); assert.equal(s.counters.oldReplies, old);
});

test('every started call is accounted for', () => {
  const s = sim.create(cfg); sim.advance(s, 4); sim.start(s, { canaryFails: false }); sim.advance(s, 25);
  const c = s.counters;
  assert.equal(c.started, c.oldReplies + c.newReplies + c.drained + c.failed + s.calls.length);
});

test('starting a second release while one is running changes nothing', () => {
  const s = sim.create(cfg); sim.start(s, { canaryFails: false }); sim.advance(s, 1);
  const phase = s.phase; sim.start(s, { canaryFails: true });
  assert.equal(s.phase, phase); sim.advance(s, 30); assert.equal(s.phase, 'complete');
});

test('a long pause is clamped, not simulated', () => {
  const s = sim.create(cfg); sim.step(s, 60); assert.ok(s.t <= 0.11);
});

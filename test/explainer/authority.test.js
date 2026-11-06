// Tests for the second explainer, docs/deploy-authority.md: its figure of module squares
// (figures-authority.js), its topology simulation (sim-topology.js), and the card states
// the page asks its figures for (chapters-authority.js).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
for (const f of ['scroll', 'story', 'rng', 'figures', 'figures-authority', 'sim-cluster', 'sim-mailbox', 'sim-release',
  'sim-topology', 'draw', 'draw-authority', 'chapters', 'chapters-authority']) {
  require('../../docs/assets/explainer/' + f + '.js');
}
const ME = globalThis.MarchExplainer, F = ME.figures, T = ME.simTopology;
const ROOT = path.join(__dirname, '../..');
const data = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/_data/authority.json'), 'utf8'));
const page = fs.readFileSync(path.join(ROOT, 'docs/deploy-authority.md'), 'utf8');
const count = (svg, re) => (svg.match(re) || []).length;
const { stage } = require('./fake-dom.js');

// ── the squares ────────────────────────────────────────────────────────────────

const reach = (st, width) => F.reach(data.modules, { width: width || 680, stage: st, dep: data.dep });

test('reach: one square per module, and one more once the dependency is added', () => {
  for (const st of F.REACH_STAGES) {
    const extra = st.startsWith('dep') ? 1 : 0;
    assert.equal(count(reach(st), /<rect class="mx-sq/g), data.modules.total + extra, st);
  }
});

test('reach: the groups are the generated counts', () => {
  const c = data.modules.classes;
  assert.equal(c.none + c.inside + c.outside, data.modules.total);
  const svg = reach('outside');
  assert.equal(count(svg, /class="mx-sq mx-quiet"/g), c.none);
  assert.equal(count(svg, /class="mx-sq mx-inside"/g), c.inside);
  assert.equal(count(svg, /class="mx-sq mx-outside"/g), c.outside);
});

test('reach: a group is not picked out before its card', () => {
  assert.equal(count(reach('all'), /mx-quiet|mx-inside|mx-outside/g), 0);
  assert.equal(count(reach('none'), /mx-outside/g), 0);
});

test('reach: the app\'s own modules are outlined, and the undeclared one is the only accent', () => {
  assert.equal(count(reach('own'), /mx-own/g), data.modules.own.length);
  const svg = reach('undeclared');
  assert.equal(count(svg, /mx-hot/g), 1);
  assert.equal(count(svg, /mx-own/g), data.modules.own.length - 1);
});

test('reach: the dependency reaches nothing at 1.0 and is the one accent after the update', () => {
  assert.deepEqual(data.dep.v1.needs, []);
  assert.ok(data.dep.v2.needs.length > 0);
  assert.equal(count(reach('dep'), /class="mx-sq mx-quiet mx-own"/g), 1);
  const updated = reach('dep-update');
  assert.equal(count(updated, /mx-hot/g), 1);
  assert.equal(count(updated, /mx-own/g), 0);
  assert.ok(updated.includes(data.dep.v2.needs[0]));
});

test('reach: no square moves between cards (only the dependency\'s is added)', () => {
  const places = (svg) => (svg.match(/<rect class="mx-sq[^"]*" x="[\d.]+" y="[\d.]+"/g) || [])
    .map((r) => r.replace(/class="[^"]*"/, '')).sort();
  const base = places(reach('all'));
  for (const st of F.REACH_STAGES) {
    const now = places(reach(st));
    for (const p of base) assert.ok(now.includes(p), st + ' lost ' + p);
  }
});

test('reach: an unknown stage is an error, and the figure mounts and reports one', () => {
  assert.throws(() => reach('nope'), /unknown stage/);
  const host = stage(680), fig = ME.figureForTest('reach')(host, data);
  fig.setState('own', 0);
  assert.ok(host.innerHTML.includes('mx-own'));
  assert.throws(() => fig.setState('nope', 0), /unknown state/);
});

test('reach: a phone gets the compact drawing, with every square still in it', () => {
  const svg = F.reach(data.modules, { width: 340, stage: 'outside', dep: data.dep, compact: true });
  assert.equal(count(svg, /<rect class="mx-sq/g), data.modules.total);
  assert.equal(count(svg, /mx-mono/g), 0);          // no table of needs lines
  assert.ok(Number(/ width="([\d.]+)"/.exec(svg)[1]) <= 340);
});

// ── the topology simulation ────────────────────────────────────────────────────

const cfg = () => ME.topologyConfig(data);
const chip = (s, role) => s.chips.filter((c) => c.role === role);
const hostId = (s, i) => s.hosts[i].id;

test('topology: the config is the generated topology', () => {
  const c = cfg(), pools = data.topology.pools;
  assert.equal(c.hosts.length, pools.reduce((n, p) => n + p.hosts.length, 0));
  assert.equal(c.every, 'Stock');
  assert.deepEqual(c.single, { role: 'Ledger', on: 'books' });
  assert.equal(c.initiates, 'Shop');
});

test('topology: placement follows the file', () => {
  const s = T.create(cfg());
  assert.equal(s.chips.length, 0);
  T.place(s); T.advance(s, 3);
  const work = data.topology.pools.find((p) => p.serves.length), books = work.hosts.filter((h) => h.labels.includes('books'));
  assert.deepEqual(chip(s, 'Stock').map((c) => hostId(s, c.host)), work.hosts.map((h) => h.name));
  assert.equal(chip(s, 'Ledger').length, 1);
  assert.equal(hostId(s, chip(s, 'Ledger')[0].host), books[books.length - 1].name);
  assert.equal(hostId(s, chip(s, 'Shop')[0].host), data.topology.pools.find((p) => p.initiates.length).hosts[0].name);
});

test('topology: no session starts before every role is placed', () => {
  const s = T.create(cfg());
  s.flow = true; T.advance(s, 2);
  assert.equal(s.sessions.length, 0);
  assert.equal(s.counters.finished, 0);
  assert.ok(s.counters.refused > 0);
});

test('topology: stopping the holder moves the single role once the cluster gives up on it', () => {
  const s = ME.buildState('topology', 'flow', data), led = chip(s, 'Ledger')[0], was = led.host;
  T.stop(s, was);
  assert.ok(s.counters.cancelled > 0 || s.sessions.every((x) => x.single !== was));
  T.advance(s, data.sim.suspect_s - 0.5);
  assert.equal(led.host, was, 'not before the suspect time');
  T.advance(s, 1);
  assert.notEqual(led.host, was);
  assert.ok(s.hosts[led.host].labels.includes('books'));
  assert.equal(s.hosts[led.host].status, 'up');
  T.advance(s, 4);
  assert.ok(s.sessions.every((x) => x.stock !== was && x.single !== was), 'nothing runs on a stopped host');
});

test('topology: a returning host offers Stock again and does not take the Ledger back', () => {
  const s = ME.buildState('topology', 'stop', data), led = chip(s, 'Ledger')[0];
  const down = s.hosts.findIndex((h) => h.status === 'down'), finished = s.counters.finished;
  assert.ok(down >= 0);
  T.start(s, down); T.advance(s, 6);
  assert.notEqual(led.host, down);
  assert.ok(s.counters.finished > finished);
});

test('topology: every card state builds, and the same card is the same picture twice', () => {
  for (const [fig, states] of [['topology', ME.TOPOLOGY_STATES], ['rollout', ME.ROLLOUT_STATES]]) {
    for (const st of states) {
      const a = ME.buildState(fig, st, data), b = ME.buildState(fig, st, data);
      const key = (s) => JSON.stringify([s.t, s.chips, s.sessions, s.counters, s.patch, s.hosts]);
      assert.equal(key(a), key(b), fig + ':' + st);
    }
  }
  assert.throws(() => ME.buildState('topology', 'nope', data), /unknown state/);
});

test('topology: moving on to the next card happens to the simulation on screen', () => {
  const s = ME.buildState('topology', 'flow', data), t = s.t;
  assert.equal(ME.liveTransition('topology', 'flow', 'stop', s, data), true);
  assert.equal(s.t, t, 'nothing is rebuilt');
  assert.ok(s.hosts.some((h) => h.status === 'down'));
  assert.equal(ME.liveTransition('topology', 'flow', 'firewall', s, data), false, 'only the next card');
});

// ── the patch ──────────────────────────────────────────────────────────────────

test('rollout: an ungranted patch never leaves the developer\'s machine', () => {
  const s = ME.buildState('rollout', 'refused', data);
  assert.equal(s.patch.phase, 'refused');
  T.advance(s, 10);
  assert.equal(s.patch.phase, 'refused');
  assert.ok(s.hosts.every((h) => h.code === 1));
});

test('rollout: a granted patch reaches the nodes and waits for their verdict', () => {
  const s = ME.buildState('rollout', 'granted', data);
  assert.equal(s.patch.phase, 'atNodes');
  assert.ok(s.hosts.every((h) => h.code === 1));
});

test('rollout: a node that refuses keeps its old code, and one that admits runs the new', () => {
  const no = ME.buildState('rollout', 'node', data);
  assert.equal(no.patch.phase, 'nodeRefused');
  assert.ok(no.hosts.every((h) => h.code === 1));
  const yes = ME.buildState('rollout', 'admitted', data);
  assert.equal(yes.patch.phase, 'activated');
  assert.ok(yes.hosts.every((h) => h.code === 2));
});

test('rollout: sessions keep running through all of it', () => {
  const before = ME.buildState('rollout', 'widen', data), after = ME.buildState('rollout', 'admitted', data);
  assert.ok(after.counters.finished > before.counters.finished);
  assert.equal(after.counters.cancelled, 0);
});

test('rollout: the verdict can arrive before the patch does', () => {
  const s = ME.buildState('rollout', 'widen', data);
  T.sendPatch(s, { grant: true }); T.resolveNodes(s, true);
  assert.ok(s.hosts.every((h) => h.code === 1), 'not until it arrives');
  T.advance(s, 4);
  assert.equal(s.patch.phase, 'activated');
});

// ── the page and its data ──────────────────────────────────────────────────────

test('every card on the page asks its figure for a state the figure has', () => {
  const known = { reach: F.REACH_STAGES, topology: ME.TOPOLOGY_STATES, rollout: ME.ROLLOUT_STATES };
  const body = page.replace(/<!--[\s\S]*?-->/g, '');            // the header comment describes the markup
  const sections = body.split('<section class="mx-scrolly"').slice(1);
  assert.equal(sections.length, 4);
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
  assert.ok(cards >= 20);
});

test('every figure on the page has a static fallback image', () => {
  for (const m of page.matchAll(/assets\/explainer\/fallback\/([\w-]+\.svg)/g)) {
    assert.ok(fs.existsSync(path.join(ROOT, 'docs/assets/explainer/fallback', m[1])), m[1]);
  }
});

test('the data tells one story: the update adds what every gate then names', () => {
  const cap = data.dep.v2.needs[0], w = data.widening;
  assert.ok(data.dep.refused.exit !== 0 && data.dep.refused.output.includes(cap));
  assert.ok(!data.dep.lock_before.includes(cap) && data.dep.lock_after.includes(cap));
  for (const pool of Object.keys(w.after)) {
    assert.deepEqual(w.added[pool], [cap], pool);
    assert.ok(!w.before[pool].includes(cap));
  }
  assert.ok(w.refusal.exit !== 0 && w.refusal.output.includes('--grant-cap ' + cap));
  assert.ok(w.granted.length === Object.keys(w.after).length && w.granted.every((l) => l.includes(cap)));
  assert.ok(w.written.exit !== 0 && w.written.output.includes(cap));
  for (const p of Object.values(data.programs)) assert.ok(p.exit !== 0 && p.headline.includes('IO.NetConnect'));
});

test('the firewall is the generated one: the cluster port between every pair of machines', () => {
  const t = data.topology, n = Object.keys(t.firewall).length;
  assert.equal(t.cluster_rules, n * (n - 1));
  assert.equal(t.control_rules, t.control_hosts.length * (t.control_hosts.length - 1));
});

test('the drawing fits its design size on a desk and on a phone', () => {
  for (const width of [900, 360]) {
    const d = ME.draw.topologyDesign({ width }), s = ME.buildState('rollout', 'refused', data);
    const L = ME.draw.topologyLayout(s, d.width);
    for (const b of L.hosts.concat([L.forge], L.pools.map((p) => p.box))) {
      assert.ok(b.x >= 0 && b.x + b.w <= d.width + 0.5 && b.y >= 0 && b.y + b.h <= d.height, JSON.stringify(b));
    }
    assert.ok(L.gate.x > 0 && L.gate.x < L.forge.x);
  }
});

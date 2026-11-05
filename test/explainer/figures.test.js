// Tests for docs/assets/explainer/figures.js. Run: node --test test/explainer/*.test.js
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const figures = require('../../docs/assets/explainer/figures.js');
const data = JSON.parse(fs.readFileSync(path.join(__dirname, '../../docs/_data/explainer.json'), 'utf8'));

const count = (svg, cls) => (svg.match(new RegExp('class="' + cls + '"', 'g')) || []).length;

// Every rect and line must sit inside the figure's own width and height.
function assertInside(svg, width) {
  const height = Number(svg.match(/<svg[^>]* height="([\d.]+)"/)[1]);
  for (const m of svg.matchAll(/<rect[^>]* x="(-?[\d.]+)" y="(-?[\d.]+)" width="([\d.]+)" height="([\d.]+)"/g)) {
    const [x, y, w, h] = m.slice(1).map(Number);
    assert.ok(x >= 0 && x + w <= width + 0.01, `rect x=${x} w=${w} leaves width ${width}`);
    assert.ok(y >= 0 && y + h <= height + 0.01, `rect y=${y} h=${h} leaves height ${height}`);
  }
}

test('fan-out draws one square per state and per function', () => {
  const svg = figures.fanOut(data.order, { width: 680, stage: 'functions' });
  assert.equal(count(svg, 'mx-state'), 15);
  assert.equal(count(svg, 'mx-fn'), 152);
  assert.equal(count(svg, 'mx-srcline'), 16);
});

test('fan-out at the source stage draws only the source lines', () => {
  const svg = figures.fanOut(data.order, { width: 680, stage: 'source' });
  assert.equal(count(svg, 'mx-srcline'), 16);
  assert.equal(count(svg, 'mx-fn'), 0);
  assert.equal(count(svg, 'mx-state'), 0);
});

test('fan-out at the states stage has states and no functions yet', () => {
  const svg = figures.fanOut(data.order, { width: 680, stage: 'states' });
  assert.equal(count(svg, 'mx-state'), 15);
  assert.equal(count(svg, 'mx-fn'), 0);
});

test('state map draws every cell and lights the first n reachable', () => {
  const sm = { axes: { A: 3, B: 3 }, cells: 9, reachable: [[0, 0], [1, 0], [1, 1], [1, 2], [2, 2]] };
  const svg = figures.stateMap(sm, { width: 680, lit: 3 });
  assert.equal(count(svg, 'mx-cell') + count(svg, 'mx-cell mx-lit'), 9);
  assert.equal(count(svg, 'mx-cell mx-lit'), 3);
});

test('state map for Order has one cell per combination and can light all reachable', () => {
  const sm = data.state_map;
  const svg = figures.stateMap(sm, { width: 680, lit: sm.reachable.length });
  assert.equal(count(svg, 'mx-cell') + count(svg, 'mx-cell mx-lit'), sm.cells);
  assert.equal(count(svg, 'mx-cell mx-lit'), sm.reachable.length);
});

test('state map marks a wrong cell that is not reachable', () => {
  const sm = { axes: { A: 3, B: 3 }, cells: 9, reachable: [[0, 0], [1, 0], [1, 1], [1, 2], [2, 2]] };
  const svg = figures.stateMap(sm, { width: 680, lit: 5, wrong: [0, 2] });
  assert.equal(count(svg, 'mx-cell mx-wrong'), 1);
  assert.equal(count(svg, 'mx-cell') + count(svg, 'mx-cell mx-lit') + count(svg, 'mx-cell mx-wrong'), 9);
});

test('timeline has one ping per second up to the cutoff', () => {
  const svg = figures.detectionTimeline({ heartbeat_s: 1, silent_timeout_s: 10 }, { width: 680, mode: 'silent', elapsed: 10 });
  assert.equal(count(svg, 'mx-ping'), 9);
  assert.equal(count(svg, 'mx-failed'), 1);
});

test('timeline part-way through shows the pings so far and no failure', () => {
  const svg = figures.detectionTimeline({ heartbeat_s: 1, silent_timeout_s: 10 }, { width: 680, mode: 'silent', elapsed: 4.5 });
  assert.equal(count(svg, 'mx-ping'), 4);
  assert.equal(count(svg, 'mx-failed'), 0);
});

test('a crash is noticed at once, with no pings', () => {
  const svg = figures.detectionTimeline({ heartbeat_s: 1, silent_timeout_s: 10 }, { width: 680, mode: 'crash', elapsed: 10 });
  assert.equal(count(svg, 'mx-ping'), 0);
  assert.equal(count(svg, 'mx-failed'), 1);
});

test('function squares mark exactly the changed functions', () => {
  const svg = figures.functionSquares({ total_functions: 40, changed_functions: ['Work.reply'] }, { width: 680, showChanged: true });
  assert.equal(count(svg, 'mx-fn') + count(svg, 'mx-fn mx-changed'), 40);
  assert.equal(count(svg, 'mx-fn mx-changed'), 1);
});

test('function squares before the change mark none', () => {
  const svg = figures.functionSquares({ total_functions: 40, changed_functions: ['Work.reply'] }, { width: 680, showChanged: false });
  assert.equal(count(svg, 'mx-fn'), 40);
});

test('strip marks steps done, the next step, and the rest', () => {
  const svg = figures.strip({ labels: ['send Want', 'recv Have', 'recv Booked', 'end'] }, { width: 300, at: 1 });
  assert.equal(count(svg, 'mx-seg mx-done'), 1);
  assert.equal(count(svg, 'mx-seg mx-next'), 1);
  assert.equal(count(svg, 'mx-seg'), 2);
});

test('hosts draws one box per machine', () => {
  const svg = figures.hosts(data.topology, { width: 680 });
  assert.equal(count(svg, 'mx-host'), 1 + data.topology.stock_hosts.length);
  for (const h of [data.topology.ingress].concat(data.topology.stock_hosts)) assert.ok(svg.includes('>' + h + '<'), h);
});

test('hosts says which machines may hold the ledger', () => {
  const svg = figures.hosts(data.topology, { width: 680 });
  assert.equal((svg.match(/may hold Ledger/g) || []).length, data.topology.books_hosts.length);
});

test('a 320 px figure keeps every element inside its width', () => {
  assertInside(figures.fanOut(data.order, { width: 320, stage: 'functions' }), 320);
  assertInside(figures.stateMap(data.state_map, { width: 320, lit: 5 }), 320);
  assertInside(figures.functionSquares({ total_functions: 700, changed_functions: ['a'] }, { width: 320, showChanged: true }), 320);
  assertInside(figures.strip({ labels: ['send Want', 'recv Have', 'recv Booked', 'end'] }, { width: 320, at: 0 }), 320);
  assertInside(figures.detectionTimeline({ heartbeat_s: 1, silent_timeout_s: 10 }, { width: 320, mode: 'silent', elapsed: 10 }), 320);
  assertInside(figures.hosts(data.topology, { width: 320 }), 320);
});

test('no figure carries a colour of its own', () => {
  const all = figures.fanOut(data.order, { width: 680, stage: 'functions' }) +
    figures.stateMap(data.state_map, { width: 680, lit: 5, wrong: [0, 0, 1] }) +
    figures.detectionTimeline(data.timings, { width: 680, mode: 'silent', elapsed: 10 });
  assert.equal(/#[0-9a-fA-F]{3,6}\b|rgb\(|fill="(?!none)/.test(all), false);
});

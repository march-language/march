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

// The cluster's failure detector is the node's own (SWIM): a probe every second, half a
// second for the ack, then a suspect timeout. There is no session heartbeat to draw.
const swim = { swim_probe_s: 1, swim_ack_ms: 500, suspect_s: 3 };

test('timeline: a hung host is probed, suspected when no ack comes, and dead when the suspect timeout ends', () => {
  const svg = figures.detectionTimeline(swim, { width: 680, mode: 'silent' });
  assert.equal(count(svg, 'mx-ping'), 2);             // the probe, and the moment it goes unanswered
  assert.equal(count(svg, 'mx-failed'), 1);
  assert.ok(svg.includes('>1.5 s<'), 'suspicion starts at probe + ack');
  assert.ok(svg.includes('>4.5 s<'), 'declared dead at probe + ack + suspect timeout');
  assert.equal(/heartbeat|10 s/.test(svg), false);
});

test('timeline: the marks are placed to scale', () => {
  const svg = figures.detectionTimeline(swim, { width: 680, mode: 'silent' });
  const xs = [...svg.matchAll(/<circle class="mx-ping" cx="([\d.]+)"/g)].map((m) => Number(m[1]));
  const end = Number(svg.match(/<line class="mx-failed" x1="([\d.]+)"/)[1]);
  const start = Number(svg.match(/<circle class="mx-ink" cx="([\d.]+)"/)[1]);
  const perSecond = (end - start) / 4.5;
  assert.ok(Math.abs(xs[0] - (start + 1 * perSecond)) < 0.2);
  assert.ok(Math.abs(xs[1] - (start + 1.5 * perSecond)) < 0.2);
});

test('timeline: a crash is noticed at once, with no probes', () => {
  const svg = figures.detectionTimeline(swim, { width: 680, mode: 'crash' });
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

test('strip: every label sits centred in its segment with room on both sides', () => {
  const labels = ['recv Want', 'choose have/out', 'send Book', 'send Skip', 'end'];
  const svg = figures.strip({ labels }, { width: 680, at: 1 });
  const rects = [...svg.matchAll(/<rect class="mx-seg[^"]*" x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)"/g)].map((m) => m.slice(1).map(Number));
  const texts = [...svg.matchAll(/<text class="[^"]*" x="([\d.]+)" y="([\d.]+)" text-anchor="middle"[^>]*>([^<]*)</g)].map((m) => [Number(m[1]), Number(m[2]), m[3]]);
  assert.equal(rects.length, labels.length);
  assert.equal(texts.length, labels.length);
  const CHAR = 7.3;                                   // 12px monospace, with a little slack
  labels.forEach((label, i) => {
    const [x, y, w, h] = rects[i], [tx, , text] = texts[i];
    assert.equal(text, label);
    assert.ok(Math.abs(tx - (x + w / 2)) < 0.11, `${label} is not centred`);
    assert.ok(w >= label.length * CHAR + 24, `${label}: ${w}px leaves under 12px each side`);
    assert.ok(h >= 26, `${label}: ${h}px tall`);
    if (i > 0 && rects[i - 1][1] === y) assert.ok(x - (rects[i - 1][0] + rects[i - 1][2]) >= 8, 'segments under 8px apart');
  });
});

test('strip: a label is held to its measured width, whatever font the reader has', () => {
  const svg = figures.strip({ labels: ['choose have/out'] }, { width: 680, at: 0 });
  assert.match(svg, /textLength="[\d.]+" lengthAdjust="spacingAndGlyphs"/);
});

test('strip: segments wrap onto a new row instead of leaving the figure', () => {
  const svg = figures.strip({ labels: ['recv Want', 'choose have/out', 'send Book', 'send Skip', 'end'] }, { width: 320, at: 0 });
  const ys = new Set([...svg.matchAll(/<rect class="mx-seg[^"]*" x="[\d.]+" y="([\d.]+)"/g)].map((m) => m[1]));
  assert.ok(ys.size >= 2);
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
  assertInside(figures.detectionTimeline(swim, { width: 320, mode: 'silent' }), 320);
  assertInside(figures.hosts(data.topology, { width: 320 }), 320);
});

test('no figure carries a colour of its own', () => {
  const all = figures.fanOut(data.order, { width: 680, stage: 'functions' }) +
    figures.stateMap(data.state_map, { width: 680, lit: 5, wrong: [0, 0, 1] }) +
    figures.detectionTimeline(swim, { width: 680, mode: 'silent' });
  assert.equal(/#[0-9a-fA-F]{3,6}\b|rgb\(|fill="(?!none)/.test(all), false);
});

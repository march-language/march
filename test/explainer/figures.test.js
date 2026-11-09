// Tests for docs/assets/explainer/figures.js. Run: node --test test/explainer/*.test.js
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const figures = require('../../docs/assets/explainer/figures.js');
const data = JSON.parse(fs.readFileSync(path.join(__dirname, '../../docs/_data/explainer.json'), 'utf8'));

const count = (svg, cls) => (svg.match(new RegExp('class="' + cls + '"', 'g')) || []).length;

// Every rect must sit inside the figure's own width and height. A figure may be wider
// than the stage it was asked to suit: the page scales it to fit (chapters.js).
function assertInside(svg) {
  const width = Number(svg.match(/<svg[^>]* width="([\d.]+)"/)[1]);
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

// Figures are drawn at one design size and scaled by the page to fill their stage, so a
// figure is exactly as big as its content, and lays itself out to suit the stage's shape.
const rectsOf = (svg, cls) => [...svg.matchAll(new RegExp('<rect class="' + cls + '[^"]*" x="([\\d.]+)" y="([\\d.]+)" width="([\\d.]+)" height="([\\d.]+)"', 'g'))].map((m) => m.slice(1).map(Number));
const svgSize = (svg) => [Number(svg.match(/<svg[^>]* width="([\d.]+)"/)[1]), Number(svg.match(/<svg[^>]* height="([\d.]+)"/)[1])];

test('state map: cells are one size whatever stage it is drawn for', () => {
  const sizes = [[320, 300], [700, 560], [1200, 400]].map(([width, height]) =>
    rectsOf(figures.stateMap(data.state_map, { width, height, lit: 0 }), 'mx-cell')[0][2]);
  assert.deepEqual(sizes, [sizes[0], sizes[0], sizes[0]]);
  assert.ok(sizes[0] >= 30);
});

test('state map: the figure is as wide as its cells and no wider', () => {
  const svg = figures.stateMap(data.state_map, { width: 700, height: 560, lit: 0 });
  const right = Math.max(...rectsOf(svg, 'mx-cell').map(([x, , w]) => x + w));
  assert.ok(svgSize(svg)[0] - right <= 12, 'empty margin on the right');
});

test('state map: blocks are arranged to suit the shape of the stage', () => {
  const blockRows = (width, height) => new Set(rectsOf(figures.stateMap(data.state_map, { width, height, lit: 0 }), 'mx-cell').map(([, y]) => y)).size / data.state_map.axes.Ledger;
  assert.equal(blockRows(700, 560), 2);        // a tall stage: two rows of two blocks
  assert.equal(blockRows(1200, 220), 1);       // a wide, low one: four in a row
  assert.equal(blockRows(343, 335), 2);        // a phone
});

test('fan-out: modules can be laid out three to a row, for a stage that is taller than it is wide', () => {
  const nameRows = (svg) => new Set([...svg.matchAll(/<text class="mx-label mx-mono" x="[\d.]+" y="([\d.]+)">Order_/g)].map((m) => m[1])).size;
  const five = figures.fanOut(data.order, { width: 680, stage: 'functions' });
  const three = figures.fanOut(data.order, { width: 416, stage: 'functions', perRow: 3 });
  assert.equal(nameRows(five), 1);
  assert.equal(nameRows(three), 2);
  assert.ok(svgSize(three)[1] > svgSize(five)[1]);
  for (const svg of [five, three]) {
    assert.equal(count(svg, 'mx-fn'), data.order.functions);
    assert.equal(count(svg, 'mx-state'), data.order.linear_states);
    assertInside(svg);
  }
});

test('fan-out: three to a row also only ever adds between its stages', () => {
  const keys = (stage) => new Set([...figures.fanOut(data.order, { width: 416, stage, perRow: 3 }).matchAll(/<(rect|text|line)[^>]*>/g)].map((m) => m[0].replace(/ class="[^"]*"/, '')));
  const stages = ['source', 'modules', 'states', 'functions'];
  for (let i = 1; i < stages.length; i++) {
    const before = keys(stages[i - 1]), after = keys(stages[i]);
    for (const k of before) assert.ok(after.has(k), `${stages[i]} moved or removed ${k}`);
  }
});

test('strip: the figure is as wide as its longest row', () => {
  const svg = figures.strip({ labels: ['recv Want', 'choose have/out', 'send Book', 'send Skip', 'end'] }, { width: 680, at: 0 });
  const right = Math.max(...rectsOf(svg, 'mx-seg').map(([x, , w]) => x + w));
  assert.ok(Math.abs(svgSize(svg)[0] - right) <= 1);
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

// ── the declaration, line by line ───────────────────────────────────────────────
const codeLines = (svg) => [...svg.matchAll(/<text class="(mx-codeline[^"]*)" x="([\d.]+)" y="([\d.]+)"[^>]*>([^<]*)</g)]
  .map((m) => ({ cls: m[1], x: Number(m[2]), y: Number(m[3]), text: m[4].replace(/&gt;/g, '>').replace(/&lt;/g, '<').replace(/&amp;/g, '&') }));

test('declaration: one line of text per source line, in order, indented as written', () => {
  const lines = codeLines(figures.declaration(data.order, { width: 680, from: 0, to: 0 }));
  assert.equal(lines.length, data.order.source.length);
  lines.forEach((l, i) => assert.equal(l.text, data.order.source[i].trim()));
  assert.ok(lines.every((l, i) => i === 0 || l.y > lines[i - 1].y));
  const indent = (i) => data.order.source[i].length - data.order.source[i].trimStart().length;
  for (let i = 1; i < lines.length; i++) {
    if (indent(i) > indent(i - 1)) assert.ok(lines[i].x > lines[i - 1].x, `line ${i + 1} is not indented`);
    if (indent(i) === indent(i - 1)) assert.equal(lines[i].x, lines[i - 1].x);
  }
  assert.ok(lines.every((l) => l.cls === 'mx-codeline'));      // nothing picked out
});

test('declaration: picking out lines 8 to 10 marks those three and dims the rest', () => {
  const svg = figures.declaration(data.order, { width: 680, from: 8, to: 10 });
  const lines = codeLines(svg);
  assert.deepEqual(lines.filter((l) => l.cls === 'mx-codeline mx-hl').map((l) => l.text),
    data.order.source.slice(7, 10).map((l) => l.trim()));
  assert.equal(lines.filter((l) => l.cls === 'mx-codeline mx-off').length, data.order.source.length - 3);
  assert.equal(count(svg, 'mx-hlbar'), 1);
});

test('declaration: picking out lines moves none of them', () => {
  const plain = codeLines(figures.declaration(data.order, { width: 680, from: 0, to: 0 }));
  const marked = codeLines(figures.declaration(data.order, { width: 680, from: 5, to: 5 }));
  assert.deepEqual(marked.map((l) => [l.x, l.y]), plain.map((l) => [l.x, l.y]));
});

test('declaration: the type shrinks to fit a phone', () => {
  const size = (w) => Number(figures.declaration(data.order, { width: w, from: 0, to: 0 }).match(/font-size="([\d.]+)"/)[1]);
  assert.ok(size(320) < size(680));
  assert.ok(size(320) >= 9);
  const longest = Math.max(...data.order.source.map((l) => l.length));
  assert.ok(longest * size(320) * 0.6 <= 320, 'the longest line is wider than the figure');
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
  assertInside(figures.fanOut(data.order, { width: 320, stage: 'functions' }));
  assertInside(figures.stateMap(data.state_map, { width: 320, lit: 5 }));
  assertInside(figures.functionSquares({ total_functions: 700, changed_functions: ['a'] }, { width: 320, showChanged: true }));
  assertInside(figures.strip({ labels: ['send Want', 'recv Have', 'recv Booked', 'end'] }, { width: 320, at: 0 }));
  assertInside(figures.detectionTimeline(swim, { width: 320, mode: 'silent' }));
  assertInside(figures.hosts(data.topology, { width: 320 }));
});

test('no figure carries a colour of its own', () => {
  const all = figures.fanOut(data.order, { width: 680, stage: 'functions' }) +
    figures.stateMap(data.state_map, { width: 680, lit: 5, wrong: [0, 0, 1] }) +
    figures.detectionTimeline(swim, { width: 680, mode: 'silent' });
  assert.equal(/#[0-9a-fA-F]{3,6}\b|rgb\(|fill="(?!none)/.test(all), false);
});

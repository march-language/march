// Tests for docs/assets/explainer/chapters.js: each chapter's figure, state by state.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
require('../../docs/assets/explainer/scroll.js');
require('../../docs/assets/explainer/story.js');
require('../../docs/assets/explainer/figures.js');
require('../../docs/assets/explainer/chapters.js');
const ME = globalThis.MarchExplainer;
const data = JSON.parse(fs.readFileSync(path.join(__dirname, '../../docs/_data/explainer.json'), 'utf8'));
const count = (svg, cls) => (svg.match(new RegExp('class="' + cls + '"', 'g')) || []).length;

// A stage to mount into: remembers what the figure drew.
function stage(width) {
  const box = { innerHTML: '', className: '' };
  return { clientWidth: width || 680, box, appendChild: () => {}, ownerDocument: { createElement: () => box } };
}
function mount(name, width) {
  const host = stage(width);
  const fig = ME.figureForTest(name)(host, data);
  return { fig, svg: () => host.box.innerHTML };
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
  assert.equal(count(m.svg(), 'mx-state'), data.order.linear_states);
  assert.equal(count(m.svg(), 'mx-fn'), data.order.functions);
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

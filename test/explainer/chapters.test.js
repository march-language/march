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

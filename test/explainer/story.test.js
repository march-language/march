// Tests for docs/assets/explainer/story.js. Run: node --test test/explainer/*.test.js
const test = require('node:test');
const assert = require('node:assert');
require('../../docs/assets/explainer/scroll.js');
require('../../docs/assets/explainer/story.js');
const ME = globalThis.MarchExplainer;

// A stand-in for the page: sections with a figure host and two cards each.
function fakeRoot(names) {
  fakeRoot.lastErrorText = '';
  fakeRoot.hosts = {};
  const sections = names.map((name) => {
    const host = {
      classes: [],
      classList: { add: (c) => host.classes.push(c) },
      insertAdjacentHTML: (_pos, html) => { fakeRoot.lastErrorText = html.replace(/<[^>]+>/g, ''); },
    };
    fakeRoot.hosts[name] = host;
    const steps = ['first', 'second'].map((state, i) => ({
      dataset: { state },
      classList: { toggle: () => {} },
      getBoundingClientRect: () => ({ top: 100 + i * 300, bottom: 400 + i * 300 }),
    }));
    const section = {
      classes: [],
      classList: { add: (c) => section.classes.push(c) },
      dataset: { figure: name },
      querySelector: (sel) => (sel === '.mx-stage' ? host : null),
      querySelectorAll: (sel) => (sel === '.mx-step' ? steps : []),
      steps,
    };
    return section;
  });
  return { sections, querySelectorAll: (sel) => (sel === '.mx-scrolly' ? sections : []) };
}

test('a figure that throws gets an error box and the others still mount', () => {
  const calls = [];
  ME.registerFigure('bad', () => { throw new Error('boom'); });
  ME.registerFigure('good', () => ({ setState: (s) => calls.push(s) }));
  ME.mountAll(fakeRoot(['bad', 'good']), {});
  assert.match(fakeRoot.lastErrorText, /bad: boom/);
  assert.deepEqual(calls, ['first']);          // the first card's state is applied on mount
});

test('an unknown figure name is reported, not thrown', () => {
  assert.doesNotThrow(() => ME.mountAll(fakeRoot(['nope']), {}));
  assert.match(fakeRoot.lastErrorText, /nope: no such figure/);
});

test('a mounted figure is marked live and a failed one is not', () => {
  ME.registerFigure('bad', () => { throw new Error('boom'); });
  ME.registerFigure('good', () => ({ setState: () => {} }));
  ME.mountAll(fakeRoot(['bad', 'good']), {});
  assert.deepEqual(fakeRoot.hosts.good.classes, ['mx-live']);
  assert.deepEqual(fakeRoot.hosts.bad.classes, []);   // its static image stays visible
});

test('error text is escaped', () => {
  ME.registerFigure('x', () => { throw new Error('<b>&'); });
  let html = '';
  const root = fakeRoot(['x']);
  fakeRoot.hosts.x.insertAdjacentHTML = (_p, h) => { html = h; };
  ME.mountAll(root, {});
  assert.ok(html.includes('&lt;b&gt;&amp;'));
});

test('landing on a later card applies that card state directly', () => {
  const calls = [];
  ME.registerFigure('good', () => ({ setState: (s) => calls.push(s) }));
  const root = fakeRoot(['good']);
  const frames = [], listeners = {};
  const env = {
    innerHeight: 800,                                  // trigger line at 480: the second card (top 400)
    addEventListener: (n, f) => { listeners[n] = f; },
    removeEventListener: () => {},
    requestAnimationFrame: (f) => frames.push(f),
  };
  ME.mountAll(root, {}, env);
  while (frames.length) frames.shift()();
  assert.equal(calls[calls.length - 1], 'second');
});

test('a figure whose setState throws later shows an error once and keeps going', () => {
  let n = 0;
  ME.registerFigure('flaky', () => ({ setState: () => { n++; if (n > 1) throw new Error('later'); } }));
  const root = fakeRoot(['flaky']);
  const frames = [], listeners = {};
  const env = { innerHeight: 800, addEventListener: (k, f) => { listeners[k] = f; }, removeEventListener: () => {},
    requestAnimationFrame: (f) => frames.push(f) };
  assert.doesNotThrow(() => { ME.mountAll(root, {}, env); while (frames.length) frames.shift()(); });
  assert.match(fakeRoot.lastErrorText, /flaky: later/);
});

// The page must read as an article when a figure is not running: with JavaScript off, or
// when a figure fails. The scrolling layout (cards dimmed and spaced a screen apart) is
// therefore switched on per section, by a class, only once its figure is up.
test('a section is switched to the scrolling layout only when its figure is running', () => {
  ME.registerFigure('bad', () => { throw new Error('boom'); });
  ME.registerFigure('good', () => ({ setState: () => {} }));
  const root = fakeRoot(['bad', 'good']);
  ME.mountAll(root, {});
  assert.deepEqual(root.sections[1].classes, ['mx-on']);
  assert.deepEqual(root.sections[0].classes, []);
});

test('a figure that cannot draw its first card keeps its static image and is not switched on', () => {
  ME.registerFigure('nodata', () => ({ setState: () => { throw new Error('data.order is missing'); } }));
  const root = fakeRoot(['nodata']);
  ME.mountAll(root, {});
  assert.match(fakeRoot.lastErrorText, /nodata: data.order is missing/);
  assert.deepEqual(fakeRoot.hosts.nodata.classes, []);      // not `mx-live`: the fallback image stays
  assert.deepEqual(root.sections[0].classes, []);
});

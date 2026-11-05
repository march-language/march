// Tests for docs/assets/explainer/scroll.js. Run: node --test test/explainer/
const test = require('node:test');
const assert = require('node:assert');
const { activeStep, stepProgress, observeSteps } = require('../../docs/assets/explainer/scroll.js');

const rects = [{ top: 100, bottom: 400 }, { top: 400, bottom: 700 }, { top: 700, bottom: 1000 }];

test('no step before the first one reaches the line', () => assert.equal(activeStep(rects, 800, 0.1), -1));
test('the step under the line is active', () => assert.equal(activeStep(rects, 800, 0.6), 1));   // line at 480
test('past the last step the last one stays active', () =>
  assert.equal(activeStep(rects.map(r => ({ top: r.top - 2000, bottom: r.bottom - 2000 })), 800, 0.6), 2));
test('progress is clamped to 0..1', () => {
  assert.equal(stepProgress({ top: 600, bottom: 900 }, 800, 0.6), 0);
  assert.equal(stepProgress({ top: 380, bottom: 580 }, 800, 0.6), 0.5);
  assert.equal(stepProgress({ top: -500, bottom: -200 }, 800, 0.6), 1);
});
test('an empty list has no active step', () => assert.equal(activeStep([], 800, 0.6), -1));
test('a step of no height reports full progress once the line passes it', () =>
  assert.equal(stepProgress({ top: 100, bottom: 100 }, 800, 0.6), 1));

// observeSteps against a stand-in window: frames run when the test says so.
function harness(tops) {
  const frames = [], listeners = {};
  const env = {
    innerHeight: 800,
    addEventListener: (name, fn) => { listeners[name] = fn; },
    removeEventListener: (name) => { delete listeners[name]; },
    requestAnimationFrame: (fn) => { frames.push(fn); return frames.length; },
    cancelAnimationFrame: () => {},
  };
  const els = tops.map((_, i) => ({ getBoundingClientRect: () => ({ top: tops[i], bottom: tops[i] + 300 }) }));
  return { env, els, listeners, flush: () => { while (frames.length) frames.shift()(); } };
}

test('observeSteps reports the step once at start, and again only when it changes', () => {
  const tops = [100, 400, 700], h = harness(tops), steps = [];
  const stop = observeSteps(h.els, { onStep: (i) => steps.push(i), env: h.env });
  h.flush();
  assert.deepEqual(steps, [1]);
  h.listeners.scroll(); h.flush();
  assert.deepEqual(steps, [1]);                       // same step: not reported again
  tops[0] -= 300; tops[1] -= 300; tops[2] -= 300;     // scroll down one card
  h.listeners.scroll(); h.flush();
  assert.deepEqual(steps, [1, 2]);
  stop();
  assert.equal(h.listeners.scroll, undefined);
});

test('the frame in which the step changes carries no progress call', () => {
  const tops = [100, 400, 700], h = harness(tops), progress = [];
  observeSteps(h.els, { onStep: () => {}, onProgress: (i, p) => progress.push([i, p]), env: h.env });
  h.flush();
  assert.deepEqual(progress, []);                     // step changed (-> 1) in this frame
  tops[1] -= 30;                                      // same step, further through it
  h.listeners.scroll(); h.flush();
  assert.equal(progress.length, 1);
  assert.equal(progress[0][0], 1);
});

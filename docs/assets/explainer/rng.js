// rng.js: seeded random numbers for the explainer's simulations.
//
// A simulation on docs/protocol-to-cluster.md must show the same thing every time a card
// is reached, so nothing there calls Math.random: each simulation draws from its own
// mulberry32 stream, started from the seed in docs/_data/explainer.json.
(function (root) {
  'use strict';

  // mulberry32: a small 32-bit generator. Returns a function giving numbers in [0, 1).
  function mulberry32(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  var api = { mulberry32: mulberry32 };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MarchExplainer = root.MarchExplainer || {};
  root.MarchExplainer.rng = api;
})(typeof window !== 'undefined' ? window : globalThis);

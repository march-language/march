// demo_app/assets/js/app.js
// Entry point for the DemoApp JS bundle.
// Bundled by esbuild -> priv/static/assets/app.js

// Import the march-islands runtime for island hydration
import '../../../islands/runtime/march_islands.js';

// Log that the bundle is loaded
console.log('[DemoApp] JS bundle loaded');

// Simple island polyfill: listen for march:msg events
// (real islands would be hydrated by WASM modules)
document.addEventListener('DOMContentLoaded', function() {
  const islands = document.querySelectorAll('[data-island]');
  islands.forEach(function(el) {
    const name = el.getAttribute('data-island');
    let state = {};
    try {
      state = JSON.parse(el.getAttribute('data-state') || '{}');
    } catch(e) {}
    console.log('[march-islands] mounting island:', name, 'state:', state);

    // Simple demo: wire up count buttons
    if (name === 'Counter') {
      const display = el.querySelector('#count-display');
      if (display) {
        display.textContent = state.count || 0;
      }
      el.addEventListener('march:msg', function(ev) {
        if (ev.detail === 'Increment') {
          state.count = (state.count || 0) + 1;
        } else if (ev.detail === 'Decrement') {
          state.count = (state.count || 0) - 1;
        }
        if (display) display.textContent = state.count;
      });
    }
  });
});

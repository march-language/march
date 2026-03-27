/**
 * march-islands.js — Client-side WASM island runtime for March.
 *
 * Bootstraps March WASM islands: finds island root elements in the DOM,
 * applies the configured hydration strategy, and runs an actor-per-island
 * message loop backed by the compiled WASM module.
 *
 * Embed in your page:
 *   <script type="module" src="/_march/islands/march-islands.js"
 *           data-march-base="/_march/islands"></script>
 *
 * Or via the March standard library:
 *   Islands.bootstrap_script("/_march/islands")
 *
 * ── Hydration attributes ───────────────────────────────────────────────────
 *
 *   data-march-island="Name"       Island module name (matches .wasm filename)
 *   data-march-hydrate="strategy"  eager | lazy | idle | interaction
 *   data-march-state='{"k":"v"}'   JSON-encoded initial state (single-quoted)
 *
 * ── Actor model ────────────────────────────────────────────────────────────
 *
 * Each hydrated island gets its own IslandActor instance. Actors communicate
 * via an async mailbox (queueMicrotask), mirroring March's actor semantics.
 * Islands can send messages to each other via window.marchIslands.send(name, msg).
 *
 * ── Event binding ─────────────────────────────────────────────────────────
 *
 * After every render, the runtime scans the island's DOM for elements with
 * data-on-* attributes and binds native event listeners:
 *
 *   data-on-click="Increment"      → actor.send({ tag: "Increment" })
 *   data-on-input="SetValue"       → actor.send({ tag: "SetValue", value: e.target.value })
 *   data-on-submit="Submit"        → actor.send({ tag: "Submit" }) (prevents default)
 *
 * ── WASM status ───────────────────────────────────────────────────────────
 *
 * WASM codegen is Tier 1 (pure compute, code complete, toolchain pending).
 * Browser target (Tier 4) requires wasm32-unknown-unknown + JS glue codegen.
 * Until then, loadWasmModule() returns null and islands remain non-interactive.
 *
 * When WASM codegen lands, the WASM module must export:
 *   init()                    → i32  (ptr to initial state, if needed)
 *   render(state_ptr: i32)    → i32  (ptr to HTML string)
 *   update(state_ptr: i32, msg_ptr: i32) → i32  (ptr to new state)
 *   march_alloc(size: i32)    → i32
 *   march_dealloc(ptr: i32)   → void
 */

'use strict';

// ── Constants ────────────────────────────────────────────────────────────────

const ISLAND_ATTR  = 'data-march-island';
const STATE_ATTR   = 'data-march-state';
const HYDRATE_ATTR = 'data-march-hydrate';

// ── IslandActor ───────────────────────────────────────────────────────────────

/**
 * IslandActor owns one island's state and drives its render/update cycle.
 *
 * Messages are processed cooperatively via queueMicrotask — only one message
 * is in flight at a time, matching March's single-threaded actor semantics.
 */
class IslandActor {
  #name;
  #wasm;
  #state;
  #element;
  #mailbox = [];
  #ticking = false;

  constructor(name, wasmInstance, initialState, element) {
    this.#name    = name;
    this.#wasm    = wasmInstance;
    this.#state   = initialState;
    this.#element = element;
  }

  get name() { return this.#name; }

  /**
   * Enqueue a message for processing.
   * Messages are processed in order; rendering happens after each update.
   */
  send(msg) {
    this.#mailbox.push(msg);
    if (!this.#ticking) {
      this.#ticking = true;
      queueMicrotask(() => this.#drain());
    }
  }

  #drain() {
    while (this.#mailbox.length > 0) {
      const msg = this.#mailbox.shift();
      try {
        this.#state = this.#wasm.update(this.#state, JSON.stringify(msg));
        this.#render();
      } catch (err) {
        console.error(`[march-islands] ${this.#name}: update error`, err);
      }
    }
    this.#ticking = false;
  }

  #render() {
    try {
      const html = this.#wasm.render(this.#state);
      this.#element.innerHTML = html;
      attachEventHandlers(this.#element, this);
    } catch (err) {
      console.error(`[march-islands] ${this.#name}: render error`, err);
    }
  }
}

// ── Event binding ─────────────────────────────────────────────────────────────

/**
 * Bind data-on-* event handlers within an island's root element.
 * Each re-render replaces innerHTML, so handlers are re-bound after every update.
 */
function attachEventHandlers(root, actor) {
  // data-on-click
  root.querySelectorAll('[data-on-click]').forEach(el => {
    const tag = el.getAttribute('data-on-click');
    el.addEventListener('click', e => {
      e.preventDefault();
      actor.send({ tag });
    }, { once: false });
  });

  // data-on-input
  root.querySelectorAll('[data-on-input]').forEach(el => {
    const tag = el.getAttribute('data-on-input');
    el.addEventListener('input', e => {
      actor.send({ tag, value: e.target.value });
    });
  });

  // data-on-change
  root.querySelectorAll('[data-on-change]').forEach(el => {
    const tag = el.getAttribute('data-on-change');
    el.addEventListener('change', e => {
      actor.send({ tag, value: e.target.value, checked: e.target.checked });
    });
  });

  // data-on-submit (form)
  root.querySelectorAll('[data-on-submit]').forEach(el => {
    const tag = el.getAttribute('data-on-submit');
    el.addEventListener('submit', e => {
      e.preventDefault();
      const data = el.tagName === 'FORM'
        ? Object.fromEntries(new FormData(el))
        : {};
      actor.send({ tag, data });
    });
  });
}

// ── WASM loading ──────────────────────────────────────────────────────────────

/**
 * Load and instantiate a WASM island module.
 *
 * TODO (Tier 4 — browser WASM target): Replace the stub below with real
 * WebAssembly.instantiateStreaming. The compiled March WASM module must export:
 *
 *   march_island_render(state_ptr: i32) → i32   (pointer to HTML string)
 *   march_island_update(state_ptr: i32, msg_ptr: i32) → i32  (new state ptr)
 *   march_island_init()                 → i32   (initial state ptr, or 0)
 *   march_alloc(size: i32)              → i32
 *   march_dealloc(ptr: i32, size: i32)  → void
 *
 * Memory layout for strings: 4-byte length prefix (LE i32) followed by UTF-8 bytes.
 * The host must call march_alloc to pass strings into WASM and march_dealloc to free
 * the returned string pointers after use.
 *
 * @param {string} baseUrl  URL prefix, e.g. "/_march/islands"
 * @param {string} name     Island name, e.g. "Counter"
 * @returns {Promise<object|null>}  WASM wrapper or null if not available
 */
async function loadWasmModule(baseUrl, name) {
  // Allow test harnesses to inject mock WASM modules.
  // Set window.__marchTestLoader = async (baseUrl, name) => ({ render, update })
  if (window.__marchTestLoader) {
    return window.__marchTestLoader(baseUrl, name);
  }

  // Stub: WASM browser target not yet available.
  // When Tier 4 lands, replace this with:
  //
  //   const wasmUrl = `${baseUrl}/${name}.wasm`;
  //   const imports = { env: buildMarchImports() };
  //   const { instance } = await WebAssembly.instantiateStreaming(
  //     fetch(wasmUrl), imports
  //   );
  //   return wrapWasmExports(instance.exports, name);
  //
  console.info(
    `[march-islands] ${name}: WASM browser target not yet compiled.` +
    ` Island will remain static (SSR content preserved).`
  );
  return null;
}

// Placeholder: wraps raw WASM exports into a friendlier JS object.
// Uncomment and complete when Tier 4 WASM codegen lands.
//
// function wrapWasmExports(exports, name) {
//   const { memory, march_alloc, march_dealloc,
//           march_island_render, march_island_update, march_island_init } = exports;
//   const decoder = new TextDecoder();
//   const encoder = new TextEncoder();
//
//   function readString(ptr) {
//     const view = new DataView(memory.buffer);
//     const len = view.getInt32(ptr, true);
//     return decoder.decode(new Uint8Array(memory.buffer, ptr + 4, len));
//   }
//
//   function writeString(s) {
//     const bytes = encoder.encode(s);
//     const ptr = march_alloc(4 + bytes.byteLength);
//     const view = new DataView(memory.buffer);
//     view.setInt32(ptr, bytes.byteLength, true);
//     new Uint8Array(memory.buffer, ptr + 4, bytes.byteLength).set(bytes);
//     return ptr;
//   }
//
//   return {
//     init() {
//       const ptr = march_island_init();
//       return ptr !== 0 ? readString(ptr) : '{}';
//     },
//     render(stateJson) {
//       const sp = writeString(stateJson);
//       const rp = march_island_render(sp);
//       march_dealloc(sp, 4 + encoder.encode(stateJson).byteLength);
//       const html = readString(rp);
//       march_dealloc(rp, 4 + encoder.encode(html).byteLength);
//       return html;
//     },
//     update(stateJson, msgJson) {
//       const sp = writeString(stateJson);
//       const mp = writeString(msgJson);
//       const np = march_island_update(sp, mp);
//       march_dealloc(sp, ...); march_dealloc(mp, ...);
//       const next = readString(np);
//       march_dealloc(np, ...);
//       return next;
//     },
//   };
// }

// ── Hydration ─────────────────────────────────────────────────────────────────

/** Parse the island's initial state from its data-march-state attribute. */
function parseState(element) {
  const raw = element.getAttribute(STATE_ATTR);
  if (!raw) return '{}';
  // Unescape &#39; → ' before JSON parsing
  const unescaped = raw.replace(/&#39;/g, "'");
  try {
    JSON.parse(unescaped); // validate
    return unescaped;
  } catch (e) {
    console.error('[march-islands] Invalid island state JSON:', raw, e);
    return '{}';
  }
}

/**
 * Hydrate one island element: load WASM, parse state, spawn actor.
 * If WASM is unavailable, the SSR content is left in place unchanged.
 */
async function hydrateIsland(element, baseUrl) {
  const name = element.getAttribute(ISLAND_ATTR);
  if (!name || element._marchActor) return; // already hydrated

  const wasm = await loadWasmModule(baseUrl, name);
  if (!wasm) return; // WASM not available; preserve SSR content

  const initialStateJson = parseState(element);
  const actor = new IslandActor(name, wasm, initialStateJson, element);

  // Store on element for inter-island messaging
  element._marchActor = actor;

  // Register globally for cross-island messaging
  window.marchIslands = window.marchIslands ?? {};
  window.marchIslands[name] = actor;

  // Kick off initial render (replaces SSR with live WASM output)
  actor.send({ tag: '__init__' });

  console.debug(`[march-islands] ${name} hydrated`);
}

// ── Hydration strategies ──────────────────────────────────────────────────────

/**
 * Apply the hydration strategy declared on an island element.
 * The strategy is read from data-march-hydrate (default: "eager").
 */
function applyStrategy(element, baseUrl) {
  const strategy = element.getAttribute(HYDRATE_ATTR) ?? 'eager';

  switch (strategy) {
    case 'eager':
      hydrateIsland(element, baseUrl);
      break;

    case 'lazy': {
      const obs = new IntersectionObserver(entries => {
        if (entries.some(e => e.isIntersecting)) {
          obs.unobserve(element);
          hydrateIsland(element, baseUrl);
        }
      });
      obs.observe(element);
      break;
    }

    case 'idle':
      if ('requestIdleCallback' in window) {
        requestIdleCallback(() => hydrateIsland(element, baseUrl));
      } else {
        // Safari fallback
        setTimeout(() => hydrateIsland(element, baseUrl), 200);
      }
      break;

    case 'interaction': {
      const triggers = ['click', 'focusin', 'touchstart', 'pointerdown'];
      function onFirstInteraction() {
        triggers.forEach(ev => element.removeEventListener(ev, onFirstInteraction));
        hydrateIsland(element, baseUrl);
      }
      triggers.forEach(ev => element.addEventListener(ev, onFirstInteraction));
      break;
    }

    default:
      console.warn(`[march-islands] Unknown hydration strategy "${strategy}"; using eager`);
      hydrateIsland(element, baseUrl);
  }
}

// ── Cross-island messaging API ────────────────────────────────────────────────

/**
 * Send a message to a named island actor from outside (e.g. from vanilla JS).
 *
 * Usage:
 *   window.marchIslands.send('Counter', { tag: 'Increment' });
 */
function sendToIsland(name, msg) {
  const el = document.querySelector(`[${ISLAND_ATTR}="${name}"]`);
  if (el?._marchActor) {
    el._marchActor.send(msg);
  } else {
    console.warn(`[march-islands] No hydrated island named "${name}"`);
  }
}

// ── Bootstrap ─────────────────────────────────────────────────────────────────

/**
 * Resolve the base URL for WASM files from the script element's
 * data-march-base attribute, falling back to /_march/islands.
 */
function resolveBaseUrl() {
  const script = document.currentScript
    ?? document.querySelector('script[data-march-base]');
  return script?.getAttribute('data-march-base') ?? '/_march/islands';
}

/** Bootstrap: discover and hydrate all islands on the page. */
function bootstrap() {
  const baseUrl = resolveBaseUrl();
  const islands = document.querySelectorAll(`[${ISLAND_ATTR}]`);

  if (islands.length === 0) return;
  console.debug(`[march-islands] Bootstrapping ${islands.length} island(s) (base: ${baseUrl})`);

  islands.forEach(el => applyStrategy(el, baseUrl));
}

// Install cross-island send API
window.marchIslands = { send: sendToIsland };

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootstrap);
} else {
  // Already loaded (e.g. script placed at end of body)
  bootstrap();
}

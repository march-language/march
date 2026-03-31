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
 * ── WASM exports ────────────────────────────────────────────────────────────
 *
 * The compiled March WASM module exports:
 *   march_island_render(state_ptr)       → i32  (ptr to HTML string)
 *   march_island_update(state_ptr, msg)  → i32  (ptr to new state)
 *   march_island_init()                  → i32  (ptr to initial state, or 0)
 *   march_alloc_export(size: i64)        → i32  (bump allocator)
 *   march_string_lit_export(ptr, len)    → i32  (builds a march_string struct)
 *   march_dealloc(ptr)                   → void
 *   _start()                             → void (module initialisation)
 *
 * ── March string layout (wasm32) ────────────────────────────────────────────
 *
 *   offset  0: rc       (i64, 8 bytes)  — reference count
 *   offset  8: tag      (i32, 4 bytes)  — type tag
 *   offset 12: pad      (i32, 4 bytes)
 *   offset 16: length   (i64, 8 bytes)  — byte length of UTF-8 data
 *   offset 24: data_ptr (i64, 8 bytes)  — pointer to UTF-8 bytes
 */

'use strict';

// ── Constants ────────────────────────────────────────────────────────────────

const ISLAND_ATTR  = 'data-march-island';
const STATE_ATTR   = 'data-march-state';
const HYDRATE_ATTR = 'data-march-hydrate';

// ── DevTools instrumentation ────────────────────────────────────────────────

/** Emit a DevTools event if __MARCH_DEBUG is enabled. */
function devtoolsEmit(type, data) {
  if (!window.__MARCH_DEBUG) return;
  window.postMessage({
    source: 'march-devtools-page',
    payload: Object.assign({ type, timestamp: Date.now() }, data),
  }, '*');
}

/** Safely parse a JSON state string; return the parsed object or the raw string. */
function safeParseJson(s) {
  try { return JSON.parse(s); } catch { return s; }
}

let _devtoolsIdCounter = 0;

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
        // DevTools state restore — bypass update, set state directly
        if (msg.tag === '__restore__' && msg.state !== undefined) {
          this.#state = typeof msg.state === 'string' ? msg.state : JSON.stringify(msg.state);
          this.#render();
          devtoolsEmit('island:state-change', {
            id: this.#element._marchIslandId,
            name: this.#name,
            state: safeParseJson(this.#state),
            msg: { tag: '__restore__' },
          });
          continue;
        }
        const prevState = this.#state;
        this.#state = this.#wasm.update(this.#state, JSON.stringify(msg));
        devtoolsEmit('island:state-change', {
          id: this.#element._marchIslandId,
          name: this.#name,
          state: safeParseJson(this.#state),
          prevState: safeParseJson(prevState),
          msg,
        });
        this.#render();
      } catch (err) {
        console.error(`[march-islands] ${this.#name}: update error`, err);
        devtoolsEmit('island:error', {
          id: this.#element._marchIslandId,
          name: this.#name,
          error: String(err),
        });
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
      devtoolsEmit('island:error', {
        id: this.#element._marchIslandId,
        name: this.#name,
        error: `render: ${err}`,
      });
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

// ── WASM string bridge ───────────────────────────────────────────────────────

const _decoder = new TextDecoder();
const _encoder = new TextEncoder();

/**
 * Read a March string from WASM linear memory.
 *
 * March string layout (wasm32):
 *   +0  rc       i64
 *   +8  tag      i32  + pad i32
 *   +16 length   i64   (byte count)
 *   +24 data_ptr i64   (pointer to UTF-8 bytes; only lower 32 bits used on wasm32)
 */
function readMarchString(memory, ptr) {
  const view = new DataView(memory.buffer);
  const len     = Number(view.getBigInt64(ptr + 16, true));
  const dataPtr = Number(view.getBigInt64(ptr + 24, true));
  return _decoder.decode(new Uint8Array(memory.buffer, dataPtr, len));
}

/**
 * Write a JS string into WASM linear memory as a March string.
 *
 * Uses march_alloc_export to allocate a data buffer, copies the UTF-8 bytes,
 * then calls march_string_lit_export to build the proper march_string struct.
 */
function writeMarchString(exports, str) {
  const { memory, march_alloc_export, march_string_lit_export } = exports;
  const encoded = _encoder.encode(str);

  // Allocate a data buffer in WASM memory for the raw bytes
  const dataPtr = march_alloc_export(BigInt(encoded.length + 1));
  const mem = new Uint8Array(memory.buffer);
  mem.set(encoded, dataPtr);
  mem[dataPtr + encoded.length] = 0; // null terminator

  // Build a proper march_string struct via the runtime
  return march_string_lit_export(dataPtr, BigInt(encoded.length));
}

// ── WASM module wrapper ──────────────────────────────────────────────────────

/**
 * Wrap raw WASM exports into the {init, render, update} interface
 * expected by IslandActor. Bridges JS strings ↔ March WASM strings.
 */
function wrapWasmExports(exports, name) {
  const { memory, march_island_render, march_island_update,
          march_island_init, march_dealloc } = exports;

  return {
    /** Call march_island_init; return JSON string or '{}'. */
    init() {
      const ptr = march_island_init();
      if (ptr === 0) return '{}';
      return readMarchString(memory, ptr);
    },

    /** Write stateJson into WASM, call render, read HTML string back. */
    render(stateJson) {
      const sp = writeMarchString(exports, stateJson);
      const rp = march_island_render(sp);
      const html = readMarchString(memory, rp);
      return html;
    },

    /** Write stateJson + msgJson into WASM, call update, read new state back. */
    update(stateJson, msgJson) {
      const sp = writeMarchString(exports, stateJson);
      const mp = writeMarchString(exports, msgJson);
      const np = march_island_update(sp, mp);
      const next = readMarchString(memory, np);
      return next;
    },
  };
}

// ── WASM loading ─────────────────────────────────────────────────────────────

/**
 * Load and instantiate a WASM island module.
 *
 * @param {string} baseUrl  URL prefix, e.g. "/_march/islands"
 * @param {string} name     Island name, e.g. "Counter"
 * @returns {Promise<object|null>}  {init, render, update} wrapper or null
 */
async function loadWasmModule(baseUrl, name) {
  // Allow test harnesses to inject mock WASM modules.
  // Set window.__marchTestLoader = async (baseUrl, name) => ({ render, update })
  if (window.__marchTestLoader) {
    return window.__marchTestLoader(baseUrl, name);
  }

  const wasmUrl = `${baseUrl}/${name}.wasm`;
  try {
    const resp = await fetch(wasmUrl);
    if (!resp.ok) {
      console.info(
        `[march-islands] ${name}: WASM not found at ${wasmUrl} (${resp.status}).` +
        ` Island will remain static (SSR content preserved).`
      );
      return null;
    }

    const { instance } = await WebAssembly.instantiate(
      await resp.arrayBuffer()
    );

    // Run module initialisation (_start sets up globals, calls main if present)
    if (instance.exports._start) {
      instance.exports._start();
    }

    return wrapWasmExports(instance.exports, name);
  } catch (err) {
    console.error(`[march-islands] ${name}: failed to load WASM`, err);
    return null;
  }
}

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

  const hydration = element.getAttribute(HYDRATE_ATTR) ?? 'eager';
  const id = 'island-' + (++_devtoolsIdCounter);
  element._marchIslandId = id;

  // Emit mount (island discovered, WASM not yet loaded)
  const initialStateJson = parseState(element);
  devtoolsEmit('island:mount', {
    id,
    name,
    hydration,
    state: safeParseJson(initialStateJson),
    wasmModule: `${name}.wasm`,
  });

  const t0 = performance.now();
  const wasm = await loadWasmModule(baseUrl, name);
  if (!wasm) return; // WASM not available; preserve SSR content

  const actor = new IslandActor(name, wasm, initialStateJson, element);

  // Store on element for inter-island messaging
  element._marchActor = actor;

  // Register globally for cross-island messaging
  window.marchIslands = window.marchIslands ?? {};
  window.marchIslands[name] = actor;

  // Emit hydrate with real WASM load duration
  const duration = Math.round(performance.now() - t0);
  devtoolsEmit('island:hydrate', { id, name, duration });

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
function sendToIsland(name, msg, fromName) {
  const el = document.querySelector(`[${ISLAND_ATTR}="${name}"]`);
  if (el?._marchActor) {
    devtoolsEmit('island:message-send', {
      from: fromName || 'external',
      to: name,
      payload: msg,
    });
    el._marchActor.send(msg);
    devtoolsEmit('island:message-receive', {
      to: name,
      from: fromName || 'external',
      payload: msg,
    });
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

// DevTools scan support — respond with real runtime state
function devtoolsScan() {
  const elements = document.querySelectorAll(`[${ISLAND_ATTR}]`);
  const islands = [];
  elements.forEach(el => {
    const name = el.getAttribute(ISLAND_ATTR);
    const id = el._marchIslandId || ('island-' + (++_devtoolsIdCounter));
    el._marchIslandId = id;
    islands.push({
      id,
      name,
      hydration: el.getAttribute(HYDRATE_ATTR) ?? 'eager',
      status: el._marchActor ? 'hydrated' : 'pending',
      state: safeParseJson(parseState(el)),
      props: {},
      wasmModule: `${name}.wasm`,
      parentId: null,
      children: [],
      mountedAt: Date.now(),
    });
  });
  window.postMessage({
    source: 'march-devtools-page',
    payload: { type: 'scan-result', islands, timestamp: Date.now() },
  }, '*');
}

// Listen for scan requests from the DevTools extension
window.addEventListener('message', event => {
  if (event.source !== window) return;
  if (event.data?.source === 'march-devtools-extension' && event.data.type === 'scan') {
    devtoolsScan();
  }
});

// Expose scan on the marchIslands object for the debug script
if (window.__MARCH_DEBUG) {
  window.__marchDevtools = window.__marchDevtools ?? {};
  window.__marchDevtools.scan = devtoolsScan;
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootstrap);
} else {
  // Already loaded (e.g. script placed at end of body)
  bootstrap();
}

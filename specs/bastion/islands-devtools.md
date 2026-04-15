# March Islands DevTools — Firefox Extension Spec

**Status:** Design spec. Implementation not started.

**Target:** Firefox WebExtension (DevTools panel) for debugging March Islands in development.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Runtime Instrumentation (`march-islands.js`)](#runtime-instrumentation)
4. [Extension Structure](#extension-structure)
5. [DevTools Panel Features](#devtools-panel-features)
6. [Communication Protocol](#communication-protocol)
7. [UI/UX Design](#uiux-design)
8. [Click-to-Inspect Integration](#click-to-inspect-integration)
9. [Performance Considerations](#performance-considerations)
10. [Build & Distribution](#build--distribution)
11. [Testing Strategy](#testing-strategy)
12. [Future Work](#future-work)

---

## Overview

The March Islands DevTools extension adds a **"March"** panel to Firefox Developer Tools. It provides real-time visibility into the island component system used by Bastion web applications: live state inspection, message tracing, component tree visualization, hydration status, and WASM module metadata.

The extension targets **development builds only**. The `march-islands.js` runtime exposes instrumentation hooks when a debug flag is set; production builds carry zero overhead.

### Design principles

- **Zero production cost.** All instrumentation is gated behind `window.__MARCH_DEBUG`. The runtime ships no debug code in production.
- **Passive observation.** The devtools read state — they never mutate island actors or inject messages (except for explicit "send test message" actions the developer initiates).
- **Familiar UX.** The panel layout follows conventions established by React DevTools and Vue DevTools: tree on the left, inspector on the right, message log below.

---

## Architecture

### High-level data flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Inspected Page                           │
│                                                                 │
│  march-islands.js (with __MARCH_DEBUG instrumentation)          │
│       │                                                         │
│       │  window.__marchDevtools.emit(event)                     │
│       ▼                                                         │
│  ┌──────────────────┐                                           │
│  │  Content Script   │  (march-devtools-content.js)             │
│  │  Listens on       │                                          │
│  │  __marchDevtools  │                                          │
│  └────────┬─────────┘                                           │
│           │  window.postMessage → port.postMessage              │
└───────────┼─────────────────────────────────────────────────────┘
            │  browser.runtime message / port
            ▼
┌───────────────────────┐       ┌─────────────────────────────────┐
│   Background Script   │◄─────►│       DevTools Panel            │
│  (march-devtools-bg.js│       │  (panel.html + panel.js)        │
│   message router)     │       │  React/Preact UI                │
└───────────────────────┘       └─────────────────────────────────┘
```

### Firefox WebExtension APIs used

| API | Purpose |
|-----|---------|
| `devtools.panels.create()` | Register the "March" panel in the DevTools sidebar |
| `devtools.inspectedWindow.tabId` | Identify the inspected tab for message routing |
| `devtools.inspectedWindow.eval()` | One-shot queries (e.g. "is March on this page?") |
| `runtime.connect()` / `Port` | Long-lived message channel between panel ↔ background |
| `runtime.onConnect` | Background script listens for panel + content script connections |
| Content script injection | `content_scripts` manifest entry matching `<all_urls>` (gated by runtime detection) |
| `tabs.sendMessage()` | Background → content script for on-demand queries |

### Why a background script?

Content scripts and devtools panels live in separate execution contexts in Firefox. The background script acts as a message router: it receives events from the content script (which observes the page) and forwards them to the devtools panel (which renders the UI). This is the standard pattern for Firefox/Chrome devtools extensions.

---

## Runtime Instrumentation

The `march-islands.js` runtime (located at `priv/js/march-islands.js`) must be extended with debug hooks. All instrumentation is gated behind a debug flag so production builds are unaffected.

### Enabling debug mode

Debug mode activates when **any** of these conditions is true:

1. `window.__MARCH_DEBUG = true` is set before the runtime script loads.
2. The `<script>` tag includes `data-march-debug="true"`:
   ```html
   <script type="module" src="/_march/islands/march-islands.js"
           data-march-base="/_march/islands"
           data-march-debug="true"></script>
   ```
3. The URL contains `?march_debug=1` (development convenience).
4. `localStorage.getItem('march_debug') === '1'` (persistent toggle from devtools panel).

The `Islands.bootstrap_script` stdlib function gains an optional `debug` parameter:

```march
fn bootstrap_script(base_url) do ... end
fn bootstrap_script_debug(base_url) do
  "<script type=\"module\" src=\"${base_url}/march-islands.js\" data-march-debug=\"true\"></script>"
end
```

### Debug event bus (`window.__marchDevtools`)

When debug mode is active, the runtime creates a global event bus:

```js
// Installed by march-islands.js when debug mode is detected
window.__marchDevtools = {
  _listeners: [],

  emit(event) {
    for (const fn of this._listeners) {
      try { fn(event); } catch (e) { /* swallow — devtools must not break app */ }
    }
  },

  on(fn) {
    this._listeners.push(fn);
    return () => {
      this._listeners = this._listeners.filter(f => f !== fn);
    };
  },

  // Snapshot APIs — called by content script on demand
  getIslands()    { /* returns island metadata array */ },
  getIslandState(name) { /* returns current state JSON */ },
  getIslandTree() { /* returns parent/child tree */ },
};
```

### Events emitted by the runtime

Every event is a plain object with a `type` field and a high-resolution timestamp.

#### `island:registered`

Fired when an island element is discovered during bootstrap.

```js
{
  type: 'island:registered',
  timestamp: performance.now(),
  island: {
    name: 'Counter',                        // data-march-island value
    hydrationStrategy: 'eager',             // data-march-hydrate value
    initialState: '{"count":0}',            // data-march-state (raw JSON)
    elementSelector: '[data-march-island="Counter"]',
    hasCSS: false,                          // data-march-island-css present?
    domDepth: 4,                            // depth in DOM tree (for tree building)
    parentIsland: null,                     // name of nearest ancestor island, or null
  }
}
```

#### `island:hydrated`

Fired after WASM is loaded and the actor is spawned.

```js
{
  type: 'island:hydrated',
  timestamp: performance.now(),
  island: 'Counter',
  hydrationStrategy: 'eager',
  wasmLoadTimeMs: 23.4,                    // time to fetch + instantiate WASM
  wasmUrl: '/_march/islands/Counter.wasm',
  wasmModuleSize: 14280,                   // bytes (from fetch response)
  totalHydrationMs: 31.2,                  // strategy trigger → first render complete
}
```

#### `island:state-change`

Fired after every successful `update` call.

```js
{
  type: 'island:state-change',
  timestamp: performance.now(),
  island: 'Counter',
  message: { tag: 'Increment' },           // the message that triggered the update
  prevState: '{"count":2}',
  nextState: '{"count":3}',
  updateDurationMs: 0.12,                  // WASM update() call time
  renderDurationMs: 0.34,                  // WASM render() call time
}
```

#### `island:message-sent`

Fired when cross-island messaging is used (`window.marchIslands.send`).

```js
{
  type: 'island:message-sent',
  timestamp: performance.now(),
  sender: 'Sender',                         // or '__external__' for vanilla JS callers
  receiver: 'Receiver',
  message: { tag: 'Ping' },
}
```

#### `island:event-bound`

Fired when `attachEventHandlers` binds a `data-on-*` handler.

```js
{
  type: 'island:event-bound',
  timestamp: performance.now(),
  island: 'EventTest',
  eventType: 'click',                       // click | input | change | submit
  messageTag: 'Increment',                  // data-on-click value
  elementSelector: 'button[data-on-click="Increment"]',
}
```

#### `island:error`

Fired on update or render errors.

```js
{
  type: 'island:error',
  timestamp: performance.now(),
  island: 'Counter',
  phase: 'update',                          // 'update' | 'render' | 'hydration'
  error: 'RuntimeError: unreachable',
  stack: '...',
}
```

### Snapshot APIs

The content script can call these synchronously to get current state without waiting for events:

```js
window.__marchDevtools.getIslands()
// Returns:
[
  {
    name: 'Counter',
    hydrated: true,
    hydrationStrategy: 'eager',
    state: '{"count":3}',
    parentIsland: null,
    childIslands: ['SubCounter'],
    wasmUrl: '/_march/islands/Counter.wasm',
    wasmModuleSize: 14280,
    hasCSS: true,
    cssLength: 482,
    elementSelector: '[data-march-island="Counter"]',
    boundEvents: [
      { type: 'click', tag: 'Increment', selector: 'button.inc' },
      { type: 'click', tag: 'Decrement', selector: 'button.dec' },
    ],
  },
  // ...
]
```

```js
window.__marchDevtools.getIslandTree()
// Returns a tree structure:
{
  roots: [
    {
      name: 'AppShell',
      children: [
        { name: 'Header', children: [] },
        { name: 'Counter', children: [
          { name: 'SubCounter', children: [] }
        ]},
        { name: 'Footer', children: [] },
      ]
    }
  ]
}
```

### Modifications to `IslandActor`

The `IslandActor` class in `march-islands.js` needs targeted instrumentation. Here is a diff-style summary of changes:

```js
class IslandActor {
  #name;
  #wasm;
  #state;
  #element;
  #mailbox = [];
  #ticking = false;

  // ── NEW: debug metadata ──
  #hydratedAt = null;      // timestamp
  #wasmUrl = null;         // URL of the loaded .wasm
  #wasmSize = null;        // byte size
  #updateCount = 0;        // total messages processed
  #lastUpdateMs = 0;       // last update duration

  constructor(name, wasmInstance, initialState, element, /* NEW */ debugMeta) {
    // ... existing code ...
    if (window.__marchDevtools && debugMeta) {
      this.#hydratedAt = performance.now();
      this.#wasmUrl = debugMeta.wasmUrl;
      this.#wasmSize = debugMeta.wasmSize;
    }
  }

  // ── NEW: expose read-only debug info ──
  get _debugInfo() {
    if (!window.__marchDevtools) return null;
    return {
      name: this.#name,
      state: this.#state,
      mailboxLength: this.#mailbox.length,
      updateCount: this.#updateCount,
      lastUpdateMs: this.#lastUpdateMs,
      hydratedAt: this.#hydratedAt,
      wasmUrl: this.#wasmUrl,
      wasmSize: this.#wasmSize,
    };
  }

  #drain() {
    while (this.#mailbox.length > 0) {
      const msg = this.#mailbox.shift();
      try {
        const prevState = this.#state;
        const t0 = performance.now();
        this.#state = this.#wasm.update(this.#state, JSON.stringify(msg));
        const t1 = performance.now();
        this.#updateCount++;
        this.#lastUpdateMs = t1 - t0;

        const t2 = performance.now();
        this.#render();
        const t3 = performance.now();

        // ── NEW: emit state change ──
        if (window.__marchDevtools) {
          window.__marchDevtools.emit({
            type: 'island:state-change',
            timestamp: t0,
            island: this.#name,
            message: msg,
            prevState: prevState,
            nextState: this.#state,
            updateDurationMs: t1 - t0,
            renderDurationMs: t3 - t2,
          });
        }
      } catch (err) {
        console.error(`[march-islands] ${this.#name}: update error`, err);
        // ── NEW: emit error ──
        if (window.__marchDevtools) {
          window.__marchDevtools.emit({
            type: 'island:error',
            timestamp: performance.now(),
            island: this.#name,
            phase: 'update',
            error: err.message,
            stack: err.stack,
          });
        }
      }
    }
    this.#ticking = false;
  }

  // ... render instrumentation follows same pattern ...
}
```

### Modifications to `hydrateIsland`

```js
async function hydrateIsland(element, baseUrl) {
  const name = element.getAttribute(ISLAND_ATTR);
  if (!name || element._marchActor) return;

  // ── NEW: emit registered ──
  if (window.__marchDevtools) {
    window.__marchDevtools.emit({
      type: 'island:registered',
      timestamp: performance.now(),
      island: {
        name,
        hydrationStrategy: element.getAttribute(HYDRATE_ATTR) ?? 'eager',
        initialState: element.getAttribute(STATE_ATTR) ?? '{}',
        elementSelector: `[data-march-island="${name}"]`,
        hasCSS: element.hasAttribute('data-march-island-css'),
        parentIsland: findParentIsland(element),
      }
    });
  }

  const t0 = performance.now();
  const wasm = await loadWasmModule(baseUrl, name);
  const t1 = performance.now();
  if (!wasm) return;

  const initialStateJson = parseState(element);
  const debugMeta = window.__marchDevtools
    ? { wasmUrl: `${baseUrl}/${name}.wasm`, wasmSize: wasm._byteSize ?? null }
    : null;
  const actor = new IslandActor(name, wasm, initialStateJson, element, debugMeta);

  element._marchActor = actor;
  window.marchIslands = window.marchIslands ?? {};
  window.marchIslands[name] = actor;
  actor.send({ tag: '__init__' });

  // ── NEW: emit hydrated ──
  if (window.__marchDevtools) {
    window.__marchDevtools.emit({
      type: 'island:hydrated',
      timestamp: performance.now(),
      island: name,
      hydrationStrategy: element.getAttribute(HYDRATE_ATTR) ?? 'eager',
      wasmLoadTimeMs: t1 - t0,
      wasmUrl: `${baseUrl}/${name}.wasm`,
      wasmModuleSize: wasm._byteSize ?? null,
      totalHydrationMs: performance.now() - t0,
    });
  }
}
```

### Parent/child detection (`findParentIsland`)

Islands are nested in the DOM. The parent/child relationship is determined by DOM ancestry:

```js
/**
 * Walk up the DOM from `element` to find the nearest ancestor with
 * data-march-island. Returns the island name or null.
 */
function findParentIsland(element) {
  let node = element.parentElement;
  while (node) {
    if (node.hasAttribute(ISLAND_ATTR)) {
      return node.getAttribute(ISLAND_ATTR);
    }
    node = node.parentElement;
  }
  return null;
}
```

### Modifications to `sendToIsland`

```js
function sendToIsland(name, msg) {
  // ── NEW: trace cross-island messages ──
  if (window.__marchDevtools) {
    window.__marchDevtools.emit({
      type: 'island:message-sent',
      timestamp: performance.now(),
      sender: window.__marchDevtools._currentSender ?? '__external__',
      receiver: name,
      message: msg,
    });
  }

  const el = document.querySelector(`[${ISLAND_ATTR}="${name}"]`);
  if (el?._marchActor) {
    el._marchActor.send(msg);
  } else {
    console.warn(`[march-islands] No hydrated island named "${name}"`);
  }
}
```

To track sender identity, the actor's `#drain` method sets `window.__marchDevtools._currentSender = this.#name` before processing messages that may trigger cross-island sends, and clears it afterward.

---

## Extension Structure

### File layout

```
march-devtools-extension/
├── manifest.json
├── devtools/
│   ├── devtools.html           # devtools page (creates panel)
│   ├── devtools.js             # calls devtools.panels.create()
│   ├── panel.html              # panel UI shell
│   ├── panel.js                # panel entry point
│   └── components/
│       ├── IslandTree.js       # tree view component
│       ├── IslandInspector.js  # state/props inspector
│       ├── MessageLog.js       # message timeline
│       ├── PerformanceTab.js   # timing / WASM metrics
│       ├── SearchBar.js        # filter/search
│       └── StateViewer.js      # JSON state viewer with diffing
├── content/
│   └── march-devtools-content.js   # content script (bridges page ↔ extension)
├── background/
│   └── march-devtools-bg.js        # background message router
├── icons/
│   ├── march-16.png
│   ├── march-32.png
│   └── march-48.png
├── styles/
│   └── panel.css
└── lib/
    └── preact.min.js           # Preact for panel UI (lightweight)
```

### `manifest.json`

```json
{
  "manifest_version": 2,
  "name": "March Islands DevTools",
  "version": "0.1.0",
  "description": "Debugging tools for March Islands (Bastion web framework)",
  "icons": {
    "16": "icons/march-16.png",
    "32": "icons/march-32.png",
    "48": "icons/march-48.png"
  },

  "devtools_page": "devtools/devtools.html",

  "background": {
    "scripts": ["background/march-devtools-bg.js"],
    "persistent": false
  },

  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content/march-devtools-content.js"],
      "run_at": "document_start",
      "all_frames": true
    }
  ],

  "permissions": [
    "activeTab"
  ]
}
```

### `devtools/devtools.js`

```js
// Check if the page has March islands before creating the panel.
// This keeps the panel hidden on non-March pages.
browser.devtools.inspectedWindow.eval(
  `!!(window.__marchDevtools || document.querySelector('[data-march-island]'))`,
  function(hasMarch) {
    if (hasMarch) {
      browser.devtools.panels.create(
        'March',
        '/icons/march-32.png',
        '/devtools/panel.html'
      );
    }
  }
);
```

---

## DevTools Panel Features

The panel has four tabs across the top: **Islands**, **Messages**, **Performance**, and **Settings**.

### Tab 1: Islands (default)

Split into two panes: **Island Tree** (left, 35% width) and **Island Inspector** (right, 65% width).

#### Island Tree (left pane)

Displays all islands on the page as a tree reflecting DOM nesting (parent/child relationships). Each node shows:

```
▼ AppShell          eager  ✓ hydrated
  ▼ Header          eager  ✓ hydrated
  ▼ Counter         eager  ✓ hydrated   3 updates
    SubCounter      lazy   ○ pending
  Footer            idle   ✓ hydrated
```

- **Expand/collapse** — click triangle to expand children.
- **Selection** — click an island name to populate the inspector.
- **Status indicators:**
  - `✓ hydrated` (green) — WASM loaded, actor running.
  - `○ pending` (gray) — registered but not yet hydrated (lazy/idle/interaction).
  - `⚠ error` (red) — hydration or runtime error occurred.
- **Update badge** — shows the number of state updates since panel opened (resets on clear).
- **Search/filter bar** at the top filters by island name, state contents, hydration strategy, or source file.

#### Island Inspector (right pane)

When an island is selected, the inspector shows four collapsible sections:

**1. Identity**

| Field | Value |
|-------|-------|
| Name | `Counter` |
| Hydration | `eager` |
| Status | Hydrated at +31.2ms |
| DOM Element | `div[data-march-island="Counter"]` (click to reveal in Elements panel) |

**2. State (live)**

A syntax-highlighted, collapsible JSON tree of the island's current state. Updates in real time as `island:state-change` events arrive. Changed fields flash yellow briefly on update.

```json
{
  "count": 3         ← highlighted: changed from 2
}
```

Features:
- **Copy state** button — copies current state JSON to clipboard.
- **Edit state** button (dev mode) — allows editing state JSON and pushing it to the actor for debugging. Uses `actor.send({ tag: '__devtools_set_state__', state: newState })` — a special message tag the runtime recognizes in debug mode.
- **State history** — a timeline slider showing the last N states (default 50). Scrub to see previous states. Clicking a history entry shows the diff.

**3. WASM Module**

| Field | Value |
|-------|-------|
| WASM URL | `/_march/islands/Counter.wasm` |
| Module size | 14.2 KB |
| Load time | 23.4ms |
| Source file | `src/Counter.march` (if source map available) |
| Exports | `march_island_render`, `march_island_update`, `march_island_init` |

The **source file** field is populated from WASM custom sections or a sidecar `.wasm.map` file if present. When the March compiler (Tier 4) emits WASM, it should embed a `march_source` custom section:

```
Custom section "march_source":
  source_file: "src/Counter.march"
  module_name: "Counter"
  compiled_at: "2026-03-28T14:30:00Z"
  march_version: "0.1.0"
```

**4. Event Bindings**

Lists all currently bound `data-on-*` handlers in the island's DOM subtree:

| Event | Tag | Element |
|-------|-----|---------|
| click | `Increment` | `button.inc` |
| click | `Decrement` | `button.dec` |
| input | `SetValue` | `input[type="number"]` |

Clicking an element selector highlights it in the page.

**5. Scoped CSS**

If the island has `data-march-island-css`, displays the scoped CSS with syntax highlighting. Shows the raw CSS length and whether the `<style>` tag has been injected into `<head>`.

### Tab 2: Messages

A filterable, searchable timeline of all inter-island and intra-island messages.

#### Message table columns

| Timestamp | Direction | Sender | Receiver | Message | Duration |
|-----------|-----------|--------|----------|---------|----------|
| 142.3ms | → | `Sender` | `Receiver` | `{ tag: "Ping" }` | 0.12ms |
| 145.7ms | ↻ | `Counter` | `Counter` | `{ tag: "Increment" }` | 0.08ms |
| 201.4ms | → | `__external__` | `Counter` | `{ tag: "SetValue", value: "5" }` | 0.15ms |

- **Direction column:** `→` for cross-island, `↻` for self (event handler within the same island), `⇐` for external (vanilla JS caller).
- **Filters:**
  - By sender island
  - By receiver island
  - By message tag (regex supported)
  - By time range
  - Cross-island only / self only / all
- **Payload inspection:** clicking a row expands it to show the full message object, previous state, next state, and a JSON diff.
- **Clear** button resets the log.
- **Pause/Resume** toggle to freeze the log while inspecting.
- **Export** button downloads the message log as JSON or CSV.

#### Message sequence diagram

A toggle switches between table view and a **sequence diagram** view (like a UML sequence diagram / MSC) showing message flow between islands as vertical lanes with arrows. Built with SVG; auto-scrolls to the latest message.

```
  Counter      Sender      Receiver
    │            │            │
    │            │──Ping─────►│
    │            │            │
    │◄──SetValue─┤            │
    │            │            │
```

### Tab 3: Performance

Aggregated performance metrics for all islands.

#### Hydration waterfall

A horizontal bar chart showing when each island was hydrated, relative to page load:

```
DOMContentLoaded ─┐
                  ├─ Counter    [████████]  23ms WASM + 8ms render
                  ├─ Header     [██████]    18ms WASM + 5ms render
                  │
viewport entry ───┤
                  ├─ LazyWidget [████]      12ms WASM + 3ms render
                  │
idle ─────────────┤
                  └─ IdleWorker [███]       9ms WASM + 2ms render
```

#### Per-island metrics table

| Island | Updates | Avg Update | Avg Render | WASM Size | Load Time | State Size |
|--------|---------|------------|------------|-----------|-----------|------------|
| Counter | 47 | 0.08ms | 0.31ms | 14.2 KB | 23.4ms | 42 B |
| Header | 2 | 0.04ms | 0.12ms | 8.1 KB | 18.1ms | 128 B |

- Sortable by any column.
- **Slow update highlight** — rows where avg update > 1ms are flagged yellow; > 5ms flagged red.

#### WASM bundle analysis

A treemap or bar chart showing the relative sizes of all loaded `.wasm` modules. Helps identify oversized island bundles.

### Tab 4: Settings

- **Debug mode toggle** — sets `localStorage.march_debug = '1'` and reloads the page.
- **State history depth** — configure how many state snapshots to retain (default 50).
- **Message log limit** — max messages before oldest are evicted (default 1000).
- **Highlight updates** — toggle the yellow flash on state changes in the inspector.
- **Overlay mode** — toggle the in-page island overlay (see Click-to-Inspect below).
- **Theme** — light/dark (follows Firefox DevTools theme via `browser.devtools.panels.themeName`).

---

## Communication Protocol

### Content script → Background → Panel

All messages follow a common envelope:

```js
{
  source: 'march-devtools',
  tabId: 42,                   // injected by content script
  payload: { /* event object from __marchDevtools.emit() */ }
}
```

### Content script (`march-devtools-content.js`)

```js
(function() {
  'use strict';

  // Inject a script into the page context to listen on __marchDevtools.
  // Content scripts run in an isolated world and cannot access page JS globals
  // directly, so we inject a small bridge script.
  const bridge = document.createElement('script');
  bridge.textContent = `
    (function() {
      // Wait for __marchDevtools to appear
      const check = setInterval(() => {
        if (!window.__marchDevtools) return;
        clearInterval(check);

        window.__marchDevtools.on(function(event) {
          window.postMessage({
            source: 'march-devtools-bridge',
            payload: event,
          }, '*');
        });

        // Signal that devtools bridge is ready
        window.postMessage({
          source: 'march-devtools-bridge',
          payload: { type: 'bridge:ready' },
        }, '*');
      }, 50);

      // Give up after 10s if no March runtime found
      setTimeout(() => clearInterval(check), 10000);
    })();
  `;
  (document.head || document.documentElement).appendChild(bridge);
  bridge.remove();

  // Listen for messages from the injected bridge script
  window.addEventListener('message', function(event) {
    if (event.source !== window) return;
    if (event.data?.source !== 'march-devtools-bridge') return;

    // Forward to background script via extension messaging
    browser.runtime.sendMessage({
      source: 'march-devtools-content',
      payload: event.data.payload,
    });
  });

  // Listen for commands from the panel (via background script)
  browser.runtime.onMessage.addListener(function(msg) {
    if (msg.source !== 'march-devtools-panel') return;

    if (msg.command === 'get-snapshot') {
      // Eval in page context to get current island state
      const script = document.createElement('script');
      script.textContent = `
        window.postMessage({
          source: 'march-devtools-bridge',
          payload: {
            type: 'snapshot:response',
            islands: window.__marchDevtools
              ? window.__marchDevtools.getIslands()
              : [],
            tree: window.__marchDevtools
              ? window.__marchDevtools.getIslandTree()
              : { roots: [] },
          }
        }, '*');
      `;
      (document.head || document.documentElement).appendChild(script);
      script.remove();
    }

    if (msg.command === 'highlight-island') {
      highlightIslandElement(msg.islandName);
    }

    if (msg.command === 'inspect-element') {
      // Open the island's DOM element in the Firefox Elements panel
      const script = document.createElement('script');
      script.textContent = `
        const el = document.querySelector('[data-march-island="${msg.islandName}"]');
        if (el) { window.__marchDevtools_inspectTarget = el; }
      `;
      (document.head || document.documentElement).appendChild(script);
      script.remove();
    }
  });

  // ── In-page highlight overlay ──
  let highlightOverlay = null;

  function highlightIslandElement(name) {
    if (!highlightOverlay) {
      highlightOverlay = document.createElement('div');
      highlightOverlay.id = 'march-devtools-highlight';
      highlightOverlay.style.cssText = `
        position: fixed; pointer-events: none; z-index: 2147483647;
        border: 2px solid #8b5cf6; background: rgba(139, 92, 246, 0.1);
        border-radius: 4px; transition: all 0.15s ease;
      `;
      document.body.appendChild(highlightOverlay);
    }

    const el = document.querySelector(`[data-march-island="${name}"]`);
    if (el) {
      const rect = el.getBoundingClientRect();
      highlightOverlay.style.display = 'block';
      highlightOverlay.style.top = rect.top + 'px';
      highlightOverlay.style.left = rect.left + 'px';
      highlightOverlay.style.width = rect.width + 'px';
      highlightOverlay.style.height = rect.height + 'px';

      // Show label
      highlightOverlay.textContent = name;
      highlightOverlay.style.color = '#8b5cf6';
      highlightOverlay.style.fontSize = '11px';
      highlightOverlay.style.fontFamily = 'system-ui, sans-serif';
      highlightOverlay.style.padding = '2px 6px';

      clearTimeout(highlightOverlay._hideTimer);
      highlightOverlay._hideTimer = setTimeout(() => {
        highlightOverlay.style.display = 'none';
      }, 2000);
    }
  }
})();
```

### Background script (`march-devtools-bg.js`)

```js
'use strict';

// Track connected panel ports by tabId
const panelPorts = new Map();

browser.runtime.onConnect.addListener(function(port) {
  if (port.name === 'march-devtools-panel') {
    // The panel sends its tabId as the first message
    port.onMessage.addListener(function(msg) {
      if (msg.type === 'init') {
        panelPorts.set(msg.tabId, port);
        port.onDisconnect.addListener(() => {
          panelPorts.delete(msg.tabId);
        });
      }
    });
  }
});

// Route content script messages to the appropriate panel
browser.runtime.onMessage.addListener(function(msg, sender) {
  if (msg.source !== 'march-devtools-content') return;

  const tabId = sender.tab?.id;
  if (!tabId) return;

  const port = panelPorts.get(tabId);
  if (port) {
    port.postMessage({
      source: 'march-devtools-bg',
      payload: msg.payload,
    });
  }
});
```

### Panel connection (`panel.js` initialization)

```js
const port = browser.runtime.connect({ name: 'march-devtools-panel' });
port.postMessage({ type: 'init', tabId: browser.devtools.inspectedWindow.tabId });

port.onMessage.addListener(function(msg) {
  if (msg.source !== 'march-devtools-bg') return;
  handleDevtoolsEvent(msg.payload);
});

// Request initial snapshot when panel opens
browser.devtools.inspectedWindow.eval(
  `window.__marchDevtools ? window.__marchDevtools.getIslands() : []`,
  function(result) {
    if (result) initializeIslandTree(result);
  }
);
```

---

## UI/UX Design

### Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│  [🏝 Islands]  [✉ Messages]  [⚡ Performance]  [⚙ Settings]       │
├──────────────────────┬──────────────────────────────────────────────┤
│  🔍 Filter islands   │  Counter                                    │
│                      │                                              │
│  ▼ AppShell    eager │  ── Identity ──                              │
│    Header      eager │  Name: Counter                               │
│    ► Counter   eager │  Hydration: eager ✓                          │
│    Footer      idle  │  Status: Hydrated at +31.2ms                 │
│                      │  Element: div[data-march-island="Counter"]   │
│                      │                                              │
│                      │  ── State (live) ──                          │
│                      │  {                                           │
│                      │    "count": 3  ← changed                    │
│                      │  }                                           │
│                      │  [Copy] [Edit] [History ◀ ▶]                │
│                      │                                              │
│                      │  ── WASM Module ──                           │
│                      │  URL: /_march/islands/Counter.wasm           │
│                      │  Size: 14.2 KB                               │
│                      │  Load time: 23.4ms                           │
│                      │  Source: src/Counter.march                   │
│                      │                                              │
│                      │  ── Event Bindings ──                        │
│                      │  click → Increment  (button.inc)             │
│                      │  click → Decrement  (button.dec)             │
├──────────────────────┴──────────────────────────────────────────────┤
│  Status: 5 islands (4 hydrated, 1 pending) │ 47 messages │ 0 errors│
└─────────────────────────────────────────────────────────────────────┘
```

### Theme integration

The panel reads `browser.devtools.panels.themeName` (`"dark"` or `"light"`) and applies matching styles. CSS custom properties:

```css
:root {
  /* Dark theme (default, matching Firefox dark DevTools) */
  --march-bg: #1e1e2e;
  --march-surface: #282840;
  --march-text: #cdd6f4;
  --march-text-dim: #6c7086;
  --march-accent: #8b5cf6;        /* March purple */
  --march-accent-dim: #6d28d9;
  --march-success: #4ade80;
  --march-warning: #fbbf24;
  --march-error: #f87171;
  --march-border: #45475a;
  --march-highlight: rgba(139, 92, 246, 0.15);
  --march-font-mono: 'SF Mono', Menlo, 'Fira Code', monospace;
}

:root[data-theme="light"] {
  --march-bg: #f8f8fc;
  --march-surface: #ffffff;
  --march-text: #1e1e2e;
  --march-text-dim: #6c7086;
  --march-accent: #7c3aed;
  --march-border: #e2e2f0;
  --march-highlight: rgba(124, 58, 237, 0.08);
}
```

### Search and filtering

The search bar at the top of the Island Tree supports:

- **Plain text** — matches island name (fuzzy).
- **`state:key=value`** — filters islands whose state JSON contains the key/value pair.
- **`hydration:lazy`** — filters by hydration strategy.
- **`source:Counter.march`** — filters by source file (when available).
- **`status:pending`** — filters by hydration status (`hydrated`, `pending`, `error`).
- **`has:css`** — islands with scoped CSS.

---

## Click-to-Inspect Integration

### Panel → Page (select island, highlight in page)

When the developer hovers over an island in the tree view, the content script highlights the corresponding DOM element with a purple overlay (see `highlightIslandElement` above). Clicking the "reveal in Elements" button uses `devtools.inspectedWindow.eval` with `inspect()`:

```js
function revealInElements(islandName) {
  browser.devtools.inspectedWindow.eval(
    `inspect(document.querySelector('[data-march-island="${islandName}"]'))`
  );
}
```

### Page → Panel (click element, select in panel)

When **Overlay mode** is enabled (toggle in Settings), the content script installs a click interceptor on the page:

```js
function enablePickerMode() {
  document.addEventListener('mousemove', function onMove(e) {
    // Find nearest ancestor with data-march-island
    let target = e.target;
    while (target && !target.hasAttribute('data-march-island')) {
      target = target.parentElement;
    }
    if (target) {
      highlightIslandElement(target.getAttribute('data-march-island'));
    }
  });

  document.addEventListener('click', function onPick(e) {
    e.preventDefault();
    e.stopPropagation();

    let target = e.target;
    while (target && !target.hasAttribute('data-march-island')) {
      target = target.parentElement;
    }
    if (target) {
      const name = target.getAttribute('data-march-island');
      browser.runtime.sendMessage({
        source: 'march-devtools-content',
        payload: { type: 'picker:selected', island: name }
      });
    }

    // Disable picker after selection
    document.removeEventListener('mousemove', onMove);
    document.removeEventListener('click', onPick, true);
  }, { capture: true, once: true });
}
```

The panel receives the `picker:selected` event and selects the corresponding island in the tree view.

---

## Performance Considerations

### Instrumentation overhead

All debug hooks are gated behind `if (window.__marchDevtools)`. When the flag is absent (production), the overhead is a single falsy property lookup per event — effectively zero.

When debug mode is active:
- `performance.now()` calls: ~2 per update cycle (negligible).
- `JSON.stringify(msg)`: messages are already stringified for WASM; we reuse the existing string where possible.
- State snapshots: `prevState` and `nextState` are the raw JSON strings the WASM bridge already produces — no extra serialization.
- Event emission: the `emit()` loop iterates a small listener array (typically 1 listener: the content script bridge).

### Panel efficiency

- The panel uses **Preact** (3 KB gzipped) for rendering — no heavy frameworks.
- State history uses a **ring buffer** to cap memory at N entries.
- Message log uses **virtualized scrolling** (only renders visible rows) to handle thousands of messages.
- The panel **pauses event processing** when the March tab is not visible (`document.visibilityState`) and replays missed events on refocus.

### Content script bridge

- The injected bridge script uses `window.postMessage` which involves structured cloning. For very high-frequency state changes (e.g. animations), the bridge applies **throttling**: at most 60 events/second are forwarded to the extension. A `_batchPending` flag collects events and flushes on `requestAnimationFrame`.

```js
// Inside the injected bridge:
let batch = [];
let batchPending = false;

window.__marchDevtools.on(function(event) {
  batch.push(event);
  if (!batchPending) {
    batchPending = true;
    requestAnimationFrame(() => {
      window.postMessage({
        source: 'march-devtools-bridge',
        payload: { type: 'batch', events: batch },
      }, '*');
      batch = [];
      batchPending = false;
    });
  }
});
```

---

## Build & Distribution

### Build toolchain

```
march-devtools-extension/
├── package.json
├── build.js                # esbuild script
└── src/                    # source (TypeScript for panel, plain JS for content/bg)
```

- **Panel UI** — TypeScript + Preact, bundled with esbuild into `devtools/panel.js`.
- **Content script** — plain JS, no bundling needed (runs in content script sandbox).
- **Background script** — plain JS, minimal.
- **Build:** `node build.js` → outputs to `dist/`.
- **Package:** `web-ext build` (Mozilla's official tool) → produces `.xpi` for Firefox.

### Development workflow

```bash
cd march-devtools-extension
npm install
npm run dev        # esbuild watch + web-ext run (opens Firefox with extension loaded)
npm run build      # production build
npm run package    # create .xpi
npm run lint       # web-ext lint (checks manifest, permissions, etc.)
```

### Distribution

- **Firefox Add-ons (AMO)** — submit the `.xpi` for review. Listed as a developer tool.
- **Self-hosted** — provide the `.xpi` download on the March documentation site for sideloading.
- **Forge integration** (future) — `forge add march-devtools` installs the extension and enables debug mode in the dev server.

---

## Testing Strategy

### Unit tests

- **Runtime instrumentation:** extend the existing browser test suite (`islands/test/browser/test_islands.html`) with tests that enable `__MARCH_DEBUG`, perform actions, and assert that the correct events are emitted.
- **Snapshot APIs:** test `getIslands()`, `getIslandTree()`, `getIslandState()` against known fixtures.
- **Parent/child detection:** test `findParentIsland()` with nested island DOM structures.

### Integration tests

- **Extension end-to-end:** use Selenium or Puppeteer with Firefox to load a test page, open DevTools, verify the March panel appears, and check that island state is displayed correctly.
- **Message routing:** verify content script → background → panel message flow using mock ports.
- **Throttling:** verify that high-frequency state changes are batched correctly.

### Manual test page

Create `islands/test/browser/devtools_test_page.html` — a page with multiple nested islands, cross-island messaging, various hydration strategies, and scoped CSS. This serves as the reference page for manual devtools testing during development.

```html
<!-- Test fixture: nested islands with cross-messaging -->
<div data-march-island="AppShell" data-march-hydrate="eager"
     data-march-state='{"page":"home"}'>
  <div data-march-island="Sidebar" data-march-hydrate="eager"
       data-march-state='{"collapsed":false}'>
    <nav>...</nav>
  </div>
  <div data-march-island="Counter" data-march-hydrate="eager"
       data-march-state='{"count":0}'
       data-march-island-css="[data-march-island=Counter] .count { color: blue; }">
    <span class="count">0</span>
    <button data-on-click="Increment">+</button>
  </div>
  <div data-march-island="LazyChart" data-march-hydrate="lazy"
       data-march-state='{"data":[]}'>
    <p>Loading chart...</p>
  </div>
</div>
```

---

## Future Work

Items not in scope for the initial release but planned for later versions:

- **Time-travel debugging.** The state history slider is a foundation. A full time-travel implementation would replay messages against a WASM module to reconstruct any past state, allowing the developer to step forward/backward through the island's lifecycle.
- **WebSocket live island tracing.** When server-backed live islands (via WebSocket) are implemented, the devtools should show server ↔ client message flow alongside client-side messages.
- **WASM memory inspector.** Show the WASM linear memory layout, allocation patterns, and GC pressure for each island module. Requires cooperation with the March WASM runtime's memory allocator.
- **Source mapping.** When the March compiler emits WASM source maps, the devtools should display the original `.march` source alongside the island inspector, with breakpoint support.
- **Chrome/Edge port.** The extension uses Manifest V2 `browser.*` APIs. Porting to Chrome's Manifest V3 (`chrome.*` with service workers) is straightforward but requires a separate build target.
- **Multi-page / SPA support.** Track islands across SPA navigations where the runtime re-bootstraps without a full page reload. Requires the runtime to emit `bootstrap:start` / `bootstrap:complete` events.
- **Network waterfall integration.** Hook into Firefox's Network panel to annotate `.wasm` requests with island metadata (which island loaded it, hydration trigger time).
- **Accessibility audit.** Scan island-rendered HTML for ARIA issues and display warnings in the inspector.
- **Performance budgets.** Allow developers to set per-island budgets (max WASM size, max update time) and flag violations in the Performance tab.

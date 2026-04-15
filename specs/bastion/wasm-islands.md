# Bastion — WASM Islands

**Status:** Framework infrastructure complete. WASM compilation pending Tier 4 browser target.

## What is an island?

An _island_ is an interactive UI component that:
1. **Renders server-side** — producing static HTML included in the page response.
2. **Hydrates client-side** — a compiled March `.wasm` module loads in the browser and takes over the DOM node, enabling full interactivity without a full client-side framework.

Surrounding static content remains plain HTML. Only islands ship and execute JavaScript (well, WASM). This is the "Islands Architecture" pattern (Astro, Qwik, Fresh).

## Island declaration

Islands are regular March modules that implement the `Island(s)` interface:

```march
-- Counter.march
mod Counter do
  type State = { count : Int }
  type Msg = Increment | Decrement | SetValue(Int)

  fn render(state : State) : String do
    "<div class=\"counter\">" ++
    "  <button data-on-click=\"Decrement\">-</button>" ++
    "  <span>${state.count}</span>" ++
    "  <button data-on-click=\"Increment\">+</button>" ++
    "</div>"
  end

  fn update(state : State, msg : Msg) : State do
    match msg do
    | Increment        -> { state with count = state.count + 1 }
    | Decrement        -> { state with count = state.count - 1 }
    | SetValue(n)      -> { state with count = n }
    end
  end

  -- Called by the Island interface impl to decode JSON messages from the JS runtime.
  fn decode_msg(json : String) : Msg do
    -- TODO: derive Json.decode when the derive macro lands.
    -- For now, hand-write or use Json.parse.
    match json do
    | "\"Increment\""        -> Increment
    | "\"Decrement\""        -> Decrement
    | _                      -> Increment  -- fallback
    end
  end
end

-- Register as an island (connects to the Islands framework):
impl Island(Counter.State) do
  fn render(state) do Counter.render(state) end
  fn update(state, msg_json) do Counter.update(state, Counter.decode_msg(msg_json)) end
end
```

## Server-side rendering

Use `Islands.wrap` in your page template:

```march
fn counter_page(conn) do
  let initial = { count = 0 }
  let state_json = Json.to_string(Json.object([
    ("count", Json.number(int_to_float(initial.count)))
  ]))
  let island_html = Islands.wrap(
    "Counter",
    Islands.Eager,
    state_json,
    Counter.render(initial)
  )
  let page = "<!DOCTYPE html><html><head>" ++
             Islands.bootstrap_script("/_march/islands") ++
             "</head><body>" ++
             island_html ++
             "</body></html>"
  HttpServer.html(conn, 200, page)
end
```

## Hydration markers

`Islands.wrap` generates a `<div>` with three data attributes:

```html
<div data-march-island="Counter"
     data-march-hydrate="eager"
     data-march-state='{"count":0}'>
  <!-- SSR content: shown immediately, replaced after WASM hydrates -->
  <div class="counter">
    <button data-on-click="Decrement">-</button>
    <span>0</span>
    <button data-on-click="Increment">+</button>
  </div>
</div>
```

| Attribute | Value | Purpose |
|-----------|-------|---------|
| `data-march-island` | `"Counter"` | Matches the `.wasm` filename |
| `data-march-hydrate` | `"eager"` | Hydration strategy |
| `data-march-state` | `'{"count":0}'` | JSON initial state (single-quoted to allow JSON double-quotes) |

Single quotes in state JSON are escaped as `&#39;` by `Islands.escape_state`.

## Hydration strategies

| Strategy | `HydrateOn` | Trigger |
|----------|-------------|---------|
| `eager` | `Eager` | DOMContentLoaded |
| `lazy` | `Lazy` | IntersectionObserver (viewport entry) |
| `idle` | `OnIdle` | requestIdleCallback (or 200ms timeout on Safari) |
| `interaction` | `OnInteraction` | First click / focusin / touchstart / pointerdown |

Choose based on the island's priority:
- **Eager**: above-the-fold, immediately interactive components.
- **Lazy**: below-the-fold components (infinite scroll items, accordions).
- **Idle**: analytics widgets, non-critical enhancements.
- **Interaction**: components that only need to be interactive when touched.

## Event binding

The JS runtime scans the island's DOM after every render for `data-on-*` attributes:

| Attribute | Event | Message sent to actor |
|-----------|-------|-----------------------|
| `data-on-click="Increment"` | click | `{ tag: "Increment" }` |
| `data-on-input="SetQuery"` | input | `{ tag: "SetQuery", value: "..." }` |
| `data-on-change="Toggle"` | change | `{ tag: "Toggle", checked: true }` |
| `data-on-submit="Save"` | submit | `{ tag: "Save", data: { ... } }` |

The actor's `update` function receives a JSON-encoded message string. The Island interface impl is responsible for decoding it into the proper `Msg` type.

## Actor-per-island model

Each hydrated island runs as a `IslandActor` in the JS runtime:

```
User event (click "Increment")
    │
    ▼
IslandActor.send({ tag: "Increment" })
    │  queued via queueMicrotask (cooperative scheduler)
    ▼
WASM: update(stateJson, msgJson) → newStateJson
    │
    ▼
WASM: render(newStateJson) → htmlString
    │
    ▼
element.innerHTML = htmlString
attachEventHandlers(element, actor)
```

Islands are isolated — state is owned by the actor. Cross-island messaging goes through the global `window.marchIslands.send(name, msg)` API, which routes to the named actor.

## WASM compilation (TODO)

**Current status:** Tier 1 WASM (pure compute, `wasm64-wasi`) is code-complete, awaiting toolchain. Browser target (`wasm32-unknown-unknown`) is Tier 4 on the roadmap.

When Tier 4 lands, the compiler will:
1. Accept `--target wasm32-unknown-unknown` for island modules.
2. Emit a JS glue sidecar (`Counter.glue.js`) alongside `Counter.wasm`.
3. Export `march_island_render`, `march_island_update`, `march_island_init`.
4. Generate `march_alloc` / `march_dealloc` for string passing across the WASM boundary.

The `loadWasmModule` stub in `march-islands.js` has the exact integration point documented:

```js
// TODO (Tier 4): Replace with real loading:
// const { instance } = await WebAssembly.instantiateStreaming(
//   fetch(`${baseUrl}/${name}.wasm`), { env: buildMarchImports() }
// );
// return wrapWasmExports(instance.exports, name);
```

## Island registry (server startup)

```march
let registry =
  Islands.empty_registry()
  |> Islands.register(Islands.Descriptor("Counter", Islands.Eager, "/_march/Counter.wasm"))
  |> Islands.register(Islands.Descriptor("Clock",   Islands.Lazy,  "/_march/Clock.wasm"))

-- In your page template:
let preloads = Islands.registry_preload_hints(registry, "/_march")
-- → <link rel="modulepreload" href="/_march/Counter.wasm">
--   <link rel="modulepreload" href="/_march/Clock.wasm">
```

## Testing islands

```march
-- Test server-side rendering without WASM:
test "counter renders initial state" do
  let html = Counter.render({ count = 0 })
  assert (String.contains(html, "0"))
end

-- Test hydration wrapping:
test "wrap produces correct attributes" do
  let html = Islands.wrap("Counter", Islands.Eager, "{\"count\":0}", "<span>0</span>")
  assert (String.contains(html, "data-march-island=\"Counter\""))
  assert (String.contains(html, "data-march-hydrate=\"eager\""))
end

-- Test state update logic (pure, no WASM needed):
test "increment increases count" do
  let s = Counter.update({ count = 5 }, Counter.Increment)
  assert (s.count == 6)
end
```

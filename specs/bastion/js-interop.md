# Bastion: JavaScript Interop

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

WASM modules cannot directly access the DOM or browser APIs. Bastion provides a thin FFI layer for WASM islands to call into JavaScript, plus a default bundler integrated into Forge for packaging JS dependencies alongside WASM bundles. The goal for v1 is pragmatic and minimal — typed wrappers over common browser APIs can be built by the ecosystem over time.

---

## FFI Layer (WASM → JS)

Islands call JavaScript through a simple FFI interface. Bastion provides a `JS` module with low-level primitives:

```march
mod Bastion.JS do
  # Call a JS function by name, passing serializable arguments
  fn call(func: String, args: List(JSValue)) -> JSValue

  # Access a JS global property
  fn global(name: String) -> JSValue

  # Evaluate raw JS (escape hatch — use sparingly)
  fn eval(code: String) -> JSValue

  # DOM helpers (thin wrappers, not a full abstraction)
  fn query_selector(selector: String) -> Option(JSElement)
  fn set_attribute(el: JSElement, key: String, value: String) -> Unit
  fn add_event_listener(el: JSElement, event: String, handler: fn(JSEvent) -> Msg) -> Unit
end
```

Islands use this FFI when they need browser APIs not covered by Bastion's built-in `Cmd` system:

```march
# Using the FFI to access the clipboard API
fn update(state, CopyToClipboard) do
  {state, Cmd.js(fn _ ->
    JS.call("navigator.clipboard.writeText", [state.selected_text])
  end)}
end

# Using the FFI to read geolocation
fn update(state, RequestLocation) do
  {state, Cmd.js(fn callback ->
    JS.call("navigator.geolocation.getCurrentPosition", [fn pos ->
      callback(GotLocation(%{lat: pos.coords.latitude, lng: pos.coords.longitude}))
    end])
  end)}
end
```

---

## Built-In Cmd Abstractions

For the most common browser interactions, Bastion provides typed `Cmd` constructors so developers don't need to drop to raw FFI:

```march
# HTTP requests (wraps fetch)
Cmd.http_get(url, response_handler)
Cmd.http_post(url, body, response_handler)

# Timers
Cmd.after(milliseconds, msg)
Cmd.every(milliseconds, msg)

# Channel communication
Cmd.channel_push(event, payload)

# Local storage (simple key-value)
Cmd.store_local(key, value)
Cmd.load_local(key, handler)

# Focus management
Cmd.focus(element_id)

# Navigation
Cmd.push_url(path)
Cmd.replace_url(path)
```

These are implemented using the JS FFI internally but expose a typed March interface.

---

## JS Dependencies and Bundling

Forge includes a default bundler for packaging JavaScript dependencies alongside WASM islands. This handles cases where an island needs a JS library (e.g., a charting library, a rich text editor, a mapping SDK).

```toml
# forge.toml
[js_deps]
chart_js = "4.4.0"
mapbox_gl = "3.0.0"
```

```march
# Using a JS dependency from an island
mod MyApp.Islands.Chart do
  import Bastion.JS

  fn init(props) do
    # The bundler ensures Chart.js is loaded before this island hydrates
    chart = JS.call("new Chart", [
      JS.query_selector("#chart-canvas"),
      props.chart_config
    ])
    %{chart: chart, data: props.data}
  end
end
```

Forge's bundler:

- Resolves JS packages from npm
- Bundles them alongside the island's WASM file
- Produces a single loadable unit per island (WASM + JS dependencies)
- Generates an import map or bundle manifest for the Bastion client runtime
- Tree-shakes unused JS code in production builds

---

## JS → WASM Interop (JSON Messages)

JavaScript can send messages *into* WASM islands using a simple JSON-based protocol. No shared memory, no complex typed bindings, no callbacks — just JSON in, JSON out.

```javascript
// JS sends a JSON message to a March island
const searchBar = Bastion.getIsland("MyApp.Islands.SearchBar");
searchBar.send({ type: "SetQuery", query: "new search term" });

// JS reads island state (returns JSON snapshot)
const state = searchBar.getState();
console.log(state.results.length);
```

On the March side, incoming JSON messages are decoded into the island's `Msg` type:

```march
mod MyApp.Islands.SearchBar do
  import Bastion.Island

  type Msg =
    | UpdateQuery(String)
    | SubmitSearch
    | SearchResults(List(User))
    | ExternalMessage(JSON.Value)  # catch-all for JS-originated messages

  # Handle messages from external JS
  fn update(state, ExternalMessage(json)) do
    case JSON.get(json, "type") do
      Ok("SetQuery") ->
        query = JSON.get_string(json, "query") |> Result.unwrap("")
        {%{state | query: query}, Cmd.none()}
      _ ->
        {state, Cmd.none()}
    end
  end
end
```

This enables incremental adoption: existing JS applications can embed March-powered WASM islands and communicate with them through a stable JSON interface. The boundary is deliberately simple — both sides serialize to JSON, no shared types across the language barrier.

---

## Typed Bidirectional Bindings (Future / v2)

Richer interop — where JS and WASM share typed interfaces, support callbacks, and avoid serialization overhead — is a v2 concern. This would include:

- Auto-generated TypeScript type definitions from March island types
- Direct function exports with typed signatures
- Shared memory for high-performance data transfer

# Browser Playground — "Try It Out" Page

**Goal:** Add a self-contained interactive playground to the docs site where visitors can write and run March code directly in the browser, with no install required.

**Approach:** Compile the OCaml pipeline (lexer → parser → desugar → typecheck → eval) to JavaScript using `js_of_ocaml`. The tree-walking interpreter already handles everything a playground needs: expressions, let bindings, functions, algebraic types, actors, pattern matching, the pipe operator. The compiled JS is loaded lazily on the playground page only.

---

## Architecture

```
docs/playground.md          ← Jekyll page (just front matter + one div)
docs/_includes/
  playground.html           ← self-contained widget HTML + inline CSS
  playground.js             ← thin JS glue (load WASM, call OCaml, render output)
docs/assets/march.js        ← js_of_ocaml output (lazy-loaded, ~2–5 MB gzipped ~600 KB)

js/
  march_browser.ml          ← OCaml entry point: exposes march_eval() to JS
  dune                      ← js_of_ocaml build target
```

The `march_browser.ml` file wraps the existing pipeline and registers a single JS-callable function:

```ocaml
let () =
  Js.export "marchEval" (fun code ->
    (* run lexer → parser → desugar → typecheck → eval *)
    (* return {output, error, type_} as a JS object *)
  )
```

Jekyll includes the widget HTML into the playground page. The widget lazy-loads `march.js` the first time the user clicks Run (no bundle download on page load).

---

## Phases

### Phase 1 — OCaml → JS bundle

**Files:** `js/march_browser.ml`, `js/dune`

1. Add a `js_of_ocaml` executable target in `js/dune` that depends on `march_eval`, `march_typecheck`, `march_parser`, `march_lexer`, `march_desugar`, `march_ast`.
2. Write `march_browser.ml`:
   - Stub `Unix` calls that can't work in a browser: `gettimeofday` → `0.0`, `open_process_in` → raise, uname detection → return `"browser"`.
   - Stub file I/O builtins (`File.read`, `File.write`) to return a user-visible error: `"File I/O is not available in the browser playground"`.
   - Run the full pipeline, capture stdout/stderr via a `Buffer.t`, return `{output: string, error: string | null}` via `Js.export`.
   - Actor concurrency works as-is: js_of_ocaml maps OCaml `Mutex` to no-ops; actor scheduling runs cooperatively in a single event loop tick, which is fine for demos.
3. Verify bundle size with `wc -c docs/assets/march.js`. Target: < 8 MB uncompressed, < 1 MB gzipped. If larger, profile with `js_of_ocaml --profile` and strip unused stdlib modules.

**Deliverable:** `docs/assets/march.js` loads in a browser console and `marchEval("1 + 1")` returns `{output: "2 : Int", error: null}`.

---

### Phase 2 — Widget HTML + JS glue

**Files:** `docs/_includes/playground.html`, `docs/_includes/playground.js`

Widget layout (two-column on desktop, stacked on mobile):

```
┌─────────────────────────────────────────────┐
│ [Example ▾]                        [Run ▶]  │
├──────────────────────┬──────────────────────┤
│                      │                      │
│   editor (textarea   │   output panel       │
│   or CodeMirror)     │   (stdout + type)    │
│                      │                      │
│                      │  Error (if any):     │
│                      │  highlighted red     │
└──────────────────────┴──────────────────────┘
```

JS glue responsibilities:
- On first Run click: inject a `<script src="/march/assets/march.js">` tag, wait for load, then call `marchEval(code)`.
- Subsequent runs: call `marchEval` directly (already loaded).
- Show a spinner while the bundle loads (first run only).
- Display output in the right panel; if `error` is non-null, show it styled as an error with a red left border.
- Preserve editor content in `sessionStorage` so it survives page refresh.

Start with a plain `<textarea>` for the editor. CodeMirror can be added later without changing the interface.

---

### Phase 3 — Examples gallery

A dropdown (or tab strip) with pre-loaded snippets that demonstrate March's distinctive features. Suggested set:

| Label | What it shows |
|---|---|
| Hello World | Minimal — functions, string concatenation |
| Pattern Matching | ADTs, exhaustiveness, guards |
| List Pipeline | Pipe operator, `List.map`, `List.filter` |
| Fibonacci | Recursion, multi-head functions |
| Option & Result | `with` chaining, safe error handling |
| Actor Counter | `actor`, `spawn`, `send` — the Elixir angle |
| FBIP Demo | Recursive tree transform, add a note about in-place reuse |

Each example is a string constant in `playground.js`. Selecting one from the dropdown replaces the editor content (with a confirmation if the editor has been modified).

---

### Phase 4 — Docs page + navigation

**File:** `docs/playground.md`

```markdown
---
layout: page
title: Try It Out
nav_order: 2
---

{% include playground.html %}
```

Add to `docs/index.md` documentation table:

```markdown
| [Try It Out](playground.md) | Run March code in your browser |
```

`nav_order: 2` puts it right below the landing page in the sidebar.

---

### Phase 5 — Polish

- **Keyboard shortcut:** `Ctrl+Enter` / `Cmd+Enter` runs the code.
- **URL state:** Encode editor content as a base64 URL fragment (`#code=...`) so examples can be linked from docs. Keep it opt-in — only write the URL hash on Run, not on every keystroke.
- **Output line limit:** Cap at 500 lines to prevent runaway output from locking up the UI.
- **Timeout:** Wrap `marchEval` in a Web Worker with a 5-second timeout to kill infinite loops. The Worker receives the code string and posts back the result; the main thread shows "Timed out after 5s" if no response arrives.
- **Mobile:** Make the layout single-column below 768 px; keep the Run button always visible.

---

## Unix stubs needed

These are the only `Unix` calls in the eval/interpreter path that need browser stubs:

| Call | Location | Stub |
|---|---|---|
| `Unix.gettimeofday ()` | `eval.ml` — `Time.now` builtin | Return `0.0` |
| `Unix.open_process_in "uname -s"` | runtime detection in `eval.ml` | Return `"browser"` |
| `Unix.getenv` | some stdlib builtins | Return `None` always |
| File descriptor ops | `File.*` builtins | Return `Error("not available in browser")` |

No changes to the core pipeline files. All stubs live in `march_browser.ml` via a `module Unix = Browser_unix` substitution or direct shadowing before linking.

---

## Build integration

Add a `make playground` target (or dune alias) that:
1. Builds `js/march_browser.ml` with js_of_ocaml
2. Copies output to `docs/assets/march.js`

This does NOT run as part of `dune build` by default — it's a manual step before deploying the docs site. The generated `march.js` is committed to the repo (like other generated docs assets) so GitHub Pages can serve it without a build step.

---

## What this does not cover

- **Sharing snippets** — URL hash encoding (Phase 5) is sufficient for linking; no server needed.
- **CodeMirror syntax highlighting** — nice to have, not required for v1. The Tree-sitter grammar already exists for Zed; a CodeMirror mode would need a separate port.
- **Saving sessions** — out of scope. `sessionStorage` for within-tab persistence is enough.
- **Multi-file programs** — single-file only. The playground is for exploration, not project development.
- **Native WASM execution** (Option B) — deferred. The interpreter is sufficient for demos and avoids needing a compilation server.

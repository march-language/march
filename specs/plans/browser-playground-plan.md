# Browser Playground — "Try It Out" Page

**Goal:** Add a self-contained interactive REPL to the docs site where visitors can write and run March code directly in the browser, with no install required.

**Approach:** Compile the OCaml pipeline (lexer → parser → desugar → typecheck → eval) to JavaScript using `js_of_ocaml`. The tree-walking interpreter handles everything a playground needs: expressions, let bindings, functions, algebraic types, actors, pattern matching, the pipe operator, and stateful sessions. The compiled JS is loaded lazily — only when the user first interacts with the REPL.

**Design reference:** [roc-lang.org/#try-roc](https://www.roc-lang.org/#try-roc). Key takeaways: terminal/REPL aesthetic rather than a split editor+output panel; stateful session so `let` bindings persist across inputs; Enter to run, Shift-Enter for newlines; minimal chrome — no explicit Run button; explanatory copy sits beside the terminal, not inside it; an arrow/hint points new users at where to start.

---

## UI Design

### Layout

Two-column on desktop, stacked on mobile. The REPL terminal occupies the left ~60%; explanatory copy sits to the right.

```
┌──────────────────────────────┐   ┌─────────────────────────────┐
│  march>                      │   │  Try March in your browser. │
│                              │   │                             │
│                              │   │  This is a live REPL —      │
│                              │   │  let bindings and function  │
│                              │   │  definitions persist for    │
│  march> █                    │   │  the session.               │
│                              │   │                             │
│                              │   │  Enter runs. Shift-Enter    │
│                              │   │  adds a newline.       ←───┘│
└──────────────────────────────┘
```

### Terminal aesthetics

- Dark background (`#1a1b26` or similar), matching the code blocks already on the docs site
- Monospace font throughout, matching `march>` prompt from the real REPL
- Output shows value + inferred type on the same line: `42 : Int`, `["a", "b"] : List(String)`
- Errors appear inline in the scroll history in a muted red, with the same friendly formatting the compiler already produces
- Scrollable history; new output appends at the bottom, input always at the bottom
- The terminal box has a subtle border and inner padding — close to the Roc style

### Input behaviour

- `Enter` — submit and run
- `Shift-Enter` — insert newline (for multi-line expressions, `do...end` blocks, etc.)
- `↑` / `↓` — navigate session history (same as the native REPL)
- Prompt is `march>`, continuation lines use `  ...>` (matching the native REPL exactly)

### First-load hint

On first render (before the bundle loads), the input is disabled and shows placeholder text: `"Loading…"`. Once ready, replace with `"Try: List.map([1, 2, 3], fn x -> x * 2)"` as the placeholder, and display a small arrow or callout pointing at the input suggesting a first expression to try — the same pattern as Roc's arrow pointing to "Try entering `0.1 + 0.2`".

### Example snippets

Below the REPL, a row of small clickable chips — not a dropdown. Clicking a chip pastes the snippet into the input (does not auto-run, so the user can read it first):

| Chip label | Snippet pasted |
|---|---|
| `1 + 1` | `1 + 1` |
| list pipeline | `[1, 2, 3, 4, 5] \|> List.filter(fn x -> x > 2) \|> List.map(fn x -> x * x)` |
| pattern match | three-line ADT + match expression |
| fibonacci | multi-head `fn fib` definition |
| actor | `actor Counter` definition + spawn + send |

Chips are small, inline, and subtle — they should feel like hints, not the main attraction.

---

## Architecture

```
docs/playground.md              ← Jekyll page (front matter + one include)
docs/_includes/
  playground.html               ← terminal UI: HTML structure + inline CSS
  playground.js                 ← session state, input handling, lazy bundle load
docs/assets/march.js            ← js_of_ocaml output (~2–5 MB, ~600 KB gzipped)

js/
  march_browser.ml              ← OCaml entry: exposes marchEval() + marchEvalStateful()
  dune                          ← js_of_ocaml build target
```

### JS API surface

`march_browser.ml` exposes two functions via `Js.export`:

```ocaml
(* Stateless: evaluate a single expression/declaration, return result *)
marchEval : string -> { output: string; error: string | null }

(* Stateful: evaluate within a persistent session environment *)
(* The session env is stored as a mutable ref in march_browser.ml *)
marchEvalSession : string -> { output: string; error: string | null }
marchResetSession : unit -> unit
```

The REPL widget uses `marchEvalSession` so `let` bindings and function definitions accumulate across inputs, matching the native REPL. `marchResetSession` is called when the user types `:reset`.

---

## Phases

### Phase 1 — OCaml → JS bundle

**Files:** `js/march_browser.ml`, `js/dune`

1. Add a `js_of_ocaml` executable target in `js/dune`:
   ```
   (executable
     (name march_browser)
     (libraries march_eval march_typecheck march_parser march_lexer march_desugar march_ast js_of_ocaml)
     (modes js))
   ```
2. Write `march_browser.ml`:
   - Maintain a mutable `session_env` ref (the eval environment, same type as `Eval.empty_env`).
   - Stub `Unix` calls: `gettimeofday` → `0.0`; `open_process_in` → raise; `getenv` → `None`; file descriptor ops → surface a user-friendly error string.
   - Capture `stdout` output via a `Buffer.t` replaced on `Format.std_formatter` before each eval call.
   - Return `{output, error}` as a `Js.t` object.
   - Actor concurrency: js_of_ocaml maps `Mutex` to no-ops; the cooperative scheduler runs fine in a single event loop tick for demo-scale programs.
3. Verify bundle size. Target: < 8 MB uncompressed, < 1 MB gzipped. Profile with `js_of_ocaml --profile` if larger.

**Deliverable:** Open a browser console, load `march.js`, call `marchEvalSession("1 + 1")`, get `{output: "2 : Int", error: null}`.

---

### Phase 2 — Terminal widget

**Files:** `docs/_includes/playground.html`, `docs/_includes/playground.js`

The widget is a single `<div class="march-repl">` containing:
- `<div class="repl-history">` — scrollable, append-only output history
- `<div class="repl-input-row">` — `<span class="prompt">march&gt;</span>` + `<textarea rows="1" ...>`

The textarea auto-grows with content (CSS `field-sizing: content` or a JS resize observer fallback). On `Enter`, submit; on `Shift-Enter`, insert `\n`.

JS responsibilities:
- On first keydown in the textarea: inject `<script src=".../march.js">` dynamically, show a "Loading…" state, wait for `window.marchEvalSession` to exist, then enable.
- On submit: append the input to history as `march> <code>`, call `marchEvalSession(code)`, append the result (or error) to history, clear the textarea, scroll to bottom.
- Maintain an in-memory input history array; `↑`/`↓` cycles through it.
- `:reset` clears history display and calls `marchResetSession()`.
- Cap history DOM nodes at 500 to avoid unbounded growth.

---

### Phase 3 — Example chips + copy

Below the two-column REPL section, a `<div class="repl-examples">` row of chips. Each chip has a `data-snippet` attribute; clicking it sets the textarea value (does not submit).

Above the REPL, a one-sentence label: **"Try March in your browser"** with a short subline: *"Enter runs. Shift-Enter adds a newline. Let bindings persist for the session."*

The right-side copy column suggests a first thing to try — `List.range(1, 6) |> List.map(fn x -> x * x)` — with a small arrow pointing left at the input, matching the Roc visual cue.

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

Add to the `docs/index.md` docs table:

```markdown
| [Try It Out](playground.md) | Run March code in your browser — no install needed |
```

`nav_order: 2` places it immediately below the landing page in the sidebar.

---

### Phase 5 — Polish

- **Web Worker timeout:** Move `marchEvalSession` into a Worker. The main thread posts the code string, waits up to 5 s, then shows *"Timed out — use `:reset` to clear the session"* if no reply arrives. Kills infinite loops without hanging the tab.
- **URL hash sharing:** On each successful eval, write `#s=<base64(code)>` to `location.hash`. On page load, if the hash is present, pre-fill the textarea with the decoded snippet. This makes it possible to link to a specific snippet from the docs (e.g., the actors page could link to a pre-filled actor example).
- **Mobile:** Single-column below 768 px. Terminal takes full width; copy moves above it.
- **`:help` in the REPL:** Intercept `:help` client-side and print a short list of available commands (`:reset`, `:type <expr>` if implemented, `:help`).

---

## Unix stubs

All stubs live in `march_browser.ml`. No changes to the core pipeline.

| Call | Where | Browser stub |
|---|---|---|
| `Unix.gettimeofday ()` | `Time.now` builtin | `0.0` |
| `Unix.open_process_in "uname -s"` | platform detection | `"browser"` constant |
| `Unix.getenv` | env builtins | always `None` |
| File descriptor ops | `File.*` builtins | `Error "File I/O is not available in the browser playground"` |

---

## Build integration

Add a dune alias:

```
(alias
  (name playground)
  (deps (alias_rec js/all))
  (action (copy js/march_browser.bc.js docs/assets/march.js)))
```

Run with `dune build @playground`. This is **not** part of the default `dune build` — it's a manual step before publishing docs. The generated `docs/assets/march.js` is committed to the repo so GitHub Pages can serve it without a CI build step.

---

## What this does not cover

- **CodeMirror syntax highlighting** — the Tree-sitter grammar exists for Zed; a CodeMirror mode needs a separate port. Plain monospace textarea is fine for v1.
- **Multi-file programs** — single expression/declaration per input. The playground is for exploration, not project development.
- **Saving sessions across tabs** — `sessionStorage` for within-tab persistence is enough.
- **Native WASM execution** (compile → run) — deferred. The interpreter is sufficient for demos and avoids needing a compilation server.

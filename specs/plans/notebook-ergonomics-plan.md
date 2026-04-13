# Notebook Ergonomics Plan

Closing the gap between `forge notebook serve` and Jupyter / Livebook.

**Current state (April 2026):** Code / Markdown / Server cells · REPL-style
cross-cell scoping · Run / Run All · Shift+Enter / Ctrl+S · elapsed time ·
HTML+SVG auto-render · DataFrame.to_html · Livebook dark theme ·
auto-reconnect WebSocket.

---

## Phase 1 — Quick JS Wins (no server changes)

All of these are pure browser-side. Ship together in one commit.

### 1.1 Clear output

- **Per-cell:** `✕` icon in the output area. `cells[idx].output = ""; cells[idx].error = null; updateCell(idx)`.
- **All:** Toolbar "Clear All" loops every cell.

### 1.2 Copy output button

Overlay "Copy" button on each output block.
`navigator.clipboard.writeText(cells[idx].output)`.
Flashes "Copied ✓" for 1.5 s.

### 1.3 Stale / dirty cell dimming

When a cell's `textarea` fires an `input` event, mark that cell and all later
cells `_dirty = true`. Clear `_dirty` on successful execution.

CSS: `[data-dirty] .cell-out { opacity: 0.4 }` + small "↻ stale" badge in the
output header. Resets on run.

### 1.4 Collapse source / output

Two toggle icons in each cell header (fold code ⌃, fold output ⌄). Store
`_src_collapsed` / `_out_collapsed` on the cell object; `display:none` the
relevant div via `updateCell`. Collapsed code cells show first line as a
preview hint.

### 1.5 Long-running cell badge (static analysis)

Even before interrupt support exists, a `⏱` clock badge in the cell header
gives users a heads-up. Applied at render time and on every `input` event via
`isPotentiallyLongRunning(src)`.

**Detection patterns:**

| Category | Patterns |
|---|---|
| HTTP | `Http.`, `HttpClient.`, `HttpTransport.` |
| Async | `Task.async`, `Task.await`, `task_spawn` |
| Subprocess | `Process.run`, `Process.spawn` |
| Sockets / TLS | `Socket.`, `ChannelSocket.`, `Tls.` |
| Explicit sleep | `System.sleep` |
| File I/O | `File.read`, `File.write` |
| Recursive fns | Heuristic: `fn name(` appears, and `name(` also appears later in the source |

```javascript
const SLOW_PATTERNS = [
  /\bHttp\./,  /\bHttpClient\./,  /\bHttpTransport\./,
  /\bTask\.async\b/,  /\bTask\.await\b/,  /\btask_spawn\b/,
  /\bProcess\.run\b/,  /\bProcess\.spawn\b/,
  /\bSocket\./,  /\bChannelSocket\./,  /\bTls\./,
  /\bSystem\.sleep\b/,
  /\bFile\.read\b/,  /\bFile\.write\b/,
];

function isPotentiallyLongRunning(src) {
  if (SLOW_PATTERNS.some(p => p.test(src))) return true;
  const m = src.match(/\bfn\s+(\w+)\s*\(/);
  if (m && new RegExp('\\b' + m[1] + '\\s*\\(').test(
        src.slice(src.indexOf(m[0]) + m[0].length))) return true;
  return false;
}
```

The clock badge sits right of the execution counter: `IN [2] · ⏱  ↑ ↓ ✕  ▶ Run`.
Hover tooltip: `"May take a while — use ⬛ to cancel"`. Left rail stays purple
(it's still a code cell).

### 1.6 Vega-Lite chart rendering

If output matches `{"$schema":"https://vega.github.io/schema/vega-lite/..."}`,
inject a `<div class="vg-embed">` and call `vegaEmbed()` (CDN script, loaded
lazily only when first chart appears).

---

## Phase 2 — Interrupt & Async Execution

### 2.1 Motivation

Currently `run_cells_to` calls `march` via `Sys.command` which blocks the
entire WebSocket loop. Long-running cells freeze the notebook UI with no way to
cancel. This is the single biggest reliability gap versus Jupyter.

### 2.2 Async process spawning (server — March)

Replace the blocking `Sys.command` in `run_cells_to` with:

1. `Process.spawn(march_bin, [runner_tmp, ...])` → returns a `LiveProcess`.
2. Store the `LiveProcess` PID in `Vault` under key `"notebook:running_pid"`.
3. Stream stdout from the live process (or wait and collect).
4. On completion, clear the Vault key, send `output` WS message.

New client→server WS message:
```json
{"type": "interrupt"}
```
Server handler: read PID from Vault, `Process.kill(pid)`, clear key, send
`{"type":"output","index":N,"stdout":"","error":"interrupted"}`.

### 2.3 Real-time elapsed time ticker (JS)

Currently elapsed time is a single snapshot at completion. With async:

```javascript
let _runningTimer = null;
// On cell start:
_runningTimer = setInterval(() => {
  const el = document.querySelector(`[data-idx="${idx}"] .cell-elapsed`);
  if (el) el.textContent =
    ((Date.now() - cells[idx]._start_ms) / 1000).toFixed(1) + 's';
}, 200);
// On cell finish: clearInterval(_runningTimer)
```

### 2.4 Stop button (JS)

While any cell has `running: true`, the Run button becomes Stop (⬛). Clicking
it sends `{type:"interrupt"}`. The server kills the process; the browser
receives the error output and renders it normally.

### 2.5 Long-running code cells (enabled by 2.1–2.4)

With a non-blocking execution loop, regular **code cells** become first-class
for slow-but-finite work: HTTP requests, file processing, recursive computation,
`Task.async` pipelines. Users no longer need a server cell as a workaround.

**Cell type distinction stays clean:**

| Cell type | Use for | Lifecycle |
|---|---|---|
| **Code** | Any computation with a definite end (fast or slow) | Runs to completion; output captured; elapsed shown |
| **Server** | Processes that run forever and stream logs | Never "completes"; Start/Stop controls |

---

## Phase 3 — Keyboard Command Mode

Jupyter's modal editing is the biggest daily ergonomics gap. Current shortcuts
only fire inside the textarea.

### 3.1 Two modes

- **Edit mode** — cursor in textarea (current behavior).
- **Command mode** — `Escape` exits the textarea, focuses the cell wrapper div.
  Cell wrapper gets `class="focused"` → blue left rail accent at full brightness.

### 3.2 Command mode shortcuts

| Key | Action |
|---|---|
| `j` / `↓` | Select next cell |
| `k` / `↑` | Select previous cell |
| `Enter` | Enter edit mode |
| `a` | Insert code cell above |
| `b` | Insert code cell below |
| `m` | Convert to Markdown |
| `y` | Convert to Code |
| `d d` | Delete cell (double-tap `d`) |
| `o` | Toggle output collapse |
| `0 0` | Clear cell output (double-tap `0`) |
| `Shift+Enter` | Run + move to next |
| `/` | Open notebook search |
| `?` | Show shortcut cheatsheet |

### 3.3 Shortcut cheatsheet

`?` opens a modal listing all shortcuts in both modes. Dismisses on `Escape` or
click-outside.

---

## Phase 4 — `forge add` & Notebook Package Management

### 4.1 `forge add` CLI command (OCaml)

New `forge/lib/cmd_add.ml`. Interface:
```
forge add <name> --git <url> [--tag v1.0 | --branch main | --rev abc123]
forge add <name> --path ../local-lib
```

Implementation:
1. `Project.load()` — find and parse `forge.toml`.
2. Check `[deps]` for existing `<name>` (error if present; `--force` to overwrite).
3. Textually append the new dep entry to the `[deps]` section (preserve existing
   comments/formatting rather than round-tripping through the TOML parser).
4. Run `forge deps` to resolve and lock.
5. Print confirmation with the resolved version.

Register in `forge/bin/main.ml` alongside the other subcommands.

### 4.2 Notebook-local project

When `forge notebook serve mynotebook.mnb` starts, the OCaml shim
(`cmd_notebook.ml`) looks for `mynotebook.toml` alongside the `.mnb` file. If
absent, it creates one:

```toml
[project]
name = "mynotebook"
type = "notebook"

[deps]
```

The `MARCH_LIB_PATH` passed to every cell run is assembled from this toml the
same way `forge build` assembles it — resolving git deps from CAS and including
their `lib/` dirs.

### 4.3 `Forge.add()` in notebook cells

New stdlib module `stdlib/forge_nb.march`:
```march
mod Forge do
  fn add(spec) do
    println("__FORGE_ADD__:" ++ spec)
  end
end
```

`Forge.add(spec)` emits a sentinel line in its output. The notebook server
intercepts it in `extract_cell_output`:

1. Parse `spec` — `"path:../my-lib"` → PathDep; bare URL → GitBranchDep.
2. Shell out to `forge add <name> --git <url>` (or `--path`) against the
   notebook's `.toml`.
3. Run `forge deps` in the notebook directory.
4. Rebuild `MARCH_LIB_PATH`; store in Vault key `"notebook:lib_path"`.
5. All subsequent cell runs read `MARCH_LIB_PATH` from Vault.
6. Send `{"type":"dep_added","name":"..."}` to browser → JS toast "Package installed ✓".

**New WS messages:**
- Server→Client: `{"type":"dep_added","name":"json","status":"ok"}`
- Server→Client: `{"type":"dep_error","message":"..."}`

**User experience:**
```march
-- In a notebook cell:
Forge.add("github.com/march-lang/json")
-- Subsequent cells can now use the Json module.
-- Re-run this cell (or later cells) after the package installs.
```

---

## Phase 5 — Variable Inspector

### 5.1 Binding tracking in `generate_runner`

`generate_runner` already calls `let_bound_name` on each cell. Thread an
accumulator of all bound names through the `go` fold. After the last cell's
output block, emit:

```march
  println("__MNB_VARS__")
  println("varname1=" ++ to_string(varname1))
  println("varname2=" ++ to_string(varname2))
  println("__MNB_VARS_END__")
```

### 5.2 Server-side extraction

Parse the `__MNB_VARS__` block out of stdout after run completes. Include it in
the output WS message:

```json
{"type":"output","index":2,"stdout":"...","vars":{"a":"1","df":"DataFrame(3×4)"}}
```

### 5.3 Inspector panel (JS)

Collapsible right sidebar (or bottom panel) showing a live table: name |
current value (truncated to 80 chars). Clicking a row expands the full value in
a popover. Updated after every cell run. Toggled by a toolbar button.

---

## Phase 6 — Sections

### 6.1 New cell type: section

Stored in `.mnb` as:
```
<!-- section: Data Loading -->
```

Parsed in `parse_cells` as `Section(title)`. Skipped by `generate_runner`
(sections produce no code).

### 6.2 Rendering

```
━━━━━━━━  Data Loading  ━━━━━━━━  [▼]
```

Full-width bold separator with a collapse toggle. Collapsing sets
`_collapsed = true` on the section cell and hides all cells until the next
section (or end of notebook). State persisted across re-renders.

### 6.3 Add bar

"+ Section" added to the between-cell add bars.

---

## Phase 7 — Drag to Reorder

Replace up/down buttons with HTML5 drag-and-drop:

- Each cell wrapper gets `draggable="true"` and a grab handle (⠿) on the
  left edge (only visible on hover, so it doesn't crowd the rail).
- `dragstart`: store `draggingIdx`.
- `dragover`: show 2 px insertion line above/below target.
- `drop`: `cells.splice(to, 0, cells.splice(from, 1)[0])`; save; re-render.
- Keep up/down arrow buttons for keyboard-only users.

---

## Phase 8 — Notebook-Wide Search

`/` in command mode (or Ctrl+F intercepted before browser default) opens a
search modal:

- Text input — searches cell source text and output text.
- Matching cells get a yellow border highlight.
- `Enter` / `n` → next match; `Shift+n` → previous match.
- `Escape` → close and clear highlights.

---

## Phase 9 — Export to HTML

**Client-side (immediate value):**

Toolbar "Export HTML" button:
1. Serialize `cells` to static HTML: markdown rendered, code in `<pre>`, output
   included.
2. Inject notebook CSS inline.
3. Trigger `<a download="name.html">` blob download.

**Server-side (CI / headless, future):**

`forge notebook render mynotebook.mnb -o mynotebook.html` — the
`run_render` path in `cmd_notebook.ml` is already sketched; it just needs the
rendered HTML to include outputs (requires a run pass first).

---

## Implementation Order

| Priority | Phase | Effort | Value |
|---|---|---|---|
| **Ship now** | 1 — Clear / copy / stale / collapse / clock badge | 1 day | High · zero risk |
| **Ship now** | 4.1 — `forge add` CLI | 0.5 day | Unblocks packages |
| **Next** | 2 — Interrupt + async execution | 1–2 days | Critical reliability |
| **Next** | 3 — Command mode shortcuts | 1 day | Biggest ergonomics win |
| **Next** | 4.2–4.3 — `Forge.add()` in notebook | 1.5 days | Depends on 4.1 |
| **Later** | 5 — Variable inspector | 1.5 days | Data-work quality of life |
| **Later** | 6 — Sections | 0.5 day | Structural organization |
| **Later** | 7 — Drag to reorder | 0.5 day | Polish |
| **Later** | 8 — Search | 0.5 day | Polish |
| **Later** | 9 — Export HTML | 0.5 day | Already half-done |
| **Stretch** | Collaborative editing | Weeks | Post-v1 |
| **Stretch** | Dependency tracking / auto-rerun | Weeks | Post-v1 |
| **Stretch** | Notebook checkpoints | Days | Post-v1 |

---

## Appendix: Multi-Line Expression Fix (shipped)

`split_last` previously grabbed the last *line* of a cell and used it as the
result expression. Multi-line expressions (`DataFrame.from_columns([...])`,
`if...do...end`, `match...do...end`) all produced parse errors like:

```
let __r0__ = ])
```

**Fix (April 2026):** `split_last` now tracks bracket depth (`(`, `[`, `)`,
`]`) and block depth (`do` / `end`) scanning backward through lines. When depth
reaches zero, that is the start of the last top-level statement. The complete
statement (possibly many lines) is returned as `last_stmt_lines`. `make_cell_inline`
uses the *first* line of `last_stmt_lines` for `let_bound_name` classification
and emits the *full* statement for binding/expression generation.

Fixes: `DataFrame.from_columns([...])`, `if cond do...end`,
`match x do...end`, any other multi-line expression or let-binding.

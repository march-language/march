# March DAP Debugger — Design & Plan

**Status:** v1 complete (2026-06-14) — VS Code + Zed clients functional, 5 integration tests
**Date:** 2026-06-14

## Goal

Make March's existing interpreter time-travel debugger usable from editors by
exposing it through the **Debug Adapter Protocol (DAP)**. v1 ships a
`launch`-model DAP server that VS Code and Zed can drive: **gutter breakpoints
at any source line, step over/into/out, continue, pause, call stack, and
locals/scopes inspection.**

Out of scope for v1 (queued for v2): reverse-debugging (the engine already
supports it — expose `stepBack`/`reverseContinue`), conditional/hit-count
breakpoints, watch expressions, actor-as-thread modeling, native/DWARF debugging.

## Existing foundation (reused, not rebuilt)

- `lib/eval/eval.ml`: `debug_ctx` (trace ring + `dc_on_dbg` + actor log), and the
  universal `eval_expr` tracing wrapper (the single chokepoint around every
  evaluation step; zero overhead when `debug_ctx = None`).
- `lib/debug/`: `make_debug_ctx`, `install`/`uninstall`, `get_frame`, and
  `trace.ml` (call-stack / where / frame formatting).
- `env = (string * value) list` — variable inspection is a frame env walk.
- A value pretty-printer in `Eval` for rendering variable values.

## Architecture

```
VS Code / Zed ──DAP/stdio──▶ march-dap
                               ├─ protocol loop (main thread): Content-Length JSON framing, request dispatch
                               └─ eval worker thread: runs the program via Eval; eval_expr hook checks
                                  "breakpoint at this line? / single-stepping?"; on pause blocks and hands
                                  control to the protocol loop via a Mutex+Condition rendezvous.
```

### 1. Engine hook (`lib/eval/eval.ml`)

Extend `debug_ctx` with a stepping controller:

```ocaml
type step_mode = Run | Pause | StepOver of int | StepIn | StepOut of int
(* the int is the call depth captured when the step was requested *)

(* added to debug_ctx: *)
mutable dc_breakpoints : (string, IntSet.t) Hashtbl.t;  (* file -> set of 1-indexed lines *)
mutable dc_step        : step_mode;
mutable dc_on_pause     : (env -> span -> unit) option;  (* blocks until resumed *)
mutable dc_last_line    : (string * int) option;         (* de-dupe: only stop once per source line *)
```

In `eval_expr`, before evaluating (only when `dc_enabled`):
- Compute the expr's start `(file, line)` from its span.
- `should_stop` =
  - `dc_step = Pause`, or
  - `(file,line)` is in `dc_breakpoints`, or
  - `StepIn` and the line changed, or
  - `StepOver d` and `dc_depth <= d` and the line changed, or
  - `StepOut d` and `dc_depth < d`.
- Suppress re-stopping on the same `(file,line)` we just stopped on (track `dc_last_line`).
- If `should_stop`, set `dc_step := Pause` and call `dc_on_pause env span`. That
  callback blocks the eval thread until the protocol loop assigns the next
  `dc_step` and signals resume.

`dc_depth` is already maintained around calls. The fast path (no debug ctx, or
disabled) is unchanged.

### 2. DAP server (`lib/dap/`)

- `dap_json.ml` — Content-Length framing over a pair of in/out channels; parse
  and serialize DAP messages (yojson).
- `dap_types.ml` — minimal typed request/response/event records for the subset
  we implement.
- `dap_server.ml` — the session: spawns the eval worker, owns the rendezvous,
  and dispatches requests.

Requests handled: `initialize`, `launch`, `setBreakpoints`, `configurationDone`,
`threads`, `stackTrace`, `scopes`, `variables`, `continue`, `next`, `stepIn`,
`stepOut`, `pause`, `evaluate` (REPL-eval against the paused frame — gives
hover/REPL nearly for free), `disconnect`/`terminate`.

Events emitted: `initialized`, `stopped` (reason breakpoint/step/pause/entry),
`continued`, `output` (program stdout/stderr), `thread` (started/exited),
`terminated`, `exited`.

Threading: one OCaml `Thread` runs the program; the protocol loop runs on the
main thread. A `Mutex`+`Condition` pair forms the rendezvous: on pause the worker
publishes the current frame/stack snapshot and waits; the protocol loop answers
`stackTrace`/`scopes`/`variables`/`evaluate` against that snapshot, then sets the
next `dc_step` and signals the worker to continue. The interpreter's own actor
scheduler is cooperative/single-threaded, so a dedicated eval thread does not race
it.

Frames/variables: the paused call stack comes from the depth chain of trace
frames; `scopes` returns a single "Locals" scope; `variables` walks that frame's
`env`, rendered with the existing value printer. Variable references are handed
out via an integer handle table so structured values (records/tuples/lists) can be
expanded lazily.

### 3. Entry point + editor glue

- `bin/march_dap.ml` (or `march debug --dap`) — wire stdio to `Dap_server.run`.
- `editors/vscode-march/` — a minimal VS Code debug extension: `package.json`
  contributes debugger type `march`, a `launch.json` schema (program path), and
  points `program`/adapter at the `march-dap` binary.
- `zed-march/` — a Zed debug-adapter binding pointing at the same binary.

## Testing

- **Engine hook unit tests** (`test/` or `lib/debug`): drive a small program with a
  scripted breakpoint set + step modes, assert the pause callback fires at the
  expected spans and that locals are visible in the paused `env`.
- **DAP protocol tests** (new `test/test_dap.ml`): a harness that feeds a scripted
  sequence of DAP requests over a pipe to `Dap_server` and asserts the response /
  event sequence (initialize → setBreakpoints → launch → stopped → stackTrace →
  variables → continue → terminated). This mirrors the existing
  `lsp/test/test_jsonrpc.ml` stdio-integration style.
- Manual smoke: a `.march` sample debugged from VS Code (breakpoint, step, inspect).

## Risks / decisions

- **Pause granularity.** `eval_expr` fires per sub-expression; stopping on every
  sub-expr of a line would be noisy. The `dc_last_line` de-dupe (stop once when a
  new source line is first entered) gives line-granular stepping, which matches
  editor expectations.
- **Thread safety.** Shared state between worker and protocol loop is confined to
  the rendezvous struct (current frame snapshot + step mode), guarded by the mutex.
  Inspection only happens while the worker is parked.
- **`launch` only.** No `attach`; not meaningful for a tree-walker.

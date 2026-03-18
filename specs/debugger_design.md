# March Time-Travel Debugger Design

## Overview

A built-in time-travel debugger for March, triggered by `dbg()` in user code. When hit, it opens an interactive debug REPL with full access to program state. The debugger records an execution trace that supports stepping backward/forward through evaluation history and replaying from any point with modified state.

Targets the tree-walking interpreter initially. The `dbg()` syntax is designed to map to a debug trap in compiled (LLVM) code in the future.

## `dbg()` Syntax & Semantics

`dbg()` is a built-in expression parsed as a new AST node:

```
| EDbg of span    (* breakpoint — pauses execution, opens debug REPL *)
```

`EDbg` carries a `span` like all other AST expression nodes.

Usage in March code:

```march
fn factorial(n) =
  dbg()
  if n <= 1 then 1
  else n * factorial(n - 1)
```

Semantics:
- When the interpreter hits `EDbg`, it captures the current env + actor state and opens the debug REPL.
- The debug REPL has full access to all bindings in scope — any expression can be evaluated.
- `dbg()` evaluates to `:unit` and execution continues when the user types `:continue`.
- When not in debug mode (`--debug` flag absent), `dbg()` is a no-op that evaluates to `:unit`.
- `dbg()` is not a function call — it's a language-level construct that has access to the lexical environment, which normal functions don't get.

## Execution Trace

### Trace Frame

Each `eval_expr` call records a frame when debug mode is active:

```ocaml
type actor_state = {
  defs : (string * (Eval.actor_def * Eval.env ref)) list;
      (* env ref is captured as ref !(original_ref) — a new ref pointing to
         the env value at snapshot time, NOT sharing the original mutable ref *)
  instances : (int * Eval.actor_inst_snapshot) list;  (* deep copy of mutable fields *)
  next_pid : int;
}

type trace_frame = {
  expr : Ast.expr;
  env : Eval.env;             (* cheap — shared structure with live env *)
  result : Eval.value option; (* None if eval raised an exception *)
  exn_info : string option;   (* exception message if eval failed *)
  actor_snapshot : actor_state;
  span : Ast.span;
  depth : int;                (* call stack depth, for indented display *)
}
```

`actor_inst_snapshot` is a deep copy of `actor_inst` with its mutable fields (`ai_state`, `ai_alive`) captured by value, not by reference. A shallow `Hashtbl.copy` is not sufficient — each `actor_inst` record must be individually copied.

### Trace Buffer

A ring buffer of `trace_frame` values with a configurable capacity (default 100,000 frames). When full, the oldest frames are evicted. Configurable via `MARCH_DEBUG_TRACE_SIZE` environment variable.

The ring buffer is implemented in `debug.ml` as a simple array + head/size/capacity structure (same pattern as the existing `result_vars.ml` and `history.ml` ring buffers in the codebase).

### Recording

Only active when the `--debug` flag is passed. Without `--debug`, zero overhead — `eval_expr` is completely untouched.

### Actor Snapshots

Each trace frame captures a full actor state snapshot: deep copy of `actor_defs_tbl` entries (including the `env ref` contents), deep copy of `actor_registry` entries (copying mutable `ai_state` and `ai_alive` fields), and the current `!next_pid`. These are small (typically few actors), so per-step cloning is acceptable.

**Optimization for v2:** Only snapshot actor state when it actually changes (detect via a generation counter bumped on `send`/`spawn`/`kill`). Frames between actor mutations share the previous snapshot.

### Exception Handling in Traces

When `eval_expr` raises `Eval_error` or `Match_failure`, the trace frame is still recorded with `result = None` and `exn_info = Some msg`. This allows stepping back to see the state just before a crash — a key debugging use case.

### What's NOT Traced

Individual pattern match arm attempts, type checking steps, parsing. Only `eval_expr` / `eval_block` / `apply` calls — the actual runtime evaluation. `eval_block` does not get its own frame — each expression within a block is individually traced via `eval_expr`.

## Why Time-Travel Is Cheap Here

March's interpreter uses immutable association-list environments. Snapshotting an env is a pointer copy — the new trace frame shares structure with the live env. No deep cloning needed. This makes recording every evaluation step feasible with minimal memory overhead.

## Debug REPL Commands

When `dbg()` triggers, the debug REPL TUI opens with the current env loaded. The scope panel shows local bindings. New debug-specific commands:

| Command | Alias | Description |
|---------|-------|-------------|
| `:continue` | `:c` | Resume execution |
| `:back [n]` | `:b` | Step back n frames (default 1) in the trace |
| `:forward [n]` | `:f` | Step forward n frames (default 1) |
| `:step` | `:s` | Execute one frame forward from current position, then pause |
| `:trace [n]` | `:t` | Show last n trace frames (default 10) with source locations |
| `:let x = expr` | `:l` | Evaluate expr and rebind x in the current env |
| `:replay` | `:r` | After `:let`, re-execute from current trace position with modified env |
| `:where` | `:w` | Show current position in trace (frame index, source location, call depth) |
| `:stack` | `:sk` | Show call stack (filtered trace frames by depth) |

### Navigation Model

A cursor (`trace_pos`) points into the trace buffer. `:back`/`:forward` move the cursor. When the cursor moves, the scope panel updates to show the env at that frame, the transcript shows the expression and its result, and the status bar shows the frame index and source location. The prompt changes to indicate debug navigation mode (e.g., `[frame 42] dbg> `). Expressions can be evaluated against any historical frame's env.

### Replay Semantics

`:let x = 42` modifies the env at the current trace frame. `:replay` then calls `eval_expr` from that point with the modified env. The trace buffer is truncated at `trace_pos` and new frames are appended from the replayed execution. This is the "what-if" capability — change a value, see what happens.

**Side effects during replay:**
- **stdout/stderr:** Output during replay is displayed normally (prefixed with `[replay]` to distinguish from original output).
- **Actor sends:** Actor state is restored from the snapshot at `trace_pos` before replay begins. Sends during replay are real — they execute against the restored actor state. This gives faithful replay of actor interactions.
- **Actor spawns:** New PIDs during replay are allocated from the restored `next_pid`, so they match the original execution unless the modified env causes different control flow.
- **stdin (`read_line`):** During replay, `read_line` calls return the same values as the original execution (recorded in the trace). If replay diverges to a new `read_line` that wasn't in the original, it prompts the user.

### `dbg()` Inside Actor Handlers

When `dbg()` is hit inside an actor handler (the `ESend` dispatch path), the debug REPL opens with the handler's env, which includes the actor's `state` binding. `:let state = new_val` followed by `:replay` restores actor state from the snapshot, applies the modification, and replays. The actor's mutable `ai_state` is also updated to match.

### Interaction with Existing Commands

`:env`, `:type`, `:help` all work in debug mode. `:quit` exits the debugger AND the program. `:continue` is the only way to resume normal execution.

## Integration with the Interpreter

### `--debug` Flag

Added to `bin/main.ml` CLI. Activates trace recording and enables `EDbg` breakpoints.

### Debug Context as Module-Level Ref

Rather than threading `debug_ctx option` through every mutually recursive function signature (`eval_expr`, `eval_block`, `apply` — 36+ call sites), the debug context uses a module-level mutable ref, matching the existing pattern used for `actor_registry`, `actor_defs_tbl`, and `next_pid`:

```ocaml
(* In lib/eval/eval.ml *)
type debug_ctx = {
  trace : trace_frame RingBuffer.t;
  mutable trace_pos : int;
  mutable enabled : bool;
  mutable depth : int;             (* current call depth *)
  on_dbg : (env -> unit) option;   (* callback to launch debug REPL — breaks circular dep *)
}

let debug_ctx : debug_ctx option ref = ref None
```

This avoids any signature changes to `eval_expr`/`eval_block`/`apply`. At each eval step, a guard checks `!debug_ctx`:

```ocaml
let eval_expr env expr =
  let result = (* ... existing eval logic ... *) in
  (match !debug_ctx with
   | Some ctx when ctx.enabled ->
     RingBuffer.push ctx.trace { expr; env; result = Some result; ... };
   | _ -> ());
  result
```

When `!debug_ctx` is `None`, this is a single pointer deref + branch — effectively zero overhead.

### Breaking the Circular Dependency

`eval.ml` cannot depend on `march_debug` (which depends on `march_eval`). Instead, `debug_ctx` includes an `on_dbg : (env -> unit) option` callback. When `eval_expr` hits `EDbg`:

1. Snapshot current actor state, push trace frame
2. Call `ctx.on_dbg env` — this invokes the debug REPL
3. When the callback returns (`:continue`), return `VUnit`

`march_debug` provides the `on_dbg` implementation and installs it into the context before execution begins. No circular dependency — `march_eval` only knows about the callback signature.

### Terminal Ownership for `dbg()` in File Execution Mode

When running `march --debug file.march` and `dbg()` is hit:

1. Flush all pending stdout output from the program.
2. The debug REPL opens in simple (line-based) mode by default, since the program may have been using stdout for its own output. The TUI mode is available via a `--debug-tui` flag.
3. On `:continue`, stdout is restored to normal and execution resumes.
4. If the program uses `read_line`, any pending stdin is left in the buffer for the program to consume after `:continue`.

## Module Structure & File Layout

New code lives in a dedicated `lib/debug/` library:

```
lib/debug/
  debug.ml          — debug_ctx type, trace_frame type, actor_state type,
                      RingBuffer, snapshot/restore actors
  trace.ml          — trace recording, navigation (:back/:forward), cursor management
  replay.ml         — :let + :replay logic (modify env, re-execute, replace trace tail)
  debug_repl.ml     — debug REPL session (commands, dispatch, TUI integration)
  dune              — (library march_debug, depends on march_eval, march_repl)
```

### Changes to Existing Files

- `lib/ast/ast.ml` — Add `EDbg of span` to `expr` type
- `lib/lexer/lexer.mll` — Recognize `dbg` keyword
- `lib/parser/parser.mly` — Parse `dbg()` as `EDbg`
- `lib/desugar/desugar.ml` — Passthrough case for `EDbg` (identity transform)
- `lib/typecheck/typecheck.ml` — `EDbg` typechecks as `Unit`
- `lib/eval/eval.ml` — Add `debug_ctx` ref, trace guard in `eval_expr`, handle `EDbg` via callback
- `lib/repl/repl.ml` — Add debug commands to command dispatch, support debug session mode
- `bin/main.ml` — Add `--debug` / `--debug-tui` CLI flags, install debug context before eval

### Dependency Graph

```
bin/main.ml
  └── march_debug (lib/debug/)
        ├── march_eval (lib/eval/)
        └── march_repl (lib/repl/)
              └── march_eval
```

`march_eval` has no dependency on `march_debug`. The debug REPL callback is injected at startup by `main.ml`. Clean, acyclic.

## Example Debug Session

```
$ march --debug factorial.march

[debug] Trace recording enabled (buffer: 100000 frames)
[debug] Hit breakpoint at factorial.march:2:3

dbg> n
3
dbg> :where
Frame 12 of 12 | factorial.march:2:3 | depth 1 (in factorial)
dbg> :stack
  0: main() at factorial.march:8:3
  1: factorial(3) at factorial.march:2:3  <-- you are here
dbg> :back 5
[frame 7] dbg> :where
Frame 7 of 12 | factorial.march:4:8 | depth 0 (in main)
[frame 7] dbg> :env
n = 3
[frame 7] dbg> :let n = 5
n rebound to 5
[frame 7] dbg> :replay
[replay] Replaying from frame 7 with modified env...
[replay] factorial(5) = 120
[replay] Done. Trace now has 18 frames.
dbg> :c
factorial(3) = 6
```

## Testing Strategy

### Unit Tests (in `test/test_march.ml`)

- `EDbg` parses correctly from `dbg()`
- `EDbg` typechecks as `Unit`
- `EDbg` evaluates to `VUnit` when debug mode is off (no-op)
- Trace recording captures correct env/result/span at each step
- Trace navigation (back/forward) moves cursor correctly
- Actor snapshot/restore round-trips faithfully (including mutable fields)
- Replay with modified env produces correct new trace
- Exception frames are recorded with `result = None` and `exn_info`

### Integration Tests (non-interactive, programmatic)

- Run a small program with `--debug` and a `dbg()` call, feed debug commands via stdin in simple mode (pipe mode), verify output
- Replay test: step back, `:let` a variable, replay, verify the new result diverges as expected
- Trace buffer overflow: verify ring buffer wraps and oldest frames are evicted
- `dbg()` inside actor handler: verify handler env is accessible and actor state restores correctly

### No TUI Tests

The Notty rendering is already tested manually via the REPL. Debug commands are dispatched through the same command infrastructure, so coverage comes from the command parsing tests.

## Future Work

- **LLVM debug support:** Emit DWARF debug info in `llvm_emit.ml`, map `EDbg` to a debug trap instruction, integrate with lldb/gdb
- **Conditional breakpoints:** `dbg(n > 10)` — only pause when the condition is true
- **`trace(expr)`:** Rust-style print-and-return for lightweight logging without pausing
- **Actor-aware stepping:** Step through actor message sends/receives as first-class debug events
- **Trace serialization:** Save/load trace to disk for post-mortem debugging
- **Smart actor snapshots:** Generation counter to skip redundant snapshots between actor mutations
- **`read_line` recording:** Full deterministic replay by recording all I/O inputs

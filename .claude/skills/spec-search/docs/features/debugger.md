# March Time-Travel Debugger

**Last Updated:** March 22, 2026
**Status:** Complete (interpreter path). Not wired to compiled/LLVM path.

**Implementation:**
- `lib/debug/debug.ml` (37 lines) — debug context type, `dbg()` handler registration
- `lib/debug/debug_repl.ml` (47 lines) — debug REPL entry point; builds `debug_handlers` record and invokes debug loop
- `lib/debug/trace.ml` — execution trace capture, actor history, `goto`/trace navigation, `save_trace`/`load_trace`
- `lib/debug/replay.ml` — step replay engine (re-evaluate from a snapshot)
- `lib/eval/eval.ml` — `on_dbg` callback hook in evaluator; `dbg(expr)` builtin

---

## Overview

The March time-travel debugger integrates into the tree-walking interpreter. When a `dbg(expr)` call is hit, the evaluator suspends execution and drops into an interactive debug REPL. The debug REPL lets you inspect values, navigate the execution trace forward and backward, diff states between steps, and view actor history.

Traces can be saved to disk and loaded in a later session.

---

## 1. Architecture

```
dbg(expr) in program
    ↓
eval.ml: on_dbg callback fires
    ↓
lib/debug/debug_repl.ml: debug_loop starts
    ↓
User enters commands (goto, diff, find, watch, replay, actors, tsave, tload)
    ↓
lib/debug/trace.ml: trace navigation
lib/debug/replay.ml: step re-evaluation
    ↓
Resume execution on :continue
```

### `debug_handlers` record (`lib/debug/debug_repl.ml:14–30`)

```ocaml
{
  dh_goto       = (fun n    -> Trace.goto ctx n);
  dh_diff       = (fun n m  -> Trace.diff ctx n m);
  dh_find       = (fun pred -> Trace.find ctx pred);
  dh_watch      = (fun expr -> Trace.watch ctx expr);
  dh_trace      = (fun n    -> Trace.show_trace ctx n);
  dh_replay     = (fun env  -> Replay.replay_from ctx env);
  dh_actor      = (fun pid goto_msg -> Trace.actor_history ctx pid goto_msg);
  dh_save_trace = (fun path -> Trace.save_trace ctx path);
  dh_load_trace = (fun path -> Trace.load_trace ctx path);
}
```

---

## 2. Debug Commands

| Command | Description |
|---------|-------------|
| `goto N` | Jump to step N in the execution trace |
| `diff N M` | Show what changed between steps N and M |
| `find PRED` | Search trace for first step where predicate is true |
| `watch EXPR` | Track expression value across all trace steps |
| `trace [N]` | Show the execution trace (optionally around step N) |
| `replay` | Re-run from the start using the captured initial env |
| `actors PID` | Show message history for actor with given PID |
| `tsave PATH` | Serialize trace to file |
| `tload PATH` | Load trace from file and enter debug mode |
| `:continue` | Resume execution from current position |
| `:quit` | Terminate the program |

---

## 3. `dbg(expr)` Builtin

The `dbg(expr)` function is registered in `eval.ml`'s `base_env`. When called:

1. Evaluates `expr` to get the current value
2. Records a trace frame with the current environment snapshot
3. Calls `on_dbg` (if registered — debug mode must be enabled)
4. Returns the value of `expr` unchanged (passthrough)

Usage:

```march
fn compute(x : Int) do
  let y = x * 2
  let z = dbg(y + 1)  -- pauses here with z in scope
  z * 3
end
```

In non-debug mode (`on_dbg` not set), `dbg(expr)` is a transparent passthrough with no overhead.

---

## 4. Trace Capture (`lib/debug/trace.ml`)

Each trace frame records:
- Step number
- Current expression being evaluated
- Environment snapshot (all bindings in scope)
- Actor state snapshots (for each live actor at this step)
- Source location (span)

### Actor history

The `actor_history` function returns all messages sent to/from a given actor PID, interleaved with the global trace. Useful for debugging actor communication bugs.

### Save/Load

Traces are serialized (format TBD — likely S-expression or JSON) for deferred analysis. `tload` restores the trace and enters the debug REPL without running the program.

---

## 5. Integration with REPL

The debug REPL is separate from the main March REPL but uses similar input handling. When triggered by `dbg()`, it runs a minimal command loop; the main REPL is suspended.

To enable debug mode in the REPL, pass `--debug` flag or use `:debug on` command (if implemented).

---

## 6. Known Limitations

- **Interpreter only** — `dbg()` has no effect in compiled (LLVM) mode; the `on_dbg` callback is never called
- **No source stepping** — debug navigates by trace step number, not by source line
- **No watchpoints** — `watch` searches existing trace but doesn't set future breakpoints
- **Trace size** — unbounded trace can consume large memory for long-running programs
- **Actor history** — only captures messages, not actor state diffs between messages

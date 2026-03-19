# March Debugger Enhancement Spec

_Date: 2026-03-19_

This document plans the next 10 enhancements to the March time-travel debugger.
They build on the foundation described in `debugger_design.md` and the
current implemented state (TUI REPL integration, `:where` with source context,
`:back`/`:forward`/`:replay`/`:stack`/`:trace`).

Enhancements are ordered by implementation priority (highest first).

---

## Priority 1 — Auto-show `:where` after navigation

### Motivation

After `:back 5` or `:step`, the user is at a new frame but sees nothing — they
must manually type `:where` to orient themselves. Every other debugger (gdb,
pry, lldb) prints the source context automatically on each step. The current UX
breaks flow.

### Behavior

After any navigation command (`:back`, `:forward`, `:step`, `:goto`) the REPL
automatically prints the `:where` output — the frame header + ±2 source lines —
before returning to the prompt.

```
[frame 7] dbg> :back 3
Frame 4 of 203 | examples/actors.march:48:5 | depth 2
     46 │   let loop = fn () ->
     47 │     let msg = receive()
→    48 │     match msg with
     49 │       | :stop -> ()
     50 │       | n -> loop()
[frame 4] dbg>
```

### Implementation

In both `run_simple` and `run_tui` in `repl.ml`, each debug navigation command
already calls the hook and then calls `List.iter (add_line fg_cyan)` on the
result (or equivalent). Currently only `:where` does this; the other nav
commands just print the new frame index. Change each nav command branch to call
`hooks.dh_where ()` and print its result after updating the cursor.

Cost: ~10 lines changed in `repl.ml`. Zero new types or modules.

---

## Priority 2 — `dbg(expr)` — value-returning trace point

### Motivation

`dbg()` is an unconditional breakpoint — it always pauses execution and opens
the REPL. This is disruptive inside loops or frequently called functions. Rust's
`dbg!` macro solves a related but different problem: it prints the expression
and its value and *returns the value*, so it can be inserted inline without
changing program semantics.

March should support both:
- `dbg()` — pause and open REPL (current behavior)
- `dbg(expr)` — evaluate `expr`, print `expr = <value>` to stderr, return the value, no pause

```march
let x = dbg(n * 2)   -- prints: [dbg] n * 2 = 84  (then x = 84)
```

This is the "printf debugging without the printf" pattern. The value flows
through, so `dbg(expr)` can wrap any sub-expression.

### Syntax

```
EDbg of span * expr option
  (* None  = breakpoint (current behavior)
     Some e = trace-and-return *)
```

When `dbg()` has an argument it is a value-returning trace point; when empty it
is a breakpoint. The ambiguity in the name is intentional — it mirrors Rust.

### Behavior

- In no-debug mode: `dbg(expr)` evaluates `expr` and returns it silently (zero
  overhead, no stderr output). `dbg()` remains a no-op.
- In `--debug` mode: `dbg(expr)` evaluates `expr`, prints
  `[dbg] <source_text> = <value>` to stderr, records a trace frame, and returns
  the value without pausing.
- `dbg()` (no arg) always pauses, as today.

```march
-- Both work:
let xs = List.map (fn x -> dbg(x * 2)) [1, 2, 3]
-- stderr: [dbg] x * 2 = 2
-- stderr: [dbg] x * 2 = 4
-- stderr: [dbg] x * 2 = 6
-- xs = [2, 4, 6]
```

### Implementation

**Parser:** `dbg()` vs `dbg(expr)` — look ahead after `(`. If next token is `)`,
parse as `EDbg (span, None)`. Otherwise parse the inner expression, expect `)`,
produce `EDbg (span, Some e)`.

**AST:** Change `EDbg of span` → `EDbg of span * expr option`.

**Desugar:** Pass through (`EDbg(s, None)` and `EDbg(s, Some e)` identity).

**Typecheck:** `EDbg(_, None)` → `Unit`. `EDbg(_, Some e)` → type of `e`
(the whole thing has the type of the inner expression).

**Eval:**
```ocaml
| EDbg (_, None) -> (* existing breakpoint logic *)
| EDbg (span, Some e) ->
  let v = eval_expr env e in
  (match !debug_ctx with
   | Some ctx when ctx.dc_enabled ->
     Printf.eprintf "[dbg] %s = %s\n%!" (pp_source_expr span) (value_to_string v);
     record_frame span env (Some v);
   | _ -> ());
  v
```

`pp_source_expr span` reads `span.file` and slices out the source text for the
span (a helper that already exists in `trace.ml` for source_context — extend it
to return a single line slice).

---

## Priority 3 — Conditional breakpoints: `dbg(cond)` pauses only when true

### Motivation

`dbg()` inside a loop fires on every iteration. The user usually wants to pause
only when a specific condition holds (e.g. `n = 0`, an invariant is broken, an
unexpected value appears). Without conditional breakpoints, the workaround is
`if cond then dbg() else ()`, which is verbose and changes program structure.

### Syntax

Reuse `dbg(expr)` where `expr` has type `Bool`:

```march
-- Pause only when n = 0:
dbg(n = 0)

-- Pause only when a list is unexpectedly empty:
dbg(xs = [])
```

When the argument has type `Bool`, `dbg(expr)` acts as a conditional
breakpoint: if the condition is `true` it pauses (opens REPL); if `false` it
is a no-op. When the argument has any other type, it is the value-returning
trace point from Enhancement 2.

### Disambiguation

Typecheck determines the behavior: `Bool` argument → conditional breakpoint;
non-`Bool` argument → value trace. The typechecker must resolve the argument
before `eval` can dispatch. This is fine — types are known at typecheck time and
can be embedded in the AST.

Extend the AST node:

```ocaml
type dbg_mode =
  | DbgBreak                (* dbg() — unconditional pause *)
  | DbgCond                 (* dbg(bool_expr) — conditional pause *)
  | DbgTrace                (* dbg(expr) — value trace-and-return *)

EDbg of span * expr option * dbg_mode
```

`DbgMode` is computed during typechecking and embedded by the desugar or
typecheck pass. Eval reads `mode` to dispatch.

### Behavior in no-debug mode

All `dbg(...)` variants are no-ops. `dbg(cond)` still evaluates `cond` (it's an
expression), but does not pause. `dbg(expr)` evaluates and returns. This means
`dbg()` is the only true zero-cost variant in no-debug mode (the others still
evaluate their argument).

---

## Priority 4 — `:goto N` — absolute frame jump

### Motivation

`:back`/`:forward` are relative. After `:trace 20` the user sees frame indices
in the output (`Frame 142 of 203`) and wants to jump directly to frame 142
without counting steps. This is a table-stakes debugger navigation feature.

### Behavior

```
[frame 7] dbg> :goto 142
Frame 142 of 203 | actors.march:23:4 | depth 1
     21 │   match msg with
     22 │     | :ping -> send(reply, :pong)
→    23 │     | :stop -> ()
[frame 142] dbg>
```

If the requested frame is out of range (> `rb_size - 1` or < 0), print an error:
`error: frame 300 out of range (0..203)`.

### Implementation

**`trace.ml`:** Add `goto (ctx : debug_ctx) (n : int) : int` — clamps `n` to
`[0, rb_size-1]`, sets `ctx.dc_pos <- n`, returns new pos.

**`repl.mli`:** Add `dh_goto : int -> int` to `debug_hooks`.

**`debug_repl.ml`:** Wire `dh_goto = (fun n -> Trace.goto ctx n)`.

**`repl.ml`:** Parse `:goto N` in both simple and TUI loops. Call
`hooks.dh_goto n`, then auto-show `:where` (Priority 1 behavior).

---

## Priority 5 — `:diff [N]` — env diff between frames

### Motivation

When stepping through a loop, the user wants to see *what changed* between
frames, not the entire env (which can be large). `:diff` shows only bindings
that are new or changed relative to the previous frame (or frame N frames back).
This is inspired by pry-stack-explorer's `show-frame` and Elm's diff-based
model message display.

### Behavior

```
[frame 14] dbg> :diff
  ~ n : 3 -> 2          (changed)
  + acc : 6             (new binding)

[frame 14] dbg> :diff 5   -- compare to frame 9
  ~ n : 7 -> 2
  ~ acc : 0 -> 6
```

Format:
- `+` prefix: binding exists in current frame, not in reference frame
- `~` prefix: binding exists in both but value changed
- `-` prefix: binding in reference frame but not in current (shadowed/dropped)

Only user-scope bindings are shown (same filter as `:env` — excludes stdlib).

### Implementation

**`trace.ml`:** Add `diff_frames (ctx : debug_ctx) (n : int) : (string * diff_entry) list`
where `diff_entry = Added of value | Changed of value * value | Removed of value`.
Compare `env_to_assoc current_frame.env` with `env_to_assoc ref_frame.env`
using the same `user_scope` filter already used in `repl.ml`.

**`repl.mli`:** Add `dh_diff : int -> string list` to `debug_hooks`
(pre-formatted strings for display).

**`repl.ml`:** Parse `:diff` and `:diff N`.

---

## Priority 6 — `:find <expr>` — search trace for condition

### Motivation

"Find the frame where `n` first became 0" or "find the frame where this list
became empty." Manually `:back`-ing through 200 frames to find a specific state
is painful. `:find` evaluates a March expression against each frame in the trace
(walking backward from the current position) and jumps to the first frame where
it returns `true`.

### Behavior

```
[frame 203] dbg> :find n = 0
Searching 203 frames...
Found at frame 87.
Frame 87 of 203 | factorial.march:4:5 | depth 3
[frame 87] dbg>
```

Search walks backward from current position by default. If no frame matches:
`No frame found where n = 0`.

### Behavior with side effects

The expression is evaluated in each frame's env using `Eval.eval_expr`.
Side-effecting expressions (e.g. `print(n)`) will fire for each tested frame.
This is consistent with how `:replay` works — the user controls what they
evaluate. Document that `:find` expressions should be pure.

### Implementation

**`replay.ml` or new `search.ml`:** `find_frame (ctx : debug_ctx) (env_at_frame : env -> value) : int option`.
Walks frames from `dc_pos` backward to oldest, calling the user-supplied
function (which is a closure over the parsed expression). Returns first frame
index where the function returns `VBool true`.

**`repl.ml`:** Parse `:find <rest_of_line>`. Re-parse `rest_of_line` as a March
expression using `March_parser.Parser.expr_eof`. Build a closure
`fun env -> March_eval.Eval.eval_expr env parsed_expr`. Call `dh_find` hook.

**Performance note:** For 100K-frame traces, walking all frames evaluating a
March expression could be slow (~seconds). Accept this for v1. A future
optimization can vectorize over env snapshots.

---

## Priority 7 — `:watch <expr>` — watch expressions

### Motivation

"Show me the value of `acc` every time I step." pry-stack-explorer has `watch`
commands; gdb and lldb have watchpoints. In the time-travel model, a watch
expression is most useful as a display overlay — after each navigation command,
automatically evaluate the watch expressions against the current frame env and
show their current values.

### Behavior

```
[frame 0] dbg> :watch n
Watch added: n
[frame 0] dbg> :back
Frame 1 of 203 | ...
  ◉ n = 5
[frame 1] dbg> :back 3
Frame 4 of 203 | ...
  ◉ n = 3
[frame 4] dbg> :watch acc
Watch added: acc
[frame 4] dbg> :back
Frame 5 of 203 | ...
  ◉ n = 3
  ◉ acc = 6
[frame 4] dbg> :unwatch n
Removed watch: n
[frame 4] dbg> :watches
  acc
```

Watch values are shown after the `:where` output on every navigation step.
If a watch expression fails to evaluate in a given frame (variable not in scope),
show `◉ n = <not in scope>`.

### Implementation

**State:** Add `watch_exprs : (string * March_ast.Ast.expr) list ref` to the
REPL loop state (local mutable). The string is the raw source text for display;
the expr is the parsed form.

**Evaluation:** After each navigation + auto-`:where`, iterate watch_exprs,
call `eval_expr frame_env expr` for each, catch exceptions, format and print.

**Commands:** `:watch <expr>`, `:unwatch <expr>`, `:watches`.

No changes to `debug_hooks` — watches are managed entirely within `repl.ml`
(they use `dh_frame_env` to get the current env, which already exists).

---

## Priority 8 — Pretty-printing for nested values

### Motivation

`value_to_string` currently produces flat, compact output:
```
{name: "Alice", age: 30, friends: ["Bob", "Carol", "Dave", ...]}
```

For deeply nested records/variants/lists, this is unreadable. Pretty-printing
with indentation is a standard debugger feature. Elm's debugger and pry both
indent nested data. This improves `:env`, `:where` result display, `:watch`
output, and all REPL expression results.

### Behavior

```march
let x = {name: "Alice", age: 30, friends: ["Bob", "Carol", "Dave"]}
```

```
march(1)> x
{ name: "Alice"
, age: 30
, friends: [ "Bob"
           , "Carol"
           , "Dave" ] }
```

Flat output is used when the value fits within a width threshold (80 chars).
Multi-line output is used otherwise.

### Implementation

Add `value_to_string_pretty (width : int) (v : value) : string` in `eval.ml`
(or a new `lib/eval/pp.ml`). The algorithm is a standard Wadler-Lindig
pretty-printer: try flat first, fall back to broken layout if it exceeds `width`.

The existing `value_to_string` is used in trace recording and other non-display
contexts — keep it as-is. The REPL uses `value_to_string_pretty` for user-facing
output only.

**Scope:** Only affects REPL output. No changes to trace recording, error
messages, or stdlib functions.

---

## Priority 9 — Trace export/import (`:save` / `:load`)

### Motivation

"I reproduced the bug, I want to save this trace and look at it later" or "share
it with a colleague." pry doesn't have this; it's more inspired by Elm's ability
to export/import the model message history for reproducibility. For a
time-travel debugger, a saved trace is a complete record of what happened.

### Behavior

```
dbg> :save /tmp/my_trace.mtr
Saved 203 frames to /tmp/my_trace.mtr.

$ march --debug factorial.march
[debug] Trace recording enabled
[debug] Breakpoint hit at factorial.march:2:3
dbg> :load /tmp/my_trace.mtr
Loaded 203 frames. Navigate with :back/:forward/:goto.
[frame 0] dbg> :goto 87
...
```

The loaded trace replaces the live trace. Navigation works normally. Expressions
can be evaluated against loaded frames (`:replay` may not make sense for loaded
traces — document as unsupported in v1).

### Format

Binary format using OCaml's `Marshal` module. Each frame contains:
- `tf_span` (file + line + col)
- `tf_env` (the env assoc list — Marshal handles this)
- `tf_result`, `tf_exn`, `tf_depth`

**Caveat:** `Marshal` is version-specific; traces are not portable across March
compiler versions. Document this. A JSON format is a future option.

**File extension:** `.mtr` (march trace).

### Implementation

**`trace.ml`:** Add `save_trace (ctx : debug_ctx) (path : string) : unit` and
`load_trace (ctx : debug_ctx) (path : string) : unit`.

`save_trace`: `Marshal.to_channel oc ctx.dc_trace []`.
`load_trace`: `ctx.dc_trace <- Marshal.from_channel ic`.

**`repl.mli`:** Add `dh_save : string -> unit` and `dh_load : string -> unit` to
`debug_hooks`.

**`repl.ml`:** Parse `:save <path>` and `:load <path>`.

---

## Priority 10 — Actor message history (Elm-inspired per-actor inbox log)

### Motivation

Elm's time-travel debugger is built around message history: every `Msg` sent to
the runtime is logged, and you can replay from any message. March actors are the
analogous model. When debugging actor-heavy code, the current trace shows every
eval step — but the user often wants a higher-level view: "what messages did
actor `counter` receive, and what state did it have before/after each one?"

This is a distinct view from the raw trace. It's the actor-level story, not the
expression-level story.

### Behavior

New command `:actors`:

```
dbg> :actors
PID 0 (counter): 12 messages
PID 1 (printer): 3 messages

dbg> :actor 0
  Msg  1: :reset           state before: 0        state after: 0
  Msg  2: :increment       state before: 0        state after: 1
  Msg  3: :increment       state before: 1        state after: 2
  Msg  4: :get(reply=1)    state before: 2        state after: 2
  Msg  5: :increment       state before: 2        state after: 3
  ...

dbg> :actor 0 5     -- jump to trace frame when message 5 was received
Frame 47 of 203 | counter.march:12:5 | depth 2
```

### Data Model

Each actor receives messages via `ESend` dispatch. During trace recording, when
`eval_expr` handles `ESend` against an actor (not a channel send), record an
`actor_message_event`:

```ocaml
type actor_message_event = {
  ame_pid     : int;
  ame_msg     : value;
  ame_state_before : value;
  ame_state_after  : value option;  (* None if handler raised *)
  ame_frame_idx    : int;           (* index into trace ring buffer *)
}
```

These are stored in a separate `actor_log : actor_message_event list ref`
(appended, no ring buffer needed — one entry per message, not per eval step).

### Implementation

**`debug.ml`:** Add `actor_log` to `debug_ctx`. Record entries in `eval.ml`
at the `ESend`→actor dispatch site (after the handler returns).

**`trace.ml`:** Add `actors_summary (ctx : debug_ctx) : string list` and
`actor_history (ctx : debug_ctx) (pid : int) : string list` formatters.

**`repl.mli`:** Add `dh_actors : unit -> string list` and
`dh_actor : int -> string list` to `debug_hooks`. Optionally add
`dh_actor_goto : int -> int -> int` (pid, msg_idx → frame_idx, then goto).

**`repl.ml`:** Parse `:actors`, `:actor <pid>`, `:actor <pid> <msg_idx>`.

---

## Implementation Order Summary

| # | Feature | Effort | Value |
|---|---------|--------|-------|
| 1 | Auto-show `:where` after nav | Tiny | High |
| 2 | `dbg(expr)` value trace | Small | High |
| 3 | Conditional `dbg(cond)` | Small | High |
| 4 | `:goto N` absolute jump | Small | Medium |
| 5 | `:diff [N]` env diff | Medium | High |
| 6 | `:find <expr>` search | Medium | Medium |
| 7 | `:watch <expr>` watches | Medium | Medium |
| 8 | Pretty-print values | Medium | Medium |
| 9 | Trace export/import | Medium | Low |
| 10 | Actor message history | Large | Medium |

Features 1–4 are independent and small enough to ship together in one pass.
Features 5–8 are medium effort and can be tackled in any order.
Features 9–10 are self-contained and can be deferred.

---

## Non-Goals for This Round

- LLVM/compiled debug support (tracked in `debugger_design.md` future work)
- DAP (Debug Adapter Protocol) integration
- Breakpoints set by file:line (vs explicit `dbg()` in source)
- Concurrent / multi-threaded trace (March actors are cooperative today)

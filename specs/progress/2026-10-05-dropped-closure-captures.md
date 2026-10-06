# `[P2]` A closure dropped without being called leaks everything it captured

**FIXED 2026-10-05**, along the fix sketch below, with the table keyed by the apply
function's address. Filed as `specs/todos/2026-10-04-dropped-closure-leaks-its-captures.md`.

## Fix

- `lib/tir/drop.ml` (`Drop.run`): for each closure type whose environment OWNS its
  captures (the same `owning_apply_fns` gate the apply-function release uses: a
  borrowing environment's captures are its scope's to release), a function
  `$clodrop$<clo>($clo)` that loads every RC'd capture and drops it with `drop_op`, so
  a captured list or closure is dropped deep.
  The name starts with `$` because it embeds the closure struct's name, and so the
  global lambda counter: hot-reload manifest diffs (forge's deploy plan,
  `forge/test/test_hcr_manifest_diff.ml`) treat a leading `$` as a generated name an
  edit may renumber. First spelled `__clodrop$`, every one-line edit to
  examples/topology_app reported 17 non-generated functions removed.
- `lib/tir/dce.ml`: nothing in TIR calls it; an allocation (or reuse) of the closure
  type is what keeps it alive.
- `lib/tir/llvm_emit.ml`: the release of a function-typed value (`EDecRC` /
  `EAtomicDecRC`) calls `march_clo_release` instead of `march_decrc[_local]`.
- `lib/tir/llvm_toplevel.ml`: `main`'s prologue (program and test runner) calls
  `@march_clo_drops_register`, which hands the runtime every (apply function, drop
  function) pair, taken from the FINAL module's closure allocations (field 0 of a
  `$Clo_*` allocation); an apply function seen with two closure types is left out.
- `runtime/march_runtime.c`: `march_clo_register_drops` fills an open-addressing table
  keyed by the apply function's address; `march_clo_release` looks up the closure's
  field 0 and, when this release frees the cell, runs the drop before freeing it. No
  entry (a runtime trampoline, a borrowing type, a hot patch or REPL fragment, which do
  not register) means a plain release: at worst the old leak, never a crash. The WASM
  runtime stubs both.

## Effect

Compiled `--opt 2`:

| Probe | Before | After |
|---|---|---|
| closure capturing a String, in a list, dropped (1000x) | 1000 objects left | 0 |
| the same, never applied (1000x) | 1000 | 0 |
| closure capturing a 20-element list, dropped (200x) | 4200 | 0 |
| `ClusterNode` register + unregister of one name (core, no actor) | 464 per pair | 29 |
| cluster session on one node, 0 / 1,000 / 10,000-byte payload | 4,420 / 6,375 / 7,893 per session | 1,384 / 3,310 / 4,829 |

The registry's share was `push_leaves`: it builds the sync frame and maps
`fn id -> Send(id, bytes)` over the linked peers, and with none the lambda holding the
frame was dropped uncalled, leaking it whole on every registration.

## Test

`test/native/dropped_closure_captures.march` (dune rule
`native_dropped_closure_captures`): dropped from a list, never applied, capturing a
list, and called then dropped; each "no growth". The first three are false with
registration disabled.

## Left

- A hot patch or REPL fragment registers nothing, so its closures keep the old leak.
- A TCO loop's deferred releases (`llvm_emit_tcoarm`) still release a closure with
  `march_decrc_local`.
- The apply function's own release drops only the captures its body loads.

## The original report


Filed 2026-10-04 while fixing
[2026-10-01-session-node-vault-tables-leak.md](../progress/2026-10-01-session-node-vault-tables-leak.md).

A closure value released at an outer site (dropped from a list, a record, a
Vault table, or simply never applied) frees its own cell and nothing it
captured. `lib/tir/drop.ml` documents the gap ("Still shallow: a bare
`EDecRC` on a closure value at an outer site"): at that site the value's
type is a function type, which names no environment layout, so Perceus has
nothing to release the captures with. Only an apply function releases its
own environment's captures, and only when the closure is called.

Measured on main (`9ee1f648b`) and the fix branch alike, compiled `--opt 2`:
a closure capturing one String, put in a list and dropped, 1000 times: 1000
live objects left (the String each time).

```march
pfn mk(i : Int) : Int -> Int do
  let s = "cap" ++ int_to_string(i)
  fn a -> a + string_length(s)
end
-- let l = Cons(mk(i), Nil); let _ = List.length(l)   -- in a loop
```

## Why it matters

Every `SessionNode` session stores closures in its tables (the installed
continuation in `handlers`, the cancel/crash/drain handlers, a hosted
party's forwards). They capture the session capability, whose `Ops`
closures capture the `Party`, which holds the session's table handles. With
`Vault.close` the tables are emptied and the closures dropped, but their
captures are not, so each session's `Party` and its 13 table HANDLES stay
alive (48 bytes each; the tables themselves are freed at the close since
2026-10-04). It is very likely a large part of the ~40,000 objects a
cluster session still leaves behind (test/two_node/session_churn measures
the tables, not this), alongside
[2026-10-01-session-message-encoding-leak.md](2026-10-01-session-message-encoding-leak.md).

## Fix sketch

drop.ml's own note: resolve the environment's layout at run time from the
code pointer in the closure's field 0. Emit, per `$Clo_*` struct, a drop
function that releases its captures typed (Perceus already knows each
capture's type when it builds the struct), and a table from apply-function
pointer to that drop function; an outer `EDecRC` on a function-typed value
becomes `march_clo_release(c)`: `march_decrc_freed(c)` and, if freed, the
looked-up drop of its captures. Mind the third owner (the C runtime hands
closures to apply functions and helpers that consume them:
`project_runtime_consumes_closure_third_party`), and ASAN it.

**Acceptance:** the loop above stays flat; test/two_node/session_churn's
node-a live-object delta per session drops (measure before and after).

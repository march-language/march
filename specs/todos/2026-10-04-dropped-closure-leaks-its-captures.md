# `[P2]` A closure dropped without being called leaks everything it captured

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

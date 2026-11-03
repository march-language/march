# A local `fn` generalized the type variables of what it captured

**Date:** 2026-10-12. Found by the interpreter-vs-compiled differential sweep
(group V): `Set.union(a, b, lt)` with `let lt = fn x -> fn y -> x < y`
printed `[1, 2, 3]` interpreted and died with SIGSEGV compiled.

## What was wrong

`infer_block`'s `ELetFn` arm (a named `fn` inside a block) created the
function's type, its parameters and its body's types at the ENCLOSING level
and then generalized at `level - 1`. Every type variable at the enclosing
level was quantified, including those of the enclosing function's own
parameters that the local fn captures. In stdlib `Set.union`:

```march
fn union(a, b, cmp) do
  fn go(acc, x) do insert(acc, x, cmp) end
  match b do HamtSet(_, node) -> node_fold(a, node, go) end
end
```

`go` became polymorphic in `cmp`'s element type, so `node_fold(a, node, go)`
instantiated a fresh copy and `union`'s inferred type came out as
`(Set(t), Set(t), (u, u) -> Bool)` — the comparator no longer tied to the
element type. With a comparator whose own element type is still open (a
`let`-bound lambda), monomorphization had nothing to bind `u` to, defaulted
it to `String` (`Mono.default_residual_tvars`) and specialized `insert` /
`key_hash` at String: the Int elements were hashed as strings
(`march_hash_string` on the immediate `1`). `Set.intersection` and
`Set.difference` had the same shape (`a`'s and `b`'s element types came
apart). The interpreter has no specialization and was always right.

## The fix

`lib/typecheck/typecheck.ml`, `ELetFn`: check the local fn one level deeper
(`enter_level`, as `ELet` already does for its right-hand side) and
generalize back at the enclosing level, so only variables created for the
local fn itself are quantified; the rest of the block continues at the
enclosing level. The stdlib's lowered signatures are now
`Set.union(a : Set(t), b : Set(t), cmp : (t, t) -> Bool)`.

## Tests

`test/native/local_fn_capture_not_generalized.march` (+ `.expected`, rule
in `test/dune`, refine audit baseline regenerated): a user-level `union` with
a capturing local `go` printing and hashing its elements, and `Set.union`
with a let-bound comparator. Compiled output equals the interpreter's
(`3#0,2#2`, `[1, 2, 3]`); before the fix the compiled binary died with
SIGSEGV before the first line.

## Not fixed here

With the types right, `Set.union` followed by `Set.intersection` and
`Set.difference` on one comparator still crashes compiled at exit — a
separate, older use-after-free:
`specs/todos/2026-10-12-set-ops-shared-comparator-use-after-free.md`.

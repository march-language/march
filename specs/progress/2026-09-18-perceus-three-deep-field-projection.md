# FIXED 2026-09-18 — a field projected three records deep got no dup before a consuming call

Found while building the cluster node service
([[2026-09-18-cluster-node-service]]): its state reads the member view at
`st.driver.swim.members`, and the first compiled node died with "panic:
non-exhaustive pattern match" or `RC underflow` on its first tick.

## The bug

```march
pfn get_vals(st : Outer) : List(Int) do vals(st.mid.inner.bag) end   -- vals consumes its Bag
```

`st.mid.inner.bag` lowers to

```
let t2 = (let t1 = (let t0 = st.mid in t0.inner) in t1.bag) in vals(t2)
```

`Perceus_core.insert_rc_expr`'s `ELet` arm decides whether `t2` is a
*borrowed field* (the record owner holds its reference, so a consuming use must
`inc_rc` first) by looking ahead through the RHS with
`result_is_borrowed_field`. That lookahead recognised `let iv = src.f in body`
(one projection) and walked through any other `let` without recording
anything. At depth three the middle binding's RHS is itself an `ELet`, not an
`EField`, so `t1` never entered the lookahead's borrowed set; the chain's last
projection `t1.bag` then looked owned, `t2` was classified owned, `vals(t2)`
got no dup, and the drop of `st` at the end of `get_vals` released the Bag a
second time. Depths 1 and 2 were fine (pinned by the depth probes in the
session log: `st.bag`, `st.mid.bag` both correct).

The binding's OWN classification was already right -- when Perceus reaches
`let t1 = (let t0 = st.mid in t0.inner)` it classifies `t1` borrowed -- only the
outer lookahead disagreed with it.

## The fix

One arm in `result_is_borrowed_field`: a nested `let iv = rhs in body` whose
`rhs` is itself a borrowed-field result adds `iv` to the lookahead's set before
checking `body`. It only makes the lookahead agree with the classification the
inner binding already gets.

## Verification

- `test/native/perceus_three_deep_field_borrow.march` (dune `runtest` rule):
  three calls of `get_vals`; pre-fix the second one panicked, post-fix `a 1 /
  b 1 / c 1`.
- The standalone probes (depth 3 with and without `Membership`, and the
  cluster node's own `core_members`, `dial_targets` and `core_tick`) all
  correct compiled after the fix; all were wrong before.
- `run_snapshots`: no TIR snapshot moved. `run_codegen` (622), `run_compiler`
  (1120), `test_stdlib_march` (69) green.
- Not run: an ASAN sweep and a benchmark A/B against a compiler without the
  fix. The change only turns a binding that was classified owned into a
  borrowed one where the chain's source record outlives it, which removes a
  missing dup; it adds no RC op on any path that was already correct.

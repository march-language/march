`[P2]` Compiled build fails to link when `compare` (or a lambda that only calls `hash`) is passed to an unannotated stdlib parameter (2026-11-11)

Not one of the 2026-10-18 claims; found while writing their repros. `OrderedMap.from_list(xs, compare)`
is the form every `OrderedMap` doc example uses. It runs interpreted, but `--compile` emits a wrapper
that calls an undefined `@compare` and clang rejects the IR. The same happens with `@hash` for
`Hamt.insert(h, k, v, fn k -> hash(k), eq)`.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let m = OrderedMap.from_list([(2, "b"), (1, "a")], compare)
  println(to_string(OrderedMap.to_list(m)))
end
end
```

Expected: `[(1, a), (2, b)]` on both backends.

Actual (interpreted / compiled): interpreted prints `[(1, a), (2, b)]`; compiled stops with `error: use of undefined value '@compare'` at `%r = call i64 @compare(i64 %a0u, i64 %a1u)`, then `march: clang failed (exit 1)`.

Source: builtin-as-value wrapper emission in `lib/tir/llvm_emit*.ml` (not investigated further). Workaround: pass an explicit lambda that does more than forward to the builtin.

Found 2026-11-11 on a7110f95f while re-verifying the 2026-10-18 doc sweep claims.

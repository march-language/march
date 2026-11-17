`[P2]` Native REPL crashes when Map.int_cmp or Map.str_cmp is passed as a value and the key is found (2026-11-11)

In `march repl`, passing the named comparators `Map.int_cmp` / `Map.str_cmp` as a function value to
`Map.get` kills the process (Bus error with int_cmp, SIGSEGV with str_cmp) when the lookup hits.
A miss returns `None` normally, and an inline lambda `fn a -> fn b -> a < b` works on a hit.
The same program is correct interpreted and compiled.

Repro (`printf '...' | march repl`):

```march
let m = Map.insert(Map.empty(), 1, "a", Map.int_cmp)
Map.get(m, 1, Map.int_cmp)
```

As a file, for the interpreted and compiled control:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let m = Map.insert(Map.empty(), 1, "a", Map.int_cmp)
  println(to_string(Map.get(m, 1, Map.int_cmp)))
end
end
```

Expected: `= Some("a")`.
Actual (REPL): `val m = HamtMap(HLeaf(269157861, 1, "a"))` then the process dies, exit 138 (139 for str_cmp).
Actual (interpreted / compiled): `Some(a)` / `Some(a)`.

Source: `int_cmp` / `str_cmp` in stdlib/map.march (curried `fn int_cmp(a) do fn b -> a < b end`); the
fragment compiler is lib/jit/repl_jit.ml. Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

## Fixed 2026-11-16

`int_cmp` takes one parameter and returns a closure, but at the call site its type is the curried
`Int -> Int -> Bool`, which `convert_ty` uncurries to two parameters. When a top-level function is
used as a value, `emit_atom` builds a `$clo_wrap` trampoline from the definition's signature in
`top_fn_param_tys`, falling back to the use-site type only when that is missing. The compiled path
fills that table for every function (`llvm_toplevel.ml`). The REPL fragment emitters
(`lib/tir/llvm_repl.ml`) registered only `top_fns`, `top_fn_ret_ty` and `top_fn_nparams`, never the
parameter types. So in a fragment the precompiled `Map.int_cmp` got a two-argument trampoline that
called `@Map.int_cmp(i64, i64)` and returned the closure pointer as a Bool. Its first call, on a
lookup hit, crashed.

All nine registration sites in `llvm_repl.ml` now also record `top_fn_param_tys`, for fragment and
precompiled functions alike, matching the compiled path. Regression tests: `test/test_jit.ml` "clang:
curried stdlib fn passed as a value" / "orc: …" (`int_cmp` and `str_cmp` hits). Both crashed before
the fix and pass after it.

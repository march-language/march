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

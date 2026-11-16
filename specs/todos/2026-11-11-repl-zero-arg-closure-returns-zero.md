`[P2]` Native REPL: a zero-arg closure bound with `let` returns 0 (or 1) instead of its result (2026-11-11)

In `march repl`, a zero-argument lambda bound with `let` and then called returns a wrong value:
`fn -> 1` gives 0, `fn -> 41 + 1` gives 0, `fn -> 2.5` gives 0, and `fn () -> "hi"` gives 1.
Calling the lambda in place, `(fn -> 7)()`, gives 7, and a one-arg closure bound with `let` works.
Interpreted and compiled programs are correct.

Repro (`printf '...' | march repl`):

```march
let f = fn -> 1
f()
let h = fn () -> "hi"
h()
```

Control as a file:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let f = fn -> 1
  println(to_string(f()))
end
end
```

Expected: `= 1` and `= "hi"`.
Actual (REPL): `= 0` and `= 1`.
Actual (interpreted / compiled): `1` / `1`.

Source: let-bound closure slots in lib/jit/repl_jit.ml. Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

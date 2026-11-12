`[P2]` Native REPL rejects `==` on Option, List and Result values: "does not implement interface Eq" (2026-11-11)

In `march repl`, `==` on an `Option`, `List` or `Result` value fails fragment typechecking with
`Option(Int) does not implement interface Eq`, even after the module has been used in the session.
Tuples and scalars compare fine. The same expression is accepted and true interpreted and compiled,
where `impl Eq(Option(a)) when Eq(a)` (stdlib/option.march) applies. This now hides item 1 of
specs/todos/2026-10-14-native-repl-quirks-found-by-doctests.md (`Vault.get(c, "h") == Some(1)`),
which fails with this error before it can compare anything. Reproduced with a private HOME, so it
is not a stale ~/.cache/march entry.

Repro (`printf '...' | march repl`):

```march
Some(1) == Some(1)
[1] == [1]
(1, 2) == (1, 2)
```

Control as a file:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Some(10) == Some(10)))
end
end
```

Expected: `= true` three times.
Actual (REPL): `error: March_jit.Repl_jit.Typecheck_failed("`Option(Int)` does not implement interface `Eq`...")`,
the same for `List(Int)`, then `= true` for the tuple.
Actual (interpreted / compiled): `true` / `true`.

Source: fragment typechecking in lib/jit/repl_jit.ml (`Typecheck_failed`). Found while re-verifying
the 2026-10-18 doc sweep claims on 2026-11-11, a7110f95f.

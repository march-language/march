`[P2]` - [x] **Native REPL rejects `==` on Option, List and Result values: "does not implement interface Eq"** (logged 2026-11-11, verified fixed 2026-11-22)

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

## Resolution (verified 2026-11-22)

Already fixed by #1294 (91e86b308, "repl: fix native-REPL quirks found by the doc-example
checks"): `Repl.preregister_stdlib_types` (lib/repl/repl.ml) now registers every stdlib
module's impls with `Typecheck.register_impl_shape`, as `check_module`'s pass 1 does, so
`impl Eq(Option(a)) when Eq(a)` and its List/Result siblings are visible to fragment
typechecking. Root cause and fix are written up in
specs/progress/2026-11-18-native-repl-quirks.md.

Re-run on origin/main with a private HOME: `Some(1) == Some(1)`, `[1] == [1]`,
`Ok(1) == Ok(1)` and `(1, 2) == (1, 2)` all print `= true`, `Some(1) == None` prints
`= false`.

The Vault item this was hiding (item 1 of
specs/todos/2026-10-14-native-repl-quirks-found-by-doctests.md, the `==` part) was fixed by the
same PR and that todo already says so; its open remainder (what a JIT `let` displays) is
unrelated to Eq.

Test: test/test_jit.ml `test_repl_stdlib_eq_literals` (`repl_session`), the todo's own repro
plus the unequal cases, answers checked in order. #1294's Vault test covered Option and List
but no Result and no bare literal. Not seen failing: the fix predates the test.

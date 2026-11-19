`[P2]` Native REPL (`march repl`) bugs found by the doc-example checks (2026-10-14)

Converting stdlib examples into checked `march>` transcripts
(scripts/check-stdlib-doctests.py feeds them to `march repl`) found native-REPL-only
bugs. The same code is correct interpreted (`march file.march`) and compiled, and in
the browser REPL unless noted. Each was worked around in the docs.

Items 1 (the `==` part), 3, 4, 5 and 6 were fixed 2026-11-18:
`specs/progress/2026-11-18-native-repl-quirks.md`. What remains open is below.

1. **Vault values decay after `==`.** ~~`Vault.get(c, "h") == Some(1)` is `true` once,
   then `false`~~ (fixed: a duplicate `__march_eq_<ty>` under ORC sent the input to the
   interpreter). **Still open:** `let x = Vault.get(c, "h")` displays `val x = None`. The
   REPL runs a `let` in the JIT AND re-runs it in the interpreter (`lib/repl/repl.ml`, the
   JIT `let` path: "Always update interpreter env (source of truth for value display)"),
   and prints the interpreter's value. The two worlds have different Vault tables, so the
   display is wrong while `x` itself (the JIT slot) is `Some(1)`. Every effect in a `let`
   also runs twice: `let x = println("hi")` prints `hi` twice. A fix is to print the JIT
   slot's value (read with `march_repl_get` and rendered by `pp_heap_value`), but the
   JIT printer does not yet render every type the way the interpreter does (test_jit pins
   `val m = HamtMap(...)`). It also needs a decision on whether the interpreter should keep
   evaluating JIT `let`s at all. Workaround in stdlib/vault.march: read with `get_or` /
   `has` / `Option.unwrap_or`.
2. **A binding named `v` is clobbered by the last result.** After `let v = 5`, entering
   `100` then `v` gives 100. This is documented behaviour, not a bug: `v` is the REPL's
   last-result variable (docs/repl.md "`v`: The Last Result", specs/features/repl.md)
   in both REPLs. Open question: should `let v = …` warn, or should a user binding shadow
   `v` until it is rebound? Until that is decided, examples avoid `v`.
3. ~~Non-ASCII strings print as escaped bytes~~: fixed 2026-11-18.
4. ~~Unit prints as `1`~~: fixed 2026-11-18.
5. ~~Record equality goes wrong after an earlier record-list `==`~~: same cause as 1,
   fixed 2026-11-18. (`==` on anonymous records is now a type error in every backend.)
6. ~~A panic ends the session~~: fixed 2026-11-18. scripts/check-stdlib-doctests.py
   still skips `** panic` examples; it could feed them now.

Also seen while fixing these: the interpreter REPL (`MARCH_REPL_INTERP=1`) reports a
deferred interface error on the input AFTER the one that caused it. Before the stdlib
impls were registered, `Some(1) == Some(1)` printed `= true` and the next input,
`let v = 5`, failed with "`Option(Int)` does not implement interface `Eq`". `{a: 1} ==
{a: 1}` still shows it.

Filed separately: `Err(:atom)` as a bare result segfaults the REPL (session task
"Fix native REPL segfault on Err(:atom) value"); NativeArray i32 values print as
9223372036854775807 (branch fix/repl-i32-native-array-sign).

Reproduce any of them with `printf '...\n' | ./_build/default/bin/main.exe repl`.

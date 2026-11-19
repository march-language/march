`[P2]` Native REPL prints some stdlib Int results still tagged (2n+1), and a `let` of one breaks (2026-11-11)

Some stdlib functions that return Int print their result in the REPL as the tagged word 2n+1.
`Presence.entry_count` (a nested local `go` helper returning its accumulator) prints 5 for 2 and 1
for 0; `LazyNicheProbe.first_or` (returns an Int taken out of `Option`) prints 15 for 7 and 7 for 3.
Only the printed value is wrong: `... == 7` is true and `... + 1` is 8. `List.length` and
`Option.unwrap_or` print correctly. Binding the result is also broken:
`let k = Presence.entry_count(Presence.make_entry([]))` shows `val k = 0` and then evaluating `k`
segfaults the REPL, and `let n = LazyNicheProbe.first_or([7, 8], 3)` fails with
`runtime error: unbound variable: LazyNicheProbe.first_or`.

Repro (`printf '...' | march repl`):

```march
Presence.entry_count(Presence.make_entry([Presence.make_meta(1, "{}"), Presence.make_meta(2, "{}")]))
LazyNicheProbe.first_or([7, 8], 3)
```

Control as a file:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(Presence.entry_count(Presence.make_entry([Presence.make_meta(1, "{}"), Presence.make_meta(2, "{}")]))))
  println(to_string(LazyNicheProbe.first_or([7, 8], 3)))
end
end
```

Expected: `= 2` and `= 7`.
Actual (REPL): `= 5` and `= 15`.
Actual (interpreted / compiled): `2`, `7` / `2`, `7`.

Source: `list_len_pr` in stdlib/presence.march, `first_or` in stdlib/lazy_niche_probe.march; result
printing and slot untagging in lib/jit/repl_jit.ml (see 70f222be7). Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

## Fixed 2026-11-17 (Presence half)

Not a REPL bug: the type checker gave `Presence.entry_count` the type `PresenceEntry -> b`.
`Typecheck_reorder.reorder_decls` orders each contiguous run of `fn` declarations
callee-first, and `type PresenceState` sat between `entry_count` and the `list_len_pr` it
calls, so the run ended there. `entry_count` was checked against `list_len_pr`'s pass-1
placeholder and generalized over it. With a free result type the REPL took the print path
for an unknown type and showed the raw tagged word; `let k = ...` then read the slot with the
wrong representation. The same hole accepted `let s : String = count(xs)` in any file whose
caller and helper were separated by a `type`.

A type declaration no longer ends a run: types are registered before any function is checked
(a function may already use a type declared below it), so the run's types move to its front
and its functions follow in dependency order. Tests: `nested_mod_prebind_erasure` "forward ref
across a type decl" (three cases; two RED before the fix) in test/test_compiler.ml, and
`repl_session` "stdlib Int result prints untagged and binds (JIT)" in test/test_jit.ml.

The `LazyNicheProbe.first_or` half is a different gap and is filed as
`specs/todos/2026-11-17-registry-loaded-module-fn-untyped.md`.

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

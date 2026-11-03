`[P3]` `List.chunks(xs, 0)` hangs when the checker cannot see the size — DONE 2026-10-27

Found while fixing the D5 hangs (`specs/progress/2026-10-27-stdlib-step-zero-hangs.md`),
not one of the four probes s1-s4. Filed and closed on the same branch.

**Cause.** `List.chunks` (`stdlib/list.march`) already had `size : {Int | _ > 0}`, so a
literal 0 is a compile-time refinement error, but it had no runtime guard. A size the
checker cannot see (the obligation is a silent skip) reached `go`, where
`split_at(lst, 0)` returns `([], lst)` and the walk repeated on the same list forever;
a negative size behaves the same. Probe (2026-10-27,
`List.length(List.chunks([1, 2, 3], hidden_int("0")))`, `hidden_int` parsing through
`string_to_int`): killed at 10 s both interpreted and compiled.

**Fix.** `if size <= 0 do panic("List.chunks: size must be positive") else go(xs, Nil) end`,
the D5 convention (List panics on a bad argument). Behaviour change: an empty list with
a size <= 0 used to return `[]`; it now panics too. `List.pmap`/`pfilter`/`preduce`
pass `pmap_threshold()` (contracted `> 0`) and `pmap_n` passes a size clamped to
`>= 1`, so no caller's behaviour changes.

**TIR.** `chunks` was never a TRMC target (its walk is a local accumulator loop, `go`).
The guard adds a branch to `List.chunks`' own body only; `go` is unchanged. See the
commit message for which snapshot files moved.

**Tests.** `test/stdlib/test_list.march`: good paths (sizes 2, 5, 1, an empty list)
unchanged; sizes 0 and -2 and an empty list with 0, passed through `opaque_int`, give
`"panic: List.chunks: size must be positive"`. RED: the test hung (killed at 20 s).
Native golden `test/native/stdlib_step_guards`: `lc good` / `lc bad` lines, compiled
and interpreted.

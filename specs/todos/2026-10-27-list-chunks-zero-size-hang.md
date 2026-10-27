`[P3]` `List.chunks(xs, 0)` hangs when the checker cannot see the size

Found while fixing the D5 hangs (`specs/progress/2026-10-27-stdlib-step-zero-hangs.md`),
not one of the four probes s1-s4. `List.chunks` (`stdlib/list.march`) already has
`size : {Int | _ > 0}`, so a literal 0 is a compile-time refinement error, but it has
no runtime guard. A size the checker cannot see (the refinement obligation is a
silent skip) reaches `go`, where `split_at(lst, 0)` returns `([], lst)` and the walk
repeats on the same list forever.

Probe (2026-10-27, `List.length(List.chunks([1, 2, 3], hidden_int("0")))` with
`hidden_int` parsing the string through `string_to_int`): killed at 10 s both
interpreted and compiled.

Fix in the D5 style: `if size <= 0 do panic("List.chunks: size must be positive")`
before the walk, a `test/stdlib/test_list.march` case through `__try_call_val`, and
the line in the CHANGELOG. `List.pmap`/`pfilter`/`preduce` call it with
`pmap_threshold()`, which is contracted `> 0`, so they are unaffected.

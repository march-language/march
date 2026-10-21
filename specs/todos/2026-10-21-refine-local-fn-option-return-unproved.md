# `[P3]` An `Option` element return produced through a local `fn` is not proved

Filed 2026-10-21 from the inference-lite design (§0, row O1).

`find_index`-shaped code — `fidx(xs, pred)` with a local `go(lst, i : {Int | _ >= 0}) :
Option({Int | _ >= 0})` — hand-annotated gives 3 skips: `unreflectable-subject` at `return of go`,
at `return of fidx`, and at the `match fidx(…) do Some(i) -> need_nn(i)` use. A local `fn`'s
`Option` return is neither checked through `Some(i)` tails nor lent. Inference rejects the
candidate (`not-true`); `List.find_index` stays unannotated.

# `[P3]` A two-argument definer passed through to `Map.filter` does not prove its return

Filed 2026-10-25 from `specs/progress/2026-10-25-refine-infer-vocab.md` (item 2).

```march
fn need_posmap(_m : Map(String, {Int | _ > 0})) : Int do 0 end
fn mfilt(m : Map(k, v), keep : k -> v -> Bool[p], cmp : k -> k -> Bool) : Map(k[p], v[p]) do
  Map.filter(m, keep, cmp)
end
fn go(m : Map(String, Int)) : Int do need_posmap(mfilt(m, fn _k -> fn v -> v > 0, Map.str_cmp)) end
```

`--check --refine-report`: 2 skipped, both `abstract-refinement-uninstantiated` — the
return of `mfilt` (3:95) and the `need_posmap` demand. The same pass-through over a user
`Assoc(k, v)` (multi-arg phase 2, `cb_passthrough`) and `Deque.filter` with a one-argument
callback both prove. `Map.filter`'s own signature is
`(m : Map(k, v), pred : k -> v -> Bool[p], cmp : k -> k -> Bool) : {Map(k[p], v[p]) | subset(keys(_), keys(m))}`;
the refined (set-measure) return is a likely suspect.

Inference proposes the K6 shape for `mfilt` and the oracle rejects it (pinned by the
`infer-vocab-oct` row "K6 over Map(k, v) … not proposed"). Once the checker proves it,
that row should flip to a proposal.

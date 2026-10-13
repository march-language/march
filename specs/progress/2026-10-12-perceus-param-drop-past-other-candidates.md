# DONE 2026-10-12: an owned record parameter released by one arm of a let's value leaked on the other

Found by the TIR verifier's leak sweep (`2026-10-12-verifier-leak-sweep.md`), in
`ClusterNode.keeps_new`, `SessionNode.fill_roles` and `Control.leader_report`.

## The bug

```march
pfn keeps_new(st : St, l : Ln) : Bool do
  let lower = if st.me < l.node_id do st.me else l.node_id end
  l.dialer == lower
end
```

Perceus's cross-branch pass releases `st` at the head of the `else` arm, where `st` is dead. The
`then` arm only reads `st.me`, and nothing released `st` after that read. The record leaked
once per call, along with every heap field in it. A 3000-call `live_allocs()` loop was not flat
when compiled, and was flat when interpreted.

`insert_owned_aggregate_param_drops` (`lib/tir/perceus.ml`) pushes a drop into a `let`'s value
when that value takes a candidate on some path and "nothing after it mentions any candidate".
Here the rest of the body reads `l`, another candidate parameter, so the push was refused. `st`
then counted as "taken" for the rest of the path, and no arm dropped it.

## The fix

When the rest of the body still mentions other candidates, the candidates the value takes on
some path and the rest never names are pushed into the value. The others continue to the rest of
the body as before. The alias guard is unchanged: nothing is pushed while the rest of the body
reads a borrowed alias.

## Red

- `test/native/partial_release_aggregate_drop.march`, leg 1: not flat before the fix, flat
  after, at default opt and `--opt 2`.
- `test/test_codegen.ml`, "rc: leak sweep shapes are clean": the verifier's leak finding on
  `keeps_new`.

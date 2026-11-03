# DONE 2026-10-12: a let-bound record that an if statement released on one path leaked on the other

Found by the TIR verifier's leak sweep (`2026-10-12-verifier-leak-sweep.md`), in
`ClusterNode__CtlWriter_CtlClose`. That is a compiled actor handler, so the leak was the actor's
state record, once per message.

## The bug

```march
pfn stmt_case(n : Int) : Int do
  let r = { fd: n % 3 - 1, name: int_to_string(n) }
  if r.fd >= 0 do touch(r.fd) else 0 end
  n * 2
end
```

The cross-branch pass releases `r` at the head of the `else` arm, where `r` is dead. The `then`
arm reads `r.fd` and keeps it. `drop_agg_at_tails` (`lib/tir/perceus_core.ml`) left alone any
`let` or statement that released `r` anywhere inside, treating "releases on some path" as
"releases". The scope-end drop was therefore withdrawn from the `then` path too.

## The fix

When a statement or a `let`'s value releases the aggregate and the aggregate is dead after it,
the walk goes into it. Each of its paths settles the aggregate for itself, and a path that
releases it is still left alone. The straight-line "already released" rule now applies only to a
leaf, not to a whole `let` or sequence, so a release nested in a later case no longer stops the
walk early.

## Red

`test/native/partial_release_aggregate_drop.march`, the statement leg: not flat before the fix,
flat after. Also the verifier's leak finding on `stmt_case` in "rc: leak sweep shapes are clean".

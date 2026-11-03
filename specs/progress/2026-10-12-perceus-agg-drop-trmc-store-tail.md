# DONE 2026-10-12: a record destructured in a TRMC'd map leaked once per element

Found by the TIR verifier's leak sweep (`2026-10-12-verifier-leak-sweep.md`), in
`Plot.render_legend`'s `go$dps`.

## The bug

```march
pfn labels(lst : List(S)) : List(String) do
  match lst do
    Nil -> Nil
    Cons(s, rest) ->
      match s.label do
        None -> labels(rest)
        Some(lbl) -> Cons(lbl ++ s.style, labels(rest))
      end
  end
end
```

Under TRMC, the arms of `labels$dps` end in a destination write, `$dst.1 <- x`, and the inner
match's synthesised panic default ends in one too. `s` is never released, on any path.

`drop_agg_at_tails` (`lib/tir/perceus_core.ml`) places an owned aggregate's scope-end drop
before each tail. It binds a tail it cannot classify to a temporary of the tail's type.
`ESetField` has no type in `tir_expr_ty`, so the walk gave up, and that cancelled the drop on
every path, not just the panic one. The non-TRMC version of the same function (an accumulator)
was already dropped correctly.

## The fix

A destination-write tail gets the release in front of it when neither the object it writes nor
the value points into the aggregate (`points_into`, which the call-tail rule already uses).

## Red

`test/native/partial_release_aggregate_drop.march`, the TRMC leg: not flat before the fix, flat
after. Also the verifier's leak finding on `go$dps` in "rc: leak sweep shapes are clean".

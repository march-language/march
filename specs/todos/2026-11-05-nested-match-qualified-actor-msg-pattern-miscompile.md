`[P2]` Compiled: a match on a qualified actor message nested in a `Some` arm panics

Found while building the M10 message guard
(`specs/progress/2026-11-05-hcr-live-data-migration-check.md`). Compiled (not interpreted),
this panics with `non-exhaustive pattern match` on its first call:

```march
fn w(m : V1.Msg, none : Counter.Msg) : Counter.Msg do
  match counter_migrate_msg(m) do
    Some(x) ->
      match x do
        Counter.Bump(p0) -> if not_137(p0) do x else none end
        _ -> x
      end
    None -> none
  end
end
```

With the bare pattern `Bump(p0)` it works, and so does the qualified pattern in a function of
its own (`fn g(x : Counter.Msg) : Bool do match x do Counter.Bump(p0) -> ... _ -> true end
end`). The `--dump-tir` of the failing shape shows the outer `case` with a default arm that
panics; the `Some` arm is the one taken. Start with the match compiler's handling of a
qualified constructor in a nested scrutinee (lib/tir/lower_match.ml).

Desugar_migrate_check works around it with a separate guard function; remove the workaround
once this is fixed.

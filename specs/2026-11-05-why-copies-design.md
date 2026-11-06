# `--why-copies`: say why an update copies instead of reusing in place

Filed 2026-11-05 from the diagnostics work (Elm/Rust comparison, "where else could we beat them").

## Why

Perceus reuses a dying cell in place (FBIP): `List.map` over a list nobody else holds rewrites its
cells instead of allocating new ones. When it can't, the program still runs, just slower and with
more allocation, and nothing says so. Koka's `fip`/`fbip` annotations reject a function that isn't
fully in place, but don't say which value was shared or where. March can say both, and offer the
rewrite.

## What the user sees

`march --why-copies FILE` (opt-in; implies the compile pipeline, stops before code generation, writes
no binary) prints one **warning** per place in the user's own code where a value is passed to a
function that would reuse its cells, but the value is still used afterwards, so the callee's reuse
finds the cell shared and allocates:

```
-- WARNING: COPY --------------------------------- main.march

`List.map` builds a new list instead of reusing `xs`'s cells, because `xs` is used again afterwards. [copy_shared]

3 |     let ys = List.map(xs, fn x -> x + 1)
                          ^^
    `xs` is used again here, so it is still shared when `List.map` runs:

4 |     let n = List.length(xs)
                            ^^
```

The corpus (`test/errors/copy_shared_*`, run with `-- MARCH-MODE: why-copies`) pins each reason
and the fix; its fix check requires the fixed program to report no copy.

When the rewrite is mechanical, the warning carries a machine fix (rendered as a diff, applied by
`forge fix`): move the later `let` above the call. `--why-copies-json` emits the same as NDJSON.

## Decisions

- Whole program, opt-in, warnings (the user's choice). Stdlib code is not reported; the call in
  user code is, since that is where the cause is.
- **Grounded in what Perceus did, not a heuristic.** The analysis runs on the TIR right after
  Perceus: a site is `inc_rc x` immediately before a call that passes `x` at a parameter the callee
  reuses (`reuse x` or `reuse_hole x` on that parameter, directly or through a callee it passes
  the parameter on to). The `inc_rc` is Perceus saying `x` is live after the call; the callee's
  reuse then fails its run-time uniqueness check.
- **Source positions from the AST, not new TIR spans.** TIR carries spans per function only
  (`Provenance`). The fact names the host function, the variable and the callee's source name;
  the driver finds that call in the host function's AST and the next use of the variable after it.
  No TIR shape changes, so no snapshot churn.
- **Report only a reason the source shows.** Each site gets one: used again later in the
  function; also an argument of the enclosing call (which holds it until it runs); or the call is
  inside a closure that captured it. A site with none (a value taken out of a tuple that still
  holds it, as in `bench/sort_small_batched.march`) is not reported: a warning naming the wrong
  cause is worse than none.
- **Fix only when safe:** the later use is a `let` in the same block, the only later use of the
  variable, its right-hand side mentions nothing bound between the call and it, passes no
  capability, and calls only functions `Purity` judges free of effects on the module *before*
  Perceus (whose RC operations it would count as effects), so moving it cannot reorder IO.

## Not in this cut

- Copies decided only at run time (a value shared through a data structure or another actor):
  that needs a run-time counter.
- A `match` on a borrowed parameter, whose cells are never the function's to reuse.
- LSP surfacing (the JSON form is the hook).

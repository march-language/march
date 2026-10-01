# Rewrite the stdlib list producers into natural style (DONE, 2026-09-28)

**Filed:** 2026-09-09 (as `specs/todos/2026-09-09-rewrite-stdlib-list-producers-into-natural-style.md`,
split out of `specs/progress/2026-08-07-trmc-tail-recursion-modulo-cons.md`).
**Closed:** 2026-09-28.

## What changed

`stdlib/list.march`, one function per commit, each confirmed with
`MARCH_TRMC_REPORT=1` to print `TRMCXFORM`:

| function | new shape | TRMC line |
|---|---|---|
| `map` | `Cons(f(h), map(t, f))` | `List.map -> List.map$dps` |
| `filter` | `if pred(h) do Cons(h, filter(t, pred)) else filter(t, pred) end` | `List.filter -> List.filter$dps` |
| `filter_map` | same shape as filter over `f(h)` | `List.filter_map -> List.filter_map$dps` |
| `append` | `Cons(h, append(t, ys))` | `List.append -> List.append$dps` |
| `flat_map` | top-level `pfn flat_map_go(sub, lst, f)`: copy the current `f(h)` cell by cell, advance on `Nil` | `List.flat_map_go -> List.flat_map_go$dps` |
| `range_step` | top-level `@[no_warn_recursion] pfn range_step_go`, next index let-bound | `List.range_step_go -> List.range_step_go$dps` |

`range` was left alone: it already walks once (it builds from `stop - 1`
downwards with no `reverse`), and its natural form hits a TRMC gap (below), so
rewriting it would have turned a loop into non-tail recursion.

## A TRMC bug this exposed, fixed in the same PR

`lib/tir/trmc.ml` `returnify`: in a function with one modulo-cons arm and one
plain tail self-call (filter's shape), the tail arm inside `f$dps` was
compiled as "call the ENTRY `f`, store its result into `$dst`". That is a
non-tail `entry -> $dps -> entry` cycle, one frame per alternation between
the arms. `List.filter(xs, fn x -> x % 2 == 0)` over 1,000,000 elements died
compiled with SIGBUS in the stack guard page right after the rewrite; all-true
and all-false predicates never alternate and ran fine. The tail arm is now
`f$dps(args, $dst)`, a genuine tail call. This also fixes the already-shipped
TRMC'd functions with a tail arm (e.g. `HttpClient.hc_strip_sensitive_headers`,
`Sort.insert_sorted`) and any user function of that shape.

- `test/test_trmc.ml` "tail arm stays in the helper": RED before the fix (the
  helper calls the entry), GREEN after.
- `test/native/trmc_filter_alternating.march` (dune rule): a user `keep_even`,
  `List.filter` and `List.filter_map` over 1,000,000 elements, alternating.
  RED before the fix (SIGBUS), GREEN after; expected output is the
  interpreter's.

## Measurements

Same-box A/B: the same compiler binary, `MARCH_STDLIB` pointed at an
origin/main copy of `stdlib/` versus this branch's. Compiled `--opt 2`, 7 runs
alternating which variant runs first, min of 7. Load average 9-13 during the
runs (other sessions), so small deltas are not meaningful; these are not small.

| probe | origin/main | this branch |
|---|---:|---:|
| `bench/list_producers.march` (`List.map`, 20k x 2000) | 0.532 s | 0.243 s |
| `bench/list_ops.march` | 0.084 s | 0.083 s (neutral) |
| `List.filter`, keep-all, 20k x 2000 | 1.664 s | 1.276 s |
| `List.filter_map`, keep-all, 20k x 2000 | 1.665 s | 1.293 s |
| `List.append(xs, [k])`, 20k x 2000 | 0.151 s | 0.078 s |
| `List.flat_map` (1-2 outputs each), 20k x 1000 | 2.274 s | 1.863 s |
| `List.range_step` (40k and 20k), x1000 | 1.544 s | 1.139 s |

The non-bench probes are scratch programs of the same shape as
`bench/list_producers.march` (thread the list so each pass sees a unique
value); outputs were byte-identical between the two stdlibs in every run.

## Stack safety

A program building a 1,000,000-element range and running `map`, alternating
`filter`, `filter_map`, `flat_map` (alternating empty/two-element results),
`append`, and a 1,000,000-element `range_step`:

- compiled `--opt 2`: exit 0, 175 MB peak RSS, same output as origin/main's stdlib;
- interpreted: exit 0, same output (162 s, 2.6 GB peak RSS). The interpreter
  gets no TRMC, but OCaml 5's growable stack takes the 1M-deep natural
  recursion; no interpreter-specific shape was needed. For scale, a
  1,000,000-element `List.map` alone took 26 s interpreted in natural style
  versus 32 s in the old accumulator style.

## Refinement contracts

`filter` and `append` keep their `subset`/`union` return refinements. On a
user copy of the natural shapes, `--check --refine-report` proves both (2/2);
perturbing `append`'s `Nil -> ys` to `Nil -> xs` stops the proof. The removed
nested `go` helpers each carried their own refinement, so the stdlib's
coverage-audit count falls from 120 to 118 enforced (still 0 unenforced) and
`test/refine_audit/corpus.baseline` was regenerated for that. The CI skip
ceiling for `stdlib/list.march` is unchanged (40 skipped, ceiling 42).

## Left open

`specs/todos/2026-09-28-trmc-computed-arg-and-nested-fn-gaps.md`: TRMC misses
`Cons(a, f(a + 1, b))` (a computed argument; the let-bound form is eligible),
and it analyses nested functions without transforming them.

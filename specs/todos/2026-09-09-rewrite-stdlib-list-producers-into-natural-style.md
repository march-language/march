# Rewrite the stdlib list producers into natural style (OPEN, 2026-09-09)

**Filed:** 2026-09-09, splitting the former Phase 6 out of
`specs/progress/2026-08-07-trmc-tail-recursion-modulo-cons.md` when TRMC's
default was flipped ON.

**Unblocked, not started.** The ordering hazard that made this dangerous is
gone: TRMC is now the default, so natural-style recursion compiles to a loop.

## What

`List.map`, `filter`, `filter_map`, `append`, `flat_map` and `range` are
hand-written as accumulator + `reverse` (`stdlib/list.march`). TRMC classifies
them `already-tail` and does not touch them, so they still traverse the list
**twice**. Rewriting them into the natural single-traversal form

```march
fn map(xs, f) do
  match xs do
    Nil        -> Nil
    Cons(h, t) -> Cons(f(h), map(t, f))
  end
end
```

lets TRMC turn each into a single-traversal loop with in-place cell reuse.

## Why it is worth doing

Measured 2026-09-09, 20k-element list, 2000 successive increments, compiled
`--opt 2`, interleaved with the warmup round discarded:

| variant | time |
|---|---:|
| natural style, TRMC on | 0.06s |
| natural style, `--no-trmc` | 0.29s |
| `List.map` accumulator + `reverse` (today) | 0.49s |

The 0.06s figure is what a rewritten `List.map` should approach. Treat it as an
upper bound on the win, not a prediction: the 0.49s row goes through a closure
parameter, which the hand-monomorphic 0.06s probe does not.

## Constraints

- **One function per commit, benchmarked after each.** Do not batch.
  `bench/list_producers.march` is the benchmark that isolates traversal count.
- Verify with `MARCH_TRMC_REPORT=1` that each rewritten function actually
  reports `TRMCXFORM` — a rewrite that silently stays `non-trmc` is a pure
  regression, since natural style without the transform is 1.8x slower than the
  accumulator form it replaced.
- Signatures and semantics must not change; these are public stdlib APIs.

## The consequence to decide before landing

After this, `--no-trmc` / `MARCH_NO_TRMC=1` stops being a safe escape hatch: a
natural-style `List.map` compiled without TRMC **stack-overflows** on a long
list (measured: exit 138 at 500k elements). CI's `trmc-suite` job runs the whole
suite with `MARCH_NO_TRMC=1` and would start failing.

Pick one before the first rewrite lands:

1. Drop `--no-trmc` and the `trmc-suite` job entirely, or
2. Keep it documented as a debugging-only switch that is unsound against a
   natural-style stdlib, and change `trmc-suite` to assert something weaker
   than a green suite.

Option 1 is cleaner but removes the only coverage of the non-TRMC path.

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

## The consequence to decide before landing: `--no-trmc` becomes unsound

This is the part to settle first, because it changes what the flag *is*.

Today `--no-trmc` is an ordinary optimisation switch: turning it off makes code
slower and nothing else, because the stdlib producers are accumulator-style and
already tail-recursive. After this rewrite they are not. Natural-style
recursion is only a loop *because* TRMC makes it one, so a stdlib compiled
without the transform has a `List.map` that consumes one stack frame per
element.

### The threshold is low enough to matter

Measured 2026-09-09, natural-style map over `List.range(1, N)`, compiled
`--opt 2`, exit status only:

| N | `--no-trmc` | default (TRMC on) |
|---:|---|---|
| 5,000 | exit 0 | exit 0 |
| 10,000 | exit 0 | exit 0 |
| 20,000 | exit 0 | exit 0 |
| **30,000** | **exit 138** | exit 0 |
| 400,000 | exit 138 | exit 0 |

The cliff is between 20k and 30k elements — not 500k, which is what the TRMC
item's ordering note happened to test with. Note that compiled `main` runs on a
green thread, so the budget is the scheduler's green-thread stack, not the 8 MB
main-thread stack.

**That number is the argument.** 30,000 elements is comfortably inside ordinary
application data and comfortably outside what a test suite maps over. So the
failure mode is not "CI goes red and we notice": it is a flag that looks like a
performance knob, produces a binary that passes every test, and then aborts on a
user's real input. There is no diagnostic — exit 138 with no output.

### What it does to CI

`trmc-suite` currently runs the whole suite with `MARCH_NO_TRMC=1`. It will not
fail at the first rewrite, because the suite's lists are small; it will fail
whenever some test grows past the cliff, and that failure will look like an
unrelated flake. A job that is green for the wrong reason and then fails for a
confusing one is worse than no job.

### Options

1. **Drop `--no-trmc`, `MARCH_NO_TRMC` and the `trmc-suite` job.** Honest: the
   transform is load-bearing, not optional, and a flag that produces crashing
   binaries should not exist. Cost: loses the only differential coverage of the
   non-TRMC path, and loses a genuinely useful bisection tool — "is this
   miscompile TRMC's fault?" is a question worth being able to ask cheaply.

2. **Keep the flag as debugging-only; weaken the job.** Document it as unsound
   against a natural-style stdlib and have `trmc-suite` assert something less
   than a green suite. Cost: the job's remaining value is close to zero, and its
   green becomes misleading rather than informative.

3. **Scope the flag to user code instead of dropping it — probably the right
   answer, and not yet investigated.** The real defect is the flag's *scope*,
   not its existence: it disables the transform globally, including for the
   stdlib that now depends on it. A `--no-trmc` that skipped TRMC only for the
   entry program's own functions would keep every bit of its debugging value
   (that is the code you are bisecting) while leaving the stdlib correct, and
   `trmc-suite` would keep asserting a green suite.

   Feasibility is plausible but unverified. `Trmc.transform_module` walks
   `m.tm_fns` after linking, and stdlib functions carry qualified names
   (`List.map`), so a name-prefix filter is the obvious mechanism. **Check
   before committing to this**: prefix attribution is exactly where March has
   burned itself before — an app module named `List` collides with the stdlib
   one (see the app-type-namespace problem), so "starts with a stdlib module
   name" is not the same predicate as "came from the stdlib". If TIR carries a
   real provenance field, use that; if it does not, adding one may be the actual
   work of this option.

Option 3 first. Fall back to 1 if provenance turns out not to be available
cheaply — option 2 buys the least and costs a misleading CI signal.

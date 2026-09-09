# `Alloc_contract.trmc_note` may be unreachable, and its test is vacuous (OPEN, 2026-09-09)

**Filed:** 2026-09-09, found while flipping TRMC's default. Not caused by that
flip — the flip only made the existing hole visible.

## What

`lib/tir/alloc_contract.ml` attaches `trmc_note` to a `no_alloc` diagnostic when
the reason is a constructor allocation and:

```ocaml
| Ctor _ when (not trmc) && trmc_eligible name -> [ trmc_note ]
```

Two probes, neither of which produced the note:

| fixture | `--no-trmc` | default |
|---|---|---|
| `inc_all(xs) = Cons(h+1, inc_all(t))` over a matched list | no `no_alloc` diagnostic at all | no diagnostic |
| `upto(n) = Cons(n, upto(n-1))`, nothing to reuse | `no_alloc` fires, **no note** | `no_alloc` fires, no note |

The first is explained: FBIP already reuses the scrutinee cell without TRMC, so
there is no allocation to complain about. That is the interesting half — it
suggests the note's premise may be structurally unreachable, because the shape
where TRMC would remove the allocation is the same shape where reuse already
removed it. The second is unexplained: the guard's `(not trmc)` half is
satisfied and a constructor allocation is being reported, so either
`trmc_eligible` is false for it or the reason is not `Ctor _`.

## Why it matters

`test/test_alloc_contract.ml`'s `TRMC hint absent when --trmc is on` asserts the
note is ABSENT. Since the default flipped, that assertion holds because the
guard is false on every ordinary build — it would pass if the flag did nothing.
It is documented as vacuous in place, but it is not coverage.

## What to do

1. Determine whether `trmc_note` can fire at all. Instrument the guard, or run
   the corpus with `MARCH_TRMC_REPORT=1` and cross-reference `trmc_eligible`
   against the functions that produce `Ctor` `no_alloc` diagnostics.
2. If it can, add a fixture that produces it and make the test assert both
   directions.
3. If it cannot, delete the note and the branch rather than leaving a message
   no user can ever see. Note the wording was already corrected on 2026-09-09
   (it used to tell the reader to pass `--trmc`, which is now backwards); a
   message that is both unreachable and prone to going stale is worth removing.

## Not in scope of the finding

Nothing here says the `no_alloc` contract itself is wrong. Both probes produced
the right accept/reject verdict in both modes; only the explanatory note is in
question.
